#include "MemoryParser.h"
#include <QJsonArray>
#include <QRegularExpression>
#include <QStringList>
#include <algorithm>

namespace {
const QStringList valueKeys = {
    "pssTotalKb",     "sharedCleanKb", "sharedDirtyKb",  "privateCleanKb",
    "privateDirtyKb", "swapTotalKb",   "swapPssTotalKb", "heapSizeKb",
    "heapAllocKb",    "heapFreeKb"};
double number(const QString &s) { return s.toDouble(); }
QJsonArray sorted(QList<QJsonObject> rows, const QString &key) {
  std::stable_sort(rows.begin(), rows.end(),
                   [&key](const auto &a, const auto &b) {
                     return a.value(key).toDouble() > b.value(key).toDouble();
                   });
  QJsonArray result;
  for (const auto &row : rows)
    result.append(row);
  return result;
}
} // namespace

QJsonObject MemoryParser::zeroValues() {
  QJsonObject values;
  for (const auto &key : valueKeys)
    values.insert(key, 0);
  return values;
}

QJsonObject MemoryParser::processMemory(const QString &raw) {
  QJsonObject total = zeroValues(), categories, nativeHeap;
  QJsonObject result{
      {"purgSumKb", 0}, {"purgPinKb", 0}, {"dmaKb", 0}, {"ashmemTotalKb", 0}};
  static const QRegularExpression whitespace("\\s+");
  static const QRegularExpression digits("^\\d+$");
  static const QRegularExpression extra(
      "^(PurgSum|PurgPin|Dma|Total Ashmem)\\s*:\\s*(\\d+)\\s*kB",
      QRegularExpression::CaseInsensitiveOption);
  for (const auto &line : raw.split('\n')) {
    const auto trimmed = line.trimmed();
    const auto tokens = trimmed.split(whitespace, Qt::SkipEmptyParts);
    if (tokens.size() >= 10) {
      const auto numeric = tokens.mid(tokens.size() - 10);
      if (std::all_of(numeric.begin(), numeric.end(), [](const auto &v) {
            return digits.match(v).hasMatch();
          })) {
        const auto name = tokens.mid(0, tokens.size() - 10).join(' ');
        QJsonObject values;
        for (int i = 0; i < valueKeys.size(); ++i)
          values[valueKeys[i]] = number(numeric[i]);
        if (name == "Total")
          total = values;
        else if (name.startsWith("jemalloc") || name.contains("brk heap") ||
                 name.contains("musl heap"))
          nativeHeap[name] = values;
        else
          categories[name] = values;
      }
    }
    const auto match = extra.match(trimmed);
    if (match.hasMatch()) {
      const auto key = match.captured(1).toLower();
      const auto dest = key == "purgsum"   ? "purgSumKb"
                        : key == "purgpin" ? "purgPinKb"
                        : key == "dma"     ? "dmaKb"
                                           : "ashmemTotalKb";
      result[dest] = number(match.captured(2));
    }
  }
  result["total"] = total;
  result["categories"] = categories;
  result["nativeHeapDetail"] = nativeHeap;
  return result;
}

QJsonObject MemoryParser::systemMemory(const QString &raw) {
  const auto get = [&raw](const QString &name) {
    return number(QRegularExpression(name + " RAM\\s*:\\s*(\\d+)\\s*kB")
                      .match(raw)
                      .captured(1));
  };
  return {{"ramTotalKb", get("Total")},
          {"ramFreeKb", get("Free")},
          {"ramUsedKb", get("Used")}};
}

QJsonObject MemoryParser::procMeminfo(const QString &raw) {
  const auto get = [&raw](const QString &name) {
    return number(QRegularExpression("^" + name + ":\\s*(\\d+)\\s*kB",
                                     QRegularExpression::MultilineOption)
                      .match(raw)
                      .captured(1));
  };
  const double total = get("MemTotal"), free = get("MemFree") + get("Cached");
  return {{"ramTotalKb", total},
          {"ramFreeKb", free},
          {"ramUsedKb", std::max(0.0, total - free)}};
}

QJsonObject MemoryParser::details(const QString &raw) {
  const auto lines = raw.split('\n');
  QString section;
  QList<QJsonObject> ashmem, dma, channels;
  double used = 0, allocated = 0;
  static const QRegularExpression digits("^\\d+$");
  static const QRegularExpression channel(
      "^Channel:\\s*(.+?)\\s*\\(Total memory:\\s*(\\d+)\\)\\s*$");
  for (const auto &line : lines) {
    const auto trimmed = line.trimmed();
    if (trimmed == "DMA:" || trimmed == "Ashmem:" || trimmed == "GPU:") {
      section = trimmed;
      continue;
    }
    if (section == "DMA:") {
      const auto parts = trimmed.split(QRegularExpression("\\s{2,}"));
      if (parts.size() >= 5 && digits.match(parts[1]).hasMatch() &&
          digits.match(parts[2]).hasMatch()) {
        bool valid;
        const double bytes = parts[3].toDouble(&valid);
        if (valid)
          dma.append({{"name", parts.last()},
                      {"fd", number(parts[2])},
                      {"ino", number(parts[4])},
                      {"sizeBytes", bytes}});
      }
    } else if (section == "Ashmem:") {
      const auto parts = line.split('\t');
      if (parts.size() >= 9 && digits.match(parts[1]).hasMatch() &&
          digits.match(parts[2]).hasMatch()) {
        auto name = parts[5];
        if (name.startsWith("dev/ashmem/"))
          name.remove(0, 11);
        ashmem.append({{"name", name},
                       {"fd", number(parts[2])},
                       {"virtualBytes", number(parts[6])},
                       {"physicalBytes", number(parts[7])}});
      }
    } else if (section == "GPU:") {
      const auto match = channel.match(line);
      if (match.hasMatch())
        channels.append({{"name", match.captured(1)},
                         {"totalBytes", number(match.captured(2))}});
      const auto u =
          QRegularExpression("^Total used memory:\\s*(\\d+)").match(line);
      const auto a =
          QRegularExpression("^Total allocated memory:\\s*(\\d+)").match(line);
      if (u.hasMatch())
        used = number(u.captured(1));
      if (a.hasMatch())
        allocated = number(a.captured(1));
    }
  }
  QJsonValue gpu = QJsonValue::Null;
  if (!channels.isEmpty() || used > 0)
    gpu = QJsonObject{{"channels", sorted(channels, "totalBytes")},
                      {"totalUsedBytes", used},
                      {"totalAllocatedBytes", allocated}};
  return {{"ashmem", sorted(ashmem, "physicalBytes")},
          {"dmabuf", sorted(dma, "sizeBytes")},
          {"gpu", gpu}};
}

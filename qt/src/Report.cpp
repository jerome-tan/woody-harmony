#include "Report.h"
#include <QColor>
#include <algorithm>
#include <cmath>
#include <limits>

namespace {
const QStringList defaultCategories{
    "Total", "GL",  "Graph", "ark ts heap",    "native heap",
    "stack", ".so", ".hap",  "AnonPage other", "FilePage other",
    "dev",   ".db", ".ttf",  "guard"};
const QStringList colors{"#e6194b", "#911eb4", "#4363d8", "#f58231", "#3cb44b",
                         "#46f0f0", "#ffe119", "#9a6324", "#f032e6", "#808080",
                         "#000000", "#008080", "#bcf60c", "#000075"};
const QStringList fallback{"#e6194b", "#3cb44b", "#ffe119", "#4363d8",
                           "#f58231", "#911eb4", "#46f0f0", "#f032e6",
                           "#bcf60c", "#9a6324", "#008080", "#808080",
                           "#000075", "#000000"};
} // namespace

QColor Report::color(const QString &category, int index) {
  const int fixed = defaultCategories.indexOf(category);
  return QColor(fixed >= 0 ? colors[fixed] : fallback[index % fallback.size()]);
}

double Report::value(const QJsonObject &sample, const QString &metric) {
  if (metric == "Total")
    return sample["total"].toObject()["pssTotalKb"].toDouble();
  if (metric == "Private Dirty")
    return sample["total"].toObject()["privateDirtyKb"].toDouble();
  if (metric == "Swap Pss")
    return sample["total"].toObject()["swapPssTotalKb"].toDouble();
  if (metric == "Heap Alloc")
    return sample["total"].toObject()["heapAllocKb"].toDouble();
  return sample["categories"]
      .toObject()[metric]
      .toObject()["pssTotalKb"]
      .toDouble();
}

void Report::load(const QJsonObject &data) {
  mCategoriesValid = mStatsValid = false;
  metadata = data["meta"].toObject();
  snapshotData = data["snapshot"].toObject();
  samples.clear();
  for (const auto &value : data["samples"].toArray())
    samples.append(value.toObject());
  emit changed();
}
void Report::append(const QJsonObject &sample) {
  mCategoriesValid = mStatsValid = false;
  samples.append(sample);
  emit changed();
}
void Report::reset() {
  mCategoriesValid = mStatsValid = false;
  metadata = {};
  snapshotData = {};
  samples.clear();
  emit changed();
}

QStringList Report::categories() const {
  if (mCategoriesValid)
    return mCategories;
  QStringList present;
  for (const auto &sample : samples)
    for (const auto &key : sample["categories"].toObject().keys())
      if (!present.contains(key))
        present.append(key);
  if (!snapshotData.isEmpty())
    present = snapshotData["categories"].toObject().keys();
  QStringList result{"Total"};
  for (const auto &name : defaultCategories)
    if (name != "Total" && present.contains(name))
      result.append(name);
  for (const auto &name : present)
    if (!result.contains(name))
      result.append(name);
  mCategories = result;
  mCategoriesValid = true;
  return mCategories;
}

double Report::duration() const {
  if (samples.isEmpty())
    return 0;
  return (samples.last()["timestamp"].toDouble() -
          samples.first()["timestamp"].toDouble()) /
         1000.0;
}

QVariantMap Report::sampleAt(int index) const {
  return index < 0 || index >= samples.size() ? QVariantMap{}
                                              : samples[index].toVariantMap();
}

int Report::nearest(double seconds) const {
  if (samples.isEmpty())
    return -1;
  const double time = samples.first()["timestamp"].toDouble() + seconds * 1000;
  const auto next = std::lower_bound(
      samples.begin(), samples.end(), time, [](const auto &sample, double t) {
        return sample["timestamp"].toDouble() < t;
      });
  if (next == samples.begin())
    return 0;
  if (next == samples.end())
    return samples.size() - 1;
  const int index = int(next - samples.begin());
  return time - samples[index - 1]["timestamp"].toDouble() <=
                 samples[index]["timestamp"].toDouble() - time
             ? index - 1
             : index;
}

int Report::peakIndex(const QString &metric) const {
  int index = -1;
  double peak = -std::numeric_limits<double>::infinity();
  for (int i = 0; i < samples.size(); ++i) {
    const auto v = value(samples[i], metric);
    if (v > peak) {
      peak = v;
      index = i;
    }
  }
  return index;
}

QVariantMap Report::stats() const {
  if (mStatsValid)
    return mStats;
  double sum = 0, peak = 0;
  for (const auto &sample : samples) {
    const auto v = value(sample, "Total");
    sum += v;
    peak = std::max(peak, v);
  }
  const double first = samples.isEmpty() ? 0 : value(samples.first(), "Total");
  const double last = samples.isEmpty() ? 0 : value(samples.last(), "Total");
  mStats = {
      {"peak", peak},
      {"avg", samples.isEmpty() ? 0 : std::round(sum / samples.size())},
      {"first", first},
      {"last", last},
      {"growth", last - first},
      {"durationMs", duration() * 1000},
      {"privateDirty",
       samples.isEmpty()
           ? 0
           : samples.last()["total"].toObject()["privateDirtyKb"].toDouble()},
      {"pid",
       samples.isEmpty() ? QVariant{} : samples.last()["pid"].toVariant()}};
  mStatsValid = true;
  return mStats;
}

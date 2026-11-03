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
// Data categories need distinct hues, independent of the lavender UI theme.
// Trends, snapshot bars/donuts, legends and tooltips all use this mapping.
const QStringList colors{
    "#7C3AED", // Total: violet
    "#0072B2", // GL: blue
    "#D55E00", // Graph: orange
    "#E31A1C", // ArkTS heap: red
    "#009E73", // Native heap: green
    "#008DA8", // Stack: cyan
    "#A88700", // .so: ochre
    "#C2188B", // .hap: magenta
    "#8C4B21", // AnonPage other: brown
    "#64748B", // FilePage other: slate
    "#658800", // dev: lime
    "#003F5C", // .db: navy
    "#DB6B8A", // .ttf: pink
    "#252525"  // guard: charcoal
};
const QStringList fallback{"#0072B2", "#D55E00", "#009E73", "#C2188B",
                           "#008DA8", "#A88700", "#E31A1C", "#7C3AED",
                           "#8C4B21", "#658800", "#003F5C", "#DB6B8A"};
} // namespace

QColor Report::color(const QString &category, int index) {
  Q_UNUSED(index);
  const int fixed = defaultCategories.indexOf(category);
  // Unknown categories must also keep their color when chart order changes.
  return QColor(fixed >= 0 ? colors[fixed]
                          : fallback[qHash(category, 0) % fallback.size()]);
}

bool Report::isMeasurement(const QJsonObject &sample) {
  // Old reports may omit pid. Explicit null/zero PID marks a waiting placeholder.
  return sample.contains("total") &&
         (!sample.contains("pid") || sample["pid"].toInteger() > 0);
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
    if (!isMeasurement(samples[i]))
      continue;
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
  double sum = 0, peak = 0, first = 0, last = 0, validDuration = 0;
  int validCount = 0;
  QJsonObject previous, latest;
  for (const auto &sample : samples) {
    if (isMeasurement(sample)) {
      const auto v = value(sample, "Total");
      if (!validCount) first = v;
      last = v;
      sum += v;
      peak = std::max(peak, v);
      ++validCount;
      latest = sample;
      if (isMeasurement(previous))
        validDuration += std::max(0.0, sample["timestamp"].toDouble() - previous["timestamp"].toDouble());
    }
    previous = sample;
  }
  mStats = {{"peak", peak}, {"avg", validCount ? std::round(sum / validCount) : 0},
            {"first", first}, {"last", last}, {"growth", last - first},
            {"durationMs", duration() * 1000}, {"validCount", validCount},
            {"validDurationMs", validDuration},
            {"currentValid", !samples.isEmpty() && isMeasurement(samples.last())},
            {"privateDirty", latest["total"].toObject()["privateDirtyKb"].toDouble()},
            {"pid", samples.isEmpty() ? QVariant{} : samples.last()["pid"].toVariant()}};
  mStatsValid = true;
  return mStats;
}

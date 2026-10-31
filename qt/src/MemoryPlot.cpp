#include "MemoryPlot.h"
#include <QDateTime>
#include <QHoverEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QQuickWindow>
#include <QWheelEvent>
#include <algorithm>
#include <cmath>

namespace {
const QStringList compareColors{"#1677ff", "#fa8c16", "#52c41a", "#722ed1"};
QString bytes(double kb) {
  if (std::abs(kb) >= 1048576)
    return QString::number(kb / 1048576, 'f', 2) + " GB";
  if (std::abs(kb) >= 1024)
    return QString::number(kb / 1024, 'f', 1) + " MB";
  return QString::number(std::round(kb), 'f', 0) + " kB";
}
QPainterPath linePath(const QVector<QPointF> &points, bool smooth) {
  QPainterPath path;
  if (points.isEmpty())
    return path;
  path.moveTo(points.first());
  for (int i = 1; i < points.size(); ++i) {
    if (!smooth) {
      path.lineTo(points[i]);
      continue;
    }
    // Monotone in x and bounded in y: smoothing never overshoots a measured
    // extremum.
    const auto a = points[i - 1], b = points[i];
    const double dx = (b.x() - a.x()) / 3;
    path.cubicTo(QPointF(a.x() + dx, a.y()), QPointF(b.x() - dx, b.y()), b);
  }
  return path;
}
} // namespace

MemoryPlot::MemoryPlot(QQuickItem *parent) : QQuickPaintedItem(parent) {
  setAntialiasing(true);
  setAcceptedMouseButtons(Qt::LeftButton);
  setAcceptHoverEvents(true);
  connect(this, &MemoryPlot::optionsChanged, this, &MemoryPlot::rebuild);
}
QVariantList MemoryPlot::reports() const {
  QVariantList result;
  for (auto report : mReports)
    result.append(QVariant::fromValue(report.data()));
  return result;
}
void MemoryPlot::setReports(const QVariantList &value) {
  for (auto report : mReports)
    if (report)
      disconnect(report, nullptr, this, nullptr);
  mReports.clear();
  for (const auto &entry : value) {
    auto *report = qobject_cast<Report *>(entry.value<QObject *>());
    if (!report)
      report = entry.value<Report *>();
    if (!report)
      continue;
    mReports.append(report);
    connect(report, &Report::changed, this, &MemoryPlot::rebuild);
    connect(report, &QObject::destroyed, this, &MemoryPlot::rebuild);
  }
  mFollowing = true;
  emit optionsChanged();
}
void MemoryPlot::invalidate() {
  mDirty = true;
  update();
}
QRectF MemoryPlot::plotRect() const {
  return {mCompact ? 60.0 : 72.0, 30,
          std::max(1.0, width() - (mCompact ? 78 : 94)),
          std::max(1.0, height() - (mCompact ? 92 : 114))};
}
QRectF MemoryPlot::overviewRect() const {
  auto p = plotRect();
  return {p.left(), height() - (mCompact ? 28 : 44), p.width(),
          mCompact ? 20.0 : 34.0};
}

void MemoryPlot::rebuild() {
  mSeries.clear();
  double alignedAnchor = 0;
  for (auto report : mReports)
    if (report && !report->samples.isEmpty()) {
      const auto peak = report->peakIndex(mMetric);
      const auto peakTime = (report->samples[peak]["timestamp"].toDouble() -
                             report->samples.first()["timestamp"].toDouble()) /
                            1000;
      alignedAnchor =
          std::max(alignedAnchor, mAlignment == "end"    ? report->duration()
                                  : mAlignment == "peak" ? peakTime
                                                         : 0);
    }
  double span = 0;
  for (int ri = 0; ri < mReports.size(); ++ri) {
    auto *report = mReports[ri].data();
    if (!report || report->samples.isEmpty())
      continue;
    const auto first = report->samples.first()["timestamp"].toDouble();
    const auto peak = report->peakIndex(mMetric);
    const double peakTime =
        (report->samples[peak]["timestamp"].toDouble() - first) / 1000;
    const double offset =
        alignedAnchor - (mAlignment == "end"    ? report->duration()
                         : mAlignment == "peak" ? peakTime
                                                : 0);
    span = std::max(span, report->duration() + offset);
    const auto metrics =
        mReports.size() > 1 ? QStringList{mMetric} : report->categories();
    for (int mi = 0; mi < metrics.size(); ++mi) {
      const auto &metric = metrics[mi];
      if (mHidden.contains(metric))
        continue;
      Series series;
      series.report = report;
      series.metric = metric;
      series.offset = offset;
      series.label = mReports.size() > 1
                         ? report->metadata["taskName"].toString(
                               report->metadata["bundleName"].toString())
                         : metric;
      series.color = mReports.size() > 1 ? QColor(report->compareColor.isEmpty()
                                                      ? compareColors[ri % 4]
                                                      : report->compareColor)
                                         : Report::color(metric, mi);
      series.peak = report->peakIndex(metric);
      series.points.reserve(report->samples.size());
      for (const auto &sample : report->samples) {
        const bool missing = metric != "Total" && metric != "Private Dirty" &&
                             metric != "Swap Pss" && metric != "Heap Alloc" &&
                             !sample["categories"].toObject().contains(metric);
        series.points.append(
            {(sample["timestamp"].toDouble() - first) / 1000 + offset,
             missing ? std::numeric_limits<double>::quiet_NaN()
                     : Report::value(sample, metric)});
      }
      mSeries.append(std::move(series));
    }
  }
  const bool wasFull = mStart == 0 && mEnd >= mSpan;
  mSpan = std::max(2.0, span);
  if (mFollowing || wasFull) {
    mEnd = mSpan;
    mStart = mLive ? std::max(0.0, mEnd - 30) : 0;
  } else {
    mEnd = std::min(mEnd, mSpan);
    mStart = std::min(mStart, std::max(0.0, mEnd - 2));
  }
  emit rangeChanged();
  invalidate();
}
void MemoryPlot::resetView() {
  mFollowing = true;
  rebuild();
}
void MemoryPlot::followLatest() {
  mFollowing = true;
  rebuild();
}
void MemoryPlot::setRange(double start, double end) {
  const auto span = std::clamp(end - start, std::min(2.0, mSpan), mSpan);
  mStart = std::clamp(start, 0.0, mSpan - span);
  mEnd = mStart + span;
  mFollowing = mLive && mEnd >= mSpan - 0.001;
  emit rangeChanged();
  invalidate();
}

void MemoryPlot::draw(QPainter &p) {
  p.setRenderHint(QPainter::Antialiasing);
  QFont font = p.font();
  font.setPixelSize(mCompact ? 10 : 11);
  p.setFont(font);
  const auto area = plotRect();
  double maximum = 0, minimum = std::numeric_limits<double>::infinity();
  for (const auto &series : mSeries) {
    for (const auto &point : series.points)
      if (point.x() >= mStart && point.x() <= mEnd &&
          std::isfinite(point.y())) {
        maximum = std::max(maximum, point.y());
        minimum = std::min(minimum, point.y());
      }
  }
  if (!std::isfinite(minimum))
    minimum = 0;
  // ECharts-compatible padded value scale, including non-zero lower bounds for
  // a flat series.
  double step = std::pow(
      10.0, std::floor(std::log10(std::max(1.0, maximum - minimum) / 5)));
  if (maximum - minimum < std::max(1.0, maximum * .2))
    step = std::max(
        step,
        std::pow(10.0, std::floor(std::log10(std::max(1.0, maximum * .2)))));
  const double lower =
      std::max(0.0, std::floor((minimum - step) / step) * step);
  double upper = std::ceil((maximum + step) / step) * step;
  if (upper <= lower)
    upper = lower + 5;
  auto map = [&](const QPointF &v) {
    return QPointF(
        area.left() + (v.x() - mStart) / (mEnd - mStart) * area.width(),
        area.bottom() - (v.y() - lower) / (upper - lower) * area.height());
  };
  p.setPen(QColor("#6e7079"));
  p.drawText(QRectF(0, 0, area.left() + 30, 24), Qt::AlignCenter,
             mReports.size() > 1 ? (mMetric == "Total" ? "Total Pss" : mMetric)
                                 : QStringLiteral("内存"));
  for (int i = 0; i <= 5; ++i) {
    const double y = area.bottom() - area.height() * i / 5;
    p.setPen(QPen(QColor("#e8e8e8"), 1, Qt::DashLine));
    p.drawLine(QPointF(area.left(), y), QPointF(area.right(), y));
    p.setPen(QColor("#6e7079"));
    p.drawText(QRectF(0, y - 8, area.left() - 8, 16),
               Qt::AlignRight | Qt::AlignVCenter,
               bytes(lower + (upper - lower) * i / 5));
  }
  for (int i = 0; i <= 4; ++i) {
    const double x = area.left() + area.width() * i / 4;
    p.setPen(QPen(QColor("#dbe4f5"), 1));
    p.drawLine(QPointF(x, area.top()), QPointF(x, area.bottom()));
    p.setPen(QColor("#6e7079"));
    p.drawText(QRectF(x - 28, area.bottom() + 4, 56, 18), Qt::AlignCenter,
               QString::number(mStart + (mEnd - mStart) * i / 4, 'f',
                               mEnd - mStart < 10 ? 1 : 0));
  }
  p.setPen(QColor("#6e7079"));
  p.drawLine(area.bottomLeft(), area.bottomRight());
  p.drawLine(area.topLeft(), area.bottomLeft());
  if (!mCompact)
    p.drawText(QRectF(area.left(), area.bottom() + 22, area.width(), 18),
               Qt::AlignCenter, QStringLiteral("相对时间 (s)"));
  p.save();
  p.setClipRect(area.adjusted(-1, -1, 1, 1));
  for (const auto &series : mSeries) {
    QVector<QPointF> mapped;
    auto flush = [&] {
      if (mapped.isEmpty())
        return;
      QColor color = series.color;
      if (!mHighlight.isEmpty() && mHighlight != series.metric)
        color.setAlphaF(.18);
      const auto path = linePath(mapped, mSmooth);
      if (series.metric == "Total" && mReports.size() == 1) {
        auto areaPath = path;
        areaPath.lineTo(mapped.last().x(), area.bottom());
        areaPath.lineTo(mapped.first().x(), area.bottom());
        areaPath.closeSubpath();
        QLinearGradient fill(0, area.top(), 0, area.bottom());
        QColor c = color;
        c.setAlphaF(.09);
        fill.setColorAt(0, c);
        c.setAlphaF(0);
        fill.setColorAt(1, c);
        p.fillPath(areaPath, fill);
      }
      p.setPen(QPen(
          color, series.metric == "Total" || mReports.size() > 1 ? 2.5 : 1.5));
      p.setBrush(Qt::NoBrush);
      p.drawPath(path);
      if (mPoints && series.metric == "Total" && mReports.size() == 1) {
        p.setPen(QPen(Qt::white, 1));
        p.setBrush(color);
        for (const auto &v : mapped)
          p.drawEllipse(v, 2.5, 2.5);
      }
      mapped.clear();
    };
    for (int i = 0; i < series.points.size(); ++i) {
      const auto v = series.points[i];
      if (!std::isfinite(v.y())) {
        flush();
        continue;
      }
      if (v.x() < mStart && i + 1 < series.points.size() &&
          series.points[i + 1].x() < mStart)
        continue;
      if (v.x() > mEnd && i > 0 && series.points[i - 1].x() > mEnd)
        break;
      mapped.append(map(v));
    }
    flush();
  }
  p.restore();
  for (const auto &series : mSeries) {
    if (mLive || (mReports.size() == 1 && series.metric != "Total") ||
        series.peak < 0 || series.peak >= series.points.size())
      continue;
    const auto value = series.points[series.peak];
    const auto at = map(value);
    if (!area.contains(at))
      continue;
    p.setPen(QPen(Qt::white, 1.5));
    p.setBrush(series.color);
    p.drawEllipse(at, 4.5, 4.5);
    const auto text = QStringLiteral("峰值 ") + bytes(value.y());
    const double labelWidth = p.fontMetrics().horizontalAdvance(text) + 12;
    QRectF label(std::clamp(at.x() - labelWidth / 2, area.left(),
                            area.right() - labelWidth),
                 std::max(2.0, at.y() - 29), labelWidth, 20);
    p.setPen(QColor("#d9d9d9"));
    p.setBrush(QColor(255, 255, 255, 217));
    p.drawRoundedRect(label, 3, 3);
    p.setPen(QColor("#262626"));
    p.drawText(label, Qt::AlignCenter, text);
  }
  if (mSelected >= 0 && !mReports.isEmpty() && mReports.first() &&
      mSelected < mReports.first()->count()) {
    const auto *r = mReports.first().data();
    const double seconds = (r->samples[mSelected]["timestamp"].toDouble() -
                            r->samples.first()["timestamp"].toDouble()) /
                           1000;
    const double x = map({seconds, 0}).x();
    if (x >= area.left() && x <= area.right()) {
      p.setPen(QPen(QColor("#ff4d4f"), 1.5, Qt::DashLine));
      p.drawLine(QPointF(x, area.top()), QPointF(x, area.bottom()));
    }
  }
  const auto overview = overviewRect();
  p.setPen(QColor("#dbe4f5"));
  p.setBrush(QColor("#f4f6fb"));
  p.drawRoundedRect(overview, 2, 2);
  if (!mSeries.isEmpty()) {
    const auto &series = mSeries.first();
    double peak = 1;
    for (const auto &v : series.points)
      if (std::isfinite(v.y()))
        peak = std::max(peak, v.y());
    QPainterPath path;
    path.moveTo(overview.bottomLeft());
    for (const auto &v : series.points)
      if (std::isfinite(v.y()))
        path.lineTo(overview.left() + v.x() / mSpan * overview.width(),
                    overview.bottom() - v.y() / peak * (overview.height() - 3));
    path.lineTo(overview.bottomRight());
    path.closeSubpath();
    p.fillPath(path, QColor("#dfe6f3"));
  }
  QRectF selection(overview.left() + mStart / mSpan * overview.width(),
                   overview.top(), (mEnd - mStart) / mSpan * overview.width(),
                   overview.height());
  p.setPen(QColor("#a9c2ef"));
  p.setBrush(QColor(91, 143, 249, 40));
  p.drawRect(selection);
  p.setBrush(Qt::white);
  for (double x : {selection.left(), selection.right()})
    p.drawRoundedRect(
        QRectF(x - 3, overview.top() + 2, 6, overview.height() - 4), 2, 2);
  if (mSeries.isEmpty()) {
    p.setPen(QColor("#8c8c8c"));
    p.drawText(area, Qt::AlignCenter, QStringLiteral("暂无采样数据"));
  }
}

void MemoryPlot::paint(QPainter *painter) {
  const double dpr = window() ? window()->devicePixelRatio() : 1;
  const QSize size(qCeil(width() * dpr), qCeil(height() * dpr));
  if (size.isEmpty())
    return;
  if (mDirty || mCache.size() != size) {
    mCache = QImage(size, QImage::Format_ARGB32_Premultiplied);
    mCache.setDevicePixelRatio(dpr);
    mCache.fill(Qt::transparent);
    QPainter p(&mCache);
    draw(p);
    mDirty = false;
  }
  painter->drawImage(QPointF(0, 0), mCache);
  const auto area = plotRect();
  if (mHoverTime >= mStart && mHoverTime <= mEnd) {
    const double x =
        area.left() + (mHoverTime - mStart) / (mEnd - mStart) * area.width();
    painter->setPen(QPen(QColor("#8c8c8c"), 1, Qt::DashLine));
    painter->drawLine(QPointF(x, area.top()), QPointF(x, area.bottom()));
  }
}
void MemoryPlot::hoverAt(const QPointF &position) {
  const auto area = plotRect();
  if (!area.contains(position) || mReports.isEmpty() || !mReports.first()) {
    mTooltip.clear();
    mHoverTime = -1;
    emit tooltipChanged();
    update();
    return;
  }
  const double time =
      mStart + (position.x() - area.left()) / area.width() * (mEnd - mStart);
  QVariantList items;
  QString heading;
  if (mReports.size() == 1) {
    auto *report = mReports.first().data();
    const int index = report->nearest(time);
    if (index < 0)
      return;
    const auto &sample = report->samples[index];
    mHoverTime = (sample["timestamp"].toDouble() -
                  report->samples.first()["timestamp"].toDouble()) /
                 1000;
    heading = QString::number(mHoverTime, 'f', 1) + " s · " +
              QDateTime::fromMSecsSinceEpoch(sample["timestamp"].toInteger())
                  .toString("HH:mm:ss.zzz");
    const double total = Report::value(sample, "Total");
    QList<QVariantMap> rows;
    for (int i = 0; i < report->categories().size(); ++i) {
      const auto name = report->categories()[i];
      if (mHidden.contains(name))
        continue;
      const double v = Report::value(sample, name);
      rows.append({{"name", name},
                   {"kb", v},
                   {"color", Report::color(name, i).name()},
                   {"percent", total > 0 ? v / total * 100 : 0}});
    }
    std::stable_sort(rows.begin(), rows.end(),
                     [](const auto &a, const auto &b) {
                       if (a["name"] == "Total")
                         return true;
                       if (b["name"] == "Total")
                         return false;
                       return a["kb"].toDouble() > b["kb"].toDouble();
                     });
    for (const auto &row : rows)
      items.append(row);
  } else {
    mHoverTime = time;
    heading = QString::number(time, 'f', 1) + " s";
    for (const auto &series : mSeries) {
      auto *r = series.report.data();
      if (!r || time < series.offset || time > series.offset + r->duration())
        continue;
      const auto index = r->nearest(time - series.offset);
      if (index < 0)
        continue;
      const auto &sample = r->samples[index];
      const bool exists = mMetric == "Total" || mMetric == "Private Dirty" ||
                          mMetric == "Swap Pss" || mMetric == "Heap Alloc" ||
                          sample["categories"].toObject().contains(mMetric);
      items.append(
          QVariantMap{{"name", series.label},
                      {"kb", exists ? QVariant(Report::value(sample, mMetric))
                                    : QVariant()},
                      {"color", series.color.name()},
                      {"percent", -1}});
    }
  }
  mTooltip = {{"x", position.x()},
              {"y", position.y()},
              {"heading", heading},
              {"items", items}};
  emit tooltipChanged();
  update();
}
void MemoryPlot::hoverMoveEvent(QHoverEvent *event) {
  if (!mDrag)
    hoverAt(event->position());
}
void MemoryPlot::hoverLeaveEvent(QHoverEvent *) {
  mTooltip.clear();
  mHoverTime = -1;
  emit tooltipChanged();
  update();
}
void MemoryPlot::wheelEvent(QWheelEvent *event) {
  if (!plotRect().contains(event->position()) &&
      !overviewRect().contains(event->position())) {
    event->ignore();
    return;
  }
  const auto delta = event->angleDelta();
  if (std::abs(delta.x()) > std::abs(delta.y()) ||
      event->modifiers().testFlag(Qt::ShiftModifier)) {
    const auto pan =
        (delta.x() ? delta.x() : delta.y()) / 600.0 * (mEnd - mStart);
    setRange(mStart - pan, mEnd - pan);
  } else {
    const auto fraction = std::clamp(
        (event->position().x() - plotRect().left()) / plotRect().width(), 0.0,
        1.0);
    const double span = (mEnd - mStart) * std::exp(-delta.y() / 800.0),
                 anchor = mStart + fraction * (mEnd - mStart);
    setRange(anchor - fraction * span, anchor + (1 - fraction) * span);
  }
  hoverAt(event->position());
  event->accept();
}
void MemoryPlot::mousePressEvent(QMouseEvent *event) {
  mPressed = event->position();
  mDragStart = mStart;
  mDragEnd = mEnd;
  const auto overview = overviewRect();
  if (overview.adjusted(-6, -4, 6, 4).contains(mPressed)) {
    const double left = overview.left() + mStart / mSpan * overview.width(),
                 right = overview.left() + mEnd / mSpan * overview.width();
    mDrag = std::abs(mPressed.x() - left) < 9    ? 2
            : std::abs(mPressed.x() - right) < 9 ? 3
                                                 : 4;
    if (mDrag == 4 && (mPressed.x() < left || mPressed.x() > right)) {
      const double center = (mPressed.x() - overview.left()) /
                            overview.width() * mSpan,
                   span = mEnd - mStart;
      setRange(center - span / 2, center + span / 2);
      mDragStart = mStart;
      mDragEnd = mEnd;
    }
  } else if (plotRect().contains(mPressed))
    mDrag = 1;
  if (mDrag)
    event->accept();
  else
    event->ignore();
}
void MemoryPlot::mouseMoveEvent(QMouseEvent *event) {
  if (!mDrag)
    return;
  const auto delta = event->position().x() - mPressed.x();
  if (mDrag == 1) {
    const auto d = -delta / plotRect().width() * (mDragEnd - mDragStart);
    setRange(mDragStart + d, mDragEnd + d);
  } else {
    const auto d = delta / overviewRect().width() * mSpan;
    if (mDrag == 2)
      setRange(std::min(mDragStart + d, mDragEnd - 2), mDragEnd);
    else if (mDrag == 3)
      setRange(mDragStart, std::max(mDragStart + 2, mDragEnd + d));
    else
      setRange(mDragStart + d, mDragEnd + d);
  }
}
void MemoryPlot::mouseReleaseEvent(QMouseEvent *event) {
  if (mDrag == 1 && (event->position() - mPressed).manhattanLength() < 4 &&
      !mReports.isEmpty() && mReports.first()) {
    const auto time = mStart + (event->position().x() - plotRect().left()) /
                                   plotRect().width() * (mEnd - mStart);
    emit pointSelected(mReports.first()->nearest(time));
  }
  mDrag = 0;
  hoverAt(event->position());
}
void MemoryPlot::geometryChange(const QRectF &next, const QRectF &old) {
  QQuickPaintedItem::geometryChange(next, old);
  invalidate();
}

#include "SnapshotPlot.h"
#include "Report.h"
#include <QHoverEvent>
#include <QPainter>
#include <algorithm>
#include <cmath>
#include <numbers>

SnapshotPlot::SnapshotPlot(QQuickItem *parent) : QQuickPaintedItem(parent) {
  setAntialiasing(true);
  setAcceptHoverEvents(true);
  connect(this, &SnapshotPlot::dataChanged, this, [this] { update(); });
}
QList<SnapshotPlot::Slice> SnapshotPlot::slices() const {
  QList<Slice> result;
  const auto cats = mSnapshot["categories"].toMap();
  for (auto it = cats.begin(); it != cats.end(); ++it) {
    const double value = it.value().toMap()["pssTotalKb"].toDouble();
    if (value > 10.24)
      result.append({it.key(), value, Report::color(it.key(), result.size())});
  }
  std::stable_sort(
      result.begin(), result.end(),
      [](const auto &a, const auto &b) { return a.value > b.value; });
  return result;
}
void SnapshotPlot::paint(QPainter *p) {
  p->setRenderHint(QPainter::Antialiasing);
  QFont font = p->font();
  font.setPixelSize(11);
  p->setFont(font);
  const auto rows = slices();
  double sum = 0;
  for (const auto &r : rows)
    sum += r.value;
  if (sum == 0) {
    p->setPen(QColor("#8c8c8c"));
    p->drawText(boundingRect(), Qt::AlignCenter, QStringLiteral("暂无数据"));
    return;
  }
  if (mMode == "bar") {
    const double left = std::min(135.0, width() * .3), right = width() - 56,
                 top = 12, bottom = height() - 24;
    const double line = (bottom - top) / std::max<qsizetype>(1, rows.size()),
                 maximum = rows.first().value;
    for (int i = 0; i < rows.size(); ++i) {
      const auto &r = rows[i];
      const double y = top + i * line;
      p->setPen(QColor("#595959"));
      p->drawText(QRectF(0, y, left - 10, line),
                  Qt::AlignRight | Qt::AlignVCenter, r.name);
      p->fillRect(QRectF(left, y + (line - std::min(18.0, line - 4)) / 2,
                         (right - left) * r.value / maximum,
                         std::min(18.0, line - 4)),
                  r.color);
      p->drawText(
          QRectF(left + (right - left) * r.value / maximum + 5, y, 55, line),
          Qt::AlignLeft | Qt::AlignVCenter,
          QString::number(r.value / 1024, 'f', 2));
    }
    p->drawText(QRectF(left, bottom + 4, right - left, 18), Qt::AlignCenter,
                "Pss (MB)");
    return;
  }
  const QPointF center(width() / 2, height() / 2);
  const double radius = std::min(width(), height()) * .29, inner = radius * .69;
  const QRectF circle(center.x() - radius, center.y() - radius, 2 * radius,
                      2 * radius);
  double angle = 90;
  for (const auto &r : rows) {
    const double degrees = r.value / sum * 360;
    p->setPen(Qt::NoPen);
    p->setBrush(r.color);
    p->drawPie(circle, int(angle * 16), -int(degrees * 16));
    if (r.value / sum >= .02) {
      const double radians = (angle - degrees / 2) * std::numbers::pi / 180;
      const double dir = std::cos(radians) >= 0 ? 1 : -1;
      const QPointF edge(center.x() + radius * std::cos(radians),
                         center.y() - radius * std::sin(radians));
      const QPointF bend(center.x() + (radius + 14) * std::cos(radians),
                         center.y() - (radius + 14) * std::sin(radians));
      const QPointF end(bend.x() + dir * 12, bend.y());
      p->setPen(QColor("#bfbfbf"));
      p->drawLine(edge, bend);
      p->drawLine(bend, end);
      const double labelWidth = std::max(
          40.0, std::min(120.0, dir > 0 ? width() - end.x() - 3 : end.x() - 3));
      const QRectF label(dir > 0 ? end.x() + 3 : end.x() - labelWidth - 3,
                         end.y() - 15, labelWidth, 30);
      const int align = dir > 0 ? Qt::AlignLeft : Qt::AlignRight;
      p->setPen(QColor("#262626"));
      p->drawText(
          QRectF(label.x(), label.y(), label.width(), 15),
          align | Qt::AlignVCenter,
          p->fontMetrics().elidedText(r.name, Qt::ElideRight, label.width()));
      p->setPen(QColor("#8c8c8c"));
      p->drawText(QRectF(label.x(), label.y() + 15, label.width(), 15),
                  align | Qt::AlignVCenter,
                  QString::number(r.value / 1024, 'f', 1) + " MB · " +
                      QString::number(r.value / sum * 100, 'f', 1) + "%");
    }
    angle -= degrees;
  }
  p->setPen(Qt::NoPen);
  p->setBrush(Qt::white);
  p->drawEllipse(center, inner, inner);
  p->setPen(QColor("#8c8c8c"));
  p->drawText(QRectF(center.x() - inner, center.y() - 20, 2 * inner, 18),
              Qt::AlignCenter, "Total Pss");
  font.setPixelSize(13);
  font.setBold(true);
  p->setFont(font);
  p->setPen(QColor("#262626"));
  p->drawText(
      QRectF(center.x() - inner, center.y() + 2, 2 * inner, 20),
      Qt::AlignCenter,
      QString::number(
          mSnapshot["total"].toMap()["pssTotalKb"].toDouble() / 1024, 'f', 1) +
          " MB");
}
void SnapshotPlot::hoverMoveEvent(QHoverEvent *event) {
  const auto rows = slices();
  double sum = 0;
  for (const auto &r : rows)
    sum += r.value;
  int index = -1;
  if (mMode == "bar") {
    index = int((event->position().y() - 12) / (height() - 36) * rows.size());
  } else {
    const auto delta = event->position() - QPointF(width() / 2, height() / 2);
    const double distance = std::hypot(delta.x(), delta.y()),
                 radius = std::min(width(), height()) * .29;
    if (distance >= radius * .69 && distance <= radius) {
      double degrees =
          std::atan2(delta.x(), -delta.y()) * 180 / std::numbers::pi;
      if (degrees < 0)
        degrees += 360;
      double end = 0;
      for (int i = 0; i < rows.size(); ++i) {
        end += rows[i].value / sum * 360;
        if (degrees <= end) {
          index = i;
          break;
        }
      }
    }
  }
  if (index < 0 || index >= rows.size()) {
    hoverLeaveEvent(nullptr);
    return;
  }
  const auto &r = rows[index];
  mTooltip = {{"x", event->position().x()},
              {"y", event->position().y()},
              {"heading", r.name},
              {"items", QVariantList{QVariantMap{
                            {"name", "Pss"},
                            {"kb", r.value},
                            {"color", r.color.name()},
                            {"percent", sum > 0 ? r.value / sum * 100 : 0}}}}};
  emit tooltipChanged();
}
void SnapshotPlot::hoverLeaveEvent(QHoverEvent *) {
  mTooltip.clear();
  emit tooltipChanged();
}

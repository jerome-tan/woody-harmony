#include "SnapshotPlot.h"
#include "Report.h"
#include <QHoverEvent>
#include <QPainter>
#include <algorithm>
#include <cmath>
#include <numbers>

namespace {
QString displayCategory(const QString &name) {
  if (name == "native heap") return "Native heap";
  if (name == "ark ts heap") return "ArkTS heap";
  if (name == "stack") return "Stack";
  return name;
}
} // namespace

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
    if (value > 0)
      result.append({it.key(), value, Report::color(it.key(), result.size())});
  }
  std::stable_sort(
      result.begin(), result.end(),
      [](const auto &a, const auto &b) { return a.value > b.value; });
  if (result.size() > 6) {
    double other = 0;
    for (int i = 5; i < result.size(); ++i) other += result[i].value;
    result = result.mid(0, 5);
    result.append({QStringLiteral("其他分类"), other, QColor("#9CA3AF")});
  }
  return result;
}
void SnapshotPlot::paint(QPainter *p) {
  p->setRenderHint(QPainter::Antialiasing);
  QFont font = p->font();
  font.setPixelSize(12);
  p->setFont(font);
  const auto rows = slices();
  double sum = 0;
  for (const auto &r : rows)
    sum += r.value;
  if (sum == 0) {
    p->setPen(QColor("#665E73"));
    p->drawText(boundingRect(), Qt::AlignCenter, QStringLiteral("暂无数据"));
    return;
  }
  if (mMode == "bar") {
    const double left = std::min(135.0, width() * .3), right = width() - 146,
                 top = 12, bottom = height() - 24;
    const double line = (bottom - top) / std::max<qsizetype>(1, rows.size()),
                 maximum = std::max_element(rows.begin(), rows.end(), [](const auto &a, const auto &b) { return a.value < b.value; })->value;
    for (int i = 0; i < rows.size(); ++i) {
      const auto &r = rows[i];
      const double y = top + i * line;
      p->setPen(QColor("#665E73"));
      p->drawText(QRectF(0, y, left - 10, line),
                  Qt::AlignRight | Qt::AlignVCenter, displayCategory(r.name));
      p->fillRect(QRectF(left, y + (line - std::min(18.0, line - 4)) / 2,
                         (right - left) * r.value / maximum,
                         std::min(18.0, line - 4)),
                  r.color);
      p->drawText(
          QRectF(left + (right - left) * r.value / maximum + 6, y, 140, line),
          Qt::AlignLeft | Qt::AlignVCenter,
          QString::number(r.value / 1024, 'f', 1) + " MB  " + QString::number(r.value / sum * 100, 'f', 1) + "%");
    }
    p->drawText(QRectF(left, bottom + 4, right - left, 18), Qt::AlignCenter,
                "Pss (MB)");
    return;
  }
  const QPointF center(width() / 2, height() / 2);
  const double radius = std::min(width(), height()) * .29, inner = radius * .69;
  const QRectF circle(center.x() - radius, center.y() - radius, 2 * radius,
                      2 * radius);
  struct Label {
    Slice slice;
    QPointF edge;
    double y;
    bool right;
  };
  QList<Label> labels;
  double angle = 90;
  for (const auto &r : rows) {
    const double degrees = r.value / sum * 360;
    p->setPen(Qt::NoPen);
    p->setBrush(r.color);
    p->drawPie(circle, int(angle * 16), -int(degrees * 16));
    if (r.value / sum >= .02) {
      const double radians = (angle - degrees / 2) * std::numbers::pi / 180;
      labels.append({r,
                     {center.x() + radius * std::cos(radians),
                      center.y() - radius * std::sin(radians)},
                     center.y() - (radius + 14) * std::sin(radians),
                     std::cos(radians) >= 0});
    }
    angle -= degrees;
  }
  // Relax each side independently, preserving angular order so leader lines do
  // not cross.
  for (bool right : {false, true}) {
    QList<Label *> side;
    for (auto &label : labels)
      if (label.right == right)
        side.append(&label);
    std::sort(side.begin(), side.end(),
              [](auto a, auto b) { return a->y < b->y; });
    const double spacing =
        std::min(24.0, (height() - 32) / std::max<qsizetype>(1, side.size()));
    double previous = 16 - spacing;
    for (auto *label : side) {
      label->y = std::max(previous + spacing, label->y);
      previous = label->y;
    }
    if (!side.isEmpty() && side.last()->y > height() - 16) {
      side.last()->y = height() - 16;
      for (int i = side.size() - 2; i >= 0; --i)
        side[i]->y = std::min(side[i]->y, side[i + 1]->y - spacing);
    }
    for (const auto *label : side) {
      const double direction = right ? 1 : -1;
      const QPointF end(center.x() + direction * (radius + 12), label->y);
      const QPointF bend(end.x() - direction * 12, label->y);
      p->setPen(QColor("#bfbfbf"));
      p->drawLine(label->edge, bend);
      p->drawLine(bend, end);
      const double available =
          std::max(0.0, right ? width() - end.x() - 7 : end.x() - 7);
      const QString value = QString::number(label->slice.value / 1024, 'f', 1) +
                            " MB · " + QString::number(label->slice.value / sum * 100, 'f', 1) + "%";
      const QFontMetricsF metrics(p->font());
      const QString detail = metrics.elidedText(value, Qt::ElideRight, available);
      const double detailWidth = metrics.horizontalAdvance(detail);
      const QString name = metrics.elidedText(displayCategory(label->slice.name),
                                              Qt::ElideRight, std::max(0.0, available - detailWidth - 6));
      const double nameWidth = metrics.horizontalAdvance(name);
      const double gap = name.isEmpty() ? 0 : 6;
      const double x = right ? end.x() + 3
                             : end.x() - 3 - nameWidth - gap - detailWidth;
      const double baseline = label->y + (metrics.ascent() - metrics.descent()) / 2;
      p->setPen(QColor("#241D35"));
      p->drawText(QPointF(x, baseline), name);
      p->setPen(QColor("#665E73"));
      p->drawText(QPointF(x + nameWidth + gap, baseline), detail);
    }
  }
  p->setPen(Qt::NoPen);
  p->setBrush(Qt::white);
  p->drawEllipse(center, inner, inner);
  p->setPen(QColor("#665E73"));
  p->drawText(QRectF(center.x() - inner, center.y() - 20, 2 * inner, 18),
              Qt::AlignCenter, "Total Pss");
  font.setPixelSize(13);
  font.setBold(true);
  p->setFont(font);
  p->setPen(QColor("#241D35"));
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

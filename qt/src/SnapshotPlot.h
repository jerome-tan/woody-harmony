#pragma once
#include <QQuickPaintedItem>
#include <QVariantMap>

class SnapshotPlot : public QQuickPaintedItem {
  Q_OBJECT
  Q_PROPERTY(QVariantMap snapshot MEMBER mSnapshot NOTIFY dataChanged)
  Q_PROPERTY(QString mode MEMBER mMode NOTIFY dataChanged)
  Q_PROPERTY(QVariantMap tooltip READ tooltip NOTIFY tooltipChanged)
public:
  explicit SnapshotPlot(QQuickItem *parent = nullptr);
  QVariantMap tooltip() const { return mTooltip; }
  void paint(QPainter *painter) override;
signals:
  void dataChanged();
  void tooltipChanged();

protected:
  void hoverMoveEvent(QHoverEvent *event) override;
  void hoverLeaveEvent(QHoverEvent *) override;

private:
  struct Slice {
    QString name;
    double value;
    QColor color;
  };
  QList<Slice> slices() const;
  QVariantMap mSnapshot, mTooltip;
  QString mMode = "pie";
};

#pragma once
#include "Report.h"
#include <QImage>
#include <QPointer>
#include <QQuickPaintedItem>

// A native, dependency-free plot. Samples remain exact; no downsampling changes
// peaks or tooltips.
class MemoryPlot : public QQuickPaintedItem {
  Q_OBJECT
  Q_PROPERTY(
      QVariantList reports READ reports WRITE setReports NOTIFY optionsChanged)
  Q_PROPERTY(QString metric MEMBER mMetric NOTIFY optionsChanged)
  Q_PROPERTY(QString alignment MEMBER mAlignment NOTIFY optionsChanged)
  Q_PROPERTY(QStringList hiddenCategories MEMBER mHidden NOTIFY optionsChanged)
  Q_PROPERTY(QString highlight MEMBER mHighlight NOTIFY optionsChanged)
  Q_PROPERTY(bool smooth MEMBER mSmooth NOTIFY optionsChanged)
  Q_PROPERTY(bool points MEMBER mPoints NOTIFY optionsChanged)
  Q_PROPERTY(bool live MEMBER mLive NOTIFY optionsChanged)
  Q_PROPERTY(bool compact MEMBER mCompact NOTIFY optionsChanged)
  Q_PROPERTY(int selectedIndex MEMBER mSelected NOTIFY optionsChanged)
  Q_PROPERTY(bool following READ following NOTIFY rangeChanged)
  Q_PROPERTY(double rangeStart READ rangeStart NOTIFY rangeChanged)
  Q_PROPERTY(double rangeEnd READ rangeEnd NOTIFY rangeChanged)
  Q_PROPERTY(double totalSpan READ totalSpan NOTIFY rangeChanged)
  Q_PROPERTY(QVariantMap tooltip READ tooltip NOTIFY tooltipChanged)
public:
  explicit MemoryPlot(QQuickItem *parent = nullptr);
  QVariantList reports() const;
  void setReports(const QVariantList &value);
  bool following() const { return mFollowing; }
  double rangeStart() const { return mStart; }
  double rangeEnd() const { return mEnd; }
  double totalSpan() const { return mSpan; }
  QVariantMap tooltip() const { return mTooltip; }
  Q_INVOKABLE void resetView();
  Q_INVOKABLE void followLatest();
  Q_INVOKABLE void setRange(double start, double end);
  void paint(QPainter *painter) override;
signals:
  void optionsChanged();
  void rangeChanged();
  void tooltipChanged();
  void pointSelected(int index);

protected:
  void hoverMoveEvent(QHoverEvent *event) override;
  void hoverLeaveEvent(QHoverEvent *event) override;
  void wheelEvent(QWheelEvent *event) override;
  void mousePressEvent(QMouseEvent *event) override;
  void mouseMoveEvent(QMouseEvent *event) override;
  void mouseReleaseEvent(QMouseEvent *event) override;
  void geometryChange(const QRectF &next, const QRectF &old) override;

private:
  struct Series {
    QString label, metric;
    QColor color;
    QPointer<Report> report;
    QVector<QPointF> points;
    int peak = -1;
    double offset = 0;
  };
  void rebuild();
  void invalidate();
  void hoverAt(const QPointF &position);
  void draw(QPainter &painter);
  QRectF plotRect() const;
  QRectF overviewRect() const;
  QList<QPointer<Report>> mReports;
  QList<Series> mSeries;
  QString mMetric = "Total", mAlignment = "start", mHighlight;
  QStringList mHidden;
  bool mSmooth = false, mPoints = true, mLive = false, mCompact = false,
       mFollowing = true;
  int mSelected = -1, mDrag = 0;
  double mStart = 0, mEnd = 2, mSpan = 2, mHoverTime = -1;
  QPointF mPressed;
  double mDragStart = 0, mDragEnd = 0;
  QVariantMap mTooltip;
  QImage mCache;
  bool mDirty = true;
};

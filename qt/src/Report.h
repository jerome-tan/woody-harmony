#pragma once
#include <QColor>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QVariant>

class Report : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantMap meta READ meta NOTIFY changed)
  Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY changed)
  Q_PROPERTY(QVariantMap stats READ stats NOTIFY changed)
  Q_PROPERTY(QStringList categories READ categories NOTIFY changed)
  Q_PROPERTY(int count READ count NOTIFY changed)
  Q_PROPERTY(double duration READ duration NOTIFY changed)
  Q_PROPERTY(QString compareColor MEMBER compareColor NOTIFY changed)
public:
  explicit Report(QObject *parent = nullptr) : QObject(parent) {}
  QJsonObject metadata;
  QJsonObject snapshotData;
  QString compareColor;
  QList<QJsonObject> samples;
  QVariantMap meta() const { return metadata.toVariantMap(); }
  QVariantMap snapshot() const { return snapshotData.toVariantMap(); }
  QVariantMap stats() const;
  QStringList categories() const;
  int count() const { return samples.size(); }
  double duration() const;
  void load(const QJsonObject &data);
  void append(const QJsonObject &sample);
  void reset();
  Q_INVOKABLE QVariantMap sampleAt(int index) const;
  Q_INVOKABLE int nearest(double seconds) const;
  Q_INVOKABLE int peakIndex(const QString &metric = "Total") const;
  static double value(const QJsonObject &sample, const QString &metric);
  static QColor color(const QString &category, int index = 0);
signals:
  void changed();
};

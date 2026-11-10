#pragma once
#include <QImage>
#include <QObject>
#include <QUrl>
#include <QVariant>

// A document renderer, not a window grab. No screen size / scroll-position dependency.
class ComparisonImageExporter : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
public:
  explicit ComparisonImageExporter(QObject *parent = nullptr) : QObject(parent) {}
  QString error() const { return mError; }
  Q_INVOKABLE QUrl defaultFile() const;
  Q_INVOKABLE bool prepare(const QVariantList &reports, const QVariantMap &options);
  Q_INVOKABLE bool copy();
  Q_INVOKABLE bool save(const QUrl &url);
  Q_INVOKABLE void clear() { mImage = QImage(); }
signals:
  void errorChanged();
private:
  bool fail(const QString &message);
  QImage mImage;
  QString mError;
};

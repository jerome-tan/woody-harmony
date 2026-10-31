#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>
#include <QStringList>
#include <atomic>
#include <memory>

class HdcClient {
public:
  QString binary;
  QString target;
  std::shared_ptr<std::atomic_bool> cancelled;
  static QString detect(const QString &configured = {});
  QString run(const QStringList &arguments, int timeoutMs = 20000,
              bool useTarget = true) const;
  QString shell(const QString &command, int timeoutMs = 20000) const;
  QJsonArray devices() const;
  QJsonArray apps() const;
  QJsonObject deviceInfo() const;
  qint64 pid(const QString &bundle) const;
  static void validateBundle(const QString &bundle);

private:
  QString parameter(const QString &name) const;
};

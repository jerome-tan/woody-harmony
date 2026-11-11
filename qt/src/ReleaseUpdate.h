#pragma once
#include <QJsonObject>
#include <QUrl>

namespace ReleaseUpdate {
struct Release {
  QString version, notes, assetName;
  QUrl page, asset, checksums;
  qint64 size = 0;
};
bool newer(const QString &candidate, const QString &current);
Release parse(const QJsonObject &json, const QString &current,
              const QString &platform, const QString &arch, bool installed);
QByteArray checksum(const QByteArray &text, const QString &asset);
}

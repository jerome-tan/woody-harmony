#include "ReleaseUpdate.h"
#include <QJsonArray>
#include <QRegularExpression>
#include <QVersionNumber>
#include <stdexcept>

namespace ReleaseUpdate {
static QVersionNumber version(QString value) {
  if (value.startsWith('v')) value.remove(0, 1);
  static const QRegularExpression pattern("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$");
  if (!pattern.match(value).hasMatch()) throw std::runtime_error("版本号不是正式版本 major.minor.patch");
  const auto result = QVersionNumber::fromString(value);
  if (result.segmentCount() != 3) throw std::runtime_error("版本号无效");
  return result;
}
bool newer(const QString &candidate, const QString &current) {
  return QVersionNumber::compare(version(candidate), version(current)) > 0;
}
Release parse(const QJsonObject &json, const QString &current, const QString &platform,
              const QString &arch, bool installed) {
  Release result;
  if (json.value("draft").toBool() || json.value("prerelease").toBool()) return result;
  const QString tag = json.value("tag_name").toString();
  if (!tag.startsWith('v')) throw std::runtime_error("Release 标签必须以 v 开头");
  if (!newer(tag, current)) return result;
  result.version = tag.mid(1);
  result.notes = json.value("body").toString();
  result.page = QUrl("https://github.com/jerome-tan/woody-harmony/releases/tag/" + tag);
  result.assetName = QString("Woody-%1-qt-%2-%3-%4").arg(result.version, platform, arch,
      platform == "win" && installed ? "setup.exe" : "portable.zip");
  const QString prefix = "https://github.com/jerome-tan/woody-harmony/releases/download/" + tag + '/';
  for (const auto &entry : json.value("assets").toArray()) {
    const auto asset = entry.toObject();
    const QString name = asset.value("name").toString();
    if (name != result.assetName && name != "SHA256SUMS.txt") continue;
    if (asset.value("browser_download_url").toString() != prefix + name
        || asset.value("state").toString() != "uploaded")
      throw std::runtime_error("Release 下载地址或附件状态无效");
    if (name == "SHA256SUMS.txt") result.checksums = QUrl(prefix + name);
    else {
      result.asset = QUrl(prefix + name);
      result.size = asset.value("size").toInteger();
    }
  }
  if (result.asset.isEmpty() || result.checksums.isEmpty() || result.size <= 0 || result.size > 1024LL*1024*1024)
    throw std::runtime_error("此 Release 缺少当前平台的完整安装包或 SHA256SUMS.txt");
  return result;
}
QByteArray checksum(const QByteArray &text, const QString &asset) {
  QByteArray result;
  const QRegularExpression linePattern("^([0-9a-fA-F]{64}) [ *](.+)$");
  for (const auto &line : QString::fromUtf8(text).split('\n')) {
    const auto match = linePattern.match(line.trimmed());
    if (match.hasMatch() && match.captured(2) == asset) {
      if (!result.isEmpty()) throw std::runtime_error("校验文件包含重复附件");
      result = match.captured(1).toLatin1().toLower();
    }
  }
  if (result.isEmpty()) throw std::runtime_error("校验文件缺少下载附件的 SHA-256");
  return result;
}
}

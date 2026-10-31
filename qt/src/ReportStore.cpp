#include "ReportStore.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QMutex>
#include <QSaveFile>
#include <algorithm>
#include <stdexcept>

namespace {
[[noreturn]] void fail(const QString &text) {
  throw std::runtime_error(text.toStdString());
}
} // namespace

QJsonObject ReportStore::readObject(const QString &file) {
  QFile input(file);
  if (!input.open(QIODevice::ReadOnly))
    fail(QStringLiteral("无法读取 %1：%2").arg(file, input.errorString()));
  QJsonParseError error;
  const auto document = QJsonDocument::fromJson(input.readAll(), &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    fail(QStringLiteral("文件已损坏（不是合法 JSON 对象）：%1").arg(file));
  return document.object();
}

void ReportStore::writeObject(const QString &file, const QJsonObject &value) {
  QDir().mkpath(QFileInfo(file).absolutePath());
  QSaveFile output(file);
  const auto data = QJsonDocument(value).toJson(QJsonDocument::Indented);
  if (!output.open(QIODevice::WriteOnly) || output.write(data) != data.size() ||
      !output.commit())
    fail(QStringLiteral("保存失败 %1：%2").arg(file, output.errorString()));
}

void ReportStore::writeText(const QString &file, const QByteArray &text,
                            bool append) {
  QDir().mkpath(QFileInfo(file).absolutePath());
  QFile output(file);
  if (!output.open(QIODevice::WriteOnly |
                   (append ? QIODevice::Append : QIODevice::Truncate)) ||
      output.write(text) != text.size())
    fail(QStringLiteral("保存失败 %1：%2").arg(file, output.errorString()));
}

QJsonObject ReportStore::load(const QString &directory) {
  const QDir root(directory);
  if (!root.exists())
    fail(QStringLiteral("所选目录不存在或不可访问"));
  if (!root.exists("meta.json"))
    fail(QStringLiteral("所选目录不是有效的报告目录（缺少 "
                        "meta.json），请选择单个报告目录，而不是输出根目录"));
  auto meta = readObject(root.filePath("meta.json"));
  meta["sessionDir"] = root.absolutePath();
  QJsonArray samples;
  QFile lines(root.filePath("samples.jsonl"));
  if (lines.open(QIODevice::ReadOnly)) {
    while (!lines.atEnd()) {
      const auto line = lines.readLine().trimmed();
      if (line.isEmpty())
        continue;
      QJsonParseError error;
      const auto sample = QJsonDocument::fromJson(line, &error);
      // Match the existing reader: a malformed JSONL report has no usable
      // samples.
      if (error.error != QJsonParseError::NoError || !sample.isObject()) {
        samples = {};
        break;
      }
      samples.append(sample.object());
    }
  }
  QJsonValue snapshot = QJsonValue::Null;
  if (meta.value("type") == "snapshot") {
    try {
      snapshot = readObject(root.filePath("snapshot.json"));
    } catch (const std::exception &) {
    }
  }
  return {{"meta", meta}, {"samples", samples}, {"snapshot", snapshot}};
}

QJsonArray ReportStore::list(const QString &root) {
  QList<QJsonObject> records;
  for (const auto &entry : QDir(root).entryInfoList(
           QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks)) {
    try {
      auto meta = readObject(entry.absoluteFilePath() + "/meta.json");
      meta["sessionDir"] = entry.absoluteFilePath();
      records.append(meta);
    } catch (const std::exception &) {
    }
  }
  std::stable_sort(records.begin(), records.end(),
                   [](const auto &a, const auto &b) {
                     return a.value("startedAt").toDouble() >
                            b.value("startedAt").toDouble();
                   });
  QJsonArray result;
  for (const auto &record : records)
    result.append(record);
  return result;
}

QString ReportStore::rawFileName(const QString &bundle, qint64 timestamp) {
  return QDateTime::fromMSecsSinceEpoch(timestamp).toString(
             "yyyyMMdd-HHmmss.zzz-") +
         bundle + ".txt";
}

void ReportStore::updateMetadata(const QString &directory,
                                 const QJsonObject &changes) {
  // Stop/finalize and rename can finish on different worker threads; merge
  // their fields atomically.
  static QMutex mutex;
  const QMutexLocker lock(&mutex);
  auto meta = readObject(QDir(directory).filePath("meta.json"));
  for (auto it = changes.begin(); it != changes.end(); ++it)
    meta[it.key()] = it.value();
  writeObject(QDir(directory).filePath("meta.json"), meta);
}
void ReportStore::rename(const QString &directory, const QString &name) {
  if (name.trimmed().isEmpty())
    fail(QStringLiteral("任务名称不能为空"));
  updateMetadata(directory, {{"taskName", name.trimmed()}});
}

void ReportStore::remove(const QString &directory,
                         const QString &lockedDirectory) {
  const auto info = QFileInfo(directory);
  if (directory.isEmpty() || info.isSymLink() || !info.isDir() ||
      !QFileInfo::exists(directory + "/meta.json"))
    fail(QStringLiteral("所选目录不是有效的报告目录"));
  if (!lockedDirectory.isEmpty() &&
      info.canonicalFilePath() ==
          QFileInfo(lockedDirectory).canonicalFilePath())
    fail(QStringLiteral("该记录正在采样中，无法删除"));
  if (!QDir(directory).removeRecursively())
    fail(QStringLiteral("删除报告失败，请检查文件权限"));
}

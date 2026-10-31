#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QString>

namespace ReportStore {
QJsonObject readObject(const QString &file);
void writeObject(const QString &file, const QJsonObject &value);
void writeText(const QString &file, const QByteArray &text,
               bool append = false);
QJsonObject load(const QString &directory);
QJsonArray list(const QString &root);
QString rawFileName(const QString &bundle, qint64 timestamp);
void rename(const QString &directory, const QString &name);
void remove(const QString &directory, const QString &lockedDirectory);
} // namespace ReportStore

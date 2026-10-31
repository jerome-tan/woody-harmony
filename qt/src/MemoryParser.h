#pragma once
#include <QJsonObject>
#include <QString>

namespace MemoryParser {
QJsonObject zeroValues();
QJsonObject processMemory(const QString &raw);
QJsonObject systemMemory(const QString &raw);
QJsonObject procMeminfo(const QString &raw);
QJsonObject details(const QString &raw);
} // namespace MemoryParser

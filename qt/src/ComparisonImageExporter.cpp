#include "ComparisonImageExporter.h"
#include "MemoryPlot.h"
#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QPainter>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>

namespace {
const QColor ink("#241D35"), muted("#665E73"), border("#E7E2EF"),
    chrome("#F8F7FC"), selected("#EDE9FE");
QFont font(int pixels = 14, bool bold = false) {
  auto f = QGuiApplication::font();
  f.setPixelSize(pixels);
  f.setWeight(bold ? QFont::DemiBold : QFont::Normal);
  return f;
}
qreal textHeight(const QString &text, qreal width, int size = 14, bool bold = false) {
  return QFontMetricsF(font(size, bold))
      .boundingRect(QRectF(0, 0, width, 100000), Qt::TextWrapAnywhere, text).height();
}
void text(QPainter &p, const QRectF &rect, const QString &value,
          QColor color = ink, int size = 14, bool bold = false,
          Qt::Alignment align = Qt::AlignLeft | Qt::AlignVCenter) {
  p.setFont(font(size, bold));
  p.setPen(color);
  p.drawText(rect, int(align) | Qt::TextWrapAnywhere, value);
}
void plot(QPainter &p, const QRectF &rect, const QVariantList &reports,
          const QVariantMap &options, int index = -1) {
  MemoryPlot chart;
  chart.setWidth(rect.width());
  chart.setHeight(rect.height());
  chart.setProperty("comparison", true);
  chart.setProperty("compact", index >= 0);
  chart.setProperty("points", false);
  chart.setProperty("metric", index >= 0 ? "Total" : options.value("metric", "Total"));
  chart.setProperty("alignment", options.value("alignment", "start"));
  if (index >= 0)
    chart.setProperty("selectedIndex", options.value("indices").toList().value(index, -1));
  chart.setReports(reports);
  p.save();
  p.translate(rect.topLeft());
  p.setClipRect(QRectF(0, 0, rect.width(), rect.height()));
  chart.renderContent(&p);
  p.restore();
}
} // namespace

bool ComparisonImageExporter::fail(const QString &message) {
  mError = message;
  emit errorChanged();
  return false;
}
QUrl ComparisonImageExporter::defaultFile() const {
  auto directory = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
  if (!QDir(directory).exists()) directory = QDir::homePath();
  return QUrl::fromLocalFile(QDir(directory).filePath(
      "Woody-compare-" + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss") + ".png"));
}
bool ComparisonImageExporter::prepare(const QVariantList &reports, const QVariantMap &options) {
  clear();
  mError.clear();
  emit errorChanged();
  const auto rows = options.value("rows").toList();
  const auto headers = options.value("headers").toList();
  const auto names = options.value("names").toStringList();
  const auto indices = options.value("indices").toList();
  const QString mode = options.value("mode").toString();
  if (reports.isEmpty() || reports.size() > 4 || headers.isEmpty() || rows.isEmpty())
    return fail(QStringLiteral("没有可导出的对比数据"));
  for (const auto &value : reports)
    if (!qobject_cast<Report *>(value.value<QObject *>()) && !value.value<Report *>())
      return fail(QStringLiteral("报告已关闭，请重新打开后导出"));

  constexpr int width = 1440, margin = 24, gap = 12, scale = 2;
  const int count = reports.size();
  const qreal contentWidth = width - margin * 2;
  const qreal chartWidth = (contentWidth - gap * (count - 1)) / count;
  qreal headingHeight = 48;
  for (int i = 0; i < count; ++i)
    headingHeight = std::max(headingHeight, textHeight(names.value(i), chartWidth - 36, 14, true) + 18);
  // Export height expands for long report names and every table row.
  qreal y = 76;
  qreal chartBottom = y;
  if (mode == "picked") chartBottom += headingHeight + 28 + 234 + 12;
  else if (mode == "overlay") chartBottom += headingHeight + 344;
  else chartBottom += headingHeight;
  qreal tableY = chartBottom + 20;
  QList<qreal> widths;
  qreal sum = 0;
  for (const auto &h : headers) sum += std::max(1.0, h.toMap().value("width", 150).toDouble());
  qreal headerHeight = 48;
  for (const auto &h : headers) {
    const auto c = h.toMap();
    const qreal w = contentWidth * std::max(1.0, c.value("width", 150).toDouble()) / sum;
    widths.append(w);
    headerHeight = std::max(headerHeight, textHeight(c.value("text").toString(), w - 24, 14, true) + 20);
  }
  QList<qreal> heights;
  qreal totalHeight = tableY + headerHeight + 48;
  for (const auto &value : rows) {
    const auto row = value.toMap();
    const auto cells = row.value("cells").toList();
    qreal height = 42;
    for (int i = 0; i < cells.size() && i < widths.size(); ++i) {
      const auto c = cells[i].toMap();
      qreal h = textHeight(c.value("text").toString(), widths[i] - 24, 14, row.value("fixed").toBool());
      if (!c.value("secondaryInline").toBool() && !c.value("secondary").toString().isEmpty())
        h += 4 + textHeight(c.value("secondary").toString(), widths[i] - 24, 12);
      height = std::max(height, h + 14);
    }
    heights.append(height);
    totalHeight += height;
  }
  const qint64 pixels = qint64(width * scale) * qCeil(totalHeight * scale);
  if (pixels > 64000000 || totalHeight > 16000)
    return fail(QStringLiteral("完整图片过大，请减少参与对比的报告或分类后重试"));
  mImage = QImage(width * scale, qCeil(totalHeight * scale), QImage::Format_ARGB32_Premultiplied);
  if (mImage.isNull()) return fail(QStringLiteral("图片内存不足，无法导出"));
  mImage.fill(Qt::white);
  QPainter p(&mImage);
  p.scale(scale, scale);
  p.setRenderHint(QPainter::Antialiasing);
  text(p, QRectF(margin, 20, 600, 28), "Woody · " + options.value("title").toString(), ink, 20, true);
  text(p, QRectF(margin, 48, contentWidth, 20),
       QStringLiteral("基准：") + names.value(options.value("baseline").toInt()) +
       (mode == "overlay" ? QStringLiteral("  ·  指标：") + options.value("metric").toString() : QString()), muted, 12);
  for (int i = 0; i < count; ++i) {
    const qreal x = margin + i * (chartWidth + gap);
    p.setPen(border); p.setBrush(mode == "picked" ? Qt::white : chrome);
    p.drawRoundedRect(QRectF(x, y, chartWidth, mode == "picked" ? chartBottom - y : headingHeight), 6, 6);
    auto *identity = qobject_cast<Report *>(reports[i].value<QObject *>());
    if (!identity) identity = reports[i].value<Report *>();
    const QColor reportColor(identity->compareColor.isEmpty() ? Report::comparisonColor(i).name() : identity->compareColor);
    p.setPen(Qt::NoPen); p.setBrush(reportColor);
    p.drawEllipse(QPointF(x + 14, y + 22), 5, 5);
    text(p, QRectF(x + 26, y + 8, chartWidth - 36, headingHeight - 12), names.value(i), reportColor.darker(125), 14, true);
    if (mode != "picked") continue;
    auto *r = qobject_cast<Report *>(reports[i].value<QObject *>());
    if (!r) r = reports[i].value<Report *>();
    const int index = indices.value(i, -1).toInt();
    const auto sample = r->sampleAt(index);
    const auto elapsed = (sample.value("timestamp").toLongLong() - r->metadata.value("startedAt").toInteger()) / 1000.;
    const QString point = index < 0 ? QStringLiteral("无有效采样点") :
        QStringLiteral("采样点 %1  ·  %2 s").arg(index + 1).arg(elapsed, 0, 'f', 1);
    text(p, QRectF(x + 12, y + headingHeight, chartWidth - 24, 24), point, muted, 12);
    plot(p, QRectF(x + 6, y + headingHeight + 28, chartWidth - 12, 234), {reports[i]}, options, i);
  }
  if (mode == "overlay")
    plot(p, QRectF(margin, y + headingHeight + 8, contentWidth, 330), reports, options);

  p.fillRect(QRectF(margin, tableY, contentWidth, headerHeight), chrome);
  qreal x = margin;
  for (int i = 0; i < headers.size(); ++i) {
    const auto h = headers[i].toMap();
    p.fillRect(QRectF(x, tableY, widths[i], headerHeight), QColor(h.value("background", chrome.name()).toString()));
    text(p, QRectF(x + 12, tableY + 8, widths[i] - 24, headerHeight - 16), h.value("text").toString(), QColor(h.value("color", ink.name()).toString()), 14, true,
         (h.value("align") == "right" ? Qt::AlignRight : Qt::AlignLeft) | Qt::AlignVCenter);
    x += widths[i];
  }
  QStringList description{options.value("title").toString(), names.join("\n")};
  y = tableY + headerHeight;
  for (int ri = 0; ri < rows.size(); ++ri) {
    const auto row = rows[ri].toMap();
    const auto cells = row.value("cells").toList();
    const qreal h = heights[ri];
    if (row.value("fixed").toBool()) p.fillRect(QRectF(margin, y, contentWidth, h), selected);
    x = margin;
    QStringList line;
    for (int i = 0; i < cells.size() && i < widths.size(); ++i) {
      const auto cell = cells[i].toMap();
      const auto primary = cell.value("text").toString(), secondary = cell.value("secondary").toString();
      const auto align = (headers[i].toMap().value("align") == "right" ? Qt::AlignRight : Qt::AlignLeft) | Qt::AlignVCenter;
      if (cell.value("secondaryInline").toBool()) {
        const QFont primaryFont = font(14, row.value("fixed").toBool()), deltaFont = font(12);
        const QFontMetricsF primaryMetrics(primaryFont), deltaMetrics(deltaFont);
        const qreal gap = secondary.isEmpty() ? 0 : 6;
        const qreal deltaWidth = deltaMetrics.horizontalAdvance(secondary);
        const QString fitted = primaryMetrics.elidedText(primary, Qt::ElideRight,
            std::max(0.0, widths[i] - 24 - deltaWidth - gap));
        const qreal primaryWidth = primaryMetrics.horizontalAdvance(fitted);
        const qreal start = align.testFlag(Qt::AlignRight)
            ? x + widths[i] - 12 - primaryWidth - gap - deltaWidth : x + 12;
        const qreal baseline = y + (h - primaryMetrics.height()) / 2 + primaryMetrics.ascent();
        p.setFont(primaryFont); p.setPen(QColor(cell.value("color", ink.name()).toString()));
        p.drawText(QPointF(start, baseline), fitted);
        p.setFont(deltaFont); p.setPen(QColor(cell.value("secondaryColor", muted.name()).toString()));
        p.drawText(QPointF(start + primaryWidth + gap, baseline), secondary);
        line.append(primary + (secondary.isEmpty() ? QString() : " " + secondary));
        x += widths[i];
        continue;
      }
      const qreal firstHeight = textHeight(primary, widths[i] - 24, 14, row.value("fixed").toBool());
      const qreal secondHeight = secondary.isEmpty() ? 0 : textHeight(secondary, widths[i] - 24, 12) + 4;
      const qreal top = y + (h - firstHeight - secondHeight) / 2;
      text(p, QRectF(x + 12, top, widths[i] - 24, firstHeight), primary, QColor(cell.value("color", ink.name()).toString()), 14, row.value("fixed").toBool(), align);
      if (!secondary.isEmpty())
        text(p, QRectF(x + 12, top + firstHeight + 4, widths[i] - 24, secondHeight - 4), secondary, QColor(cell.value("secondaryColor", muted.name()).toString()), 12, false, align);
      line.append(primary + (secondary.isEmpty() ? QString() : "  " + secondary));
      x += widths[i];
    }
    description.append(line.join(" | "));
    p.setPen(border); p.drawLine(QPointF(margin, y + h), QPointF(width - margin, y + h));
    y += h;
  }
  text(p, QRectF(margin, y + 12, contentWidth, 20),
       QStringLiteral("Woody · %1 份报告 · %2 行 · 完整内容").arg(count).arg(rows.size()), muted, 12);
  p.end();
  mImage.setText("Description", description.join("\n"));
  return true;
}
bool ComparisonImageExporter::copy() {
  if (mImage.isNull()) return fail(QStringLiteral("请先生成对比图片"));
  QGuiApplication::clipboard()->setImage(mImage);
  return true;
}
bool ComparisonImageExporter::save(const QUrl &url) {
  if (mImage.isNull()) return fail(QStringLiteral("请先生成对比图片"));
  if (!url.isLocalFile()) return fail(QStringLiteral("请选择本地 PNG 文件"));
  QString path = url.toLocalFile();
  if (!path.endsWith(".png", Qt::CaseInsensitive)) path += ".png";
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly) || !mImage.save(&file, "PNG") || !file.commit())
    return fail(QStringLiteral("无法保存图片：") + file.errorString());
  return true;
}

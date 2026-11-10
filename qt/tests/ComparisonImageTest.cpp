#include "ComparisonImageExporter.h"
#include "Report.h"
#include <QTemporaryDir>
#include <QtTest>

class ComparisonImageTest : public QObject {
  Q_OBJECT
  Report a, b;
  QVariantMap options(int count) {
    QVariantList rows;
    for (int i = 0; i < count; ++i)
      rows.append(QVariantMap{{"fixed", i == 0}, {"cells", QVariantList{
          QVariantMap{{"text", i == count - 1 ? "LAST-CATEGORY" : QString("Category %1").arg(i)}},
          QVariantMap{{"text", "100.0 MB"}},
          QVariantMap{{"text", "120.0 MB"}, {"secondary", "+20.0 MB  +20.0%"}, {"secondaryColor", "#C43D50"}}}}});
    return {{"mode", "picked"}, {"title", "测试报告"}, {"baseline", 0},
            {"names", QStringList{"A · 很长的报告名称需要完整保留，不能因窗口宽度而裁切", "B · 对比报告"}},
            {"indices", QVariantList{1, 1}},
            {"headers", QVariantList{QVariantMap{{"text", "分类"}, {"width", 150}},
              QVariantMap{{"text", "A（基准）"}, {"width", 190}},
              QVariantMap{{"text", "B"}, {"width", 190}}}}, {"rows", rows}};
  }
private slots:
  void initTestCase() {
    for (auto *r : {&a, &b}) {
      r->metadata = {{"startedAt", 1000}, {"taskName", "测试"}};
      r->append(QJsonObject{{"timestamp", 1000}, {"pid", 1}, {"total", QJsonObject{{"pssTotalKb", 102400}}}});
      r->append(QJsonObject{{"timestamp", 2000}, {"pid", 1}, {"total", QJsonObject{{"pssTotalKb", 122880}}}});
      r->compareColor = Report::comparisonColor(r == &a ? 0 : 1).name();
    }
  }
  void fullContentAndSave() {
    ComparisonImageExporter exporter;
    const QVariantList reports{QVariant::fromValue(&a), QVariant::fromValue(&b)};
    QTemporaryDir directory;
    QVERIFY(exporter.prepare(reports, options(80)));
    const auto path = directory.filePath("完整图片.png");
    QVERIFY(exporter.save(QUrl::fromLocalFile(path)));
    QImage image(path);
    QCOMPARE(image.width(), 2880);
    QVERIFY(image.height() > 8000); // Far beyond the window; no viewport truncation.
    QVERIFY(image.text("Description").contains("LAST-CATEGORY"));
    QVERIFY(image.text("Description").contains("不能因窗口宽度而裁切"));
    // The final row actually has painted glyphs, not just metadata.
    int ink = 0;
    for (int y = image.height() - 170; y < image.height() - 100; ++y)
      for (int x = 48; x < image.width() - 48; ++x)
        if (qGray(image.pixel(x, y)) < 150) ++ink;
    QVERIFY(ink > 20);
    QVERIFY(!exporter.save(QUrl::fromLocalFile(directory.filePath("missing/image.png"))));
    QVERIFY(!exporter.error().isEmpty());
    QVERIFY(QImage(path) == image); // Failed save doesn't damage the earlier result.
    exporter.clear();
    QVERIFY(!exporter.save(QUrl::fromLocalFile(path)));
  }
  void reportColorsSurviveReorderingAndHiding() {
    ComparisonImageExporter exporter;
    QTemporaryDir directory;
    auto config = options(2);
    config["names"] = QStringList{"B", "A"};
    QVERIFY(exporter.prepare({QVariant::fromValue(&b), QVariant::fromValue(&a)}, config));
    const auto path = directory.filePath("reordered.png");
    QVERIFY(exporter.save(QUrl::fromLocalFile(path)));
    QCOMPARE(QImage(path).pixelColor(76, 196), Report::comparisonColor(1));
    config["names"] = QStringList{"B"};
    QVERIFY(exporter.prepare({QVariant::fromValue(&b)}, config));
    QVERIFY(exporter.save(QUrl::fromLocalFile(path)));
    QCOMPARE(QImage(path).pixelColor(76, 196), Report::comparisonColor(1));
  }
  void rejectInvalidAndOversize() {
    ComparisonImageExporter exporter;
    QVERIFY(!exporter.prepare({}, options(1)));
    QVERIFY(!exporter.copy());
    QVERIFY(!exporter.prepare({QVariant::fromValue(&a), QVariant::fromValue(&b)}, options(3000)));
    QVERIFY(!exporter.copy());
  }
};
QTEST_MAIN(ComparisonImageTest)
#include "ComparisonImageTest.moc"

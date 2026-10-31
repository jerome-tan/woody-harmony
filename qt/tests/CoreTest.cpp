#include "MemoryParser.h"
#include "ReportStore.h"
#include <QTemporaryDir>
#include <QtTest>
#include <stdexcept>

class CoreTest : public QObject {
  Q_OBJECT
private slots:
  void memoryRows() {
    const auto parsed =
        MemoryParser::processMemory("Total 120 1 2 3 4 5 6 7 8 9\r\n"
                                    "ark ts heap 45 0 0 0 0 0 0 0 0 0\n"
                                    "jemalloc meta 3 0 0 0 0 0 0 0 0 0\n"
                                    "PurgSum: 77 kB\nTotal Ashmem:8 kB\n");
    QCOMPARE(parsed["total"].toObject()["pssTotalKb"].toInt(), 120);
    QCOMPARE(parsed["categories"].toObject().size(), 1);
    QCOMPARE(parsed["nativeHeapDetail"].toObject().size(), 1);
    QCOMPARE(parsed["purgSumKb"].toInt(), 77);
    QCOMPARE(parsed["ashmemTotalKb"].toInt(), 8);
    QCOMPARE(MemoryParser::processMemory("")["total"].toObject(),
             MemoryParser::zeroValues());
  }
  void detailSections() {
    const auto details = MemoryParser::details(
        "DMA:\napp  22  3  4096  100  RenderXComponent\n"
        "Ashmem:\napp\t22\t4\t0\t22\tdev/ashmem/Create "
        "PixelMap\t8192\t2048\t0\n"
        "GPU:\nChannel:GL (Total memory: 1024)\nTotal used memory: 4096\nTotal "
        "allocated memory: 8192\n");
    QCOMPARE(
        details["dmabuf"].toArray().first().toObject()["sizeBytes"].toInt(),
        4096);
    QCOMPARE(details["ashmem"].toArray().first().toObject()["name"].toString(),
             QString("Create PixelMap"));
    QCOMPARE(details["gpu"].toObject()["totalAllocatedBytes"].toInt(), 8192);
  }
  void reportCompatibility() {
    QTemporaryDir root;
    const auto dir = root.path() + "/report 中文";
    ReportStore::writeObject(
        dir + "/meta.json",
        {{"id", "one"}, {"startedAt", 1000}, {"sessionDir", "/old/path"}});
    ReportStore::writeText(dir + "/samples.jsonl",
                           "{\"timestamp\":1000,\"pid\":null}\n");
    const auto report = ReportStore::load(dir);
    QCOMPARE(report["meta"].toObject()["sessionDir"].toString(), dir);
    QCOMPARE(report["samples"].toArray().size(), 1);
    ReportStore::rename(dir, " Task 测试 ");
    QCOMPARE(ReportStore::list(root.path())
                 .first()
                 .toObject()["taskName"]
                 .toString(),
             QString("Task 测试"));
    QVERIFY_THROWS_EXCEPTION(std::runtime_error, ReportStore::remove(dir, dir));
    ReportStore::remove(dir, "");
    QVERIFY(!QDir(dir).exists());
  }
  void procMeminfo() {
    const auto info = MemoryParser::procMeminfo(
        "MemTotal: 8192 kB\nMemFree: 1024 kB\nCached: 2048 kB\n");
    QCOMPARE(info["ramUsedKb"].toInt(), 5120);
  }
};
QTEST_GUILESS_MAIN(CoreTest)
#include "CoreTest.moc"

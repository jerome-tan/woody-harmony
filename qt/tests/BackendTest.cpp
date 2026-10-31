#include "Backend.h"
#include "ReportStore.h"
#include <QTemporaryDir>
#include <QtTest>

class BackendTest : public QObject {
  Q_OBJECT
private:
  QTemporaryDir directory;
  std::unique_ptr<Backend> backend;
  QString statePath, reports;
  void state(const QJsonObject &value) {
    ReportStore::writeObject(statePath, value);
  }
  void start(bool persist) {
    backend->startSampling({{"intervalMs", 200},
                            {"maxDurationMs", 0},
                            {"showAshmem", true},
                            {"showDmabuf", true},
                            {"showGpumem", true}},
                           "com.example.woodyqa", "Woody QA", persist,
                           "测试任务");
  }
private slots:
  void init() {
    QVERIFY(directory.isValid());
    statePath = directory.path() + "/state.json";
    reports = directory.path() + "/reports";
    state({{"pid", 2411}});
    qputenv("WOODY_FAKE_STATE", statePath.toUtf8());
    const auto profile = directory.path() + "/profile";
    const auto fake = QCoreApplication::applicationDirPath() + "/woody_fake_hdc"
#ifdef Q_OS_WIN
                                                               ".exe"
#endif
        ;
    ReportStore::writeObject(profile + "/settings.json",
                             {{"hdcPath", fake}, {"sessionsDir", reports}});
    backend = std::make_unique<Backend>(profile);
    backend->initialize();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->deviceInfo().isEmpty(), 10000);
    QTRY_VERIFY_WITH_TIMEOUT(!backend->apps().isEmpty(), 10000);
    QCOMPARE(backend->target(), QString("WOODY-QA-001"));
    QCOMPARE(backend->deviceInfo()["ramTotalKb"].toInt(), 12582912);
  }
  void cleanup() {
    if (backend->sampling()) {
      backend->stopSampling();
      QTRY_VERIFY_WITH_TIMEOUT(!backend->sampling(), 5000);
    }
    backend.reset();
    QDir(reports).removeRecursively();
  }
  void watchDoesNotWriteReports() {
    start(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend->live()->count() >= 2, 5000);
    QCOMPARE(backend->live()->stats()["last"].toInt(), 196608);
    backend->stopSampling();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->sampling(), 5000);
    QVERIFY(!QFileInfo::exists(reports));
  }
  void zeroSamplesRestartRenameAndDeleteGuard() {
    state({{"pid", 0}});
    start(true);
    QTRY_VERIFY_WITH_TIMEOUT(backend->live()->count() >= 2, 5000);
    QVERIFY(backend->live()->samples.first()["pid"].isNull());
    QCOMPARE(backend->live()
                 ->samples.first()["total"]
                 .toObject()["pssTotalKb"]
                 .toInt(),
             0);
    const auto session = backend->live()->meta()["sessionDir"].toString();
    QSignalSpy errors(backend.get(), &Backend::error);
    backend->deleteReports({session});
    QTRY_COMPARE(errors.size(), 1);
    QVERIFY(QFileInfo::exists(session + "/meta.json"));
    state({{"pid", 7001}});
    QTRY_COMPARE_WITH_TIMEOUT(backend->live()->stats()["pid"].toInt(), 7001,
                              5000);
    state({{"pid", 7002}});
    QTRY_COMPARE_WITH_TIMEOUT(backend->live()->stats()["pid"].toInt(), 7002,
                              5000);
    backend->renameReport(session, "重命名中文报告");
    QTRY_COMPARE(
        ReportStore::readObject(session + "/meta.json")["taskName"].toString(),
        QString("重命名中文报告"));
    QSignalSpy opened(backend.get(), &Backend::reportOpened);
    backend->stopSampling();
    QTRY_VERIFY(!backend->sampling());
    QTRY_COMPARE(opened.size(), 1);
    const auto loaded = ReportStore::load(session),
               meta = loaded["meta"].toObject();
    QCOMPARE(meta["taskName"].toString(), QString("重命名中文报告"));
    QCOMPARE(meta["sampleCount"].toInt(), loaded["samples"].toArray().size());
    auto *openedReport = qvariant_cast<Report *>(opened.first().first());
    QVERIFY(openedReport);
    backend->renameReport(QDir::toNativeSeparators(session), "窗口同步重命名");
    QTRY_COMPARE(openedReport->meta()["taskName"].toString(), QString("窗口同步重命名"));
    QVERIFY(meta["endedAt"].toDouble() >= meta["startedAt"].toDouble());
    QVERIFY(
        !QDir(session + "/raw").entryList({"*.txt"}, QDir::Files).isEmpty());
    backend->deleteReports({session});
    QTRY_VERIFY(!QFileInfo::exists(session));
  }
  void snapshotDetailsAndSmaps() {
    QSignalSpy opened(backend.get(), &Backend::reportOpened);
    backend->takeSnapshot("com.example.woodyqa", "QA", "快照",
                          {{"showAshmem", true},
                           {"showDmabuf", true},
                           {"showGpumem", true},
                           {"includeSmaps", true}});
    QTRY_COMPARE_WITH_TIMEOUT(opened.size(), 1, 5000);
    const auto *report = qvariant_cast<Report *>(opened.first().first());
    QVERIFY(report);
    const auto snapshot = report->snapshotData;
    QCOMPARE(snapshot["ashmemDetail"]
                 .toArray()
                 .first()
                 .toObject()["name"]
                 .toString(),
             QString("Create PixelMap"));
    QCOMPARE(snapshot["dmabufDetail"]
                 .toArray()
                 .first()
                 .toObject()["sizeBytes"]
                 .toInt(),
             4194304);
    QCOMPARE(snapshot["gpuDetail"].toObject()["totalUsedBytes"].toInt(),
             67108864);
    const auto session = report->metadata["sessionDir"].toString();
    QCOMPARE(QDir(session).entryList({"*.smaps.txt"}, QDir::Files).size(), 1);
    QVERIFY(!QFileInfo::exists(session + "/samples.jsonl"));
  }
  void stopCancelsSubprocessAndFinalizesReport() {
    state({{"pid", 2411}, {"delayMs", 3000}});
    start(true);
    QTRY_COMPARE(backend->status()["state"].toString(), QString("sampling"));
    QTest::qWait(100);
    QElapsedTimer timer;
    timer.start();
    backend->stopSampling();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->sampling(), 1500);
    QVERIFY(timer.elapsed() < 1500);
    const auto meta = ReportStore::readObject(
        backend->live()->meta()["sessionDir"].toString() + "/meta.json");
    QCOMPARE(meta["sampleCount"].toInt(), 0);
    QVERIFY(meta.contains("endedAt"));
  }
  void automaticDurationAndQuit() {
    backend->startSampling({{"intervalMs", 200}, {"maxDurationMs", 450}},
                           "com.example.woodyqa", "QA", true, "自动停止");
    QSignalSpy finished(backend.get(), &Backend::samplingFinished);
    QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 1, 5000);
    QVERIFY(finished.first()[2].toBool());
    QVERIFY(!backend->sampling());
    start(true);
    QTRY_VERIFY(backend->live()->count() > 0);
    QSignalSpy quit(backend.get(), &Backend::quitReady);
    backend->requestQuit();
    QTRY_VERIFY(!quit.isEmpty());
    QVERIFY(!backend->sampling());
    QVERIFY(ReportStore::readObject(
                backend->live()->meta()["sessionDir"].toString() + "/meta.json")
                .contains("endedAt"));
  }
};
QTEST_GUILESS_MAIN(BackendTest)
#include "BackendTest.moc"

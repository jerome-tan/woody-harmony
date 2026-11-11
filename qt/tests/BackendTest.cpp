#include "Backend.h"
#include "ReportStore.h"
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>
#include <cstdio>
#include <stdexcept>

class BackendTest : public QObject {
  Q_OBJECT
private:
  QTemporaryDir directory;
  std::unique_ptr<Backend> backend;
  QString statePath, reports;
  void state(const QJsonObject &value) {
    // A child can briefly have this fixture open while reading its command
    // state. Windows denies atomic replacement during that read; retry only
    // this test-fixture write, without changing application discovery behavior.
    QElapsedTimer timer;
    timer.start();
    QString problem;
    do {
      try {
        ReportStore::writeObject(statePath, value);
        return;
      } catch (const std::exception &e) {
        problem = QString::fromUtf8(e.what());
      }
      QTest::qWait(10);
    } while (timer.elapsed() < 2000);
    QFAIL(qPrintable(problem));
  }
  void deviceEvent(bool arrival) {
    auto *monitor = backend->findChild<DeviceMonitor *>("deviceMonitor");
    QVERIFY(monitor);
    emit monitor->topologyChanged(arrival);
  }
  int deviceQueries() const {
    return commandCount("list targets");
  }
  int commandCount(const QByteArray &command) const {
    QFile log(statePath + ".commands");
    if (!log.open(QIODevice::ReadOnly)) return 0;
    return log.readAll().count(command);
  }
  QVariantMap selectedApp() const {
    for (const auto &entry : backend->apps()) {
      const auto app = entry.toMap();
      if (app["bundleName"].toString() == backend->selectedBundle())
        return app;
    }
    return {};
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
  void appDebugModeReadsOnlyBooleanApplicationFlag() {
    HdcClient hdc;
    hdc.binary = backend->hdcPath();
    hdc.target = backend->target();
    QCOMPARE(hdc.appDebugMode("com.example.woodyqa"), QJsonValue(true));
    QCOMPARE(hdc.appDebugMode("com.example.stopped"), QJsonValue(false));
    for (const auto &output : {
             QString(), QString("error: permission denied"),
             QString("{\"applicationInfo\":{\"appProvisionType\":\"debug\"}}"),
             QString("{\"applicationInfo\":{\"debug\":\"false\"}}"),
             QString("{\"debug\":true,\"applicationInfo\":{}}"),
             QString("{\"applicationInfo\":{\"debug\":false}")}) {
      state({{"appInfoOutput", output}});
      QVERIFY(hdc.appDebugMode("com.example.woodyqa").isNull());
    }
    state({{"failAppInfo", true}});
    QVERIFY(hdc.appDebugMode("com.example.woodyqa").isNull());
  }
  void selectedStatusRefreshDoesNotReloadInstalledApplications() {
    backend->selectApp("com.example.woodyqa");
    const auto appQueries = commandCount("bm dump -a");
    for (const int pid : {7001, 0, 7002}) {
      state({{"pid", pid}});
      backend->refreshSelectedAppStatus();
      QTRY_COMPARE(selectedApp()["pid"].toLongLong(), qint64(pid));
      QVERIFY(selectedApp()["statusKnown"].toBool());
    }
    QCOMPARE(commandCount("bm dump -a"), appQueries);
    QCOMPARE(backend->apps().size(), 2);
    QCOMPARE(backend->selectedBundle(), QString("com.example.woodyqa"));
    state({{"hdcFailure", "[Fail][E000004]:transport is not ready"}});
    backend->refreshSelectedAppStatus();
    QTRY_VERIFY(!selectedApp()["statusKnown"].toBool());
    QVERIFY(selectedApp()["pid"].isNull());
    state({{"pid", 7003}});
    backend->refreshSelectedAppStatus();
    QTRY_COMPARE(selectedApp()["pid"].toLongLong(), qint64(7003));
    QVERIFY(selectedApp()["statusKnown"].toBool());
    QCOMPARE(commandCount("bm dump -a"), appQueries);
  }
  void selectedStatusIgnoresRepliesAfterSelectionChangeAndDisconnect() {
    backend->selectApp("com.example.woodyqa");
    state({{"pid", 7001}, {"pidDelayMs", 900}});
    const auto before = commandCount("pidof ");
    backend->refreshSelectedAppStatus();
    backend->refreshSelectedAppStatus(); // Never overlap requests for one selection.
    QTRY_COMPARE(commandCount("pidof "), before + 1);
    state({{"pid", 7002}, {"runningBundle", "com.example.stopped"}});
    backend->selectApp("com.example.stopped");
    backend->refreshSelectedAppStatus();
    QTRY_COMPARE(selectedApp()["pid"].toLongLong(), qint64(7002));
    QTest::qWait(1000);
    QCOMPARE(selectedApp()["pid"].toLongLong(), qint64(7002));

    state({{"pid", 7003}, {"pidDelayMs", 900}});
    const auto next = commandCount("pidof ");
    backend->refreshSelectedAppStatus();
    QTRY_COMPARE(commandCount("pidof "), next + 1);
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY(backend->target().isEmpty());
    QTest::qWait(1000);
    QVERIFY(backend->apps().isEmpty());
    QVERIFY(backend->selectedBundle().isEmpty());
  }
  void hdcFailureWithZeroExitIsNotDeviceMetadata() {
    HdcClient hdc;
    hdc.binary = backend->hdcPath();
    hdc.target = backend->target();
    const QString failure = "[Fail][E000004]:The communication channel is being established.\n"
                            "Please wait for several seconds and try again.";
    state({{"hdcFailure", failure}, {"failEnumeration", true}});
    QVERIFY_EXCEPTION_THROWN(hdc.devices(), std::runtime_error);
    QVERIFY_EXCEPTION_THROWN(hdc.shell("echo woody-device-ready"), std::runtime_error);
    const auto info = hdc.deviceInfo();
    QVERIFY(!info["marketName"].toString().contains("[Fail]"));
    QVERIFY(!info["model"].toString().contains("[Fail]"));
    QCOMPARE(info["marketName"].toString(), QStringLiteral("未知"));
  }
  void manualDeviceRefreshReloadsMetadataAndApps() {
    backend->selectApp("com.example.woodyqa");
    state({{"marketName", "Updated Device"}, {"pid", 7001}});
    backend->refreshDevices();
    QTRY_COMPARE_WITH_TIMEOUT(backend->deviceInfo()["marketName"].toString(),
                             QString("Updated Device"), 5000);
    QTRY_VERIFY(!backend->loadingApps());
    QCOMPARE(backend->selectedBundle(), QString("com.example.woodyqa"));
    bool found = false;
    for (const auto &entry : backend->apps()) {
      const auto app = entry.toMap();
      if (app["bundleName"] == "com.example.woodyqa") {
        QCOMPARE(app["pid"].toInt(), 7001);
        found = true;
      }
    }
    QVERIFY(found);
  }
  void arrivalWaitsForTransportEvenAfterEnumeration() {
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY(backend->target().isEmpty());
    state({{"hdcFailure", "[Fail][E000004]:The communication channel is being established."}});
    const auto before = deviceQueries();
    deviceEvent(true);
    QTRY_VERIFY(deviceQueries() >= before + 2);
    QCOMPARE(backend->devices().size(), 1); // Visible to HDC, but shell is not ready.
    QVERIFY(backend->target().isEmpty());
    QVERIFY(backend->apps().isEmpty());
    state({{"marketName", "Reconnected Device"}});
    QTRY_COMPARE_WITH_TIMEOUT(backend->deviceInfo()["marketName"].toString(),
                             QString("Reconnected Device"), 5000);
    QTRY_COMPARE(backend->apps().size(), 2);
    const auto settled = deviceQueries();
    QTest::qWait(3300);
    QCOMPARE(deviceQueries(), settled);
  }
  void unchangedAppRefreshDoesNotInvalidateList() {
    QSignalSpy changes(backend.get(), &Backend::appsChanged);
    QSignalSpy loading(backend.get(), &Backend::loadingAppsChanged);
    backend->refreshApps();
    QVERIFY(backend->loadingApps());
    QTRY_VERIFY(!backend->loadingApps());
    QCOMPARE(loading.count(), 2);
    QCOMPARE(changes.count(), 0);

    backend->requestAppDebugMode("com.example.woodyqa");
    QTRY_COMPARE(changes.count(), 1);
    changes.clear();
    backend->refreshApps();
    QTRY_VERIFY(!backend->loadingApps());
    QCOMPARE(changes.count(), 0);

    state({{"pid", 0}});
    backend->refreshApps();
    QTRY_VERIFY(!backend->loadingApps());
    QCOMPARE(changes.count(), 1);
    changes.clear();
    state({{"failApps", true}});
    backend->refreshApps();
    QTRY_VERIFY(!backend->loadingApps());
    QCOMPARE(changes.count(), 0);
  }
  void appDebugModesAreCachedAndClearedOnDeviceSwitch() {
    const auto mode = [this](const QString &bundle) {
      for (const auto &entry : backend->apps()) {
        const auto app = entry.toMap();
        if (app["bundleName"].toString() == bundle)
          return QJsonValue::fromVariant(app.value("debug"));
      }
      return QJsonValue(QJsonValue::Null);
    };
    backend->requestAppDebugMode("com.example.woodyqa");
    backend->requestAppDebugMode("com.example.stopped");
    QTRY_COMPARE(mode("com.example.woodyqa"), QJsonValue(true));
    QTRY_COMPARE(mode("com.example.stopped"), QJsonValue(false));
    state({{"failAppInfo", true}});
    backend->refreshApps();
    QTRY_VERIFY(!backend->loadingApps());
    backend->requestAppDebugMode("com.example.woodyqa");
    QTest::qWait(100);
    QCOMPARE(mode("com.example.woodyqa"), QJsonValue(true));

    state({{"appInfoDelayMs", 900}, {"appDebug", true},
           {"installedBundles", QJsonArray{"com.example.other"}}});
    backend->refreshApps();
    QTRY_COMPARE(backend->apps().size(), 1);
    backend->requestAppDebugMode("com.example.other");
    QTest::qWait(100);
    state({{"appDebug", false}});
    backend->selectDevice("WOODY-QA-002");
    QTRY_COMPARE(backend->apps().size(), 2);
    QVERIFY(mode("com.example.woodyqa").isNull());
    backend->requestAppDebugMode("com.example.woodyqa");
    QTRY_COMPARE(mode("com.example.woodyqa"), QJsonValue(false));
    QTest::qWait(1000);
    QCOMPARE(backend->apps().size(), 2);
    QCOMPARE(mode("com.example.woodyqa"), QJsonValue(false));
  }
  void recordingSavesFreshDebugModeAndPreservesUnknown() {
    backend->requestAppDebugMode("com.example.woodyqa");
    QTRY_VERIFY(backend->apps().first().toMap().value("debug").toBool());
    for (const auto &debug : {QJsonValue(false), QJsonValue(true),
                              QJsonValue(QJsonValue::Null)}) {
      state({{"appDebug", debug}});
      start(true);
      QTRY_VERIFY_WITH_TIMEOUT(backend->live()->count() > 0, 5000);
      const auto session = backend->live()->meta()["sessionDir"].toString();
      backend->stopSampling();
      QTRY_VERIFY_WITH_TIMEOUT(!backend->sampling(), 5000);
      QCOMPARE(ReportStore::load(session)["meta"].toObject()["appDebug"], debug);
    }
  }
  void selectedApplicationSurvivesProcessExitQueryFailureAndRestart() {
    QCOMPARE(backend->selectedBundle(), QString("com.example.woodyqa"));
    backend->selectApp("com.example.stopped");
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
    state({{"pid", 0}});
    backend->refreshApps();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->loadingApps(), 5000);
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
    state({{"failApps", true}});
    backend->refreshApps();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->loadingApps(), 5000);
    QCOMPARE(backend->apps().size(), 2);
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
    for (const auto &output : {QString("error: service unavailable"), QString()}) {
      state({{"appsOutput", output}});
      backend->refreshApps();
      QTRY_VERIFY_WITH_TIMEOUT(!backend->loadingApps(), 5000);
      QCOMPARE(backend->apps().size(), 2);
      QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
    }

    state({{"pid", 2411}});
    const auto profile = backend->profile();
    backend.reset();
    backend = std::make_unique<Backend>(profile);
    backend->initialize();
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 10000);
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
    for (const auto &entry : backend->apps()) {
      const auto app = entry.toMap();
      QCOMPARE(app["label"].toString(), app["bundleName"].toString());
    }
  }
  void deviceChoicesSurviveSwitchesAndStaleResponses() {
    const QJsonArray targets{"WOODY-QA-001", "WOODY-QA-002", "WOODY-QA-003"};
    state({{"pid", 2411}, {"targets", targets}});
    backend->selectApp("com.example.stopped");
    backend->selectDevice("WOODY-QA-002");
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 10000);
    QCOMPARE(backend->selectedBundle(), QString("com.example.woodyqa"));
    backend->selectDevice("WOODY-QA-001");
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 10000);
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));

    state({{"pid", 2411}, {"appsDelayMs", 600}, {"targets", targets}});
    QFile::remove(statePath + ".commands");
    backend->refreshApps();
    const auto appQueryStarted = [this] {
      QFile log(statePath + ".commands");
      return log.open(QIODevice::ReadOnly) && log.readAll().contains("bm dump -a");
    };
    QTRY_VERIFY_WITH_TIMEOUT(appQueryStarted(), 5000);
    state({{"installedBundles", QJsonArray{"com.example.second"}},
           {"targets", targets},
           {"runningBundle", "com.example.second"}});
    backend->selectDevice("WOODY-QA-003");
    QTRY_COMPARE_WITH_TIMEOUT(backend->selectedBundle(),
                             QString("com.example.second"), 10000);
    QCOMPARE(backend->apps().size(), 1);

    state({{"pid", 2411}});
    backend->selectDevice("WOODY-QA-001");
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 10000);
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
  }
  void uninstallClearsSelectionWithoutChoosingAnotherApplication() {
    backend->selectApp("com.example.stopped");
    state({{"installedBundles", QJsonArray{"com.example.woodyqa"}}});
    backend->refreshApps();
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 1, 5000);
    QVERIFY(backend->selectedBundle().isEmpty());
    backend->refreshApps();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->loadingApps(), 5000);
    QVERIFY(backend->selectedBundle().isEmpty());
    const auto profile = backend->profile();
    backend.reset();
    backend = std::make_unique<Backend>(profile);
    backend->initialize();
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 1, 10000);
    QVERIFY(backend->selectedBundle().isEmpty());
  }
  void detectsUnplugAndReplugWithoutManualRefresh() {
    backend->selectApp("com.example.stopped");
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend->target().isEmpty(), 5000);
    QVERIFY(backend->devices().isEmpty());
    QVERIFY(backend->deviceInfo().isEmpty());
    QVERIFY(backend->apps().isEmpty());
    QVERIFY(backend->selectedBundle().isEmpty());
    QVERIFY(!backend->loadingApps());
    QCOMPARE(ReportStore::readObject(backend->profile() + "/settings.json")
                 ["selectedApps"].toObject()["WOODY-QA-001"].toString(),
             QString("com.example.stopped"));
    state({{"pid", 7001}});
    deviceEvent(true);
    QTRY_COMPARE_WITH_TIMEOUT(backend->target(), QString("WOODY-QA-001"), 5000);
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 5000);
    QCOMPARE(backend->selectedBundle(), QString("com.example.stopped"));
  }
  void backgroundDiscoveryDoesNotToggleRefreshButtonOrResetDeviceModel() {
    state({{"devicesDelayMs", 250}});
    QSignalSpy busyChanges(backend.get(), &Backend::discoveringChanged);
    QSignalSpy deviceChanges(backend.get(), &Backend::devicesChanged);
    // Idle has no queries, even beyond the former three-second interval.
    const auto idleQueries = deviceQueries();
    QTest::qWait(3300);
    QCOMPARE(deviceQueries(), idleQueries);
    deviceEvent(true);
    QTRY_VERIFY(deviceQueries() > idleQueries);
    QCOMPARE(busyChanges.size(), 0);
    QCOMPARE(deviceChanges.size(), 0);
    QVERIFY(!backend->discovering());
    backend->refreshDevices();
    QVERIFY(backend->discovering());
    QTRY_VERIFY_WITH_TIMEOUT(!backend->discovering(), 3000);
    QCOMPARE(busyChanges.size(), 2);
    QCOMPARE(deviceChanges.size(), 0);
  }
  void detectsConnectionAfterStartingWithoutDeviceAndDiscoveryFailure() {
    const auto profile = backend->profile();
    backend.reset();
    state({{"targets", QJsonArray{}}});
    backend = std::make_unique<Backend>(profile);
    backend->initialize();
    QTest::qWait(300);
    QVERIFY(backend->target().isEmpty());
    state({{"pid", 2411}});
    deviceEvent(true);
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 5000);
    QSignalSpy notifications(backend.get(), &Backend::notification);
    state({{"failDevices", true}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend->target().isEmpty(), 5000);
    QVERIFY(backend->apps().isEmpty());
    QCOMPARE(notifications.size(), 0);
    state({{"pid", 2411}});
    deviceEvent(true);
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 5000);
  }
  void unplugInvalidatesPendingAppsAndDeviceInfoEvenForSameSerial_data() {
    QTest::addColumn<bool>("delayApps");
    QTest::newRow("pending-apps") << true;
    QTest::newRow("pending-device-info") << false;
  }
  void unplugInvalidatesPendingAppsAndDeviceInfoEvenForSameSerial() {
    QFETCH(bool, delayApps);
    // Each request must remain cancellable on hosts with a single worker.
    backend->selectDevice("");
    state({{delayApps ? "appsDelayMs" : "deviceInfoDelayMs", 5000}});
    QFile::remove(statePath + ".commands");
    backend->selectDevice("WOODY-QA-001");
    const auto queriesStarted = [this, delayApps] {
      QFile log(statePath + ".commands");
      if (!log.open(QIODevice::ReadOnly)) return false;
      const auto text = log.readAll();
      return text.contains(delayApps ? "bm dump -a" : "param get");
    };
    QTRY_VERIFY_WITH_TIMEOUT(queriesStarted(), 3000);
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend->target().isEmpty(), 5000);
    QVERIFY(!backend->loadingApps());
    QVERIFY(backend->apps().isEmpty());
    QVERIFY(backend->selectedBundle().isEmpty());
    state({{"installedBundles", QJsonArray{"com.example.second"}},
           {"runningBundle", "com.example.second"}});
    deviceEvent(true);
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 1, 5000);
    QCOMPARE(backend->apps().first().toMap()["bundleName"].toString(),
             QString("com.example.second"));
    QTRY_VERIFY_WITH_TIMEOUT(!backend->deviceInfo().isEmpty(), 5000);
    QTest::qWait(800);
    QCOMPARE(backend->apps().size(), 1);
    QVERIFY(!backend->loadingApps());
  }
  void arrivalRetriesUntilSecondDeviceIsReadyThenStops() {
    const auto before = deviceQueries();
    deviceEvent(true);
    QTRY_VERIFY(deviceQueries() > before);
    // USB enumeration precedes HDC readiness; the existing target is not success.
    state({{"targets", QJsonArray{"WOODY-QA-001", "WOODY-QA-002"}}});
    QTRY_COMPARE_WITH_TIMEOUT(backend->devices().size(), 2, 5000);
    const auto settled = deviceQueries();
    QTest::qWait(3300);
    QCOMPARE(deviceQueries(), settled);
  }
  void eventDuringQueryDiscardsStaleResult() {
    state({{"devicesDelayMs", 1000}});
    const auto before = deviceQueries();
    backend->refreshDevices();
    QTRY_VERIFY(deviceQueries() > before);
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend->target().isEmpty(), 3000);
    QVERIFY(backend->apps().isEmpty());
    QVERIFY(!backend->discovering());
  }
  void eventRetriesExpireWithoutBackgroundFallback() {
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY(backend->target().isEmpty());
    const auto before = deviceQueries();
    deviceEvent(true); // USB present, but HDC never becomes ready.
    QTest::qWait(11000);
    const auto expired = deviceQueries();
    QVERIFY(expired > before);
    QVERIFY(expired - before <= 7);
    QTest::qWait(3300);
    QCOMPARE(deviceQueries(), expired);
    state({{"pid", 2411}});
    backend->refreshDevices(); // Manual refresh still works after retries expire.
    QTRY_COMPARE(backend->target(), QString("WOODY-QA-001"));
  }
  void wakeRefreshesAndQuitStopsEvents() {
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY(backend->target().isEmpty());
    state({{"pid", 2411}});
    emit backend->findChild<DeviceMonitor *>("deviceMonitor")->resumed();
    QTRY_COMPARE(backend->target(), QString("WOODY-QA-001"));
    backend->requestQuit();
    const auto before = deviceQueries();
    deviceEvent(true);
    emit backend->findChild<DeviceMonitor *>("deviceMonitor")->resumed();
    QTest::qWait(500);
    QCOMPARE(deviceQueries(), before);
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
    deviceEvent(true);
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
    QCOMPARE(report->metadata["appDebug"], QJsonValue(true));
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
    QCOMPARE(ReportStore::load(session)["meta"].toObject()["appDebug"], QJsonValue(true));
  }
  void cancelSnapshotDoesNotPublishPartialReport() {
    state({{"pid", 2411}, {"delayMs", 3000}});
    QSignalSpy opened(backend.get(), &Backend::reportOpened);
    QSignalSpy errors(backend.get(), &Backend::error);
    QSignalSpy notifications(backend.get(), &Backend::notification);
    backend->takeSnapshot("com.example.woodyqa", "QA", "取消快照", {{"includeSmaps", true}});
    QVERIFY(backend->snapshotting());
    QTest::qWait(100);
    backend->cancelSnapshot();
    QTRY_VERIFY_WITH_TIMEOUT(!backend->snapshotting(), 1500);
    QCOMPARE(opened.size(), 0);
    QCOMPARE(errors.size(), 0);
    QCOMPARE(notifications.size(), 1);
    QVERIFY(ReportStore::list(reports).isEmpty());
    state({{"pid", 2411}});
    backend->takeSnapshot("com.example.woodyqa", "QA", "重试快照", {});
    QTRY_COMPARE_WITH_TIMEOUT(opened.size(), 1, 5000);
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
  void disconnectFinalizesRecordingWithoutResuming_data() {
    QTest::addColumn<bool>("withSamples");
    QTest::addColumn<bool>("queryFailure");
    QTest::newRow("saved-samples") << true << false;
    QTest::newRow("first-sample-in-flight") << false << false;
    QTest::newRow("connection-query-failed") << true << true;
  }
  void disconnectFinalizesRecordingWithoutResuming() {
    QFETCH(bool, withSamples);
    QFETCH(bool, queryFailure);
    QSignalSpy notifications(backend.get(), &Backend::notification);
    QSignalSpy errors(backend.get(), &Backend::error);
    QSignalSpy finished(backend.get(), &Backend::samplingFinished);
    QSignalSpy opened(backend.get(), &Backend::reportOpened);
    if (!withSamples)
      state({{"delayMs", 10000}});
    start(true);
    QTRY_COMPARE(backend->status()["state"].toString(), QString("sampling"));
    if (withSamples)
      QTRY_VERIFY(backend->live()->count() >= 2);
    const auto countBefore = backend->live()->count();
    const auto session = backend->live()->meta()["sessionDir"].toString();
    // Keep a different device connected: only the recording target matters.
    state({{"targets", QJsonArray{"WOODY-QA-002"}},
           {"failDevices", queryFailure}, {"delayMs", 10000}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(!backend->sampling(), 5000);
    QTRY_COMPARE(opened.size(), 1);
    QCOMPARE(finished.size(), 1);
    QVERIFY(!finished.first()[2].toBool()); // Not the duration-limit notification.
    QCOMPARE(errors.size(), 0);
    QCOMPARE(notifications.size(), 1);
    QVERIFY(notifications.first().first().toString().contains("已有数据已保存"));
    const auto loaded = ReportStore::load(session);
    const auto meta = loaded["meta"].toObject();
    QCOMPARE(meta["stopReason"].toString(), QString("device-disconnected"));
    QCOMPARE(meta["sampleCount"].toInt(), loaded["samples"].toArray().size());
    QCOMPARE(meta["sampleCount"].toInt(), backend->live()->count());
    QVERIFY(meta["sampleCount"].toInt() >= countBefore);
    QVERIFY(meta["endedAt"].toInteger() >= meta["startedAt"].toInteger());
    const auto savedSamples = loaded["samples"];
    // Observe an empty-device event before reconnecting the original target.
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(backend->target().isEmpty(), 5000);
    state({{"pid", 7001}});
    deviceEvent(true);
    QTRY_COMPARE_WITH_TIMEOUT(backend->target(), QString("WOODY-QA-001"), 5000);
    QTRY_COMPARE_WITH_TIMEOUT(backend->apps().size(), 2, 5000);
    QTest::qWait(3200);
    QVERIFY(!backend->sampling());
    QCOMPARE(finished.size(), 1);
    QCOMPARE(notifications.size(), 1);
    QCOMPARE(ReportStore::load(session)["samples"], savedSamples);
    start(true); // A fresh recording is allowed only through an explicit start.
    QTRY_VERIFY(backend->live()->count() > 0);
    backend->stopSampling();
    QTRY_VERIFY(!backend->sampling());
    const auto nextSession = backend->live()->meta()["sessionDir"].toString();
    QVERIFY(nextSession != session);
    QVERIFY(!ReportStore::readObject(nextSession + "/meta.json").contains("stopReason"));
    QCOMPARE(notifications.size(), 1);
  }
  void disconnectDuringRecordingStartup() {
    state({{"pidDelayMs", 10000}});
    QFile::remove(statePath + ".commands");
    QSignalSpy notifications(backend.get(), &Backend::notification);
    QSignalSpy errors(backend.get(), &Backend::error);
    start(true);
    const auto queryStarted = [this] {
      QFile log(statePath + ".commands");
      return log.open(QIODevice::ReadOnly) && log.readAll().contains("pidof ");
    };
    QTRY_VERIFY_WITH_TIMEOUT(queryStarted(), 3000);
    state({{"targets", QJsonArray{}}});
    deviceEvent(false);
    QTRY_VERIFY_WITH_TIMEOUT(!backend->sampling(), 5000);
    QCOMPARE(notifications.size(), 1);
    QVERIFY(notifications.first().first().toString().contains("尚未产生可保存的数据"));
    QCOMPARE(errors.size(), 0);
    QVERIFY(ReportStore::list(reports).isEmpty());
  }
};
int main(int argc, char **argv) {
  // Keep the last test name and exception diagnostics if the process crashes.
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  std::setvbuf(stderr, nullptr, _IONBF, 0);
  QCoreApplication app(argc, argv);
  BackendTest test;
  return QTest::qExec(&test, argc, argv);
}
#include "BackendTest.moc"

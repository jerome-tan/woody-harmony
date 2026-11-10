#include "DeviceMonitor.h"
#include <QtTest>

class DeviceMonitorTest : public QObject {
  Q_OBJECT
private slots:
  void nativeRegistrationAndCleanup() {
    for (int i = 0; i < 3; ++i) {
      DeviceMonitor monitor;
      QString error;
      QVERIFY2(monitor.start(&error), qPrintable(error));
      QVERIFY(monitor.start(&error)); // Reinitialization must not duplicate observers.
      QTest::qWait(20);
      monitor.stop();
      monitor.stop();
      QVERIFY2(monitor.start(&error), qPrintable(error));
      // Destruction also unregisters an active observer.
    }
    QTest::qWait(20);
  }
};
QTEST_MAIN(DeviceMonitorTest)
#include "DeviceMonitorTest.moc"

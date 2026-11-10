#pragma once
#include <QObject>
#include <QString>

// Native notifications only. No polling or HDC calls in platform callbacks.
class DeviceMonitor : public QObject {
  Q_OBJECT
public:
  explicit DeviceMonitor(QObject *parent = nullptr) : QObject(parent) {
    setObjectName("deviceMonitor");
  }
  ~DeviceMonitor() override { stop(); }
  bool start(QString *error);
  void stop();
signals:
  void topologyChanged(bool arrival);
  void resumed();
private:
  struct Native;
  Native *mNative = nullptr;
};

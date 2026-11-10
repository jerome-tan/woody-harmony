#include "DeviceMonitor.h"

bool DeviceMonitor::start(QString *error) {
  if (error) *error = QStringLiteral("Native device notifications are unavailable on this platform");
  return false;
}
void DeviceMonitor::stop() {}

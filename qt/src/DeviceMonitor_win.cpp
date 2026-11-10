#include "DeviceMonitor.h"
#include <windows.h>
#include <cfgmgr32.h>
#include <powrprof.h>
#include <powerbase.h>

struct DeviceMonitor::Native {
  DeviceMonitor *owner;
  HCMNOTIFICATION usb = nullptr;
  HPOWERNOTIFY power = nullptr;

  static DWORD CALLBACK deviceChanged(HCMNOTIFICATION, PVOID context,
      CM_NOTIFY_ACTION action, PCM_NOTIFY_EVENT_DATA, DWORD) {
    auto *self = static_cast<Native *>(context);
    if (action == CM_NOTIFY_ACTION_DEVICEINTERFACEARRIVAL ||
        action == CM_NOTIFY_ACTION_DEVICEINTERFACEREMOVAL) {
      // Callbacks run on Windows worker threads. Backend uses queued connections.
      emit self->owner->topologyChanged(action == CM_NOTIFY_ACTION_DEVICEINTERFACEARRIVAL);
    }
    return ERROR_SUCCESS;
  }
  static ULONG CALLBACK powerChanged(PVOID context, ULONG type, PVOID) {
    if (type == PBT_APMRESUMEAUTOMATIC || type == PBT_APMRESUMESUSPEND)
      emit static_cast<Native *>(context)->owner->resumed();
    return ERROR_SUCCESS;
  }
  ~Native() {
    // Unregistration waits for callbacks before their context is destroyed.
    if (usb) CM_Unregister_Notification(usb);
    if (power) PowerUnregisterSuspendResumeNotification(power);
  }
};

bool DeviceMonitor::start(QString *error) {
  if (mNative) return true;
  auto *native = new Native{this};
  CM_NOTIFY_FILTER filter{};
  filter.cbSize = sizeof(filter);
  filter.FilterType = CM_NOTIFY_FILTER_TYPE_DEVICEINTERFACE;
  // GUID_DEVINTERFACE_USB_DEVICE, inline to avoid an external GUID definition.
  filter.u.DeviceInterface.ClassGuid =
      {0xa5dcbf10, 0x6530, 0x11d2, {0x90, 0x1f, 0x00, 0xc0, 0x4f, 0xb9, 0x51, 0xed}};
  const auto result = CM_Register_Notification(&filter, native,
      Native::deviceChanged, &native->usb);
  DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS power{};
  power.Callback = Native::powerChanged;
  power.Context = native;
  const auto powerResult = result == CR_SUCCESS
      ? PowerRegisterSuspendResumeNotification(DEVICE_NOTIFY_CALLBACK, &power, &native->power)
      : ERROR_NOT_SUPPORTED;
  if (result != CR_SUCCESS || powerResult != ERROR_SUCCESS) {
    if (error) *error = QStringLiteral("Windows notification error %1 / %2")
        .arg(result).arg(powerResult);
    delete native;
    return false;
  }
  mNative = native;
  return true;
}

void DeviceMonitor::stop() {
  delete mNative;
  mNative = nullptr;
}

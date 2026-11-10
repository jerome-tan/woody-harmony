#include "DeviceMonitor.h"
#include <QPointer>
#import <AppKit/AppKit.h>
#include <IOKit/IOKitLib.h>

struct DeviceMonitor::Native {
  DeviceMonitor *owner;
  IONotificationPortRef port = nullptr;
  io_iterator_t added = IO_OBJECT_NULL, removed = IO_OBJECT_NULL;
  id wakeObserver = nil;
  bool armed = false;

  static void drain(void *context, io_iterator_t iterator) {
    auto *self = static_cast<Native *>(context);
    bool changed = false;
    while (auto service = IOIteratorNext(iterator)) {
      changed = true;
      IOObjectRelease(service);
    }
    // Initial iteration arms notifications, but is not an insertion event.
    if (changed && self->armed)
      emit self->owner->topologyChanged(iterator == self->added);
  }
  ~Native() {
    armed = false;
    if (wakeObserver)
      [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:wakeObserver];
    if (port) {
      CFRunLoopRemoveSource(CFRunLoopGetMain(),
          IONotificationPortGetRunLoopSource(port), kCFRunLoopCommonModes);
    }
    if (added) IOObjectRelease(added);
    if (removed) IOObjectRelease(removed);
    if (port) IONotificationPortDestroy(port);
  }
};

bool DeviceMonitor::start(QString *error) {
  if (mNative) return true;
  auto *native = new Native{this};
  native->port = IONotificationPortCreate(kIOMainPortDefault);
  kern_return_t result = KERN_FAILURE;
  if (native->port) {
    CFRunLoopAddSource(CFRunLoopGetMain(),
        IONotificationPortGetRunLoopSource(native->port), kCFRunLoopCommonModes);
    result = IOServiceAddMatchingNotification(native->port, kIOFirstMatchNotification,
        IOServiceMatching("IOUSBHostDevice"), Native::drain, native, &native->added);
    if (result == KERN_SUCCESS) {
      Native::drain(native, native->added);
      result = IOServiceAddMatchingNotification(native->port, kIOTerminatedNotification,
          IOServiceMatching("IOUSBHostDevice"), Native::drain, native, &native->removed);
      if (result == KERN_SUCCESS) Native::drain(native, native->removed);
    }
  }
  if (result != KERN_SUCCESS) {
    if (error) *error = QStringLiteral("IOKit error %1").arg(result);
    delete native;
    return false;
  }
  const QPointer<DeviceMonitor> owner(this);
  native->wakeObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
      addObserverForName:NSWorkspaceDidWakeNotification object:nil
      queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *) {
        if (owner) emit owner->resumed();
      }];
  native->armed = true;
  mNative = native;
  return true;
}

void DeviceMonitor::stop() {
  delete mNative;
  mNative = nullptr;
}

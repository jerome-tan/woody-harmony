#include "PlatformWindow.h"
#import <AppKit/AppKit.h>
#include <QWindow>

void configurePlatformWindow(QWindow *window) {
  auto *view = reinterpret_cast<NSView *>(window->winId());
  NSWindow *native = view.window;
  native.titleVisibility = NSWindowTitleHidden;
  native.titlebarAppearsTransparent = YES;
}

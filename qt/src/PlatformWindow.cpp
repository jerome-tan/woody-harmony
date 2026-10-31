#include "PlatformWindow.h"
#include <QDebug>
#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <uxtheme.h>

void configurePlatformWindow(QWindow *window) {
  // ExpandedClientAreaHint preserves native caption buttons, but Windows still
  // paints its own icon/text. Hide that decoration without clearing the title
  // used by the taskbar, Alt+Tab and accessibility.
  const DWORD flags = WTNCA_NODRAWCAPTION | WTNCA_NODRAWICON;
  WTA_OPTIONS options{flags, flags};
  const auto result = SetWindowThemeAttribute(
      reinterpret_cast<HWND>(window->winId()), WTA_NONCLIENT, &options,
      sizeof(options));
  if (FAILED(result))
    qWarning("Could not configure native caption: 0x%08lx",
             static_cast<unsigned long>(result));
}
#else
void configurePlatformWindow(QWindow *) {}
#endif

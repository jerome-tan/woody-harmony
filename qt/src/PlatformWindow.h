#pragma once
class QWindow;
// Keep the native caption buttons while the QML header owns the window title.
void configurePlatformWindow(QWindow *window);

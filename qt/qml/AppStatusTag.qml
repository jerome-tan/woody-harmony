import QtQuick
import "Theme.js" as T

WTag {
    property var application: null
    readonly property bool running: !!application && Number(application.pid) > 0
    visible: !!application
    text: running ? "运行中 · PID " + application.pid : "未运行"
    ink: running ? T.successText : T.error
    tint: running ? T.successBackground : T.errorBackground
}

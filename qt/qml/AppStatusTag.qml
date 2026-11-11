import QtQuick
import "Theme.js" as T

WTag {
    property var application: null
    readonly property bool known: !!application && application.statusKnown !== false
    readonly property bool running: !!application && Number(application.pid) > 0
    visible: !!application
    text: !known ? "状态暂不可用" : running ? "运行中 · PID " + application.pid : "未运行"
    ink: !known ? T.muted : running ? T.successText : T.error
    tint: !known ? T.sectionHeader : running ? T.successBackground : T.errorBackground
}

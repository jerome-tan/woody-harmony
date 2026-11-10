import QtQuick
import "Theme.js" as T
import "Format.js" as F

WTag {
    id: root
    property var application: null
    visible: !!application
    text: F.debugMode(application ? application.debug : undefined)
    ink: application && application.debug === true ? T.accent : T.muted
    tint: application && application.debug === true ? T.selected : T.sectionHeader
    Accessible.role: Accessible.StaticText
    Accessible.name: "调试模式：" + text
    function requestMode() {
        if (visible && application)
            backend.requestAppDebugMode(application.bundleName);
    }
    onApplicationChanged: requestMode()
    onVisibleChanged: requestMode()
    Component.onCompleted: requestMode()
}

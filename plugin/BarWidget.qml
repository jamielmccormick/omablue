import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    moduleName: "omablue"

    readonly property var engine: bar && bar.shell
        ? bar.shell.serviceFor("omablue")
        : null
    readonly property int unreadCount: engine ? engine.unreadCount : 0
    readonly property bool newMessage: engine ? engine.newMessagePending : false
    readonly property bool syncing: engine ? engine.syncing : false
    readonly property bool offline: engine ? engine.offline : true
    readonly property color baseForeground: bar ? bar.foreground : Color.foreground
    readonly property color iconColor: {
        if (root.offline) return Qt.darker(root.baseForeground, 1.45)
        if (root.newMessage) return root.pulsePhase > 0.45 ? Color.accent : root.baseForeground
        if (root.syncing) return Color.accent
        return root.baseForeground
    }
    readonly property string tooltip: {
        if (root.offline) return "iMessage · Offline"
        if (root.syncing) return "iMessage · Syncing"
        if (root.unreadCount > 0) return "iMessage · " + root.unreadCount + " unread"
        return "iMessage"
    }
    property real pulsePhase: 0

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.settings = root.settings
        if (button) panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
    }

    function togglePanel() {
        if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
    }

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true
        : false

    function open() {
        if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
    }

    function closeForPopoutSwitch() {
        if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
            panelLoader.item.closeForPopoutSwitch()
    }

    onBarChanged: injectPanel()
    onSettingsChanged: {
        injectPanel()
        if (root.engine && "settings" in root.engine) root.engine.settings = root.settings
    }
    onEngineChanged: {
        injectPanel()
        if (root.engine && "settings" in root.engine) root.engine.settings = root.settings
    }

    SequentialAnimation on pulsePhase {
        running: root.newMessage
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 760; easing.type: Easing.InOutSine }
    }

    onNewMessageChanged: {
        if (!root.newMessage) root.pulsePhase = 0
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: chatBubbleIcon
        foreground: root.iconColor
        useActiveColor: false
        slotSize: Style.bar.statusSlot
        tooltipText: root.tooltip
        onPressed: root.togglePanel()
    }

    Component {
        id: chatBubbleIcon

        Item {
            anchors.fill: parent

            Rectangle {
                x: parent.width * 0.16
                y: parent.height * 0.13
                width: parent.width * 0.68
                height: parent.height * 0.60
                radius: width * 0.28
                color: root.iconColor
            }

            Canvas {
                id: bubbleTail
                x: parent.width * 0.57
                y: parent.height * 0.56
                width: parent.width * 0.30
                height: parent.height * 0.31

                onPaint: {
                    var context = getContext("2d")
                    context.clearRect(0, 0, width, height)
                    context.fillStyle = root.iconColor
                    context.beginPath()
                    context.moveTo(width * 0.04, 0)
                    context.lineTo(width * 0.96, 0)
                    context.lineTo(width * 0.72, height * 0.96)
                    context.closePath()
                    context.fill()
                }

                Connections {
                    target: root
                    function onIconColorChanged() { bubbleTail.requestPaint() }
                }
            }

            Row {
                width: parent.width * 0.34
                height: parent.height * 0.12
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -parent.height * 0.04
                spacing: width * 0.12

                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: (parent.width - parent.spacing * 2) / 3
                        height: width
                        radius: width / 2
                        color: Color.background
                    }
                }
            }
        }
    }

    Rectangle {
        id: unreadBadge
        visible: root.unreadCount > 0
        z: 3
        anchors.right: button.right
        anchors.top: button.top
        anchors.rightMargin: Style.space(1)
        anchors.topMargin: Style.space(1)
        width: Math.max(Style.space(16), badgeText.implicitWidth + Style.space(6))
        height: Style.space(11)
        radius: height / 2
        color: Color.urgent

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.unreadCount > 99 ? "99+" : String(root.unreadCount)
            color: Color.background
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.space(7)
            font.bold: true
        }
    }
}

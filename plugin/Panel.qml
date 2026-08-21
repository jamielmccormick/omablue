import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
    id: root

    moduleName: "omablue"
    manageIpc: false

    property Item anchorItem: null
    property var hostWidget: null
    property int selectedIndex: 0
    property string view: "inbox"
    property string selectedConversationId: ""

    readonly property var engine: bar && bar.shell
        ? bar.shell.serviceFor("omablue")
        : null
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(root.foreground, 1.45)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property var conversations: engine ? engine.conversations : []
    readonly property var visibleConversations: root.conversations.slice(0, 5)
    readonly property var selectedConversation: {
        for (var i = 0; i < root.conversations.length; i++) {
            if (String(root.conversations[i].id) === root.selectedConversationId)
                return root.conversations[i]
        }
        return null
    }
    readonly property var threadMessages: {
        if (!root.selectedConversationId || !engine) return []
        return engine.messages.filter(function(message) {
            return String(message.conversation_id) === root.selectedConversationId
        })
    }

    function initials(participant) {
        var name = String(participant && (participant.display_name || participant.id) || "iM")
        var words = name.trim().split(/\s+/).filter(function(word) { return word !== "" })
        if (words.length === 1) return words[0].slice(0, 2).toUpperCase()
        return (words[0].charAt(0) + words[words.length - 1].charAt(0)).toUpperCase()
    }

    function conversationTitle(conversation) {
        if (!conversation) return "Messages"
        if (conversation.title) return String(conversation.title)
        var participants = conversation.participants || []
        if (participants.length === 0) return "iMessage"
        return participants.map(function(participant) {
            return String(participant.display_name || participant.id || "Participant")
        }).join(", ")
    }

    function timeLabel(value) {
        if (!value) return ""
        var date = new Date(value)
        if (isNaN(date.getTime())) return ""
        return Qt.formatDateTime(date, "HH:mm")
    }

    function openConversation(conversation) {
        if (!conversation) return
        selectedConversationId = String(conversation.id)
        selectedIndex = 0
        view = "thread"
        if (engine) engine.clearNewMessagePending()
        Qt.callLater(function() {
            threadScroller.contentY = 0
            threadScroller.forceActiveFocus()
        })
    }

    function goBack() {
        if (view === "thread") {
            view = "inbox"
            selectedConversationId = ""
            selectedIndex = 0
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        } else {
            close()
        }
    }

    function moveCursor(dx, dy) {
        if (view === "thread") {
            var maximum = Math.max(0, threadScroller.contentHeight - threadScroller.height)
            threadScroller.contentY = Math.max(0, Math.min(maximum, threadScroller.contentY - dy * Style.space(44)))
            return
        }
        if (visibleConversations.length === 0) return
        selectedIndex = Math.max(0, Math.min(visibleConversations.length - 1, selectedIndex + dy))
    }

    function activateCursor() {
        if (view === "inbox" && visibleConversations[selectedIndex])
            openConversation(visibleConversations[selectedIndex])
    }

    onOpenedChanged: {
        if (!opened) return
        if (engine) engine.clearNewMessagePending()
        selectedIndex = 0
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    Component {
        id: bubbleIconComponent
        Text {
            text: "󰍸"
            color: root.engine && root.engine.offline ? root.dim : Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
        }
    }

    Component {
        id: backIconComponent
        Text {
            text: ""
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
        }
    }

    KeyboardPanel {
        id: keyboardPanel
        anchorItem: root.anchorItem
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: fittedContentWidth(Style.space(390))
        contentHeight: fittedContentHeight(content.implicitHeight, Style.space(630))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
            onActivateRequested: root.activateCursor()
            onCloseRequested: root.goBack()
        }

        Column {
            id: content
            width: parent.width
            spacing: Style.space(10)

            PanelHero {
                width: parent.width
                title: root.view === "thread" ? root.conversationTitle(root.selectedConversation) : "Messages"
                meta: root.view === "thread"
                    ? "THREAD"
                    : (root.engine ? root.engine.deviceName : "Connected Mac")
                detail: root.view === "inbox" && root.engine && root.engine.unreadCount > 0
                    ? String(root.engine.unreadCount)
                    : ""
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconComponent: root.view === "thread" ? backIconComponent : bubbleIconComponent
            }

            Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                    width: parent.width - syncIndicator.width - parent.spacing
                    text: root.engine
                        ? (root.engine.offline ? (root.engine.errorText || "Mac bridge offline")
                            : (root.engine.syncing ? "Syncing quietly" : "Content hidden until opened"))
                        : "Mac bridge is starting"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: syncIndicator
                    width: Style.space(7)
                    height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.engine && root.engine.offline
                        ? Color.urgent
                        : (root.engine && root.engine.syncing ? Color.accent : Color.muted)
                }
            }

            PanelSeparator { width: parent.width }

            Item {
                visible: root.view === "inbox"
                width: parent.width
                implicitHeight: inboxScroller.height

                Flickable {
                    id: inboxScroller
                    width: parent.width
                    height: Math.min(Style.space(360), inboxColumn.implicitHeight)
                    clip: true
                    contentWidth: width
                    contentHeight: inboxColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: inboxColumn
                        width: inboxScroller.width
                        spacing: Style.space(3)

                        Text {
                            visible: root.visibleConversations.length === 0
                            width: parent.width
                            text: root.engine && root.engine.offline
                                ? "Reconnect to see conversations"
                                : "No conversations yet"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            topPadding: Style.space(18)
                            bottomPadding: Style.space(18)
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Repeater {
                            model: root.visibleConversations

                            delegate: Item {
                                required property var modelData
                                required property int index
                                width: inboxColumn.width
                                height: Style.space(58)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Style.cornerRadius
                                    color: root.selectedIndex === index
                                        ? Color.menu.selectedBackground
                                        : "transparent"
                                }

                                Item {
                                    id: avatarStack
                                    width: Style.space(44)
                                    height: width
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.space(8)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Repeater {
                                        model: Math.min(modelData.participants ? modelData.participants.length : 0, 3)
                                        delegate: Rectangle {
                                            required property int index
                                            x: index * Style.space(8)
                                            y: index * Style.space(4)
                                            width: Style.space(30)
                                            height: width
                                            radius: width / 2
                                            color: index === 0 ? Color.accent : Color.menu.selectedBackground
                                            border.width: index === 0 ? 0 : 1
                                            border.color: Color.popups.border

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.initials(modelData.participants[index])
                                                color: index === 0 ? Color.background : root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                                font.bold: true
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: !modelData.participants || modelData.participants.length === 0
                                        width: Style.space(30)
                                        height: width
                                        radius: width / 2
                                        color: Color.accent
                                        anchors.centerIn: parent

                                        Text {
                                            anchors.centerIn: parent
                                            text: "iM"
                                            color: Color.background
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.bodySmall
                                            font.bold: true
                                        }
                                    }
                                }

                                Column {
                                    anchors.left: avatarStack.right
                                    anchors.leftMargin: Style.space(10)
                                    anchors.right: rowMeta.left
                                    anchors.rightMargin: Style.space(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(2)

                                    Text {
                                        width: parent.width
                                        text: root.conversationTitle(modelData)
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                        font.bold: modelData.unread_count > 0
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.unread_count > 0 ? "New message" : "Message thread"
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideRight
                                    }
                                }

                                Column {
                                    id: rowMeta
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.space(8)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(3)

                                    Text {
                                        anchors.right: parent.right
                                        text: root.timeLabel(modelData.last_message_at)
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                    }

                                    Rectangle {
                                        visible: modelData.unread_count > 0
                                        anchors.right: parent.right
                                        width: unreadLabel.implicitWidth + Style.space(8)
                                        height: Math.max(Style.space(15), unreadLabel.implicitHeight + Style.space(2))
                                        radius: height / 2
                                        color: Color.urgent

                                        Text {
                                            id: unreadLabel
                                            anchors.centerIn: parent
                                            text: modelData.unread_count > 99 ? "99+" : String(modelData.unread_count)
                                            color: Color.background
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.bodySmall
                                            font.bold: true
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onEntered: root.selectedIndex = index
                                    onClicked: root.openConversation(modelData)
                                }
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.view === "thread"
                width: parent.width
                implicitHeight: threadColumn.implicitHeight

                Rectangle {
                    id: backButton
                    width: parent.width
                    height: Style.space(32)
                    radius: Style.cornerRadius
                    color: backArea.containsMouse ? Color.menu.selectedBackground : "transparent"
                    border.width: 1
                    border.color: Color.popups.border

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)

                        Text {
                            text: ""
                            color: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Back to conversations"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.goBack()
                    }
                }

                Flickable {
                    id: threadScroller
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(42)
                    width: parent.width
                    height: Style.space(390)
                    clip: true
                    contentWidth: width
                    contentHeight: threadColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    focus: true

                    Column {
                        id: threadColumn
                        width: threadScroller.width
                        spacing: Style.space(8)

                        Repeater {
                            model: root.threadMessages

                            delegate: Item {
                                required property var modelData
                                width: threadColumn.width
                                height: bubble.implicitHeight + Style.space(4)

                                Rectangle {
                                    id: bubble
                                    width: Math.min(threadColumn.width * 0.82, Math.max(Style.space(92), bubbleText.implicitWidth + Style.space(24)))
                                    height: bubbleText.implicitHeight + Style.space(16)
                                    x: modelData.direction === "outgoing" ? parent.width - width : 0
                                    radius: Style.cornerRadius
                                    color: modelData.direction === "outgoing"
                                        ? Color.menu.selectedBackground
                                        : Color.popups.background
                                    border.width: 1
                                    border.color: modelData.direction === "outgoing" ? Color.accent : Color.popups.border

                                    Text {
                                        id: bubbleText
                                        anchors.fill: parent
                                        anchors.margins: Style.space(8)
                                        text: modelData.text || ((modelData.attachments || []).length > 0 ? "Image attachment" : "Message")
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.body
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.top: threadScroller.bottom
                    anchors.topMargin: Style.space(10)
                    width: parent.width
                    height: Style.space(38)
                    radius: Style.cornerRadius
                    color: Color.menu.selectedBackground
                    border.width: 1
                    border.color: Color.popups.border

                    Text {
                        anchors.centerIn: parent
                        text: root.engine && root.engine.capabilities.send_text
                            ? "Compose a message"
                            : "Sending will arrive with outcome-safe sends"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }
            }
        }
    }
}

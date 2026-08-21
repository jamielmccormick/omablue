import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var shell: null
    property var manifest: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    property var settings: ({})

    readonly property string pluginId: manifest && manifest.id
        ? String(manifest.id)
        : "omablue"
    readonly property string pluginDir: manifest && manifest.__sourceDir
        ? String(manifest.__sourceDir)
        : (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/" + pluginId
    readonly property string helperPath: pluginDir + "/bin/omablue-helper"

    property bool enabled: true
    property bool helperReady: false
    property bool syncing: false
    property bool initialSyncComplete: false
    property bool syncHasMore: false
    property string statusText: "Starting OmaBlue helper"
    property string errorText: ""
    property string serverVersion: ""
    property var source: null
    property var capabilities: ({})
    property var conversations: []
    property var messages: []
    property var events: []
    property string pendingSyncRequestId: ""
    property int requestSequence: 0
    property bool newMessagePending: false
    property bool statusRequestPending: false
    property bool watchActive: false
    property bool panelOpen: false
    property double lastNotificationAt: 0

    readonly property int notificationCooldownSeconds: {
        var value = settings && settings.notificationCooldownSeconds
        return Number.isFinite(Number(value)) ? Number(value) : 0
    }

    readonly property int unreadCount: {
        var count = 0
        for (var i = 0; i < conversations.length; i++)
            count += Number(conversations[i].unread_count || 0)
        return count
    }
    readonly property string deviceName: settings && settings.deviceName
        ? String(settings.deviceName)
        : "Connected Mac"
    readonly property bool offline: !helperReady || errorText !== ""

    function mergeRecords(existing, incoming, key) {
        var merged = existing.slice()
        var positions = ({})
        for (var i = 0; i < merged.length; i++) positions[String(merged[i][key])] = i
        for (var j = 0; j < incoming.length; j++) {
            var record = incoming[j]
            var recordKey = String(record[key])
            if (positions[recordKey] === undefined) {
                positions[recordKey] = merged.length
                merged.push(record)
            } else {
                merged[positions[recordKey]] = record
            }
        }
        return merged
    }

    function mergeSyncFrame(frame) {
        var incomingConversations = Array.isArray(frame.conversations) ? frame.conversations : []
        var incomingMessages = Array.isArray(frame.messages) ? frame.messages : []
        var wasLive = initialSyncComplete

        conversations = mergeRecords(conversations, incomingConversations, "id").sort(function(a, b) {
            return String(b.last_message_at || "").localeCompare(String(a.last_message_at || ""))
        })
        messages = mergeRecords(messages, incomingMessages, "id").sort(function(a, b) {
            return Number(a.source_rowid || 0) - Number(b.source_rowid || 0)
        })
        events = Array.isArray(frame.events) ? events.concat(frame.events) : events

        if (wasLive && incomingMessages.length > 0) {
            newMessagePending = true
            notifyNewMessages(incomingMessages.length, incomingMessages, incomingConversations)
        }
    }

    function conversationLabel(conversationId, candidates) {
        var records = (candidates || []).concat(conversations)
        for (var i = 0; i < records.length; i++) {
            if (String(records[i].id) !== String(conversationId)) continue
            if (records[i].title) return String(records[i].title)
            var participants = records[i].participants || []
            var names = participants.map(function(participant) {
                return String(participant.display_name || participant.id || "Participant")
            }).filter(function(name) { return name !== "" })
            if (names.length > 0) return names.join(", ")
        }
        return "iMessage"
    }

    function notifyNewMessages(count, incomingMessages, incomingConversations) {
        if (settings && settings.notificationsEnabled === false) return
        var now = Date.now()
        if (notificationCooldownSeconds > 0
            && lastNotificationAt > 0
            && now - lastNotificationAt < notificationCooldownSeconds * 1000) return
        lastNotificationAt = now
        var labels = []
        for (var i = 0; i < incomingMessages.length; i++) {
            var label = conversationLabel(incomingMessages[i].conversation_id, incomingConversations)
            if (labels.indexOf(label) === -1) labels.push(label)
        }
        var from = labels.slice(0, 2).join(", ")
        if (labels.length > 2) from += " and others"
        var summary = labels.length > 0
            ? (count === 1 ? "New iMessage from " : "New iMessages from ") + from
            : "New iMessage"
        Quickshell.execDetached([
            root.omarchyPath + "/bin/omarchy-notification-send",
            "-u", "normal",
            "-t", "6000",
            "-a", "OmaBlue",
            summary,
            count === 1 ? "Open OmaBlue to read it" : "Open OmaBlue to read new messages"
        ])
    }

    function clearNewMessagePending() {
        newMessagePending = false
    }

    function requestId(prefix) {
        requestSequence++
        return prefix + "-" + Date.now() + "-" + requestSequence
    }

    function send(command) {
        if (!backend.running || !backend.stdinEnabled) return false
        backend.write(JSON.stringify(command) + "\n")
        return true
    }

    function requestStatus() {
        if (statusRequestPending) return false
        statusRequestPending = true
        var sent = send({
            command: "status",
            request_id: requestId("status"),
            protocol_version: 1
        })
        if (!sent) {
            statusRequestPending = false
        } else {
            statusRequestTimeout.restart()
        }
        return sent
    }

    function requestSync() {
        if (syncing || pendingSyncRequestId !== "") return false
        var sent = send({
            command: "sync",
            request_id: requestId("sync"),
            protocol_version: 1,
            limit: 100
        })
        if (!sent) return false
        syncing = true
        statusText = "Syncing messages"
        return true
    }

    function resetCursor() {
        send({
            command: "reset",
            request_id: requestId("reset"),
            protocol_version: 1
        })
    }

    function startWatchIfPossible() {
        if (!helperReady || watchActive || syncing || pendingSyncRequestId !== "") return
        if (!capabilities || capabilities.watch_messages !== true) return
        send({
            command: "watch",
            request_id: requestId("watch"),
            protocol_version: 1
        })
    }

    function handleEvent(frame) {
        var kind = String(frame.event_type || "")
        if (kind === "resync_required") {
            watchActive = false
            statusText = "Messages changed; resyncing"
            resetCursor()
            return
        }
        if (kind === "conversation_upsert" && frame.conversation) {
            conversations = mergeRecords(conversations, [frame.conversation], "id").sort(function(a, b) {
                return String(b.last_message_at || "").localeCompare(String(a.last_message_at || ""))
            })
            return
        }
        if (kind === "message_upsert" && frame.message) {
            var message = frame.message
            var incomingConversations = frame.conversation ? [frame.conversation] : []
            messages = mergeRecords(messages, [message], "id").sort(function(a, b) {
                return Number(a.source_rowid || 0) - Number(b.source_rowid || 0)
            })
            if (frame.conversation) {
                conversations = mergeRecords(conversations, [frame.conversation], "id").sort(function(a, b) {
                    return String(b.last_message_at || "").localeCompare(String(a.last_message_at || ""))
                })
            } else {
                for (var i = 0; i < conversations.length; i++) {
                    if (String(conversations[i].id) === String(message.conversation_id)) {
                        var bumped = Object.assign({}, conversations[i])
                        if (String(message.direction) === "incoming" && !panelOpen)
                            bumped.unread_count = Number(bumped.unread_count || 0) + 1
                        bumped.last_message_at = message.sent_at || bumped.last_message_at
                        conversations[i] = bumped
                        break
                    }
                }
            }
            if (String(message.direction) === "incoming") {
                newMessagePending = true
                notifyNewMessages(1, [message], incomingConversations)
            }
            return
        }
        if (kind === "message_deleted" && frame.message_id) {
            messages = messages.filter(function(message) {
                return String(message.id) !== String(frame.message_id)
            })
        }
        // reaction_changed is ignored for now; reactions refresh on the next
        // sync batch.
    }

    function handleFrame(line) {
        var frame
        try {
            frame = JSON.parse(String(line || ""))
        } catch (error) {
            syncing = false
            errorText = "Helper emitted an invalid frame"
            statusText = errorText
            return
        }

        if (frame.type === "error") {
            if (frame.code === "sync_ack_required" && syncing) return
            statusRequestTimeout.stop()
            statusRequestPending = false
            syncing = false
            if (frame.code === "resync_required") {
                // The Mac database generation changes whenever Messages writes
                // to chat.db. Reset the cursor and recover instead of going
                // permanently offline.
                statusText = "Messages changed; resyncing"
                resetCursor()
                return
            }
            if (frame.code === "cursor_missing") {
                // Watch was requested before the first sync committed a
                // cursor; polling covers us until then.
                return
            }
            errorText = String(frame.code || "Helper request failed")
            statusText = errorText
            return
        }

        if (frame.type === "watch_started") {
            watchActive = true
            statusText = "Live"
            return
        }

        if (frame.event_type) {
            handleEvent(frame)
            return
        }

        if (frame.type === "reset") {
            conversations = []
            messages = []
            events = []
            initialSyncComplete = false
            newMessagePending = false
            requestStatus()
            return
        }

        if (frame.type === "ack") {
            if (String(frame.acknowledged_request_id || "") !== pendingSyncRequestId) return
            pendingSyncRequestId = ""
            syncing = false
            initialSyncComplete = true
            if (syncHasMore) {
                requestSync()
            } else {
                statusText = watchActive ? "Live" : "Ready"
                startWatchIfPossible()
            }
            return
        }

        if (frame.capabilities && frame.source) {
            statusRequestTimeout.stop()
            statusRequestPending = false
            errorText = ""
            source = frame.source
            capabilities = frame.capabilities
            if (!helperReady) {
                helperReady = true
                serverVersion = String(frame.server_version || "")
                statusText = "Bridge ready"
                requestSync()
            } else if (watchActive) {
                statusText = "Live"
            } else {
                statusText = "Ready"
                if (!syncing && pendingSyncRequestId === "") requestSync()
            }
            return
        }

        if (frame.messages && frame.next_cursor && frame.request_id) {
            // Apply the whole batch before acknowledging it. The helper keeps
            // the cursor pending until this ACK arrives.
            mergeSyncFrame(frame)
            syncHasMore = frame.has_more === true
            pendingSyncRequestId = String(frame.request_id)
            source = frame.source || source
            send({
                command: "ack",
                request_id: requestId("ack"),
                protocol_version: 1,
                acknowledged_request_id: pendingSyncRequestId
            })
        }
    }

    Process {
        id: backend
        property bool launched: false
        command: [root.helperPath, "--announce-status"]
        running: root.enabled && root.helperPath !== ""
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function(line) { root.handleFrame(line) }
        }
        stderr: SplitParser {}
        onStarted: {
            launched = true
            helperReady = false
            initialSyncComplete = false
        }
        onRunningChanged: {
            if (running) {
                launched = false
                root.restartingHelper = false
                return
            }
            if (launched) return
            if (root.restartingHelper) return
            if (!root.enabled) return
            helperReady = false
            syncing = false
            errorText = "OmaBlue helper is missing"
            statusText = errorText
        }
        onExited: function(code) {
            var wasWatching = root.watchActive
            root.watchActive = false
            helperReady = false
            syncing = false
            if (root.restartingHelper) return
            if (!root.enabled) return
            if (code === 0 && wasWatching) {
                // Clean watch-stream end; reconnect quietly from the cursor.
                statusText = "Reconnecting"
                return
            }
            errorText = code === 0 ? "OmaBlue helper stopped" : "OmaBlue helper unavailable"
            statusText = errorText
        }
    }

    property bool restartingHelper: false

    Timer {
        id: startupRequest
        interval: 2000
        repeat: true
        running: root.enabled && !root.helperReady && !root.syncing && root.pendingSyncRequestId === ""
        onTriggered: root.requestStatus()
    }

    Timer {
        id: healthCheck
        interval: 4000
        repeat: true
        running: root.enabled && root.helperReady && root.errorText !== "" && !root.syncing
        onTriggered: root.requestStatus()
    }

    Timer {
        id: syncPoll
        interval: 20000
        repeat: true
        running: root.enabled && root.helperReady && root.errorText === ""
            && !root.syncing && root.pendingSyncRequestId === "" && !root.watchActive
        onTriggered: root.requestSync()
    }

    Timer {
        id: restartHelper
        interval: 3000
        repeat: true
        running: root.enabled && !backend.running
        onTriggered: {
            root.restartingHelper = true
            backend.running = false
            backend.running = true
        }
    }

    onEnabledChanged: {
        if (!enabled) {
            backend.running = false
        } else if (!backend.running) {
            restartingHelper = true
            backend.running = true
        }
    }

    Timer {
        id: statusRequestTimeout
        interval: 8000
        repeat: false
        onTriggered: root.statusRequestPending = false
    }
}

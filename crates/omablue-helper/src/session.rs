use omablue_protocol::{Cursor, Event, Request, Source, StatusResponse, SyncResponse};
use serde_json::Value;

use crate::{
    CursorStore, EventDecision, EventLedger, SshBridge, SshTransportConfig, StateError,
    TransportError, WatchError,
};

#[derive(Debug)]
pub enum SessionError {
    Transport(TransportError),
    State(StateError),
    InvalidResponse,
    RequestIdMismatch,
    NoCursor,
    Watch(WatchError),
    Json(serde_json::Error),
}

impl SessionError {
    pub fn remote_code(&self) -> Option<&str> {
        match self {
            Self::Transport(TransportError::RemoteError(code)) => Some(code),
            _ => None,
        }
    }
}

impl From<TransportError> for SessionError {
    fn from(error: TransportError) -> Self {
        Self::Transport(error)
    }
}

impl From<StateError> for SessionError {
    fn from(error: StateError) -> Self {
        Self::State(error)
    }
}

impl From<WatchError> for SessionError {
    fn from(error: WatchError) -> Self {
        Self::Watch(error)
    }
}

impl From<serde_json::Error> for SessionError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

pub struct ReadOnlySession {
    transport: SshTransportConfig,
    cursor_store: CursorStore,
}

impl ReadOnlySession {
    pub fn new(transport: SshTransportConfig, cursor_store: CursorStore) -> Self {
        Self {
            transport,
            cursor_store,
        }
    }

    pub fn status(&self, request_id: impl Into<String>) -> Result<StatusResponse, SessionError> {
        let request_id = request_id.into();
        let mut bridge = SshBridge::connect(&self.transport)?;
        let value = bridge.request(&Request::Status {
            request_id: request_id.clone(),
            protocol_version: omablue_protocol::PROTOCOL_VERSION,
        })?;
        let response: StatusResponse = serde_json::from_value(value)?;
        if response.request_id != request_id
            || response.protocol_version != omablue_protocol::PROTOCOL_VERSION
        {
            return Err(SessionError::RequestIdMismatch);
        }
        Ok(response)
    }

    pub fn sync(
        &self,
        request_id: impl Into<String>,
        limit: u16,
    ) -> Result<SyncResponse, SessionError> {
        let request_id = request_id.into();
        let cursor = self.cursor_store.load()?.map(|stored| stored.cursor);
        let mut bridge = SshBridge::connect(&self.transport)?;
        let value = bridge.request(&Request::Sync {
            request_id: request_id.clone(),
            protocol_version: omablue_protocol::PROTOCOL_VERSION,
            cursor,
            limit,
        })?;
        let response: SyncResponse = serde_json::from_value(value)?;
        if response.request_id != request_id
            || response.protocol_version != omablue_protocol::PROTOCOL_VERSION
            || !response.next_cursor.belongs_to(&response.source)
        {
            return Err(SessionError::InvalidResponse);
        }
        Ok(response)
    }

    pub fn commit_sync(&self, response: &SyncResponse) -> Result<(), SessionError> {
        if !response.next_cursor.belongs_to(&response.source) {
            return Err(SessionError::InvalidResponse);
        }
        self.cursor_store
            .commit(&response.source, &response.next_cursor)?;
        Ok(())
    }

    pub fn reset_cursor(&self) -> Result<(), SessionError> {
        self.cursor_store.clear()?;
        Ok(())
    }

    pub fn begin_watch(&self) -> Result<WatchSession, SessionError> {
        let stored = self.cursor_store.load()?.ok_or(SessionError::NoCursor)?;
        let request = Request::Watch {
            request_id: format!("watch-{}", stored.cursor.rowid),
            protocol_version: omablue_protocol::PROTOCOL_VERSION,
            cursor: stored.cursor.clone(),
        };
        let mut bridge = SshBridge::connect(&self.transport)?;
        bridge.begin_watch(&request)?;
        let ledger = EventLedger::new(stored.source, stored.cursor, 512)?;
        Ok(WatchSession {
            bridge,
            ledger,
            cursor_store: self.cursor_store.clone(),
        })
    }
}

pub struct WatchSession {
    bridge: SshBridge,
    ledger: EventLedger,
    cursor_store: CursorStore,
}

#[derive(Debug, Clone, PartialEq)]
pub enum WatchItem {
    Event(Event),
    Duplicate,
    ResyncRequired(Event),
}

impl WatchSession {
    pub fn next_item(&mut self) -> Result<WatchItem, SessionError> {
        let value = self.bridge.next_frame()?;
        let event = EventLedger::decode(value)?;
        match self.ledger.classify(&event)? {
            EventDecision::Apply => Ok(WatchItem::Event(event)),
            EventDecision::Duplicate => Ok(WatchItem::Duplicate),
            EventDecision::ResyncRequired => Ok(WatchItem::ResyncRequired(event)),
        }
    }

    pub fn commit_event(&mut self, event: &Event) -> Result<(), SessionError> {
        if self.ledger.classify(event)? != EventDecision::Apply {
            return Err(SessionError::Watch(WatchError::InvalidEvent));
        }
        self.ledger.commit(event)?;
        self.cursor_store
            .commit(self.ledger.source(), self.ledger.cursor())?;
        Ok(())
    }

    pub fn reset(&mut self, source: Source, cursor: Cursor) -> Result<(), SessionError> {
        self.ledger
            .reset(source, cursor)
            .map_err(SessionError::Watch)
    }

    pub fn cursor(&self) -> &Cursor {
        self.ledger.cursor()
    }

    pub fn source(&self) -> &Source {
        self.ledger.source()
    }
}

pub fn response_request_id(value: &Value) -> Option<&str> {
    value.get("request_id").and_then(Value::as_str)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temporary_root() -> std::path::PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("omablue-session-{stamp}"));
        fs::create_dir(&root).unwrap();
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
        root
    }

    fn session(root: &std::path::Path, response: &str) -> ReadOnlySession {
        let script = root.join("fake-ssh");
        fs::write(
            &script,
            format!("#!/bin/sh\nread request\nprintf '%s\\n' '{response}'\n"),
        )
        .unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o700)).unwrap();
        let store = CursorStore::open(root.join("cursor.json")).unwrap();
        let transport = SshTransportConfig {
            ssh_program: script,
            destination: "user@mac.example".into(),
            identity_file: "/tmp/omablue-test-key".into(),
            identity_agent: "/tmp/omablue-test-agent".into(),
            known_hosts_file: "/tmp/omablue-test-known-hosts".into(),
        };
        ReadOnlySession::new(transport, store)
    }

    #[test]
    fn status_is_decoded_into_the_typed_protocol_model() {
        let root = temporary_root();
        let response = r#"{"request_id":"status-1","protocol_version":1,"server_version":"0.1.0","source":{"instance":"source","database_generation":"generation"},"capabilities":{"read_messages":true,"watch_messages":true,"send_text":false,"send_attachments":false,"send_reactions":false}}"#;
        let session = session(&root, response);
        let status = session.status("status-1").unwrap();
        assert_eq!(status.source.instance, "source");
        assert!(status.capabilities.read_messages);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn sync_cursor_is_committed_only_after_explicit_commit() {
        let root = temporary_root();
        let response = r#"{"request_id":"sync-1","protocol_version":1,"source":{"instance":"source","database_generation":"generation"},"conversations":[],"messages":[],"events":[],"next_cursor":{"source_instance":"source","database_generation":"generation","rowid":7},"has_more":false}"#;
        let session = session(&root, response);
        let sync = session.sync("sync-1", 100).unwrap();
        assert!(
            CursorStore::open(root.join("cursor.json"))
                .unwrap()
                .load()
                .unwrap()
                .is_none()
        );
        session.commit_sync(&sync).unwrap();
        assert_eq!(
            CursorStore::open(root.join("cursor.json"))
                .unwrap()
                .load()
                .unwrap()
                .unwrap()
                .cursor
                .rowid,
            7
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn watch_event_is_persisted_after_commit() {
        let root = temporary_root();
        let response = r#"{"protocol_version":1,"event_id":"event-1","cursor":{"source_instance":"source","database_generation":"generation","rowid":1},"recorded_at":"2026-08-17T00:00:00Z","event_type":"message_deleted","message_id":"message-1"}"#;
        let store = CursorStore::open(root.join("cursor.json")).unwrap();
        let source = Source {
            instance: "source".into(),
            database_generation: "generation".into(),
        };
        let cursor = Cursor {
            source_instance: "source".into(),
            database_generation: "generation".into(),
            rowid: 0,
        };
        store.commit(&source, &cursor).unwrap();
        let session = session(&root, response);
        let mut watch = session.begin_watch().unwrap();
        let WatchItem::Event(event) = watch.next_item().unwrap() else {
            panic!("expected a new event");
        };
        watch.commit_event(&event).unwrap();
        assert_eq!(watch.cursor().rowid, 1);
        fs::remove_dir_all(root).unwrap();
    }
}

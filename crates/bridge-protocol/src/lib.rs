use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_SYNC_LIMIT: u16 = 500;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Request {
    Status {
        request_id: String,
        protocol_version: u16,
    },
    Sync {
        request_id: String,
        protocol_version: u16,
        cursor: Option<Cursor>,
        limit: u16,
    },
    Watch {
        request_id: String,
        protocol_version: u16,
        cursor: Cursor,
    },
}

impl Request {
    pub fn validate(&self) -> Result<(), ValidationError> {
        let (request_id, protocol_version) = match self {
            Self::Status {
                request_id,
                protocol_version,
            }
            | Self::Sync {
                request_id,
                protocol_version,
                ..
            }
            | Self::Watch {
                request_id,
                protocol_version,
                ..
            } => (request_id, *protocol_version),
        };

        if request_id.is_empty() {
            return Err(ValidationError::EmptyRequestId);
        }
        if protocol_version != PROTOCOL_VERSION {
            return Err(ValidationError::UnsupportedProtocolVersion(
                protocol_version,
            ));
        }
        if let Self::Sync { limit, .. } = self {
            if !(1..=MAX_SYNC_LIMIT).contains(limit) {
                return Err(ValidationError::InvalidSyncLimit(*limit));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValidationError {
    EmptyRequestId,
    UnsupportedProtocolVersion(u16),
    InvalidSyncLimit(u16),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cursor {
    pub source_instance: String,
    pub database_generation: String,
    pub rowid: u64,
}

impl Cursor {
    pub fn belongs_to(&self, source: &Source) -> bool {
        self.source_instance == source.instance
            && self.database_generation == source.database_generation
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Source {
    pub instance: String,
    pub database_generation: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StatusResponse {
    pub request_id: String,
    pub protocol_version: u16,
    pub server_version: String,
    pub source: Source,
    pub capabilities: Capabilities,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Capabilities {
    pub read_messages: bool,
    pub watch_messages: bool,
    pub send_text: bool,
    pub send_attachments: bool,
    pub send_reactions: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncResponse {
    pub request_id: String,
    pub protocol_version: u16,
    pub source: Source,
    pub conversations: Vec<Conversation>,
    pub messages: Vec<Message>,
    pub events: Vec<Event>,
    pub next_cursor: Cursor,
    pub has_more: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Event {
    pub protocol_version: u16,
    pub event_id: String,
    pub cursor: Cursor,
    pub recorded_at: String,
    #[serde(flatten)]
    pub payload: EventPayload,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "event_type", rename_all = "snake_case")]
pub enum EventPayload {
    ConversationUpsert {
        conversation: Conversation,
    },
    MessageUpsert {
        message: Box<Message>,
        conversation: Option<Box<Conversation>>,
    },
    MessageDeleted {
        message_id: String,
    },
    ReactionChanged {
        message_id: String,
        actor_id: Option<String>,
        kind: ReactionKind,
        active: bool,
    },
    ResyncRequired {
        reason: ResyncReason,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResyncReason {
    DatabaseGenerationChanged,
    CursorExpired,
    WatchOverflow,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub title: Option<String>,
    pub service: Option<Service>,
    pub participants: Vec<Participant>,
    pub unread_count: Option<u32>,
    pub last_message_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Participant {
    pub id: String,
    pub display_name: Option<String>,
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Service {
    #[serde(rename = "imessage")]
    IMessage,
    Sms,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub source_rowid: u64,
    pub conversation_id: String,
    pub direction: Direction,
    pub sender_id: Option<String>,
    pub text: Option<String>,
    pub sent_at: String,
    pub delivered_at: Option<String>,
    pub read_at: Option<String>,
    pub reply_to: Option<String>,
    pub attachments: Vec<Attachment>,
    pub reactions: Vec<Reaction>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Direction {
    Incoming,
    Outgoing,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attachment {
    pub id: Option<String>,
    pub media_type: Option<String>,
    pub byte_count: u64,
    pub display_name: Option<String>,
    pub available: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Reaction {
    pub actor_id: Option<String>,
    pub kind: ReactionKind,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
pub enum ReactionKind {
    Love,
    Like,
    Dislike,
    Laugh,
    Emphasis,
    Question,
    Emoji(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_fixture_round_trips() {
        let fixture = include_str!("../../../protocol/fixtures/v1/status-response.json");
        let value: StatusResponse = serde_json::from_str(fixture).unwrap();
        assert_eq!(value.protocol_version, PROTOCOL_VERSION);
        assert_eq!(value.server_version, "0.1.0");

        let encoded = serde_json::to_value(value).unwrap();
        let expected: serde_json::Value = serde_json::from_str(fixture).unwrap();
        assert_eq!(encoded, expected);
    }

    #[test]
    fn sync_fixture_round_trips() {
        let fixture = include_str!("../../../protocol/fixtures/v1/sync-response.json");
        let value: SyncResponse = serde_json::from_str(fixture).unwrap();
        assert!(!value.has_more);
        assert_eq!(value.messages.len(), 2);

        let encoded = serde_json::to_value(value).unwrap();
        let expected: serde_json::Value = serde_json::from_str(fixture).unwrap();
        assert_eq!(encoded, expected);
    }

    #[test]
    fn event_fixture_round_trips() {
        let fixture = include_str!("../../../protocol/fixtures/v1/message-event.json");
        let value: Event = serde_json::from_str(fixture).unwrap();
        assert!(matches!(value.payload, EventPayload::MessageUpsert { .. }));

        let encoded = serde_json::to_value(value).unwrap();
        let expected: serde_json::Value = serde_json::from_str(fixture).unwrap();
        assert_eq!(encoded, expected);
    }

    #[test]
    fn request_rejects_unknown_fields() {
        let request = r#"{
            "type":"status",
            "request_id":"req-example",
            "protocol_version":1,
            "command":"arbitrary"
        }"#;
        assert!(serde_json::from_str::<Request>(request).is_err());
    }

    #[test]
    fn request_validation_is_fail_closed() {
        let invalid_version = Request::Status {
            request_id: "req-example".into(),
            protocol_version: 2,
        };
        assert_eq!(
            invalid_version.validate(),
            Err(ValidationError::UnsupportedProtocolVersion(2))
        );

        let invalid_limit = Request::Sync {
            request_id: "req-example".into(),
            protocol_version: PROTOCOL_VERSION,
            cursor: None,
            limit: 0,
        };
        assert_eq!(
            invalid_limit.validate(),
            Err(ValidationError::InvalidSyncLimit(0))
        );
    }

    #[test]
    fn cursor_is_scoped_to_source_and_generation() {
        let source = Source {
            instance: "source-example".into(),
            database_generation: "generation-a".into(),
        };
        let cursor = Cursor {
            source_instance: source.instance.clone(),
            database_generation: source.database_generation.clone(),
            rowid: 42,
        };
        assert!(cursor.belongs_to(&source));

        let replacement = Source {
            instance: source.instance.clone(),
            database_generation: "generation-b".into(),
        };
        assert!(!cursor.belongs_to(&replacement));
    }

    #[test]
    fn response_models_accept_additive_fields() {
        let fixture = r#"{
            "request_id":"req-example",
            "protocol_version":1,
            "server_version":"0.1.0",
            "source":{"instance":"source-example","database_generation":"generation-a"},
            "capabilities":{"read_messages":true,"watch_messages":true,"send_text":false,"send_attachments":false,"send_reactions":false},
            "future_optional_field":true
        }"#;
        assert!(serde_json::from_str::<StatusResponse>(fixture).is_ok());
    }
}

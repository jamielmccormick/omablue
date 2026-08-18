use std::collections::{HashSet, VecDeque};

use omablue_protocol::{Event, EventPayload, Source};
use serde_json::Value;

pub const MAX_EVENT_ID_BYTES: usize = 256;

#[derive(Debug)]
pub enum WatchError {
    InvalidEvent,
    EventIdTooLarge,
    SourceMismatch,
    ResyncRequired,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventDecision {
    Apply,
    Duplicate,
    ResyncRequired,
}

pub struct EventLedger {
    source: Source,
    cursor: omablue_protocol::Cursor,
    capacity: usize,
    event_ids: HashSet<String>,
    order: VecDeque<String>,
}

impl EventLedger {
    pub fn new(
        source: Source,
        cursor: omablue_protocol::Cursor,
        capacity: usize,
    ) -> Result<Self, WatchError> {
        if capacity == 0 || !cursor.belongs_to(&source) {
            return Err(WatchError::SourceMismatch);
        }
        Ok(Self {
            source,
            cursor,
            capacity,
            event_ids: HashSet::new(),
            order: VecDeque::new(),
        })
    }

    pub fn decode(value: Value) -> Result<Event, WatchError> {
        serde_json::from_value(value).map_err(|_| WatchError::InvalidEvent)
    }

    pub fn classify(&self, event: &Event) -> Result<EventDecision, WatchError> {
        self.validate_event(event)?;
        if matches!(&event.payload, EventPayload::ResyncRequired { .. }) {
            return Ok(EventDecision::ResyncRequired);
        }
        if self.event_ids.contains(&event.event_id) {
            return Ok(EventDecision::Duplicate);
        }
        Ok(EventDecision::Apply)
    }

    pub fn commit(&mut self, event: &Event) -> Result<(), WatchError> {
        if matches!(&event.payload, EventPayload::ResyncRequired { .. }) {
            return Err(WatchError::ResyncRequired);
        }
        self.validate_event(event)?;
        if self.event_ids.insert(event.event_id.clone()) {
            self.order.push_back(event.event_id.clone());
            while self.order.len() > self.capacity {
                if let Some(expired) = self.order.pop_front() {
                    self.event_ids.remove(&expired);
                }
            }
        }
        self.cursor = event.cursor.clone();
        Ok(())
    }

    pub fn reset(
        &mut self,
        source: Source,
        cursor: omablue_protocol::Cursor,
    ) -> Result<(), WatchError> {
        if !cursor.belongs_to(&source) {
            return Err(WatchError::SourceMismatch);
        }
        self.source = source;
        self.cursor = cursor;
        self.event_ids.clear();
        self.order.clear();
        Ok(())
    }

    pub fn cursor(&self) -> &omablue_protocol::Cursor {
        &self.cursor
    }

    pub fn source(&self) -> &Source {
        &self.source
    }

    fn validate_event(&self, event: &Event) -> Result<(), WatchError> {
        if event.event_id.is_empty() {
            return Err(WatchError::InvalidEvent);
        }
        if event.event_id.len() > MAX_EVENT_ID_BYTES {
            return Err(WatchError::EventIdTooLarge);
        }
        if matches!(&event.payload, EventPayload::ResyncRequired { .. }) {
            return Ok(());
        }
        if !event.cursor.belongs_to(&self.source) {
            return Err(WatchError::SourceMismatch);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use omablue_protocol::{Cursor, EventPayload, ResyncReason};

    fn source(generation: &str) -> Source {
        Source {
            instance: "source".into(),
            database_generation: generation.into(),
        }
    }

    fn cursor(generation: &str, rowid: u64) -> Cursor {
        Cursor {
            source_instance: "source".into(),
            database_generation: generation.into(),
            rowid,
        }
    }

    fn event(id: &str, rowid: u64) -> Event {
        Event {
            protocol_version: 1,
            event_id: id.into(),
            cursor: cursor("generation", rowid),
            recorded_at: "2026-08-17T00:00:00Z".into(),
            payload: EventPayload::MessageDeleted {
                message_id: "message".into(),
            },
        }
    }

    #[test]
    fn cursor_advances_only_after_commit_and_replays_are_deduplicated() {
        let mut ledger =
            EventLedger::new(source("generation"), cursor("generation", 0), 2).unwrap();
        let first = event("event-1", 1);
        assert_eq!(ledger.classify(&first).unwrap(), EventDecision::Apply);
        assert_eq!(ledger.cursor().rowid, 0);
        ledger.commit(&first).unwrap();
        assert_eq!(ledger.cursor().rowid, 1);
        assert_eq!(ledger.classify(&first).unwrap(), EventDecision::Duplicate);
    }

    #[test]
    fn generation_mismatch_fails_closed() {
        let ledger = EventLedger::new(source("generation"), cursor("generation", 0), 2).unwrap();
        let mut replacement = event("event-2", 2);
        replacement.cursor = cursor("replacement", 2);
        assert!(matches!(
            ledger.classify(&replacement),
            Err(WatchError::SourceMismatch)
        ));
    }

    #[test]
    fn resync_does_not_advance_or_enter_the_dedupe_window() {
        let mut ledger =
            EventLedger::new(source("generation"), cursor("generation", 4), 2).unwrap();
        let event = Event {
            protocol_version: 1,
            event_id: "resync-1".into(),
            cursor: cursor("generation", 4),
            recorded_at: "2026-08-17T00:00:00Z".into(),
            payload: EventPayload::ResyncRequired {
                reason: ResyncReason::DatabaseGenerationChanged,
            },
        };
        assert_eq!(
            ledger.classify(&event).unwrap(),
            EventDecision::ResyncRequired
        );
        assert_eq!(ledger.cursor().rowid, 4);
        assert!(matches!(
            ledger.commit(&event),
            Err(WatchError::ResyncRequired)
        ));
    }
}

use std::env;
use std::fs;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

use omablue_helper::{
    CursorStore, ReadOnlySession, SessionError, SshTransportConfig, TransportError,
};
use omablue_protocol::PROTOCOL_VERSION;
use serde::Deserialize;
use serde_json::{Value, json};

const MAX_LOCAL_FRAME_BYTES: usize = 65_536;

#[derive(Debug, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case", deny_unknown_fields)]
enum LocalCommand {
    Status {
        request_id: String,
        protocol_version: u16,
    },
    Sync {
        request_id: String,
        protocol_version: u16,
        limit: u16,
    },
    Ack {
        request_id: String,
        protocol_version: u16,
        acknowledged_request_id: String,
    },
    Reset {
        request_id: String,
        protocol_version: u16,
    },
}

impl LocalCommand {
    fn request_id(&self) -> &str {
        match self {
            Self::Status { request_id, .. }
            | Self::Sync { request_id, .. }
            | Self::Ack { request_id, .. }
            | Self::Reset { request_id, .. } => request_id,
        }
    }

    fn protocol_version(&self) -> u16 {
        match self {
            Self::Status {
                protocol_version, ..
            }
            | Self::Sync {
                protocol_version, ..
            }
            | Self::Ack {
                protocol_version, ..
            }
            | Self::Reset {
                protocol_version, ..
            } => *protocol_version,
        }
    }

    fn valid(&self) -> bool {
        let valid_limit = match self {
            Self::Sync { limit, .. } => (1..=omablue_protocol::MAX_SYNC_LIMIT).contains(limit),
            _ => true,
        };
        !self.request_id().is_empty() && self.protocol_version() == PROTOCOL_VERSION && valid_limit
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct HelperConfig {
    destination: String,
    identity_file: PathBuf,
    identity_agent: PathBuf,
    known_hosts_file: PathBuf,
    #[serde(default)]
    state_file: Option<PathBuf>,
}

struct PendingSync {
    request_id: String,
    response: omablue_protocol::SyncResponse,
}

fn main() {
    let announce_status = env::args().nth(1).as_deref() == Some("--announce-status");
    if run(announce_status).is_err() {
        std::process::exit(1);
    }
}

fn run(announce_status: bool) -> Result<(), ()> {
    let config = load_config()?;
    let state_file = config.state_file.unwrap_or(default_state_path()?);
    let store = CursorStore::open(state_file).map_err(|_| ())?;
    let transport = SshTransportConfig::new(
        config.destination,
        config.identity_file,
        config.identity_agent,
        config.known_hosts_file,
    );
    let session = ReadOnlySession::new(transport, store);
    let stdin = io::stdin();
    let mut input = BufReader::new(stdin.lock());
    let stdout = io::stdout();
    let mut output = BufWriter::new(stdout.lock());
    let mut pending_sync: Option<PendingSync> = None;

    if announce_status {
        let response = match session.status("startup-status") {
            Ok(response) => serde_json::to_value(response).map_err(|_| ())?,
            Err(error) => error_response(Some("startup-status"), session_error_code(&error)),
        };
        write_frame(&mut output, &response)?;
    }

    loop {
        let Some(value) = read_frame(&mut input)? else {
            return Ok(());
        };
        let command: LocalCommand = match serde_json::from_slice(&value) {
            Ok(command) => command,
            Err(_) => {
                write_frame(&mut output, &error_response(None, "invalid_local_request"))?;
                continue;
            }
        };
        if !command.valid() {
            write_frame(
                &mut output,
                &error_response(Some(command.request_id()), "invalid_local_request"),
            )?;
            continue;
        }

        match command {
            LocalCommand::Status { request_id, .. } => {
                if pending_sync.is_some() {
                    write_frame(
                        &mut output,
                        &error_response(Some(&request_id), "sync_ack_required"),
                    )?;
                    continue;
                }
                match session.status(request_id.clone()) {
                    Ok(response) => write_frame(
                        &mut output,
                        &serde_json::to_value(response).map_err(|_| ())?,
                    )?,
                    Err(error) => write_frame(
                        &mut output,
                        &error_response(Some(&request_id), session_error_code(&error)),
                    )?,
                }
            }
            LocalCommand::Sync {
                request_id, limit, ..
            } => {
                if pending_sync.is_some() {
                    write_frame(
                        &mut output,
                        &error_response(Some(&request_id), "sync_ack_required"),
                    )?;
                    continue;
                }
                match session.sync(request_id.clone(), limit) {
                    Ok(response) => {
                        write_frame(
                            &mut output,
                            &serde_json::to_value(&response).map_err(|_| ())?,
                        )?;
                        pending_sync = Some(PendingSync {
                            request_id,
                            response,
                        });
                    }
                    Err(error) => write_frame(
                        &mut output,
                        &error_response(Some(&request_id), session_error_code(&error)),
                    )?,
                }
            }
            LocalCommand::Ack {
                request_id,
                acknowledged_request_id,
                ..
            } => {
                let Some(pending) = pending_sync.as_ref() else {
                    write_frame(
                        &mut output,
                        &error_response(Some(&request_id), "no_pending_sync"),
                    )?;
                    continue;
                };
                if pending.request_id != acknowledged_request_id {
                    write_frame(
                        &mut output,
                        &error_response(Some(&request_id), "sync_commit_failed"),
                    )?;
                    continue;
                }
                if session.commit_sync(&pending.response).is_err() {
                    write_frame(
                        &mut output,
                        &error_response(Some(&request_id), "sync_commit_failed"),
                    )?;
                    continue;
                }
                pending_sync = None;
                write_frame(
                    &mut output,
                    &json!({
                        "type": "ack",
                        "request_id": request_id,
                        "protocol_version": PROTOCOL_VERSION,
                        "acknowledged_request_id": acknowledged_request_id,
                    }),
                )?;
            }
            LocalCommand::Reset { request_id, .. } => {
                if pending_sync.is_some() || session.reset_cursor().is_err() {
                    write_frame(
                        &mut output,
                        &error_response(Some(&request_id), "reset_failed"),
                    )?;
                    continue;
                }
                write_frame(
                    &mut output,
                    &json!({
                        "type": "reset",
                        "request_id": request_id,
                        "protocol_version": PROTOCOL_VERSION,
                    }),
                )?;
            }
        }
    }
}

fn load_config() -> Result<HelperConfig, ()> {
    let path = config_path()?;
    let metadata = fs::symlink_metadata(&path).map_err(|_| ())?;
    if !metadata.is_file() || metadata.permissions().mode() & 0o077 != 0 {
        return Err(());
    }
    let data = fs::read(path).map_err(|_| ())?;
    if data.len() > 16_384 {
        return Err(());
    }
    serde_json::from_slice(&data).map_err(|_| ())
}

fn config_path() -> Result<PathBuf, ()> {
    let home = env::var_os("HOME").map(PathBuf::from).ok_or(())?;
    if let Some(config_home) = env::var_os("XDG_CONFIG_HOME").map(PathBuf::from) {
        if config_home.is_absolute() {
            return Ok(config_home.join("omablue/config.json"));
        }
    }
    Ok(home.join(".config/omablue/config.json"))
}

fn default_state_path() -> Result<PathBuf, ()> {
    let home = env::var_os("HOME").map(PathBuf::from).ok_or(())?;
    if let Some(state_home) = env::var_os("XDG_STATE_HOME").map(PathBuf::from) {
        if state_home.is_absolute() {
            return Ok(state_home.join("omablue/cursor.json"));
        }
    }
    Ok(home.join(".local/state/omablue/cursor.json"))
}

fn read_frame(reader: &mut impl BufRead) -> Result<Option<Vec<u8>>, ()> {
    let mut frame = Vec::new();
    let count = reader.read_until(b'\n', &mut frame).map_err(|_| ())?;
    if count == 0 {
        return Ok(None);
    }
    if frame.len() > MAX_LOCAL_FRAME_BYTES || frame.last() != Some(&b'\n') {
        return Err(());
    }
    frame.pop();
    if frame.last() == Some(&b'\r') {
        frame.pop();
    }
    Ok(Some(frame))
}

fn write_frame(writer: &mut impl Write, value: &Value) -> Result<(), ()> {
    let mut data = serde_json::to_vec(value).map_err(|_| ())?;
    if data.len() > MAX_LOCAL_FRAME_BYTES {
        return Err(());
    }
    data.push(b'\n');
    writer.write_all(&data).map_err(|_| ())?;
    writer.flush().map_err(|_| ())
}

fn error_response(request_id: Option<&str>, code: &str) -> Value {
    json!({
        "type": "error",
        "request_id": request_id,
        "protocol_version": PROTOCOL_VERSION,
        "code": code,
    })
}

fn session_error_code(error: &SessionError) -> &str {
    if let Some(code) = error.remote_code() {
        return code;
    }
    match error {
        SessionError::Transport(TransportError::UnexpectedEndOfStream) => "ssh_eof",
        SessionError::Transport(TransportError::Io(_)) => "ssh_io_error",
        SessionError::Transport(TransportError::Json(_)) => "ssh_json_error",
        SessionError::Transport(TransportError::InvalidFrame) => "ssh_invalid_frame",
        SessionError::Transport(TransportError::FrameTooLarge) => "ssh_frame_too_large",
        SessionError::RequestIdMismatch => "request_id_mismatch",
        SessionError::InvalidResponse => "invalid_remote_response",
        SessionError::State(_) => "state_error",
        SessionError::Watch(_) => "watch_error",
        SessionError::Json(_) => "json_error",
        SessionError::NoCursor => "cursor_missing",
        SessionError::Transport(_) => "remote_unavailable",
    }
}

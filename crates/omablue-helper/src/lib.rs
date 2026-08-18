use std::ffi::OsString;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, ExitStatus, Stdio};

use omablue_protocol::{Request, ValidationError};
use serde_json::Value;

mod session;
mod state;
mod watch;

pub use session::{ReadOnlySession, SessionError, WatchItem, WatchSession, response_request_id};
pub use state::{CursorStore, StateError, StoredCursor};
pub use watch::{EventDecision, EventLedger, MAX_EVENT_ID_BYTES, WatchError};

pub const MAX_FRAME_BYTES: usize = 1_048_576;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SshTransportConfig {
    pub ssh_program: PathBuf,
    pub destination: String,
    pub identity_file: PathBuf,
    pub identity_agent: PathBuf,
    pub known_hosts_file: PathBuf,
}

impl SshTransportConfig {
    pub fn new(
        destination: impl Into<String>,
        identity_file: impl Into<PathBuf>,
        identity_agent: impl Into<PathBuf>,
        known_hosts_file: impl Into<PathBuf>,
    ) -> Self {
        Self {
            ssh_program: PathBuf::from("/usr/bin/ssh"),
            destination: destination.into(),
            identity_file: identity_file.into(),
            identity_agent: identity_agent.into(),
            known_hosts_file: known_hosts_file.into(),
        }
    }

    fn validate(&self) -> Result<(), TransportError> {
        if !self.ssh_program.is_absolute() {
            return Err(TransportError::InvalidConfiguration(
                "ssh_program must be an absolute path",
            ));
        }
        if self.destination.is_empty()
            || self.destination.starts_with('-')
            || self
                .destination
                .bytes()
                .any(|byte| byte == 0 || byte.is_ascii_whitespace() || byte.is_ascii_control())
        {
            return Err(TransportError::InvalidConfiguration(
                "destination contains an invalid byte",
            ));
        }
        validate_file_path(&self.identity_file, "identity_file")?;
        validate_file_path(&self.identity_agent, "identity_agent")?;
        validate_file_path(&self.known_hosts_file, "known_hosts_file")?;
        Ok(())
    }

    fn command_args(&self) -> Vec<OsString> {
        let mut args = vec![
            OsString::from("-F"),
            OsString::from("/dev/null"),
            OsString::from("-T"),
            OsString::from("-o"),
            OsString::from("BatchMode=yes"),
            OsString::from("-o"),
            OsString::from("RequestTTY=no"),
            OsString::from("-o"),
            OsString::from("ClearAllForwardings=yes"),
            OsString::from("-o"),
            OsString::from("ForwardAgent=no"),
            OsString::from("-o"),
            OsString::from("ForwardX11=no"),
            OsString::from("-o"),
            OsString::from("PermitLocalCommand=no"),
            OsString::from("-o"),
            OsString::from("ProxyCommand=none"),
            OsString::from("-o"),
            OsString::from("ProxyJump=none"),
            OsString::from("-o"),
            OsString::from("ControlMaster=no"),
            OsString::from("-o"),
            OsString::from("RemoteCommand=none"),
            OsString::from("-o"),
            OsString::from("PermitRemoteOpen=none"),
            OsString::from("-o"),
            OsString::from("SendEnv=none"),
            OsString::from("-o"),
            OsString::from("StrictHostKeyChecking=yes"),
            OsString::from("-o"),
            OsString::from("IdentitiesOnly=yes"),
            OsString::from("-o"),
            OsString::from("ConnectTimeout=10"),
            OsString::from("-o"),
            OsString::from("ServerAliveInterval=30"),
            OsString::from("-o"),
            OsString::from("ServerAliveCountMax=3"),
            OsString::from("-o"),
            OsString::from(format!(
                "UserKnownHostsFile={}",
                self.known_hosts_file.display()
            )),
            OsString::from("-o"),
            OsString::from(format!("IdentityAgent={}", self.identity_agent.display())),
            OsString::from("-i"),
            self.identity_file.as_os_str().to_owned(),
            OsString::from(&self.destination),
        ];
        args.shrink_to_fit();
        args
    }
}

fn validate_file_path(path: &Path, name: &'static str) -> Result<(), TransportError> {
    if path.as_os_str().is_empty() || !path.is_absolute() || path.to_string_lossy().contains('\0') {
        return Err(TransportError::InvalidConfiguration(name));
    }
    Ok(())
}

fn harden_environment(command: &mut Command) {
    command.env_clear().env("PATH", "/usr/bin:/bin");
    if let Some(home) = std::env::var_os("HOME") {
        command.env("HOME", home);
    }
    if let Some(agent_socket) = std::env::var_os("SSH_AUTH_SOCK") {
        command.env("SSH_AUTH_SOCK", agent_socket);
    }
}

#[derive(Debug)]
pub enum TransportError {
    InvalidConfiguration(&'static str),
    InvalidRequest(ValidationError),
    InvalidFrame,
    FrameTooLarge,
    UnexpectedEndOfStream,
    RequestIdMismatch,
    RemoteError(String),
    Closed,
    Io(io::Error),
    Json(serde_json::Error),
}

impl From<io::Error> for TransportError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<serde_json::Error> for TransportError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

pub struct SshBridge {
    child: Child,
    stdin: Option<BufWriter<ChildStdin>>,
    stdout: BufReader<ChildStdout>,
}

impl SshBridge {
    pub fn connect(config: &SshTransportConfig) -> Result<Self, TransportError> {
        config.validate()?;

        let mut command = Command::new(&config.ssh_program);
        command
            .args(config.command_args())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        harden_environment(&mut command);

        let mut child = command.spawn()?;
        let stdin = child
            .stdin
            .take()
            .ok_or(TransportError::UnexpectedEndOfStream)?;
        let stdout = child
            .stdout
            .take()
            .ok_or(TransportError::UnexpectedEndOfStream)?;

        Ok(Self {
            child,
            stdin: Some(BufWriter::new(stdin)),
            stdout: BufReader::new(stdout),
        })
    }

    pub fn request(&mut self, request: &Request) -> Result<Value, TransportError> {
        request.validate().map_err(TransportError::InvalidRequest)?;
        if matches!(request, Request::Watch { .. }) {
            return Err(TransportError::InvalidConfiguration(
                "watch requests require begin_watch",
            ));
        }

        self.write_json(request)?;
        self.close_stdin()?;
        let response = self.read_json()?;
        validate_response(&response, request_id(request))?;
        Ok(response)
    }

    pub fn begin_watch(&mut self, request: &Request) -> Result<(), TransportError> {
        request.validate().map_err(TransportError::InvalidRequest)?;
        if !matches!(request, Request::Watch { .. }) {
            return Err(TransportError::InvalidConfiguration(
                "begin_watch requires a watch request",
            ));
        }
        self.write_json(request)?;
        self.close_stdin()
    }

    pub fn next_frame(&mut self) -> Result<Value, TransportError> {
        self.read_json()
    }

    pub fn shutdown(mut self) -> Result<ExitStatus, TransportError> {
        self.close_stdin()?;
        Ok(self.child.wait()?)
    }

    fn close_stdin(&mut self) -> Result<(), TransportError> {
        if let Some(mut stdin) = self.stdin.take() {
            stdin.flush()?;
        }
        Ok(())
    }

    fn write_json<T: serde::Serialize>(&mut self, value: &T) -> Result<(), TransportError> {
        let mut frame = serde_json::to_vec(value)?;
        if frame.len() > MAX_FRAME_BYTES {
            return Err(TransportError::FrameTooLarge);
        }
        frame.push(b'\n');
        let stdin = self.stdin.as_mut().ok_or(TransportError::Closed)?;
        stdin.write_all(&frame)?;
        stdin.flush()?;
        Ok(())
    }

    fn read_json(&mut self) -> Result<Value, TransportError> {
        let mut frame = Vec::new();
        let bytes = self.stdout.read_until(b'\n', &mut frame)?;
        if bytes == 0 {
            return Err(TransportError::UnexpectedEndOfStream);
        }
        if frame.len() > MAX_FRAME_BYTES + 1 || frame.last() != Some(&b'\n') {
            return Err(TransportError::FrameTooLarge);
        }
        frame.pop();
        if frame.last() == Some(&b'\r') {
            frame.pop();
        }
        if frame.is_empty() {
            return Err(TransportError::InvalidFrame);
        }
        Ok(serde_json::from_slice(&frame)?)
    }
}

impl Drop for SshBridge {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn request_id(request: &Request) -> &str {
    match request {
        Request::Status { request_id, .. }
        | Request::Sync { request_id, .. }
        | Request::Watch { request_id, .. } => request_id,
    }
}

fn validate_response(response: &Value, expected_request_id: &str) -> Result<(), TransportError> {
    let object = response.as_object().ok_or(TransportError::InvalidFrame)?;
    if object.get("request_id").and_then(Value::as_str) != Some(expected_request_id) {
        return Err(TransportError::RequestIdMismatch);
    }
    if object.get("type").and_then(Value::as_str) == Some("error") {
        let code = object
            .get("code")
            .and_then(Value::as_str)
            .ok_or(TransportError::InvalidFrame)?;
        return Err(TransportError::RemoteError(code.to_owned()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temporary_script(body: &str) -> (PathBuf, PathBuf) {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!("omablue-helper-{suffix}"));
        fs::create_dir(&directory).unwrap();
        let script = directory.join("fake-ssh");
        fs::write(&script, body).unwrap();
        fs::set_permissions(&script, fs::Permissions::from_mode(0o700)).unwrap();
        (directory, script)
    }

    fn config(script: PathBuf) -> SshTransportConfig {
        SshTransportConfig {
            ssh_program: script,
            destination: "user@mac.example".into(),
            identity_file: PathBuf::from("/tmp/omablue-test-key"),
            identity_agent: PathBuf::from("/tmp/omablue-test-agent"),
            known_hosts_file: PathBuf::from("/tmp/omablue-test-known-hosts"),
        }
    }

    #[test]
    fn command_disables_interactive_and_forwarding_features() {
        let (directory, script) = temporary_script("#!/bin/sh\ncat\n");
        let args = config(script).command_args();
        let args: Vec<String> = args
            .into_iter()
            .map(|arg| arg.into_string().unwrap())
            .collect();
        assert!(args.contains(&"-T".into()));
        assert!(args.contains(&"/dev/null".into()));
        assert!(args.contains(&"RequestTTY=no".into()));
        assert!(args.contains(&"ClearAllForwardings=yes".into()));
        assert!(args.contains(&"ForwardAgent=no".into()));
        assert!(args.contains(&"ForwardX11=no".into()));
        assert!(args.contains(&"ProxyCommand=none".into()));
        assert!(args.contains(&"ProxyJump=none".into()));
        assert!(args.contains(&"RemoteCommand=none".into()));
        assert!(args.contains(&"SendEnv=none".into()));
        assert!(args.contains(&"IdentityAgent=/tmp/omablue-test-agent".into()));
        assert_eq!(args.last().unwrap(), "user@mac.example");
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn round_trip_is_bounded_and_validates_request_id() {
        let (directory, script) = temporary_script(
            "#!/bin/sh\nread request\nprintf '%s\\n' '{\"request_id\":\"req-1\",\"protocol_version\":1}'\n",
        );
        let mut bridge = SshBridge::connect(&config(script)).unwrap();
        let request = Request::Status {
            request_id: "req-1".into(),
            protocol_version: 1,
        };
        let response = bridge.request(&request).unwrap();
        assert_eq!(response["protocol_version"], 1);
        drop(bridge);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn watch_is_write_only_until_frames_arrive() {
        let (directory, script) = temporary_script(
            "#!/bin/sh\nread request\nprintf '%s\\n' '{\"event_type\":\"resync_required\"}'\n",
        );
        let mut bridge = SshBridge::connect(&config(script)).unwrap();
        let request = Request::Watch {
            request_id: "watch-1".into(),
            protocol_version: 1,
            cursor: omablue_protocol::Cursor {
                source_instance: "source".into(),
                database_generation: "generation".into(),
                rowid: 0,
            },
        };
        bridge.begin_watch(&request).unwrap();
        let frame = bridge.next_frame().unwrap();
        assert_eq!(frame["event_type"], "resync_required");
        drop(bridge);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn oversized_response_frame_is_rejected() {
        let (directory, script) = temporary_script(
            "#!/bin/sh\nread request\nhead -c 1048577 /dev/zero | tr '\\000' a\nprintf '\\n'\n",
        );
        let mut bridge = SshBridge::connect(&config(script)).unwrap();
        let request = Request::Status {
            request_id: "req-oversized".into(),
            protocol_version: 1,
        };
        assert!(matches!(
            bridge.request(&request),
            Err(TransportError::FrameTooLarge)
        ));
        drop(bridge);
        fs::remove_dir_all(directory).unwrap();
    }
}

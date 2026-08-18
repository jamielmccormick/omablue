use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

use omablue_protocol::{Cursor, PROTOCOL_VERSION, Source};
use serde::{Deserialize, Serialize};

#[derive(Debug)]
pub enum StateError {
    InvalidPath,
    UnsafePath,
    CursorSourceMismatch,
    CorruptState,
    Io(io::Error),
    Json(serde_json::Error),
}

impl From<io::Error> for StateError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<serde_json::Error> for StateError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StoredCursor {
    pub protocol_version: u16,
    pub source: Source,
    pub cursor: Cursor,
}

#[derive(Clone)]
pub struct CursorStore {
    path: PathBuf,
}

impl CursorStore {
    pub fn open(path: impl Into<PathBuf>) -> Result<Self, StateError> {
        let path = path.into();
        validate_path(&path)?;
        ensure_secure_parent(path.parent().ok_or(StateError::InvalidPath)?)?;
        if let Ok(metadata) = fs::symlink_metadata(&path) {
            validate_secure_file(&metadata)?;
        }
        Ok(Self { path })
    }

    pub fn load(&self) -> Result<Option<StoredCursor>, StateError> {
        let data = match fs::read(&self.path) {
            Ok(data) => data,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        let stored: StoredCursor = serde_json::from_slice(&data).map_err(|error| {
            let _ = error;
            StateError::CorruptState
        })?;
        if stored.protocol_version != PROTOCOL_VERSION || !stored.cursor.belongs_to(&stored.source)
        {
            return Err(StateError::CorruptState);
        }
        Ok(Some(stored))
    }

    pub fn commit(&self, source: &Source, cursor: &Cursor) -> Result<(), StateError> {
        if !cursor.belongs_to(source) {
            return Err(StateError::CursorSourceMismatch);
        }
        let stored = StoredCursor {
            protocol_version: PROTOCOL_VERSION,
            source: source.clone(),
            cursor: cursor.clone(),
        };
        let data = serde_json::to_vec(&stored)?;
        if data.len() > 16_384 {
            return Err(StateError::CorruptState);
        }

        let parent = self.path.parent().ok_or(StateError::InvalidPath)?;
        let temporary = temporary_path(&self.path);
        let result = (|| -> Result<(), StateError> {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&temporary)?;
            file.write_all(&data)?;
            file.sync_all()?;
            fs::set_permissions(&temporary, fs::Permissions::from_mode(0o600))?;
            fs::rename(&temporary, &self.path)?;
            let metadata = fs::symlink_metadata(&self.path)?;
            validate_secure_file(&metadata)?;
            let directory = File::open(parent)?;
            directory.sync_all()?;
            Ok(())
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn clear(&self) -> Result<(), StateError> {
        match fs::symlink_metadata(&self.path) {
            Ok(metadata) => {
                validate_secure_file(&metadata)?;
                fs::remove_file(&self.path)?;
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(error.into()),
        }
        let parent = self.path.parent().ok_or(StateError::InvalidPath)?;
        File::open(parent)?.sync_all()?;
        Ok(())
    }
}

fn validate_path(path: &Path) -> Result<(), StateError> {
    if path.as_os_str().is_empty() || !path.is_absolute() {
        return Err(StateError::InvalidPath);
    }
    Ok(())
}

fn ensure_secure_parent(parent: &Path) -> Result<(), StateError> {
    match fs::symlink_metadata(parent) {
        Ok(metadata) => validate_secure_directory(&metadata),
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            fs::create_dir_all(parent)?;
            fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
            let metadata = fs::symlink_metadata(parent)?;
            validate_secure_directory(&metadata)
        }
        Err(error) => Err(error.into()),
    }
}

fn validate_secure_directory(metadata: &fs::Metadata) -> Result<(), StateError> {
    if !metadata.is_dir() || metadata.permissions().mode() & 0o077 != 0 {
        return Err(StateError::UnsafePath);
    }
    Ok(())
}

fn validate_secure_file(metadata: &fs::Metadata) -> Result<(), StateError> {
    if !metadata.is_file() || metadata.permissions().mode() & 0o077 != 0 {
        return Err(StateError::UnsafePath);
    }
    Ok(())
}

fn temporary_path(path: &Path) -> PathBuf {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_nanos());
    let name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("cursor.json");
    path.with_file_name(format!(".{name}.tmp-{}-{stamp}", process::id()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn temporary_root() -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("omablue-state-{stamp}"))
    }

    fn source() -> Source {
        Source {
            instance: "source".into(),
            database_generation: "generation".into(),
        }
    }

    fn cursor() -> Cursor {
        Cursor {
            source_instance: "source".into(),
            database_generation: "generation".into(),
            rowid: 42,
        }
    }

    #[test]
    fn cursor_commit_round_trips_with_secure_modes() {
        let root = temporary_root();
        let path = root.join("cursor.json");
        let store = CursorStore::open(&path).unwrap();
        store.commit(&source(), &cursor()).unwrap();

        let loaded = store.load().unwrap().unwrap();
        assert_eq!(loaded.cursor, cursor());
        assert_eq!(
            fs::metadata(&root).unwrap().permissions().mode() & 0o777,
            0o700
        );
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn mismatched_cursor_cannot_be_committed() {
        let root = temporary_root();
        let store = CursorStore::open(root.join("cursor.json")).unwrap();
        let mut replacement = cursor();
        replacement.database_generation = "replacement".into();
        assert!(matches!(
            store.commit(&source(), &replacement),
            Err(StateError::CursorSourceMismatch)
        ));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn corrupt_state_is_not_silently_reset() {
        let root = temporary_root();
        let path = root.join("cursor.json");
        let store = CursorStore::open(&path).unwrap();
        fs::write(&path, b"not-json").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
        assert!(matches!(store.load(), Err(StateError::CorruptState)));
        fs::remove_dir_all(root).unwrap();
    }
}

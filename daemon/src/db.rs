use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::{Connection, params};
use serde::Serialize;
use zbus::zvariant::Type;

#[derive(Debug, Clone, Serialize, Type)]
pub struct NoteRecord {
    pub id: i64,
    pub content: String,
    pub created_at: String,
    pub alarm_at: i64,
    pub alarm_fired: bool,
}

pub fn unix_timestamp_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn app_data_dir() -> PathBuf {
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
        .unwrap_or_else(std::env::temp_dir);
    base.join("CatchyPills")
}

pub fn init_database() -> Result<(Connection, PathBuf), rusqlite::Error> {
    let data_dir = app_data_dir();
    let clips_dir = data_dir.join("clips");
    let _ = fs::create_dir_all(&clips_dir);

    let conn = Connection::open(data_dir.join("catchypills.db3"))?;
    conn.execute_batch(
        "
        PRAGMA journal_mode = WAL;
        PRAGMA busy_timeout = 5000;
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            mime TEXT NOT NULL,
            preview TEXT NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            image_path TEXT NOT NULL DEFAULT '',
            content_hash TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_clipboard_hash ON clipboard_items(kind, content_hash);
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY,
            content TEXT,
            created_at DATETIME,
            alarm_at INTEGER NULL,
            alarm_fired INTEGER NOT NULL DEFAULT 0
        );
        ",
    )?;

    // Soft migrations for existing catchypills.db3 databases without losing notes.
    let _ = conn.execute("ALTER TABLE notes ADD COLUMN alarm_at INTEGER NULL", []);
    let _ = conn.execute(
        "ALTER TABLE notes ADD COLUMN alarm_fired INTEGER NOT NULL DEFAULT 0",
        [],
    );

    Ok((conn, clips_dir))
}

pub fn get_notes(conn: &Connection) -> Vec<NoteRecord> {
    let Ok(mut stmt) = conn.prepare(
        "SELECT id, COALESCE(content, ''), COALESCE(created_at, ''), COALESCE(alarm_at, 0), COALESCE(alarm_fired, 0)
         FROM notes
         ORDER BY id DESC",
    ) else {
        return Vec::new();
    };

    let Ok(rows) = stmt.query_map([], |row| {
        let fired_int: i64 = row.get(4)?;
        Ok(NoteRecord {
            id: row.get(0)?,
            content: row.get(1)?,
            created_at: row.get(2)?,
            alarm_at: row.get(3)?,
            alarm_fired: fired_int != 0,
        })
    }) else {
        return Vec::new();
    };

    rows.flatten().collect()
}

pub fn add_note(conn: &Connection, content: &str, alarm_epoch: Option<i64>) -> Option<i64> {
    let trimmed = content.trim();
    if trimmed.is_empty() {
        return None;
    }

    let alarm_val = alarm_epoch.filter(|&ts| ts > 0);
    conn.execute(
        "INSERT INTO notes (content, created_at, alarm_at, alarm_fired)
         VALUES (?1, datetime('now'), ?2, 0)",
        params![trimmed, alarm_val],
    )
    .ok()?;

    Some(conn.last_insert_rowid())
}

pub fn snooze_note_alarm(conn: &Connection, note_id: i64, new_alarm_epoch: i64) -> bool {
    conn.execute(
        "UPDATE notes SET alarm_at = ?1, alarm_fired = 0 WHERE id = ?2",
        params![new_alarm_epoch, note_id],
    )
    .map(|n| n > 0)
    .unwrap_or(false)
}

pub fn dismiss_note_alarm(conn: &Connection, note_id: i64) -> bool {
    conn.execute(
        "UPDATE notes SET alarm_at = NULL, alarm_fired = 1 WHERE id = ?1",
        params![note_id],
    )
    .map(|n| n > 0)
    .unwrap_or(false)
}

pub fn delete_note(conn: &Connection, note_id: i64) -> bool {
    conn.execute("DELETE FROM notes WHERE id = ?1", params![note_id])
        .map(|n| n > 0)
        .unwrap_or(false)
}

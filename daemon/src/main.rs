mod db;

use std::collections::{HashMap, hash_map::DefaultHasher};
use std::error::Error;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io::Read;
use std::os::fd::AsFd;
use std::path::{Path, PathBuf};
use std::sync::{
    Arc, Mutex, RwLock,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};

use ignore::WalkBuilder;
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use nucleo::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config as MatcherConfig, Matcher, Utf32Str};
use rusqlite::{Connection, params};
use serde::Serialize;
use wayland_client::{
    Connection as WaylandConnection, Dispatch, Proxy, QueueHandle,
    backend::ObjectId,
    delegate_dispatch, event_created_child,
    protocol::{wl_registry, wl_seat},
};
use wayland_protocols::ext::data_control::v1::client::{
    ext_data_control_device_v1::{self, ExtDataControlDeviceV1},
    ext_data_control_manager_v1::ExtDataControlManagerV1,
    ext_data_control_offer_v1::{self, ExtDataControlOfferV1},
};
use zbus::{connection, interface, object_server::SignalEmitter, zvariant::Type};

const DBUS_SERVICE_NAME: &str = "io.hearnelabs.CatchyPillsDaemon";
const DBUS_OBJECT_PATH: &str = "/io/hearnelabs/CatchyPillsDaemon";
const KDE_SECRET_HINT_MIME: &str = "x-kde-passwordManagerHint";
const MAX_CLIPBOARD_BYTES: usize = 32 * 1024 * 1024;

#[derive(Debug, Clone, Serialize, Type)]
struct ClipboardEntryDto {
    id: i64,
    kind: String,
    preview: String,
    created_at: i64,
}

#[derive(Debug, Clone, Serialize, Type)]
struct FileMatchDto {
    name: String,
    path: String,
    score: u32,
}

#[derive(Debug, Clone)]
struct IndexedFile {
    name: String,
    path: String,
}

/// D-Bus IPC surface exposed on the Session Bus for the Qt6/QML frontend.
struct DaemonIpc {
    db: Arc<Mutex<Connection>>,
    file_index: Arc<RwLock<Vec<IndexedFile>>>,
    indexed_count: Arc<AtomicUsize>,
    clipboard_paused: Arc<AtomicBool>,
    itsm_enabled: Arc<AtomicBool>,
}

#[interface(name = "io.hearnelabs.CatchyPillsDaemon1")]
impl DaemonIpc {
    async fn ping(&self) -> String {
        format!(
            "catchypillsd alive (indexed_files={})",
            self.indexed_count.load(Ordering::Relaxed)
        )
    }

    async fn set_clipboard_paused(&self, paused: bool) -> bool {
        self.clipboard_paused.store(paused, Ordering::Relaxed);
        paused
    }

    async fn is_clipboard_paused(&self) -> bool {
        self.clipboard_paused.load(Ordering::Relaxed)
    }

    async fn set_itsm_enabled(&self, enabled: bool) -> bool {
        self.itsm_enabled.store(enabled, Ordering::Relaxed);
        enabled
    }

    async fn is_itsm_enabled(&self) -> bool {
        self.itsm_enabled.load(Ordering::Relaxed)
    }

    async fn get_recent_clips(&self, limit: u32) -> Vec<ClipboardEntryDto> {
        let clamped = limit.clamp(1, 200) as i64;
        let Ok(conn) = self.db.lock() else {
            return Vec::new();
        };
        let Ok(mut stmt) = conn.prepare(
            "SELECT id, kind, preview, created_at
             FROM clipboard_items
             ORDER BY created_at DESC, id DESC
             LIMIT ?1",
        ) else {
            return Vec::new();
        };
        let Ok(rows) = stmt.query_map(params![clamped], |row| {
            Ok(ClipboardEntryDto {
                id: row.get(0)?,
                kind: row.get(1)?,
                preview: row.get(2)?,
                created_at: row.get(3)?,
            })
        }) else {
            return Vec::new();
        };
        rows.flatten().collect()
    }

    async fn search_files(&self, query: String, limit: u32) -> Vec<FileMatchDto> {
        let trimmed = query.trim().to_string();
        if trimmed.is_empty() {
            return Vec::new();
        }
        let max_results = limit.clamp(1, 200) as usize;
        let index = Arc::clone(&self.file_index);

        tokio::task::spawn_blocking(move || {
            let guard = match index.read() {
                Ok(g) => g,
                Err(_) => return Vec::new(),
            };
            let pattern = Pattern::parse(&trimmed, CaseMatching::Ignore, Normalization::Smart);
            let mut matcher = Matcher::new(MatcherConfig::DEFAULT.match_paths());
            let mut buf = Vec::new();

            let mut scored: Vec<FileMatchDto> = guard
                .iter()
                .filter_map(|entry| {
                    buf.clear();
                    let haystack = Utf32Str::new(&entry.path, &mut buf);
                    pattern.score(haystack, &mut matcher).map(|score| FileMatchDto {
                        name: entry.name.clone(),
                        path: entry.path.clone(),
                        score,
                    })
                })
                .collect();

            scored.sort_unstable_by(|a, b| b.score.cmp(&a.score).then_with(|| a.name.len().cmp(&b.name.len())));
            scored.truncate(max_results);
            scored
        })
        .await
        .unwrap_or_default()
    }

    async fn get_notes(&self) -> Vec<db::NoteRecord> {
        let Ok(conn) = self.db.lock() else {
            return Vec::new();
        };
        db::get_notes(&conn)
    }

    async fn add_note(&self, content: String) -> i64 {
        let Ok(conn) = self.db.lock() else {
            return 0;
        };
        db::add_note(&conn, &content, None).unwrap_or(0)
    }

    async fn add_note_with_alarm(&self, content: String, alarm_epoch: i64) -> i64 {
        let Ok(conn) = self.db.lock() else {
            return 0;
        };
        let alarm = if alarm_epoch > 0 { Some(alarm_epoch) } else { None };
        db::add_note(&conn, &content, alarm).unwrap_or(0)
    }

    async fn snooze_note_alarm(&self, note_id: i64, new_alarm_epoch: i64) -> bool {
        let Ok(conn) = self.db.lock() else {
            return false;
        };
        db::snooze_note_alarm(&conn, note_id, new_alarm_epoch)
    }

    async fn dismiss_note_alarm(&self, note_id: i64) -> bool {
        let Ok(conn) = self.db.lock() else {
            return false;
        };
        db::dismiss_note_alarm(&conn, note_id)
    }

    async fn delete_note(&self, note_id: i64) -> bool {
        let Ok(conn) = self.db.lock() else {
            return false;
        };
        db::delete_note(&conn, note_id)
    }

    /// Emitted whenever ext-data-control-v1 captures a non-secret clipboard change.
    #[zbus(signal)]
    async fn clipboard_updated(
        emitter: &SignalEmitter<'_>,
        clip_id: i64,
        preview: &str,
    ) -> zbus::Result<()>;

    /// Emitted when ITSM integration is enabled and HTML markup is copied.
    #[zbus(signal)]
    async fn html_clipboard_ready(
        emitter: &SignalEmitter<'_>,
        html_text: &str,
    ) -> zbus::Result<()>;
}

fn load_env_files() {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(config_home) = std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty()) {
        let base = PathBuf::from(config_home);
        candidates.push(base.join("catchypills/.env"));
        candidates.push(base.join("CatchyPills/.env"));
    } else if let Some(home) = std::env::var_os("HOME").filter(|v| !v.is_empty()) {
        let base = PathBuf::from(home).join(".config");
        candidates.push(base.join("catchypills/.env"));
        candidates.push(base.join("CatchyPills/.env"));
    }

    for path in candidates {
        if path.is_file() {
            let _ = dotenvy::from_path(&path);
        }
    }
    let _ = dotenvy::dotenv();
}

fn env_flag_enabled(keys: &[&str]) -> bool {
    keys.iter().any(|k| {
        std::env::var(k)
            .map(|v| {
                matches!(
                    v.trim().to_ascii_lowercase().as_str(),
                    "1" | "true" | "yes" | "on"
                )
            })
            .unwrap_or(false)
    })
}

fn looks_like_html(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return false;
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.contains("<html") || lower.contains("<!doctype html") || lower.contains("<body") {
        return true;
    }

    let bytes = lower.as_bytes();
    let mut i = 0;
    while i + 3 < bytes.len() {
        if bytes[i] == b'<' && bytes[i + 1] == b'/' && bytes[i + 2].is_ascii_alphabetic() {
            if let Some(close_rel) = bytes[i + 2..].iter().position(|&b| b == b'>') {
                let tag = &lower[i + 2..i + 2 + close_rel];
                if !tag.is_empty() && tag.bytes().all(|b| b.is_ascii_alphanumeric()) {
                    let open_prefix = format!("<{tag}");
                    if lower[..i].contains(&open_prefix) {
                        return true;
                    }
                }
            }
        }
        i += 1;
    }
    false
}

fn hash_bytes(bytes: &[u8]) -> String {
    let mut hasher = DefaultHasher::new();
    bytes.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn make_preview(text: &str) -> String {
    let collapsed: String = text.split_whitespace().collect::<Vec<_>>().join(" ");
    collapsed.chars().take(80).collect()
}

fn store_clipboard_payload(
    db: &Mutex<Connection>,
    clips_dir: &Path,
    kind: &str,
    mime: &str,
    payload: &[u8],
) -> Option<(i64, String)> {
    if payload.is_empty() {
        return None;
    }

    let now_ms = db::unix_timestamp_ms();
    let digest = hash_bytes(payload);

    let (preview, text_content, image_path) = if kind == "image" {
        let ext = match mime {
            "image/jpeg" => "jpg",
            "image/webp" => "webp",
            _ => "png",
        };
        let target = clips_dir.join(format!("clip-{now_ms}-{digest}.{ext}"));
        if fs::write(&target, payload).is_err() {
            return None;
        }
        (
            format!("Image ({} KB)", (payload.len() / 1024).max(1)),
            String::new(),
            target.to_string_lossy().into_owned(),
        )
    } else {
        let text = String::from_utf8_lossy(payload).into_owned();
        if text.trim().is_empty() {
            return None;
        }
        (make_preview(&text), text, String::new())
    };

    let conn = db.lock().ok()?;
    let existing: Option<i64> = conn
        .query_row(
            "SELECT id FROM clipboard_items WHERE kind = ?1 AND content_hash = ?2 ORDER BY id DESC LIMIT 1",
            params![kind, digest],
            |row| row.get(0),
        )
        .ok();

    if let Some(id) = existing {
        let _ = conn.execute(
            "UPDATE clipboard_items SET created_at = ?1 WHERE id = ?2",
            params![now_ms, id],
        );
        if !image_path.is_empty() {
            let _ = fs::remove_file(&image_path);
        }
        return Some((id, preview));
    }

    conn.execute(
        "INSERT INTO clipboard_items (kind, mime, preview, content, image_path, content_hash, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![kind, mime, preview, text_content, image_path, digest, now_ms],
    )
    .ok()?;

    Some((conn.last_insert_rowid(), preview))
}

/// Wayland clipboard listener using KWin 6.8's standardized ext_data_control_manager_v1.
struct ClipboardWaylandState {
    manager: Option<ExtDataControlManagerV1>,
    seat: Option<wl_seat::WlSeat>,
    device: Option<ExtDataControlDeviceV1>,
    offers: HashMap<ObjectId, Vec<String>>,
    db: Arc<Mutex<Connection>>,
    clips_dir: PathBuf,
    dbus_conn: zbus::Connection,
    tokio_rt: tokio::runtime::Handle,
    clipboard_paused: Arc<AtomicBool>,
    itsm_enabled: Arc<AtomicBool>,
}

impl ClipboardWaylandState {
    fn read_offer_bytes(
        wl_conn: &WaylandConnection,
        offer: &ExtDataControlOfferV1,
        mime: &str,
        max_bytes: usize,
    ) -> Option<Vec<u8>> {
        let (mut reader, writer) = os_pipe::pipe().ok()?;
        offer.receive(mime.to_string(), writer.as_fd());
        drop(writer);
        if wl_conn.flush().is_err() {
            return None;
        }

        let mut buf = Vec::new();
        let mut chunk = [0u8; 8192];
        while buf.len() < max_bytes {
            match reader.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => buf.extend_from_slice(&chunk[..n]),
                Err(err) if err.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => return None,
            }
        }
        Some(buf)
    }

    fn handle_selection(&mut self, wl_conn: &WaylandConnection, offer: ExtDataControlOfferV1) {
        let mimes = self.offers.remove(&offer.id()).unwrap_or_default();

        if self.clipboard_paused.load(Ordering::Relaxed) {
            offer.destroy();
            return;
        }

        // Respect KDE/KeePassXC/KWallet privacy convention: skip clipboard offers
        // carrying x-kde-passwordManagerHint with payload "secret".
        if mimes.iter().any(|m| m == KDE_SECRET_HINT_MIME) {
            if let Some(hint) = Self::read_offer_bytes(wl_conn, &offer, KDE_SECRET_HINT_MIME, 64) {
                if String::from_utf8_lossy(&hint).trim() == "secret" {
                    offer.destroy();
                    return;
                }
            }
        }

        let chosen = ["image/png", "image/webp", "image/jpeg"]
            .into_iter()
            .find(|candidate| mimes.iter().any(|m| m == candidate))
            .map(|m| ("image", m))
            .or_else(|| {
                ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain"]
                    .into_iter()
                    .find(|candidate| mimes.iter().any(|m| m == candidate))
                    .map(|m| ("text", m))
            })
            .or_else(|| {
                mimes
                    .iter()
                    .any(|m| m == "text/html")
                    .then_some(("text", "text/html"))
            });

        if let Some((kind, mime)) = chosen {
            if let Some(bytes) = Self::read_offer_bytes(wl_conn, &offer, mime, MAX_CLIPBOARD_BYTES) {
                if let Some((clip_id, preview)) =
                    store_clipboard_payload(&self.db, &self.clips_dir, kind, mime, &bytes)
                {
                    let html_payload = if kind == "text" && self.itsm_enabled.load(Ordering::Relaxed) {
                        let text = String::from_utf8_lossy(&bytes).into_owned();
                        looks_like_html(&text).then_some(text)
                    } else {
                        None
                    };

                    let conn = self.dbus_conn.clone();
                    self.tokio_rt.spawn(async move {
                        if let Ok(emitter) = SignalEmitter::new(&conn, DBUS_OBJECT_PATH) {
                            let _ = DaemonIpc::clipboard_updated(&emitter, clip_id, &preview).await;
                            if let Some(html_text) = html_payload {
                                let _ = DaemonIpc::html_clipboard_ready(&emitter, &html_text).await;
                            }
                        }
                    });
                }
            }
        }

        offer.destroy();
    }
}

impl Dispatch<wl_registry::WlRegistry, ()> for ClipboardWaylandState {
    fn event(
        state: &mut Self,
        registry: &wl_registry::WlRegistry,
        event: wl_registry::Event,
        _data: &(),
        _conn: &WaylandConnection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        {
            match interface.as_str() {
                "ext_data_control_manager_v1" => {
                    let mgr = registry.bind::<ExtDataControlManagerV1, _, _>(
                        name,
                        version.min(1),
                        qh,
                        (),
                    );
                    state.manager = Some(mgr);
                }
                "wl_seat" if state.seat.is_none() => {
                    let seat =
                        registry.bind::<wl_seat::WlSeat, _, _>(name, version.min(9), qh, ());
                    state.seat = Some(seat);
                }
                _ => {}
            }
        }
    }
}

struct ExtDataControlHandler;

impl Dispatch<ExtDataControlManagerV1, (), ClipboardWaylandState> for ExtDataControlHandler {
    fn event(
        _state: &mut ClipboardWaylandState,
        _proxy: &ExtDataControlManagerV1,
        _event: <ExtDataControlManagerV1 as Proxy>::Event,
        _data: &(),
        _conn: &WaylandConnection,
        _qh: &QueueHandle<ClipboardWaylandState>,
    ) {
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for ClipboardWaylandState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_seat::WlSeat,
        _event: wl_seat::Event,
        _data: &(),
        _conn: &WaylandConnection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ExtDataControlDeviceV1, (), ClipboardWaylandState> for ExtDataControlHandler {
    fn event(
        state: &mut ClipboardWaylandState,
        _proxy: &ExtDataControlDeviceV1,
        event: ext_data_control_device_v1::Event,
        _data: &(),
        conn: &WaylandConnection,
        _qh: &QueueHandle<ClipboardWaylandState>,
    ) {
        match event {
            ext_data_control_device_v1::Event::DataOffer { id } => {
                state.offers.insert(id.id(), Vec::new());
            }
            ext_data_control_device_v1::Event::Selection { id } => {
                if let Some(offer) = id {
                    state.handle_selection(conn, offer);
                }
            }
            ext_data_control_device_v1::Event::PrimarySelection { id } => {
                if let Some(offer) = id {
                    state.offers.remove(&offer.id());
                    offer.destroy();
                }
            }
            _ => {}
        }
    }

    // Required by wayland-client 0.31 whenever a server event constructs a new child proxy.
    event_created_child!(ClipboardWaylandState, ExtDataControlDeviceV1, [
        ext_data_control_device_v1::EVT_DATA_OFFER_OPCODE => (ExtDataControlOfferV1, ())
    ]);
}

impl Dispatch<ExtDataControlOfferV1, (), ClipboardWaylandState> for ExtDataControlHandler {
    fn event(
        state: &mut ClipboardWaylandState,
        proxy: &ExtDataControlOfferV1,
        event: ext_data_control_offer_v1::Event,
        _data: &(),
        _conn: &WaylandConnection,
        _qh: &QueueHandle<ClipboardWaylandState>,
    ) {
        if let ext_data_control_offer_v1::Event::Offer { mime_type } = event {
            if let Some(mimes) = state.offers.get_mut(&proxy.id()) {
                mimes.push(mime_type);
            }
        }
    }
}

delegate_dispatch!(ClipboardWaylandState: [ExtDataControlManagerV1: ()] => ExtDataControlHandler);
delegate_dispatch!(ClipboardWaylandState: [ExtDataControlDeviceV1: ()] => ExtDataControlHandler);
delegate_dispatch!(ClipboardWaylandState: [ExtDataControlOfferV1: ()] => ExtDataControlHandler);

fn spawn_clipboard_worker(
    db: Arc<Mutex<Connection>>,
    clips_dir: PathBuf,
    dbus_conn: zbus::Connection,
    tokio_rt: tokio::runtime::Handle,
    clipboard_paused: Arc<AtomicBool>,
    itsm_enabled: Arc<AtomicBool>,
    shutdown: Arc<AtomicBool>,
) -> std::thread::JoinHandle<()> {
    std::thread::Builder::new()
        .name("clipboard-ext-data-control".to_string())
        .spawn(move || {
            let Ok(wl_conn) = WaylandConnection::connect_to_env() else {
                eprintln!("[catchypillsd] Wayland display unavailable; clipboard watcher idle");
                return;
            };

            let mut queue = wl_conn.new_event_queue();
            let qh = queue.handle();
            let mut state = ClipboardWaylandState {
                manager: None,
                seat: None,
                device: None,
                offers: HashMap::new(),
                db,
                clips_dir,
                dbus_conn,
                tokio_rt,
                clipboard_paused,
                itsm_enabled,
            };

            let _registry = wl_conn.display().get_registry(&qh, ());
            if let Err(err) = queue.roundtrip(&mut state) {
                eprintln!("[catchypillsd] Wayland roundtrip failed: {err}");
                return;
            }

            if let (Some(manager), Some(seat)) = (&state.manager, &state.seat) {
                state.device = Some(manager.get_data_device(seat, &qh, ()));
                let _ = queue.roundtrip(&mut state);
                println!("[catchypillsd] Bound ext_data_control_manager_v1 clipboard listener");
            } else {
                eprintln!("[catchypillsd] Compositor does not advertise ext_data_control_manager_v1");
                return;
            }

            while !shutdown.load(Ordering::Relaxed) {
                if let Err(err) = queue.blocking_dispatch(&mut state) {
                    eprintln!("[catchypillsd] Wayland dispatch error: {err}");
                    if !shutdown.load(Ordering::Relaxed) {
                        std::process::exit(1);
                    }
                    break;
                }
            }
        })
        .expect("spawn clipboard watcher thread")
}

fn spawn_file_indexer_worker(
    file_index: Arc<RwLock<Vec<IndexedFile>>>,
    indexed_count: Arc<AtomicUsize>,
    shutdown: Arc<AtomicBool>,
) -> tokio::task::JoinHandle<()> {
    tokio::task::spawn_blocking(move || {
        let Some(home) = std::env::var_os("HOME").map(PathBuf::from) else {
            eprintln!("[catchypillsd] HOME unset; skipping file indexer");
            return;
        };

        let collected = Arc::new(Mutex::new(Vec::<IndexedFile>::with_capacity(32_768)));
        let walker = WalkBuilder::new(&home)
            .hidden(false)
            .git_ignore(true)
            .ignore(true)
            .threads(4)
            .build_parallel();

        walker.run(|| {
            let collected = Arc::clone(&collected);
            let shutdown = Arc::clone(&shutdown);
            let mut local_batch = Vec::with_capacity(512);

            Box::new(move |entry| {
                if shutdown.load(Ordering::Relaxed) {
                    return ignore::WalkState::Quit;
                }
                if let Ok(dirent) = entry {
                    if dirent.depth() > 0 {
                        let path = dirent.path();
                        let name = path
                            .file_name()
                            .map(|n| n.to_string_lossy().into_owned())
                            .unwrap_or_default();
                        if !name.is_empty() {
                            local_batch.push(IndexedFile {
                                name,
                                path: path.to_string_lossy().into_owned(),
                            });
                        }
                        if local_batch.len() >= 512 {
                            if let Ok(mut global) = collected.lock() {
                                global.append(&mut local_batch);
                            }
                        }
                    }
                }
                ignore::WalkState::Continue
            })
        });

        let initial = collected
            .lock()
            .map(|mut guard| std::mem::take(&mut *guard))
            .unwrap_or_default();
        let count = initial.len();
        if let Ok(mut index) = file_index.write() {
            *index = initial;
        }
        indexed_count.store(count, Ordering::Relaxed);
        println!("[catchypillsd] Indexed {count} files under {}", home.display());

        // Keep index fresh on create/remove via inotify.
        let index_for_watch = Arc::clone(&file_index);
        let count_for_watch = Arc::clone(&indexed_count);
        let mut watcher: Option<RecommendedWatcher> =
            notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
                let Ok(event) = res else { return };
                match event.kind {
                    EventKind::Create(_) => {
                        if let Ok(mut guard) = index_for_watch.write() {
                            for path in event.paths {
                                let p_str = path.to_string_lossy().into_owned();
                                if !guard.iter().any(|f| f.path == p_str) {
                                    let name = path
                                        .file_name()
                                        .map(|n| n.to_string_lossy().into_owned())
                                        .unwrap_or_default();
                                    if !name.is_empty() {
                                        guard.push(IndexedFile { name, path: p_str });
                                    }
                                }
                            }
                            count_for_watch.store(guard.len(), Ordering::Relaxed);
                        }
                    }
                    EventKind::Remove(_) => {
                        if let Ok(mut guard) = index_for_watch.write() {
                            guard.retain(|item| !event.paths.iter().any(|p| p.to_string_lossy() == item.path));
                            count_for_watch.store(guard.len(), Ordering::Relaxed);
                        }
                    }
                    _ => {}
                }
            })
            .ok();

        if let Some(ref mut w) = watcher {
            let _ = w.watch(&home, RecursiveMode::Recursive);
        }

        while !shutdown.load(Ordering::Relaxed) {
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
    })
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    load_env_files();

    let (conn, clips_dir) = db::init_database()?;
    let db = Arc::new(Mutex::new(conn));
    let file_index = Arc::new(RwLock::new(Vec::new()));
    let indexed_count = Arc::new(AtomicUsize::new(0));
    let clipboard_paused = Arc::new(AtomicBool::new(false));
    let itsm_enabled = Arc::new(AtomicBool::new(env_flag_enabled(&[
        "ENABLE_ITSM",
        "CATCHYPILLS_ENABLE_ITSM",
    ])));
    let shutdown = Arc::new(AtomicBool::new(false));

    let ipc = DaemonIpc {
        db: Arc::clone(&db),
        file_index: Arc::clone(&file_index),
        indexed_count: Arc::clone(&indexed_count),
        clipboard_paused: Arc::clone(&clipboard_paused),
        itsm_enabled: Arc::clone(&itsm_enabled),
    };

    let dbus_conn = connection::Builder::session()?
        .name(DBUS_SERVICE_NAME)?
        .serve_at(DBUS_OBJECT_PATH, ipc)?
        .build()
        .await?;

    println!("[catchypillsd] Serving D-Bus at {DBUS_SERVICE_NAME} ({DBUS_OBJECT_PATH})");

    let db_for_cleanup = Arc::clone(&db);
    let shutdown_for_cleanup = Arc::clone(&shutdown);
    let cleanup_task = tokio::spawn(async move {
        let mut ticker = tokio::time::interval(std::time::Duration::from_secs(3600));
        loop {
            ticker.tick().await;
            if shutdown_for_cleanup.load(Ordering::Relaxed) {
                break;
            }
            let db_ref = Arc::clone(&db_for_cleanup);
            let _ = tokio::task::spawn_blocking(move || {
                if let Ok(conn) = db_ref.lock() {
                    let deleted = db::prune_expired_clipboard(&conn);
                    if deleted > 0 {
                        println!("[catchypillsd] Pruned {deleted} clipboard items older than 24h");
                    }
                }
            })
            .await;
        }
    });

    let _clipboard_thread = spawn_clipboard_worker(
        db,
        clips_dir,
        dbus_conn,
        tokio::runtime::Handle::current(),
        clipboard_paused,
        itsm_enabled,
        Arc::clone(&shutdown),
    );
    let indexer_task =
        spawn_file_indexer_worker(file_index, indexed_count, Arc::clone(&shutdown));

    tokio::signal::ctrl_c().await?;
    println!("[catchypillsd] Shutdown requested");
    shutdown.store(true, Ordering::Relaxed);
    cleanup_task.abort();
    let _ = indexer_task.await;

    Ok(())
}

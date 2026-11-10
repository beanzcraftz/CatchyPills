use std::error::Error;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use serde::Serialize;
use wayland_client::{
    Connection as WaylandConnection, Dispatch, QueueHandle,
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

/// D-Bus IPC surface exposed on the Session Bus for the Qt6/QML frontend.
struct DaemonIpc {
    indexed_count: Arc<std::sync::atomic::AtomicUsize>,
}

#[interface(name = "io.hearnelabs.CatchyPillsDaemon1")]
impl DaemonIpc {
    async fn ping(&self) -> String {
        format!(
            "catchypillsd alive (indexed_files={})",
            self.indexed_count.load(Ordering::Relaxed)
        )
    }

    async fn get_recent_clips(&self, _limit: u32) -> Vec<ClipboardEntryDto> {
        // Stub: will query SQLite clipboard_items once clipboard worker lands.
        Vec::new()
    }

    async fn search_files(&self, _query: String, _limit: u32) -> Vec<FileMatchDto> {
        // Stub: will query nucleo + ignore snapshot once file indexer worker lands.
        Vec::new()
    }

    /// Emitted whenever ext-data-control-v1 captures a non-secret clipboard change.
    #[zbus(signal)]
    async fn clipboard_updated(
        emitter: &SignalEmitter<'_>,
        clip_id: i64,
        preview: &str,
    ) -> zbus::Result<()>;
}

/// Minimal Wayland state for binding KWin 6.8's ext_data_control_manager_v1.
/// Note: KWin 6.8+ exposes ext_data_control_manager_v1 (not zwlr_data_control_manager_v1),
/// allowing passive background clipboard reads without stealing keyboard focus.
struct ClipboardWaylandState {
    manager: Option<ExtDataControlManagerV1>,
    seat: Option<wl_seat::WlSeat>,
    device: Option<ExtDataControlDeviceV1>,
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

impl Dispatch<ExtDataControlManagerV1, ()> for ClipboardWaylandState {
    fn event(
        _state: &mut Self,
        _proxy: &ExtDataControlManagerV1,
        _event: <ExtDataControlManagerV1 as wayland_client::Proxy>::Event,
        _data: &(),
        _conn: &WaylandConnection,
        _qh: &QueueHandle<Self>,
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

impl Dispatch<ExtDataControlDeviceV1, ()> for ClipboardWaylandState {
    fn event(
        _state: &mut Self,
        _proxy: &ExtDataControlDeviceV1,
        event: ext_data_control_device_v1::Event,
        _data: &(),
        _conn: &WaylandConnection,
        _qh: &QueueHandle<Self>,
    ) {
        match event {
            ext_data_control_device_v1::Event::DataOffer { id } => {
                let _ = id;
            }
            ext_data_control_device_v1::Event::Selection { id: _ } => {
                // Next phase: read pipe FD unless offer carries x-kde-passwordManagerHint=secret,
                // persist in rusqlite, and emit DaemonIpc::clipboard_updated via SignalEmitter.
            }
            _ => {}
        }
    }
}

impl Dispatch<ExtDataControlOfferV1, ()> for ClipboardWaylandState {
    fn event(
        _state: &mut Self,
        _proxy: &ExtDataControlOfferV1,
        event: ext_data_control_offer_v1::Event,
        _data: &(),
        _conn: &WaylandConnection,
        _qh: &QueueHandle<Self>,
    ) {
        if let ext_data_control_offer_v1::Event::Offer { mime_type } = event {
            let _ = mime_type;
        }
    }
}

fn spawn_clipboard_worker(
    dbus_conn: zbus::Connection,
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
            }

            let _emitter = SignalEmitter::new(&dbus_conn, DBUS_OBJECT_PATH).ok();

            while !shutdown.load(Ordering::Relaxed) {
                if let Err(err) = queue.blocking_dispatch(&mut state) {
                    eprintln!("[catchypillsd] Wayland dispatch error: {err}");
                    break;
                }
            }
        })
        .expect("spawn clipboard watcher thread")
}

fn spawn_file_indexer_worker(
    indexed_count: Arc<std::sync::atomic::AtomicUsize>,
    shutdown: Arc<AtomicBool>,
) -> tokio::task::JoinHandle<()> {
    tokio::task::spawn_blocking(move || {
        // Scaffold: next phase wires ignore::WalkBuilder + notify::recommended_watcher
        // + nucleo::Nucleo fuzzy matcher + rusqlite FTS5 cache.
        println!("[catchypillsd] File indexer worker initialized (stub)");
        let _ = indexed_count.load(Ordering::Relaxed);
        while !shutdown.load(Ordering::Relaxed) {
            std::thread::sleep(std::time::Duration::from_millis(250));
        }
    })
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let indexed_count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let shutdown = Arc::new(AtomicBool::new(false));

    let ipc = DaemonIpc {
        indexed_count: Arc::clone(&indexed_count),
    };

    let dbus_conn = connection::Builder::session()?
        .name(DBUS_SERVICE_NAME)?
        .serve_at(DBUS_OBJECT_PATH, ipc)?
        .build()
        .await?;

    println!("[catchypillsd] Serving D-Bus at {DBUS_SERVICE_NAME} ({DBUS_OBJECT_PATH})");

    let _clipboard_thread = spawn_clipboard_worker(dbus_conn.clone(), Arc::clone(&shutdown));
    let indexer_task = spawn_file_indexer_worker(indexed_count, Arc::clone(&shutdown));

    tokio::signal::ctrl_c().await?;
    println!("[catchypillsd] Shutdown requested");
    shutdown.store(true, Ordering::Relaxed);
    let _ = indexer_task.await;

    Ok(())
}

use crate::{
    files::{ImportPlan, ImportSettings},
    imaging::{ExportSettings, Images},
    model::*,
    store::{Database, Store},
};
use base64::Engine;
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    num::NonZeroUsize,
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
};
use tauri::{ipc::Channel, State};

pub struct AppData {
    volumes: Mutex<Vec<Volume>>,
    files: Mutex<HashMap<String, MediaFile>>,
    store: Mutex<Store>,
    images: Images,
    cache: crate::cache::ThumbnailCache,
    encoded: Mutex<lru::LruCache<String, String>>,
    scan_version: AtomicU64,
    operations: Mutex<HashMap<String, Arc<AtomicBool>>>,
    deletions: Mutex<HashMap<String, DeletionPlan>>,
    imports: Mutex<HashMap<String, ImportPlan>>,
    mutation: Mutex<()>,
    grid: Arc<tokio::sync::Semaphore>,
    preview: Arc<tokio::sync::Semaphore>,
    prefetch: Arc<tokio::sync::Semaphore>,
    #[cfg(windows)]
    undo: Mutex<Vec<(RecycledFile, String, FileMark)>>,
}
impl AppData {
    pub fn new(data: &Path, cache: &Path) -> Result<Self, String> {
        std::fs::create_dir_all(cache).map_err(|e| e.to_string())?;
        let store = Store::open(data)?;
        let folders = store
            .data
            .folders
            .iter()
            .filter_map(|p| crate::volumes::folder(Path::new(p)).ok())
            .collect();
        Ok(Self {
            volumes: Mutex::new(folders),
            files: Mutex::new(HashMap::new()),
            store: Mutex::new(store),
            images: Images::default(),
            cache: crate::cache::ThumbnailCache::new(cache)?,
            encoded: Mutex::new(lru::LruCache::new(NonZeroUsize::new(48).unwrap())),
            scan_version: AtomicU64::new(0),
            operations: Mutex::new(HashMap::new()),
            deletions: Mutex::new(HashMap::new()),
            imports: Mutex::new(HashMap::new()),
            mutation: Mutex::new(()),
            grid: Arc::new(tokio::sync::Semaphore::new(4)),
            preview: Arc::new(tokio::sync::Semaphore::new(2)),
            prefetch: Arc::new(tokio::sync::Semaphore::new(1)),
            #[cfg(windows)]
            undo: Mutex::new(vec![]),
        })
    }
    fn file(&self, path: &str) -> Result<MediaFile, String> {
        self.files
            .lock()
            .get(path)
            .cloned()
            .ok_or("file_not_in_library".into())
    }
    fn start(&self, id: &str) -> Result<Arc<AtomicBool>, String> {
        let mut operations = self.operations.lock();
        if operations.contains_key(id) {
            return Err("operation_exists".into());
        }
        let token = Arc::new(AtomicBool::new(false));
        operations.insert(id.into(), token.clone());
        Ok(token)
    }
    fn finish(&self, id: &str) {
        self.operations.lock().remove(id);
    }
}
type App<'a> = State<'a, Arc<AppData>>;
async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|e| e.to_string())?
}
#[derive(Serialize)]
pub struct Bootstrap {
    pub database: Database,
    pub volumes: Vec<Volume>,
    pub can_undo: bool,
}
#[tauri::command]
pub async fn bootstrap(state: App<'_>) -> Result<Bootstrap, String> {
    let state = state.inner().clone();
    blocking(move || {
        let volumes = refresh(&state);
        Ok(Bootstrap {
            database: state.store.lock().data.clone(),
            volumes,
            can_undo: false,
        })
    })
    .await
}
fn refresh(state: &AppData) -> Vec<Volume> {
    let mut volumes = state.volumes.lock();
    let mut detected = crate::volumes::list();
    detected.extend(
        volumes
            .iter()
            .filter(|v| v.manual && Path::new(&v.path).is_dir())
            .cloned(),
    );
    *volumes = detected.clone();
    detected
}
#[tauri::command]
pub async fn list_volumes(state: App<'_>) -> Result<Vec<Volume>, String> {
    let state = state.inner().clone();
    blocking(move || Ok(refresh(&state))).await
}
#[tauri::command]
pub async fn add_folder(state: App<'_>, path: String) -> Result<Volume, String> {
    let state = state.inner().clone();
    blocking(move || {
        let volume = crate::volumes::folder(Path::new(&path))?;
        let mut volumes = state.volumes.lock();
        if let Some(existing) = volumes
            .iter()
            .find(|v| Path::new(&volume.path).starts_with(&v.path))
        {
            return Ok(existing.clone());
        }
        if !volumes.iter().any(|v| v.id == volume.id) {
            let mut store = state.store.lock();
            let previous = store.data.folders.clone();
            if !store.data.folders.contains(&volume.path) {
                store.data.folders.push(volume.path.clone());
            }
            if let Err(error) = store.save() {
                store.data.folders = previous;
                return Err(error);
            }
            volumes.push(volume.clone())
        }
        Ok(volume)
    })
    .await
}
#[derive(Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ScanEvent {
    Batch { files: Vec<MediaFile> },
    Warning { message: String },
    Done { count: usize },
}
#[tauri::command]
pub async fn scan(
    state: App<'_>,
    ids: Vec<String>,
    id: String,
    on_event: Channel<ScanEvent>,
) -> Result<(), String> {
    let state = state.inner().clone();
    let version = state.scan_version.fetch_add(1, Ordering::SeqCst) + 1;
    let token = state.start(&id)?;
    blocking(move || {
        let _guard = state.mutation.lock();
        if state.scan_version.load(Ordering::SeqCst) != version {
            state.finish(&id);
            return Ok(());
        }
        let volumes: Vec<_> = state
            .volumes
            .lock()
            .iter()
            .filter(|v| ids.contains(&v.id))
            .cloned()
            .collect();
        state.files.lock().clear();
        state.deletions.lock().clear();
        state.imports.lock().clear();
        let mut count = 0;
        let result = {
            for volume in volumes {
                let result = crate::files::scan(
                    &volume,
                    &token,
                    |mut batch| {
                        if state.scan_version.load(Ordering::SeqCst) != version {
                            token.store(true, Ordering::Relaxed);
                            return;
                        }
                        {
                            let mut files = state.files.lock();
                            batch.retain(|f| !files.contains_key(&f.path));
                            count += batch.len();
                            for file in &batch {
                                files.insert(file.path.clone(), file.clone());
                            }
                        }
                        if on_event.send(ScanEvent::Batch { files: batch }).is_err() {
                            token.store(true, Ordering::Relaxed);
                        }
                    },
                    |message| {
                        let _ = on_event.send(ScanEvent::Warning { message });
                    },
                );
                if let Err(message) = result {
                    let _ = on_event.send(ScanEvent::Warning { message });
                }
            }
            let _ = on_event.send(ScanEvent::Done { count });
            Ok(())
        };
        state.finish(&id);
        result
    })
    .await
}
#[tauri::command]
pub fn cancel(state: App<'_>, id: String) {
    if let Some(token) = state.operations.lock().get(&id) {
        token.store(true, Ordering::Relaxed)
    }
}
#[tauri::command]
pub async fn compute_pairs(state: App<'_>, rule: Rule) -> Result<Pairs, String> {
    let state = state.inner().clone();
    blocking(move || {
        Ok(pair(
            &state.files.lock().values().cloned().collect::<Vec<_>>(),
            &rule,
        ))
    })
    .await
}
#[derive(Serialize)]
pub struct ImageReply {
    pub data: String,
    pub width: u32,
    pub height: u32,
}
#[tauri::command]
pub async fn image(
    state: App<'_>,
    path: String,
    px: u32,
    lane: String,
    id: String,
) -> Result<ImageReply, String> {
    let state = state.inner().clone();
    let file = state.file(&path)?;
    let px = px.clamp(64, 3200);
    let token = state.start(&id)?;
    let gate = match lane.as_str() {
        "prefetch" => state.prefetch.clone(),
        "preview" => state.preview.clone(),
        _ => state.grid.clone(),
    };
    let permit = gate.acquire_owned().await.map_err(|e| e.to_string())?;
    blocking(move || {
        let _permit = permit;
        let result = (|| {
            if token.load(Ordering::Relaxed) {
                return Err("cancelled".into());
            }
            if !unchanged(&file) {
                return Err("file_changed".into());
            }
            let key = format!(
                "{}|{}|{}|{}|{}",
                path, file.fingerprint, file.modified_nanos, file.file_size, px
            );
            let disk = format!("{:x}.jpg", Sha256::digest(&key));
            if let Some(data) = state.encoded.lock().get(&key).cloned() {
                return Ok(ImageReply {
                    data,
                    width: 0,
                    height: 0,
                });
            }
            let bytes = if let Some(bytes) = state.cache.get(&disk) {
                bytes
            } else {
                let decoded = crate::imaging::decode(Path::new(&path), true);
                #[cfg(windows)]
                let decoded = decoded.or_else(|_| crate::shell::thumbnail(Path::new(&path), px));
                let decoded = decoded?;
                let small = decoded.resize(px, px, image::imageops::FilterType::Triangle);
                let bytes = crate::imaging::jpeg(&small, 85)?;
                if !token.load(Ordering::Relaxed) {
                    state.cache.put(&disk, &bytes);
                }
                bytes
            };
            let data = format!(
                "data:image/jpeg;base64,{}",
                base64::engine::general_purpose::STANDARD.encode(bytes)
            );
            {
                let mut encoded = state.encoded.lock();
                encoded.put(key, data.clone());
                while encoded.iter().map(|(_, v)| v.len()).sum::<usize>() > 64 * 1024 * 1024
                    && encoded.len() > 1
                {
                    encoded.pop_lru();
                }
            }
            Ok(ImageReply {
                data,
                width: 0,
                height: 0,
            })
        })();
        state.finish(&id);
        result
    })
    .await
}
#[tauri::command]
pub async fn read_exif(state: App<'_>, path: String) -> Result<crate::imaging::Exif, String> {
    state.file(&path)?;
    blocking(move || Ok(crate::imaging::exif_info(Path::new(&path)))).await
}
#[tauri::command]
pub async fn plan_deletion(
    state: App<'_>,
    selected: Vec<String>,
    rule: Rule,
) -> Result<DeletionPlan, String> {
    let state = state.inner().clone();
    blocking(move || {
        let plan = deletion_plan(
            &state.files.lock().values().cloned().collect::<Vec<_>>(),
            &selected,
            &rule,
        );
        let mut plans = state.deletions.lock();
        plans.clear();
        plans.insert(plan.id.clone(), plan.clone());
        Ok(plan)
    })
    .await
}
#[tauri::command]
pub async fn delete_files(
    state: App<'_>,
    plan_id: String,
    permanent: bool,
    id: String,
    on_event: Channel<Progress>,
) -> Result<Outcome, String> {
    let state = state.inner().clone();
    let plan = state
        .deletions
        .lock()
        .remove(&plan_id)
        .ok_or("plan_expired")?;
    let token = state.start(&id)?;
    blocking(move || {
        let _guard = state.mutation.lock();
        let mut outcome = Outcome::default();
        #[cfg(windows)]
        state.undo.lock().clear();
        let targets: Vec<_> = plan.selected.into_iter().chain(plan.paired).collect();
        for (index, file) in targets.iter().enumerate() {
            if token.load(Ordering::Relaxed) {
                outcome.cancelled = true;
                break;
            }
            let result = if !unchanged(file) {
                Err("file_changed".into())
            } else if permanent {
                std::fs::remove_file(&file.path)
                    .map(|_| None)
                    .map_err(|e| e.to_string())
            } else {
                crate::files::recycle(Path::new(&file.path))
            };
            match result {
                Ok(receipt) => {
                    outcome.completed.push(file.path.clone());
                    state.files.lock().remove(&file.path);
                    let mark = state
                        .store
                        .lock()
                        .data
                        .marks
                        .remove(&file.key)
                        .unwrap_or_default();
                    #[cfg(windows)]
                    if let Some(item) = receipt {
                        state.undo.lock().push((item, file.key.clone(), mark));
                    }
                    #[cfg(not(windows))]
                    let _ = (receipt, mark);
                }
                Err(e) => outcome.failures.push(format!("{}: {e}", file.name)),
            }
            let _ = on_event.send(Progress {
                id: id.clone(),
                done: index + 1,
                total: targets.len(),
                name: file.name.clone(),
                bytes: 0,
            });
        }
        let saved = state.store.lock().save();
        state.finish(&id);
        saved?;
        Ok(outcome)
    })
    .await
}
#[tauri::command]
pub async fn undo_delete(state: App<'_>) -> Result<Outcome, String> {
    let state = state.inner().clone();
    blocking(move || {
        let _guard = state.mutation.lock();
        let mut outcome = Outcome::default();
        #[cfg(windows)]
        {
            let entries = std::mem::take(&mut *state.undo.lock());
            let mut retry = vec![];
            for (item, key, mark) in entries {
                let path = std::path::PathBuf::from(&item.path);
                if path.symlink_metadata().is_ok() {
                    outcome.failures.push(path.to_string_lossy().into());
                    retry.push((item, key, mark));
                    continue;
                }
                match crate::shell::restore(&item) {
                    Ok(()) => {
                        outcome.completed.push(path.to_string_lossy().into());
                        if !mark.empty() {
                            state.store.lock().data.marks.insert(key, mark);
                        }
                    }
                    Err(e) => {
                        outcome.failures.push(e.to_string());
                        retry.push((item, key, mark));
                    }
                }
            }
            *state.undo.lock() = retry;
            state.store.lock().save()?;
        }
        #[cfg(not(windows))]
        outcome.failures.push("undo_windows_only".into());
        Ok(outcome)
    })
    .await
}
#[derive(Deserialize)]
pub struct MarkUpdate {
    pub path: String,
    pub mark: FileMark,
}
#[tauri::command]
pub async fn set_marks(state: App<'_>, updates: Vec<MarkUpdate>) -> Result<Database, String> {
    let state = state.inner().clone();
    blocking(move || {
        let _guard = state.mutation.lock();
        let mut checked = vec![];
        for update in updates {
            update.mark.validate()?;
            checked.push((state.file(&update.path)?, update.mark));
        }
        let mut store = state.store.lock();
        let previous = store.data.clone();
        for (file, mark) in &checked {
            if mark.empty() {
                store.data.marks.remove(&file.key);
            } else {
                store.data.marks.insert(file.key.clone(), mark.clone());
            }
        }
        if let Err(error) = store.save() {
            store.data = previous;
            return Err(error);
        }
        if store.data.preferences.write_xmp {
            for (file, mark) in checked {
                let before = previous.marks.get(&file.key).cloned().unwrap_or_default();
                if before.rating != mark.rating || before.label != mark.label {
                    if !unchanged(&file) {
                        return Err("file_changed".into());
                    }
                    crate::xmp::write(Path::new(&file.path), &mark)?;
                }
            }
        }
        Ok(store.data.clone())
    })
    .await
}
#[tauri::command]
pub async fn save_preferences(
    state: App<'_>,
    mut preferences: Preferences,
) -> Result<Database, String> {
    let state = state.inner().clone();
    blocking(move || {
        preferences.prefetch = preferences.prefetch.min(20);
        let mut store = state.store.lock();
        let previous = store.data.preferences.clone();
        store.data.preferences = preferences;
        if let Err(error) = store.save() {
            store.data.preferences = previous;
            return Err(error);
        }
        Ok(store.data.clone())
    })
    .await
}
#[tauri::command]
pub async fn render_preview(
    state: App<'_>,
    path: String,
    adjustments: Adjustments,
    include_crop: bool,
    id: String,
) -> Result<ImageReply, String> {
    let state = state.inner().clone();
    let file = state.file(&path)?;
    let token = state.start(&id)?;
    let permit = state
        .preview
        .clone()
        .acquire_owned()
        .await
        .map_err(|e| e.to_string())?;
    blocking(move || {
        let _permit = permit;
        let result = (|| {
            if token.load(Ordering::Relaxed) {
                return Err("cancelled".into());
            }
            if !unchanged(&file) {
                return Err("file_changed".into());
            }
            let source = state.images.editor_source(&file)?;
            if token.load(Ordering::Relaxed) {
                return Err("cancelled".into());
            }
            let image = crate::imaging::render(&source, &adjustments, include_crop)?;
            Ok(ImageReply {
                width: image.width(),
                height: image.height(),
                data: format!(
                    "data:image/jpeg;base64,{}",
                    base64::engine::general_purpose::STANDARD
                        .encode(crate::imaging::jpeg(&image, 92)?)
                ),
            })
        })();
        state.finish(&id);
        result
    })
    .await
}
#[tauri::command]
pub async fn export_image(
    state: App<'_>,
    path: String,
    destination: String,
    adjustments: Adjustments,
    settings: ExportSettings,
) -> Result<(), String> {
    let state = state.inner().clone();
    let file = state.file(&path)?;
    blocking(move || {
        let _guard = state.mutation.lock();
        if !unchanged(&file) {
            return Err("file_changed".into());
        }
        crate::imaging::export(
            Path::new(&path),
            Path::new(&destination),
            &adjustments,
            &settings,
        )
    })
    .await
}
#[tauri::command]
pub async fn plan_import(
    state: App<'_>,
    selected: Vec<String>,
    rule: Rule,
    settings: ImportSettings,
    id: String,
) -> Result<ImportPlan, String> {
    let state = state.inner().clone();
    let token = state.start(&id)?;
    blocking(move || {
        let result = (|| {
            let targets = if settings.include_paired {
                let plan = deletion_plan(
                    &state.files.lock().values().cloned().collect::<Vec<_>>(),
                    &selected,
                    &rule,
                );
                plan.selected.into_iter().chain(plan.paired).collect()
            } else {
                selected
                    .iter()
                    .map(|p| state.file(p))
                    .collect::<Result<Vec<_>, _>>()?
            };
            crate::files::plan_import(&targets, settings, &token)
        })();
        state.finish(&id);
        let plan = result?;
        let mut plans = state.imports.lock();
        plans.clear();
        plans.insert(plan.id.clone(), plan.clone());
        Ok(plan)
    })
    .await
}
#[tauri::command]
pub async fn perform_import(
    state: App<'_>,
    plan_id: String,
    id: String,
    on_event: Channel<Progress>,
) -> Result<Outcome, String> {
    let state = state.inner().clone();
    let plan = state
        .imports
        .lock()
        .remove(&plan_id)
        .ok_or("plan_expired")?;
    let token = state.start(&id)?;
    blocking(move || {
        let _guard = state.mutation.lock();
        let result = (|| {
            if fs2::available_space(&plan.settings.destination).map_err(|e| e.to_string())?
                < plan.total_bytes
            {
                return Err("not_enough_space".into());
            }
            let mut outcome = Outcome {
                skipped: plan.skipped,
                ..Default::default()
            };
            let mut bytes = 0;
            for (index, item) in plan.items.iter().enumerate() {
                if token.load(Ordering::Relaxed) {
                    outcome.cancelled = true;
                    break;
                }
                let result = if unchanged(&item.source) {
                    crate::files::copy_verified(
                        Path::new(&item.source.path),
                        Path::new(&item.destination),
                        &token,
                        |n| {
                            bytes += n;
                            let _ = on_event.send(Progress {
                                id: id.clone(),
                                done: index,
                                total: plan.items.len(),
                                name: item.source.name.clone(),
                                bytes,
                            });
                        },
                    )
                } else {
                    Err("file_changed".into())
                };
                match result {
                    Ok(()) => {
                        outcome.completed.push(item.source.path.clone());
                        if plan.settings.delete_after && unchanged(&item.source) {
                            match crate::files::recycle(Path::new(&item.source.path)) {
                                Ok(_) => {
                                    state.files.lock().remove(&item.source.path);
                                    state.store.lock().data.marks.remove(&item.source.key);
                                }
                                Err(e) => {
                                    outcome.failures.push(format!("{}: {e}", item.source.name))
                                }
                            }
                        }
                    }
                    Err(e) if e == "cancelled" => {
                        outcome.cancelled = true;
                        break;
                    }
                    Err(e) => outcome.failures.push(format!("{}: {e}", item.source.name)),
                }
                let _ = on_event.send(Progress {
                    id: id.clone(),
                    done: index + 1,
                    total: plan.items.len(),
                    name: item.source.name.clone(),
                    bytes,
                });
            }
            state.store.lock().save()?;
            Ok(outcome)
        })();
        state.finish(&id);
        result
    })
    .await
}
#[tauri::command]
pub async fn open_path(state: App<'_>, path: String, action: String) -> Result<(), String> {
    if action != "paypal" {
        state.file(&path)?;
    }
    blocking(move || {
        let target = if action == "paypal" {
            "https://www.paypal.com/paypalme/yinxu0619"
        } else {
            &path
        };
        #[cfg(windows)]
        {
            crate::shell::open(target, action == "reveal")?;
        }
        #[cfg(not(windows))]
        {
            let mut command = std::process::Command::new("open");
            if action == "reveal" {
                command.arg("-R");
            }
            command.arg(target).spawn().map_err(|e| e.to_string())?;
        }
        Ok(())
    })
    .await
}

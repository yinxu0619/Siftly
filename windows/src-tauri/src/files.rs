use crate::model::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
};

pub fn checksum(path: &Path, cancel: &AtomicBool) -> Result<[u8; 32], String> {
    let mut input = File::open(path).map_err(|e| e.to_string())?;
    let mut buffer = vec![0u8; 4 * 1024 * 1024];
    let mut hash = Sha256::new();
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err("cancelled".into());
        }
        let n = input.read(&mut buffer).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        hash.update(&buffer[..n]);
    }
    Ok(hash.finalize().into())
}
pub fn copy_verified(
    source: &Path,
    dest: &Path,
    cancel: &AtomicBool,
    mut progress: impl FnMut(u64),
) -> Result<(), String> {
    let parent = dest.parent().ok_or("invalid_destination")?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    let mut input = File::open(source).map_err(|e| e.to_string())?;
    let metadata = input.metadata().map_err(|e| e.to_string())?;
    let mut buffer = vec![0u8; 4 * 1024 * 1024];
    let mut hash = Sha256::new();
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err("cancelled".into());
        }
        let n = input.read(&mut buffer).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        temp.write_all(&buffer[..n]).map_err(|e| e.to_string())?;
        hash.update(&buffer[..n]);
        progress(n as u64);
    }
    let final_metadata = input.metadata().map_err(|e| e.to_string())?;
    if metadata.len() != final_metadata.len()
        || metadata.modified().ok() != final_metadata.modified().ok()
    {
        return Err("file_changed".into());
    }
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    if <[u8; 32]>::from(hash.finalize()) != checksum(temp.path(), cancel)? {
        return Err("verification_failed".into());
    }
    filetime::set_file_mtime(
        temp.path(),
        filetime::FileTime::from_last_modification_time(&metadata),
    )
    .map_err(|e| e.to_string())?;
    if cancel.load(Ordering::Relaxed) {
        return Err("cancelled".into());
    }
    temp.persist_noclobber(dest).map_err(|e| e.to_string())?;
    Ok(())
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ImportSettings {
    pub destination: String,
    pub organization: String,
    pub include_paired: bool,
    pub delete_after: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ImportItem {
    pub source: MediaFile,
    pub destination: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ImportPlan {
    pub id: String,
    pub settings: ImportSettings,
    pub items: Vec<ImportItem>,
    pub skipped: Vec<String>,
    pub total_bytes: u64,
    pub free_bytes: u64,
}
pub fn plan_import(
    files: &[MediaFile],
    settings: ImportSettings,
    cancel: &AtomicBool,
) -> Result<ImportPlan, String> {
    let root = PathBuf::from(&settings.destination);
    if !root.is_dir() {
        return Err("not_a_directory".into());
    }
    let mut items = vec![];
    let mut skipped = vec![];
    let mut claimed = std::collections::HashSet::new();
    for file in files {
        if cancel.load(Ordering::Relaxed) {
            return Err("cancelled".into());
        }
        let date = chrono::DateTime::from_timestamp(file.modified, 0)
            .unwrap_or_default()
            .with_timezone(&chrono::Local);
        let mut folder = root.clone();
        match settings.organization.as_str() {
            "date" => folder.push(date.format("%Y-%m-%d").to_string()),
            "month" => {
                folder.push(date.format("%Y").to_string());
                folder.push(date.format("%Y-%m").to_string());
            }
            "kind" => {
                folder.push(date.format("%Y-%m-%d").to_string());
                folder.push(if file.is_raw {
                    "RAW"
                } else if file.is_video {
                    "Video"
                } else {
                    "JPEG"
                });
            }
            _ => (),
        }
        let mut candidate = folder.join(&file.name);
        let mut suffix = 1;
        let mut same = false;
        let mut source_hash = None;
        while candidate.symlink_metadata().is_ok()
            || claimed.contains(&candidate.to_string_lossy().to_lowercase())
        {
            if !claimed.contains(&candidate.to_string_lossy().to_lowercase())
                && candidate
                    .metadata()
                    .is_ok_and(|m| m.is_file() && m.len() == file.file_size)
            {
                let original = match source_hash {
                    Some(h) => h,
                    None => {
                        let h = checksum(Path::new(&file.path), cancel)?;
                        source_hash = Some(h);
                        h
                    }
                };
                if checksum(&candidate, cancel)? == original {
                    same = true;
                    break;
                }
            }
            candidate = folder.join(format!("{}-{}.{}", file.base_name, suffix, file.ext));
            suffix += 1;
        }
        if same {
            skipped.push(file.path.clone())
        } else {
            claimed.insert(candidate.to_string_lossy().to_lowercase());
            items.push(ImportItem {
                source: file.clone(),
                destination: candidate.to_string_lossy().into(),
            });
        }
    }
    let total_bytes = items.iter().map(|i| i.source.file_size).sum();
    let free_bytes = fs2::available_space(&root).map_err(|e| e.to_string())?;
    Ok(ImportPlan {
        id: uuid::Uuid::new_v4().to_string(),
        settings,
        items,
        skipped,
        total_bytes,
        free_bytes,
    })
}
pub fn scan(
    volume: &Volume,
    cancel: &AtomicBool,
    mut emit: impl FnMut(Vec<MediaFile>),
    mut warning: impl FnMut(String),
) -> Result<(), String> {
    if !Path::new(&volume.path).is_dir() {
        return Err("volume_unavailable".into());
    }
    let mut batch = Vec::with_capacity(256);
    for entry in walkdir::WalkDir::new(&volume.path)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| {
            let name = e.file_name().to_string_lossy();
            e.depth() == 0
                || (!name.starts_with('.')
                    && name != "$RECYCLE.BIN"
                    && name != "System Volume Information")
        })
    {
        if cancel.load(Ordering::Relaxed) {
            return Ok(());
        }
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                warning(e.to_string());
                continue;
            }
        };
        if !entry.file_type().is_file() {
            continue;
        }
        let ext = entry
            .path()
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or_default()
            .to_lowercase();
        if !supported(&ext) {
            continue;
        }
        match read_media(entry.path(), volume) {
            Ok(file) => batch.push(file),
            Err(e) => warning(e),
        }
        if batch.len() == 256 {
            emit(std::mem::take(&mut batch));
        }
    }
    if !batch.is_empty() {
        emit(batch)
    }
    Ok(())
}

pub fn recycle(path: &Path) -> Result<(), String> {
    #[cfg(windows)]
    {
        crate::shell::recycle(path)
    }
    #[cfg(not(windows))]
    {
        trash::delete(path).map_err(|e| e.to_string())
    }
}

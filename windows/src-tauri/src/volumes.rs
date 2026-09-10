use crate::model::Volume;
use sha2::{Digest, Sha256};
use std::path::Path;
pub fn folder(path: &Path) -> Result<Volume, String> {
    let path = path.canonicalize().map_err(|e| e.to_string())?;
    if !path.is_dir() {
        return Err("not_a_directory".into());
    }
    let text = path.to_string_lossy().to_string();
    Ok(Volume {
        id: format!("folder-{:x}", Sha256::digest(text.to_lowercase())),
        name: path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string(),
        path: text,
        total: fs2::total_space(&path).unwrap_or(0),
        free: fs2::available_space(&path).unwrap_or(0),
        manual: true,
    })
}
#[cfg(windows)]
pub fn list() -> Vec<Volume> {
    use windows::{
        core::PCWSTR,
        Win32::Storage::FileSystem::{
            GetDiskFreeSpaceExW, GetDriveTypeW, GetLogicalDrives, GetVolumeInformationW,
        },
    };
    let mut volumes = vec![];
    unsafe {
        let mask = GetLogicalDrives();
        for i in 0..26 {
            if mask & (1 << i) == 0 {
                continue;
            }
            let root = format!("{}:\\", (b'A' + i) as char);
            let wide: Vec<u16> = root.encode_utf16().chain(Some(0)).collect();
            if GetDriveTypeW(PCWSTR(wide.as_ptr())) != 2 {
                continue;
            }
            let mut label = [0u16; 261];
            let mut serial = 0;
            if GetVolumeInformationW(
                PCWSTR(wide.as_ptr()),
                Some(&mut label),
                Some(&mut serial),
                None,
                None,
                None,
            )
            .is_err()
            {
                continue;
            }
            let mut total = 0;
            let mut free = 0;
            let _ = GetDiskFreeSpaceExW(
                PCWSTR(wide.as_ptr()),
                Some(&mut free),
                Some(&mut total),
                None,
            );
            let label = String::from_utf16_lossy(
                &label[..label.iter().position(|x| *x == 0).unwrap_or(label.len())],
            );
            volumes.push(Volume {
                id: format!("win-{serial:08x}"),
                name: if label.is_empty() {
                    root.clone()
                } else {
                    label
                },
                path: std::fs::canonicalize(&root)
                    .unwrap_or(root.into())
                    .to_string_lossy()
                    .into(),
                total,
                free,
                manual: false,
            });
        }
    }
    volumes
}
#[cfg(not(windows))]
pub fn list() -> Vec<Volume> {
    vec![]
}

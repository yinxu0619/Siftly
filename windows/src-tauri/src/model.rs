use serde::{Deserialize, Serialize};
use std::{
    collections::{HashMap, HashSet},
    path::Path,
};

pub const RAW: &[&str] = &[
    "arw", "cr2", "cr3", "nef", "nrw", "raf", "rw2", "orf", "dng", "pef", "srw", "x3f", "raw",
    "3fr", "erf", "mef",
];
pub const VIDEO: &[&str] = &[
    "mov", "mp4", "m4v", "avi", "mts", "m2ts", "mxf", "3gp", "mpg", "mpeg", "wmv",
];
pub fn supported(ext: &str) -> bool {
    RAW.contains(&ext)
        || VIDEO.contains(&ext)
        || [
            "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        ]
        .contains(&ext)
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Volume {
    pub id: String,
    pub name: String,
    pub path: String,
    pub total: u64,
    pub free: u64,
    pub manual: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct MediaFile {
    pub path: String,
    pub name: String,
    pub base_name: String,
    pub ext: String,
    pub directory: String,
    pub fingerprint: String,
    pub file_size: u64,
    pub modified: i64,
    pub modified_nanos: String,
    pub volume_id: String,
    pub volume_name: String,
    pub volume_path: String,
    pub key: String,
    pub is_raw: bool,
    pub is_video: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Adjustments {
    pub exposure: f32,
    pub brightness: f32,
    pub contrast: f32,
    pub highlights: f32,
    pub shadows: f32,
    pub hdr: f32,
    pub saturation: f32,
    pub vibrance: f32,
    pub temperature: f32,
    pub tint: f32,
    pub sharpen: f32,
    pub vignette: f32,
    pub curve: Vec<[f32; 2]>,
    pub rotation_quarters: i32,
    pub straighten: f32,
    pub flip_horizontal: bool,
    pub crop_rect: Option<[f32; 4]>,
}
impl Default for Adjustments {
    fn default() -> Self {
        Self {
            exposure: 0.,
            brightness: 0.,
            contrast: 0.,
            highlights: 0.,
            shadows: 0.,
            hdr: 0.,
            saturation: 0.,
            vibrance: 0.,
            temperature: 0.,
            tint: 0.,
            sharpen: 0.,
            vignette: 0.,
            curve: vec![[0., 0.], [1., 1.]],
            rotation_quarters: 0,
            straighten: 0.,
            flip_horizontal: false,
            crop_rect: None,
        }
    }
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct FileMark {
    pub rating: u8,
    pub label: String,
    pub adjustments: Adjustments,
}
impl FileMark {
    pub fn empty(&self) -> bool {
        self.rating == 0
            && (self.label.is_empty() || self.label == "none")
            && self.adjustments == Adjustments::default()
    }
    pub fn validate(&self) -> Result<(), String> {
        if self.rating > 5
            || ![
                "", "none", "red", "orange", "yellow", "green", "blue", "purple", "gray",
            ]
            .contains(&self.label.as_str())
        {
            return Err("invalid_mark".into());
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Preferences {
    pub language: String,
    pub prefetch: usize,
    pub write_xmp: bool,
    pub show_exif: bool,
}
impl Default for Preferences {
    fn default() -> Self {
        Self {
            language: "system".into(),
            prefetch: 3,
            write_xmp: false,
            show_exif: true,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Rule {
    pub preset: String,
    pub cross_location: bool,
}
impl Default for Rule {
    fn default() -> Self {
        Self {
            preset: "universal".into(),
            cross_location: false,
        }
    }
}
pub type Pairs = HashMap<String, Vec<String>>;
pub fn pair(files: &[MediaFile], rule: &Rule) -> Pairs {
    let raw: &[&str] = match rule.preset.as_str() {
        "sony" => &["arw"],
        "canon" => &["cr2", "cr3"],
        "nikon" => &["nef", "nrw"],
        "fuji" => &["raf"],
        _ => RAW,
    };
    let mut buckets: HashMap<(String, String), Vec<String>> = HashMap::new();
    for f in files {
        if raw.contains(&f.ext.as_str())
            || ["jpg", "jpeg", "heic", "heif"].contains(&f.ext.as_str())
            || VIDEO.contains(&f.ext.as_str())
        {
            buckets
                .entry((
                    if rule.cross_location {
                        String::new()
                    } else {
                        f.directory.to_lowercase()
                    },
                    f.base_name.to_lowercase(),
                ))
                .or_default()
                .push(f.path.clone());
        }
    }
    let mut result = Pairs::new();
    for group in buckets.values().filter(|g| g.len() > 1) {
        for path in group {
            result.insert(
                path.clone(),
                group.iter().filter(|p| *p != path).cloned().collect(),
            );
        }
    }
    result
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeletionPlan {
    pub id: String,
    pub selected: Vec<MediaFile>,
    pub paired: Vec<MediaFile>,
    pub total_bytes: u64,
}
pub fn deletion_plan(files: &[MediaFile], selected: &[String], rule: &Rule) -> DeletionPlan {
    let selected: HashSet<_> = selected.iter().cloned().collect();
    let pairs = pair(files, rule);
    let extras: HashSet<_> = selected
        .iter()
        .flat_map(|p| pairs.get(p).cloned().unwrap_or_default())
        .filter(|p| !selected.contains(p))
        .collect();
    let mut direct: Vec<_> = files
        .iter()
        .filter(|f| selected.contains(&f.path))
        .cloned()
        .collect();
    let mut paired: Vec<_> = files
        .iter()
        .filter(|f| extras.contains(&f.path))
        .cloned()
        .collect();
    direct.sort_by_key(|f| f.path.clone());
    paired.sort_by_key(|f| f.path.clone());
    let total_bytes = direct.iter().chain(&paired).map(|f| f.file_size).sum();
    DeletionPlan {
        id: uuid::Uuid::new_v4().to_string(),
        selected: direct,
        paired,
        total_bytes,
    }
}
pub fn read_media(path: &Path, volume: &Volume) -> Result<MediaFile, String> {
    let metadata = std::fs::symlink_metadata(path).map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.file_type().is_symlink() {
        return Err("not_regular_file".into());
    }
    let modified = metadata
        .modified()
        .map_err(|e| e.to_string())?
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_lowercase();
    let relative = path
        .strip_prefix(&volume.path)
        .map_err(|_| "outside_volume")?
        .to_string_lossy()
        .replace('\\', "/");
    Ok(MediaFile {
        path: path.to_string_lossy().into(),
        name: path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into(),
        base_name: path
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into(),
        directory: path.parent().unwrap_or(path).to_string_lossy().into(),
        fingerprint: file_identity(path, &metadata)?,
        file_size: metadata.len(),
        modified: modified.as_secs() as i64,
        modified_nanos: modified.as_nanos().to_string(),
        volume_id: volume.id.clone(),
        volume_name: volume.name.clone(),
        volume_path: volume.path.clone(),
        key: format!("{}::{}", volume.id, relative.to_lowercase()),
        is_raw: RAW.contains(&ext.as_str()),
        is_video: VIDEO.contains(&ext.as_str()),
        ext,
    })
}
pub fn unchanged(file: &MediaFile) -> bool {
    std::fs::symlink_metadata(&file.path).is_ok_and(|m| {
        m.is_file()
            && !m.file_type().is_symlink()
            && file_identity(Path::new(&file.path), &m).is_ok_and(|id| id == file.fingerprint)
            && m.len() == file.file_size
            && m.modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .is_some_and(|t| t.as_nanos().to_string() == file.modified_nanos)
    })
}
#[derive(Clone, Debug, Serialize)]
pub struct Progress {
    pub id: String,
    pub done: usize,
    pub total: usize,
    pub name: String,
    pub bytes: u64,
}
#[derive(Default, Debug, Serialize)]
pub struct Outcome {
    pub completed: Vec<String>,
    pub skipped: Vec<String>,
    pub failures: Vec<String>,
    pub cancelled: bool,
}

#[cfg(unix)]
fn file_identity(_path: &Path, metadata: &std::fs::Metadata) -> Result<String, String> {
    use std::os::unix::fs::MetadataExt;
    Ok(format!("{}-{}", metadata.dev(), metadata.ino()))
}
#[cfg(windows)]
fn file_identity(path: &Path, _metadata: &std::fs::Metadata) -> Result<String, String> {
    use std::os::windows::io::AsRawHandle;
    use windows::Win32::{
        Foundation::HANDLE,
        Storage::FileSystem::{GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION},
    };
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut info = BY_HANDLE_FILE_INFORMATION::default();
    unsafe { GetFileInformationByHandle(HANDLE(file.as_raw_handle()), &mut info) }
        .map_err(|e| e.to_string())?;
    Ok(format!(
        "{}-{}-{}",
        info.dwVolumeSerialNumber, info.nFileIndexHigh, info.nFileIndexLow
    ))
}

#[cfg(windows)]
#[derive(Clone)]
pub struct RecycledFile {
    pub id: String,
    pub path: String,
}

#[cfg(not(windows))]
pub type RecycledFile = ();

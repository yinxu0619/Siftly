use lru::LruCache;
use parking_lot::Mutex;
use std::{
    fs,
    io::Write,
    num::NonZeroUsize,
    path::{Path, PathBuf},
};
const MAX_BYTES: u64 = 512 * 1024 * 1024;
const MAX_FILES: usize = 8192;
struct Index {
    items: LruCache<String, u64>,
    bytes: u64,
}
fn valid(name: &str) -> bool {
    name.len() == 68
        && name.ends_with(".jpg")
        && name[..64].bytes().all(|b| b.is_ascii_hexdigit())
}
pub struct ThumbnailCache {
    root: PathBuf,
    index: Mutex<Index>,
}
impl ThumbnailCache {
    pub fn new(root: &Path) -> Result<Self, String> {
        fs::create_dir_all(root).map_err(|e| e.to_string())?;
        let mut entries: Vec<_> = fs::read_dir(root)
            .map_err(|e| e.to_string())?
            .filter_map(Result::ok)
            .filter_map(|entry| {
                let name = entry.file_name().to_str()?.to_owned();
                if !valid(&name) {
                    return None;
                }
                let meta = entry.metadata().ok()?;
                if !meta.is_file() {
                    return None;
                }
                Some((meta.modified().ok(), name, meta.len()))
            })
            .collect();
        entries.sort_by_key(|e| e.0);
        let mut index = Index {
            items: LruCache::new(NonZeroUsize::new(MAX_FILES).unwrap()),
            bytes: 0,
        };
        for (_, name, size) in entries {
            index.bytes += size;
            if let Some((old, bytes)) = index.items.push(name, size) {
                index.bytes -= bytes;
                let _ = fs::remove_file(root.join(old));
            }
        }
        Self::prune(root, &mut index);
        Ok(Self {
            root: root.into(),
            index: Mutex::new(index),
        })
    }
    fn prune(root: &Path, index: &mut Index) {
        while index.bytes > MAX_BYTES {
            if let Some((name, size)) = index.items.pop_lru() {
                index.bytes -= size;
                let _ = fs::remove_file(root.join(name));
            } else {
                break;
            }
        }
    }
    pub fn get(&self, name: &str) -> Option<Vec<u8>> {
        if !valid(name) {
            return None;
        }
        self.index.lock().items.get(name)?;
        fs::read(self.root.join(name)).ok()
    }
    /// Whether `name` is cached on disk; marks it recently used.
    pub fn contains(&self, name: &str) -> bool {
        let mut index = self.index.lock();
        if index.items.get(name).is_none() {
            return false;
        }
        if self.root.join(name).is_file() {
            return true;
        }
        if let Some(size) = index.items.pop(name) {
            index.bytes -= size;
        }
        false
    }
    pub fn put(&self, name: &str, bytes: &[u8]) -> bool {
        let mut index = self.index.lock();
        let Ok(mut temp) = tempfile::NamedTempFile::new_in(&self.root) else {
            return false;
        };
        if temp.write_all(bytes).is_err() || temp.persist(self.root.join(name)).is_err() {
            return false;
        }
        index.bytes += bytes.len() as u64;
        if let Some((old, size)) = index.items.push(name.into(), bytes.len() as u64) {
            index.bytes -= size;
            if old != name {
                let _ = fs::remove_file(self.root.join(old));
            }
        }
        Self::prune(&self.root, &mut index);
        index.items.contains(name)
    }
}

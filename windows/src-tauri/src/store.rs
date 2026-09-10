use crate::model::*;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    io::Write,
    path::{Path, PathBuf},
};
#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Database {
    pub marks: HashMap<String, FileMark>,
    pub folders: Vec<String>,
    pub preferences: Preferences,
}
pub struct Store {
    pub data: Database,
    path: PathBuf,
}
impl Store {
    pub fn open(root: &Path) -> Result<Self, String> {
        std::fs::create_dir_all(root).map_err(|e| e.to_string())?;
        let path = root.join("library.json");
        let data = if path.exists() {
            serde_json::from_slice(&std::fs::read(&path).map_err(|e| e.to_string())?)
                .map_err(|e| format!("library_corrupt: {e}"))?
        } else {
            Database::default()
        };
        Ok(Self { data, path })
    }
    pub fn save(&self) -> Result<(), String> {
        let mut temp = tempfile::NamedTempFile::new_in(self.path.parent().unwrap())
            .map_err(|e| e.to_string())?;
        temp.write_all(&serde_json::to_vec(&self.data).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        temp.as_file().sync_all().map_err(|e| e.to_string())?;
        temp.persist(&self.path).map_err(|e| e.to_string())?;
        Ok(())
    }
}

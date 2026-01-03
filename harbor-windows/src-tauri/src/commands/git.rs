use crate::platform::executable_locator::WindowsExecutableLocator;
use serde::Serialize;
use std::path::PathBuf;

#[derive(Debug, Serialize)]
pub struct GitInfo {
    pub path: Option<String>,
    pub version: Option<String>,
    pub error: Option<String>,
}

/// Locate git executable
#[tauri::command]
pub fn locate_git() -> Result<GitInfo, String> {
    let locator = WindowsExecutableLocator::new();

    match locator.locate("git") {
        Some(path) => {
            let version = locator.version(&path).ok();
            Ok(GitInfo {
                path: Some(path.to_string_lossy().to_string()),
                version,
                error: None,
            })
        }
        None => Ok(GitInfo {
            path: None,
            version: None,
            error: Some("Git executable not found".to_string()),
        }),
    }
}

/// Get version of executable at path
#[tauri::command]
pub fn get_executable_version(path: String) -> Result<String, String> {
    let locator = WindowsExecutableLocator::new();
    let path_buf = PathBuf::from(path);
    locator.version(&path_buf).map_err(|e| e.to_string())
}

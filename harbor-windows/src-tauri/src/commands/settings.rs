use crate::platform::settings_storage::{JSONFileSettingsStorage, UserSettings};
use std::sync::Mutex;
use tauri::State;

/// Application state for settings
pub struct SettingsState {
    pub storage: Mutex<JSONFileSettingsStorage>,
}

impl SettingsState {
    pub fn new() -> Result<Self, anyhow::Error> {
        let storage = JSONFileSettingsStorage::new("RepoBar")?;
        Ok(Self {
            storage: Mutex::new(storage),
        })
    }
}

impl Default for SettingsState {
    fn default() -> Self {
        Self::new().expect("Failed to initialize settings storage")
    }
}

/// Load user settings
#[tauri::command]
pub fn load_settings(state: State<'_, SettingsState>) -> Result<UserSettings, String> {
    let storage = state.storage.lock().map_err(|e| e.to_string())?;
    storage.load().map_err(|e| e.to_string())
}

/// Save user settings
#[tauri::command]
pub fn save_settings(
    settings: UserSettings,
    state: State<'_, SettingsState>,
) -> Result<bool, String> {
    let storage = state.storage.lock().map_err(|e| e.to_string())?;
    storage.save(&settings).map_err(|e| e.to_string())?;
    Ok(true)
}

/// Reset settings to defaults
#[tauri::command]
pub fn reset_settings(state: State<'_, SettingsState>) -> Result<UserSettings, String> {
    let storage = state.storage.lock().map_err(|e| e.to_string())?;
    let defaults = UserSettings::default();
    storage.save(&defaults).map_err(|e| e.to_string())?;
    Ok(defaults)
}

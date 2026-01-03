use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// User settings structure (mirrors Swift UserSettings)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserSettings {
    #[serde(default)]
    pub appearance: AppearanceSettings,
    #[serde(default)]
    pub repositories: RepositorySettings,
    #[serde(default)]
    pub refresh: RefreshSettings,
    #[serde(default)]
    pub advanced: AdvancedSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppearanceSettings {
    #[serde(default = "default_accent_tone")]
    pub accent_tone: String,
    #[serde(default = "default_true")]
    pub show_icons: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepositorySettings {
    #[serde(default = "default_max_repos")]
    pub max_repos: u32,
    #[serde(default = "default_true")]
    pub show_private: bool,
    #[serde(default = "default_true")]
    pub show_public: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RefreshSettings {
    #[serde(default = "default_auto_refresh")]
    pub auto_refresh: bool,
    #[serde(default = "default_refresh_interval")]
    pub refresh_interval_minutes: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdvancedSettings {
    #[serde(default)]
    pub git_path: Option<String>,
    #[serde(default = "default_true")]
    pub launch_at_login: bool,
}

fn default_accent_tone() -> String {
    "blue".to_string()
}

fn default_true() -> bool {
    true
}

fn default_max_repos() -> u32 {
    100
}

fn default_auto_refresh() -> bool {
    true
}

fn default_refresh_interval() -> u32 {
    15
}

impl Default for AppearanceSettings {
    fn default() -> Self {
        Self {
            accent_tone: default_accent_tone(),
            show_icons: true,
        }
    }
}

impl Default for RepositorySettings {
    fn default() -> Self {
        Self {
            max_repos: default_max_repos(),
            show_private: true,
            show_public: true,
        }
    }
}

impl Default for RefreshSettings {
    fn default() -> Self {
        Self {
            auto_refresh: true,
            refresh_interval_minutes: default_refresh_interval(),
        }
    }
}

impl Default for AdvancedSettings {
    fn default() -> Self {
        Self {
            git_path: None,
            launch_at_login: true,
        }
    }
}

impl Default for UserSettings {
    fn default() -> Self {
        Self {
            appearance: AppearanceSettings::default(),
            repositories: RepositorySettings::default(),
            refresh: RefreshSettings::default(),
            advanced: AdvancedSettings::default(),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct SettingsEnvelope {
    version: u32,
    settings: UserSettings,
}

/// JSON file-based settings storage for Windows
pub struct JSONFileSettingsStorage {
    file_path: PathBuf,
}

const CURRENT_VERSION: u32 = 3;

impl JSONFileSettingsStorage {
    /// Create a new settings storage with app name
    pub fn new(app_name: &str) -> Result<Self> {
        let config_dir = Self::get_config_dir(app_name)?;
        fs::create_dir_all(&config_dir)
            .context("Failed to create config directory")?;

        let file_path = config_dir.join("settings.json");
        Ok(Self { file_path })
    }

    /// Get Windows AppData directory for the app
    fn get_config_dir(app_name: &str) -> Result<PathBuf> {
        // Use %APPDATA%\RepoBar on Windows
        let app_data = dirs::config_dir()
            .context("Failed to get AppData directory")?;
        Ok(app_data.join(app_name))
    }

    /// Load settings from JSON file
    pub fn load(&self) -> Result<UserSettings> {
        if !self.file_path.exists() {
            return Ok(UserSettings::default());
        }

        let contents = fs::read_to_string(&self.file_path)
            .context("Failed to read settings file")?;

        match serde_json::from_str::<SettingsEnvelope>(&contents) {
            Ok(envelope) => {
                let mut settings = envelope.settings;
                if envelope.version < CURRENT_VERSION {
                    Self::apply_migrations(&mut settings, envelope.version);
                    self.save(&settings)?;
                }
                Ok(settings)
            }
            Err(_) => {
                // If we can't parse the envelope, try parsing as raw settings (old format)
                match serde_json::from_str::<UserSettings>(&contents) {
                    Ok(settings) => {
                        // Save in new format
                        self.save(&settings)?;
                        Ok(settings)
                    }
                    Err(_) => {
                        // If all parsing fails, return defaults
                        Ok(UserSettings::default())
                    }
                }
            }
        }
    }

    /// Save settings to JSON file
    pub fn save(&self, settings: &UserSettings) -> Result<()> {
        let envelope = SettingsEnvelope {
            version: CURRENT_VERSION,
            settings: settings.clone(),
        };

        let json = serde_json::to_string_pretty(&envelope)
            .context("Failed to serialize settings")?;

        fs::write(&self.file_path, json)
            .context("Failed to write settings file")?;

        Ok(())
    }

    /// Apply migrations for older settings versions
    fn apply_migrations(_settings: &mut UserSettings, _from_version: u32) {
        // Apply incremental migrations here as settings schema evolves
        // Example:
        // if from_version < 2 {
        //     settings.some_new_field = default_value;
        // }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_settings_default() {
        let settings = UserSettings::default();
        assert_eq!(settings.appearance.accent_tone, "blue");
        assert_eq!(settings.repositories.max_repos, 100);
        assert!(settings.refresh.auto_refresh);
    }

    #[test]
    fn test_settings_serialization() {
        let settings = UserSettings::default();
        let json = serde_json::to_string(&settings).unwrap();
        let deserialized: UserSettings = serde_json::from_str(&json).unwrap();
        assert_eq!(settings.appearance.accent_tone, deserialized.appearance.accent_tone);
    }
}

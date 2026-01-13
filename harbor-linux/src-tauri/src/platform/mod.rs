//!
//! Platform Services for Linux
//!
//! This module provides Linux-specific implementations of platform services
//! including credential storage, file system access, and platform utilities.
//!

use std::path::PathBuf;
use std::sync::Mutex;
use secret_service::Collection;
use once_cell::sync::Lazy;

/// Linux-specific platform services implementation
pub struct LinuxPlatformServices {
    /// Credential storage (Secret Service API / libsecret)
    credentials: Mutex<Option<Collection>>,
}

impl Default for LinuxPlatformServices {
    fn default() -> Self {
        Self::new()
    }
}

impl LinuxPlatformServices {
    /// Create a new LinuxPlatformServices instance
    pub fn new() -> Self {
        Self {
            credentials: Mutex::new(None),
        }
    }

    /// Initialize the credential collection
    fn init_credentials(&self) -> Result<(), String> {
        let mut collection = self.credentials.lock().map_err(|e| e.to_string())?;

        if collection.is_none() {
            let ss = secret_service::SecretService::new(secret_service::EncryptionType::Dh)
                .map_err(|e| format!("Failed to connect to Secret Service: {}", e))?;
            let coll = ss
                .get_collection(secret_service::CollectionType::Default)
                .map_err(|e| format!("Failed to get default collection: {}", e))?;
            *collection = Some(coll);
        }

        Ok(())
    }
}

/// Credential storage using Linux Secret Service API
impl super::CredentialStorage for LinuxPlatformServices {
    fn store_token(&self, service: &str, account: &str, token: &[u8]) -> Result<(), String> {
        self.init_credentials()?;
        let collection = self.credentials
            .lock()
            .map_err(|e| e.to_string())?
            .as_ref()
            .ok_or("Credentials not initialized")?;

        let label = format!("Harbor {} token for {}", service, account);
        let attributes = vec![
            ("service", service),
            ("account", account),
            ("application", "Harbor"),
        ];

        // Check if secret already exists
        let existing = collection.search_items(attributes.clone()).ok();

        if let Ok(items) = existing {
            for item in items {
                let _ = item.delete();
            }
        }

        collection
            .create_item(label, attributes, token, "application/x-harbor-token")
            .map_err(|e| format!("Failed to store credential: {}", e))?;

        Ok(())
    }

    fn load_token(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, String> {
        self.init_credentials()?;
        let collection = self.credentials
            .lock()
            .map_err(|e| e.to_string())?
            .as_ref()
            .ok_or("Credentials not initialized")?;

        let attributes = vec![
            ("service", service),
            ("account", account),
            ("application", "Harbor"),
        ];

        let items = collection.search_items(attributes.clone())
            .map_err(|e| format!("Failed to search credentials: {}", e))?;

        for item in items {
            if let Ok(secret) = item.get_secret() {
                return Ok(Some(secret));
            }
        }

        Ok(None)
    }

    fn delete_token(&self, service: &str, account: &str) -> Result<bool, String> {
        self.init_credentials()?;
        let collection = self.credentials
            .lock()
            .map_err(|e| e.to_string())?
            .as_ref()
            .ok_or("Credentials not initialized")?;

        let attributes = vec![
            ("service", service),
            ("account", account),
            ("application", "Harbor"),
        ];

        let items = collection.search_items(attributes.clone())
            .map_err(|e| format!("Failed to search credentials: {}", e))?;

        let mut deleted = false;
        for mut item in items {
            if item.delete().is_ok() {
                deleted = true;
            }
        }

        Ok(deleted)
    }
}

/// File system utilities for Linux
impl super::FileSystem for LinuxPlatformServices {
    fn config_dir(&self) -> Result<PathBuf, String> {
        dirs::config_dir()
            .map(|mut p| {
                p.push("Harbor");
                p
            })
            .ok_or("Could not determine config directory".to_string())
    }

    fn cache_dir(&self) -> Result<PathBuf, String> {
        dirs::cache_dir()
            .map(|mut p| {
                p.push("Harbor");
                p
            })
            .ok_or("Could not determine cache directory".to_string())
    }

    fn data_dir(&self) -> Result<PathBuf, String> {
        dirs::data_dir()
            .map(|mut p| {
                p.push("Harbor");
                p
            })
            .ok_or("Could not determine data directory".to_string())
    }
}

/// Platform utilities for Linux
impl super::PlatformUtilities for LinuxPlatformServices {
    fn platform_name(&self) -> &'static str {
        "linux"
    }

    fn version(&self) -> String {
        std::env::consts::OS_VERSION.to_string()
    }

    fn is_sandboxed(&self) -> bool {
        // Check if running in a flatpak or snap sandbox
        std::env::var("FLATPAK_ID").is_ok() || std::env::var("SNAP_INSTANCE_NAME").is_ok()
    }

    fn restart(&self) -> Result<(), String> {
        // On Linux, we can't really restart the app programmatically
        // The app should be launched with a wrapper script
        Err("Restart not supported on Linux".to_string())
    }
}

pub mod callback_server;
pub mod executable_locator;
pub mod settings_storage;
pub mod token_storage;

use crate::auth::types::{OAuthClientCredentials, OAuthTokens};
use anyhow::Result;

/// Platform services bundle - Windows implementation
pub struct WindowsPlatformServices {
    pub token_storage: token_storage::WindowsCredentialManagerStorage,
    pub settings_storage: settings_storage::JSONFileSettingsStorage,
}

impl WindowsPlatformServices {
    pub fn new() -> Result<Self> {
        Ok(Self {
            token_storage: token_storage::WindowsCredentialManagerStorage::new(
                "com.steipete.repobar.auth".to_string(),
            ),
            settings_storage: settings_storage::JSONFileSettingsStorage::new("RepoBar")?,
        })
    }
}

impl Default for WindowsPlatformServices {
    fn default() -> Self {
        Self::new().expect("Failed to initialize platform services")
    }
}

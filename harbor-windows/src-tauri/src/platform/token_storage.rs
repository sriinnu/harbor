use anyhow::{Context, Result};
use keyring::Entry;
use serde::{Deserialize, Serialize};

use crate::auth::types::{OAuthClientCredentials, OAuthTokens};

/// Windows implementation using Windows Credential Manager via keyring crate
pub struct WindowsCredentialManagerStorage {
    service: String,
}

impl WindowsCredentialManagerStorage {
    pub fn new(service: String) -> Self {
        Self { service }
    }

    /// Save OAuth tokens securely to Windows Credential Manager
    pub fn save_tokens(&self, tokens: &OAuthTokens) -> Result<()> {
        let entry = Entry::new(&self.service, "default")
            .context("Failed to create credential entry for tokens")?;
        let json = serde_json::to_string(tokens).context("Failed to serialize tokens to JSON")?;
        entry
            .set_password(&json)
            .context("Failed to save tokens to Windows Credential Manager")?;
        Ok(())
    }

    /// Load OAuth tokens from Windows Credential Manager
    pub fn load_tokens(&self) -> Result<Option<OAuthTokens>> {
        let entry = Entry::new(&self.service, "default")
            .context("Failed to create credential entry for tokens")?;
        match entry.get_password() {
            Ok(json) => {
                let tokens: OAuthTokens = serde_json::from_str(&json)
                    .context("Failed to deserialize tokens from JSON")?;
                Ok(Some(tokens))
            }
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e).context("Failed to load tokens from Windows Credential Manager"),
        }
    }

    /// Save OAuth client credentials securely
    pub fn save_client_credentials(&self, credentials: &OAuthClientCredentials) -> Result<()> {
        let entry = Entry::new(&self.service, "client")
            .context("Failed to create credential entry for client credentials")?;
        let json = serde_json::to_string(credentials)
            .context("Failed to serialize credentials to JSON")?;
        entry
            .set_password(&json)
            .context("Failed to save credentials to Windows Credential Manager")?;
        Ok(())
    }

    /// Load OAuth client credentials
    pub fn load_client_credentials(&self) -> Result<Option<OAuthClientCredentials>> {
        let entry = Entry::new(&self.service, "client")
            .context("Failed to create credential entry for client credentials")?;
        match entry.get_password() {
            Ok(json) => {
                let credentials: OAuthClientCredentials = serde_json::from_str(&json)
                    .context("Failed to deserialize credentials from JSON")?;
                Ok(Some(credentials))
            }
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(e).context("Failed to load credentials from Windows Credential Manager"),
        }
    }

    /// Clear all stored tokens and credentials
    pub fn clear(&self) -> Result<()> {
        // Clear tokens
        if let Ok(entry) = Entry::new(&self.service, "default") {
            let _ = entry.delete_credential();
        }

        // Clear client credentials
        if let Ok(entry) = Entry::new(&self.service, "client") {
            let _ = entry.delete_credential();
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_storage_roundtrip() {
        let storage = WindowsCredentialManagerStorage::new("com.test.repobar".to_string());

        // Clear any existing data
        let _ = storage.clear();

        let tokens = OAuthTokens {
            access_token: "test_access".to_string(),
            refresh_token: "test_refresh".to_string(),
            expires_at: Some(chrono::Utc::now() + chrono::Duration::hours(1)),
        };

        storage.save_tokens(&tokens).unwrap();
        let loaded = storage.load_tokens().unwrap();

        assert!(loaded.is_some());
        assert_eq!(loaded.unwrap().access_token, "test_access");

        storage.clear().unwrap();
        assert!(storage.load_tokens().unwrap().is_none());
    }
}

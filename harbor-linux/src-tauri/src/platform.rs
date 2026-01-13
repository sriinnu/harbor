//!
//! Platform Abstraction Layer
//!
//! This module defines the platform traits that each platform-specific
//! implementation must provide. This enables code sharing across platforms
//! while maintaining platform-specific optimizations.
//!

use std::path::PathBuf;

/// Credential storage trait
pub trait CredentialStorage {
    /// Store an authentication token
    fn store_token(&self, service: &str, account: &str, token: &[u8]) -> Result<(), String>;

    /// Load an authentication token
    fn load_token(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, String>;

    /// Delete an authentication token
    fn delete_token(&self, service: &str, account: &str) -> Result<bool, String>;
}

/// File system utilities trait
pub trait FileSystem {
    /// Get the configuration directory
    fn config_dir(&self) -> Result<PathBuf, String>;

    /// Get the cache directory
    fn cache_dir(&self) -> Result<PathBuf, String>;

    /// Get the data directory
    fn data_dir(&self) -> Result<PathBuf, String>;
}

/// Platform utilities trait
pub trait PlatformUtilities {
    /// Get the platform name
    fn platform_name(&self) -> &'static str;

    /// Get the OS version
    fn version(&self) -> String;

    /// Check if running in a sandbox
    fn is_sandboxed(&self) -> bool;

    /// Restart the application
    fn restart(&self) -> Result<(), String>;
}

/// Combined platform services
pub trait PlatformServices:
    CredentialStorage + FileSystem + PlatformUtilities + Send + Sync
{
}

impl<T> PlatformServices for T where T: CredentialStorage + FileSystem + PlatformUtilities + Send + Sync {}

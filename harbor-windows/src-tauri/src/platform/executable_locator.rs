use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Command;

/// Windows executable locator
pub struct WindowsExecutableLocator;

impl WindowsExecutableLocator {
    pub fn new() -> Self {
        Self
    }

    /// Locate an executable by name on Windows
    pub fn locate(&self, name: &str) -> Option<PathBuf> {
        // Add .exe extension if not present
        let exe_name = if name.ends_with(".exe") {
            name.to_string()
        } else {
            format!("{}.exe", name)
        };

        // Try Windows-specific paths first
        let candidates = vec![
            // Git for Windows default locations
            format!("C:\\Program Files\\Git\\cmd\\{}", exe_name),
            format!("C:\\Program Files\\Git\\bin\\{}", exe_name),
            format!("C:\\Program Files (x86)\\Git\\cmd\\{}", exe_name),
            format!("C:\\Program Files (x86)\\Git\\bin\\{}", exe_name),
            // System paths
            format!("C:\\Windows\\System32\\{}", exe_name),
            format!("C:\\Windows\\{}", exe_name),
        ];

        // Check static paths first
        for path_str in &candidates {
            let path = PathBuf::from(path_str);
            if path.exists() && path.is_file() {
                return Some(path);
            }
        }

        // Try PATH environment variable
        if let Ok(path_env) = std::env::var("PATH") {
            for dir in path_env.split(';') {
                let path = PathBuf::from(dir).join(&exe_name);
                if path.exists() && path.is_file() {
                    return Some(path);
                }
            }
        }

        // Try using 'where' command (Windows equivalent of 'which')
        if let Ok(output) = Command::new("where").arg(&exe_name).output() {
            if output.status.success() {
                if let Ok(path_str) = String::from_utf8(output.stdout) {
                    // 'where' may return multiple paths, take the first one
                    if let Some(first_line) = path_str.lines().next() {
                        let path = PathBuf::from(first_line.trim());
                        if path.exists() {
                            return Some(path);
                        }
                    }
                }
            }
        }

        None
    }

    /// Get version information for an executable
    pub fn version(&self, path: &PathBuf) -> Result<String> {
        let output = Command::new(path)
            .arg("--version")
            .output()
            .context("Failed to execute --version command")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(anyhow::anyhow!(
                "Command failed with exit code {}: {}",
                output.status.code().unwrap_or(-1),
                stderr
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(stdout.trim().to_string())
    }
}

impl Default for WindowsExecutableLocator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_locate_git() {
        let locator = WindowsExecutableLocator::new();

        // This test will only pass on Windows with Git installed
        #[cfg(target_os = "windows")]
        {
            if let Some(git_path) = locator.locate("git") {
                println!("Found git at: {:?}", git_path);
                assert!(git_path.exists());

                if let Ok(version) = locator.version(&git_path) {
                    println!("Git version: {}", version);
                    assert!(version.contains("git"));
                }
            }
        }
    }
}

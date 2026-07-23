use crate::auth::OAuthLoginFlow;
use crate::platform::token_storage::WindowsCredentialManagerStorage;
use serde::Serialize;
use std::sync::Mutex;
use tauri::State;

/// Application state for auth
pub struct AuthState {
    pub oauth_flow: Mutex<OAuthLoginFlow>,
}

impl AuthState {
    pub fn new() -> Self {
        let token_storage =
            WindowsCredentialManagerStorage::new("com.sriinnu.harbor.auth".to_string());
        let oauth_flow = OAuthLoginFlow::new(token_storage);

        Self {
            oauth_flow: Mutex::new(oauth_flow),
        }
    }
}

impl Default for AuthState {
    fn default() -> Self {
        Self::new()
    }
}

/// Result type for auth commands
#[derive(Debug, Serialize)]
pub struct AuthResult {
    pub success: bool,
    pub error: Option<String>,
}

/// Start OAuth login flow
#[tauri::command]
pub async fn start_oauth_login(
    client_id: String,
    client_secret: String,
    host: String,
    state: State<'_, AuthState>,
) -> Result<AuthResult, String> {
    let oauth_flow = state.oauth_flow.lock().map_err(|e| e.to_string())?;

    let host_url = url::Url::parse(&host).map_err(|e| format!("Invalid host URL: {}", e))?;

    match oauth_flow
        .login(
            client_id,
            client_secret,
            host_url,
            53682, // Default OAuth callback port
            Some("repo read:org".to_string()),
            180, // 3 minute timeout
        )
        .await
    {
        Ok(_) => Ok(AuthResult {
            success: true,
            error: None,
        }),
        Err(e) => Ok(AuthResult {
            success: false,
            error: Some(e.to_string()),
        }),
    }
}

/// Logout (clear all stored tokens and credentials)
#[tauri::command]
pub fn logout(state: State<'_, AuthState>) -> Result<bool, String> {
    let oauth_flow = state.oauth_flow.lock().map_err(|e| e.to_string())?;
    oauth_flow.logout().map_err(|e| e.to_string())?;
    Ok(true)
}

/// Check if user is authenticated
#[tauri::command]
pub fn is_authenticated(state: State<'_, AuthState>) -> Result<bool, String> {
    let oauth_flow = state.oauth_flow.lock().map_err(|e| e.to_string())?;
    let tokens = oauth_flow.load_tokens().map_err(|e| e.to_string())?;
    Ok(tokens.is_some())
}

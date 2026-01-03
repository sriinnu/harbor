use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// OAuth token structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OAuthTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: Option<DateTime<Utc>>,
}

/// OAuth client credentials
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OAuthClientCredentials {
    pub client_id: String,
    pub client_secret: String,
}

/// Token response from OAuth provider
#[derive(Debug, Deserialize)]
pub struct TokenResponse {
    pub access_token: String,
    #[serde(default)]
    pub token_type: String,
    #[serde(default)]
    pub scope: String,
    pub expires_in: Option<u64>,
    pub refresh_token: Option<String>,
}

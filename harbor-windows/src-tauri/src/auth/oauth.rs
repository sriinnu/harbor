use super::pkce::PKCE;
use super::types::{OAuthClientCredentials, OAuthTokens, TokenResponse};
use crate::platform::callback_server::CallbackServer;
use crate::platform::token_storage::WindowsCredentialManagerStorage;
use anyhow::{anyhow, Context, Result};
use reqwest;
use std::collections::HashMap;
use url::Url;
use uuid::Uuid;

/// OAuth login flow with PKCE
pub struct OAuthLoginFlow {
    token_storage: WindowsCredentialManagerStorage,
}

impl OAuthLoginFlow {
    pub fn new(token_storage: WindowsCredentialManagerStorage) -> Self {
        Self { token_storage }
    }

    /// Perform OAuth login flow
    pub async fn login(
        &self,
        client_id: String,
        client_secret: String,
        host: Url,
        loopback_port: u16,
        scope: Option<String>,
        timeout_secs: u64,
    ) -> Result<OAuthTokens> {
        // Normalize host URL
        let normalized_host = Self::normalize_host(host)?;
        let auth_base = normalized_host
            .to_string()
            .trim_end_matches('/')
            .to_string();

        let auth_endpoint = format!("{}/login/oauth/authorize", auth_base);
        let token_endpoint = format!("{}/login/oauth/access_token", auth_base);

        // Generate PKCE
        let pkce = PKCE::generate();
        let state = Uuid::new_v4().to_string();

        // Start callback server
        let mut server = CallbackServer::new(loopback_port);
        let redirect_uri = server.start()?;

        // Build authorization URL
        let mut auth_url = Url::parse(&auth_endpoint)?;
        auth_url
            .query_pairs_mut()
            .append_pair("client_id", &client_id)
            .append_pair("redirect_uri", &redirect_uri)
            .append_pair("state", &state)
            .append_pair(
                "scope",
                &scope.unwrap_or_else(|| "repo read:org".to_string()),
            )
            .append_pair("code_challenge", &pkce.challenge)
            .append_pair("code_challenge_method", "S256");

        // Always release the loopback port before exchanging the OAuth code.
        let callback_result = (|| {
            Self::open_browser(&auth_url)?;
            server.wait_for_callback(timeout_secs)
        })();
        server.stop();
        let (code, returned_state) = callback_result?;

        // Verify state matches
        if returned_state != state {
            return Err(anyhow!("OAuth state mismatch - possible CSRF attack"));
        }

        // Exchange code for tokens
        let tokens = self
            .exchange_code_for_tokens(
                &token_endpoint,
                &client_id,
                &client_secret,
                &code,
                &redirect_uri,
                &pkce.verifier,
            )
            .await?;

        // Save tokens
        self.token_storage.save_tokens(&tokens)?;

        // Save client credentials
        let credentials = OAuthClientCredentials {
            client_id,
            client_secret,
        };
        self.token_storage.save_client_credentials(&credentials)?;

        Ok(tokens)
    }

    /// Exchange authorization code for access tokens
    async fn exchange_code_for_tokens(
        &self,
        token_endpoint: &str,
        client_id: &str,
        client_secret: &str,
        code: &str,
        redirect_uri: &str,
        code_verifier: &str,
    ) -> Result<OAuthTokens> {
        let client = reqwest::Client::new();

        let mut params = HashMap::new();
        params.insert("client_id", client_id);
        params.insert("client_secret", client_secret);
        params.insert("code", code);
        params.insert("redirect_uri", redirect_uri);
        params.insert("grant_type", "authorization_code");
        params.insert("code_verifier", code_verifier);

        let response = client
            .post(token_endpoint)
            .header("Accept", "application/json")
            .form(&params)
            .send()
            .await
            .context("Failed to send token request")?;

        if !response.status().is_success() {
            return Err(anyhow!(
                "Token exchange failed with status {}",
                response.status()
            ));
        }

        let token_response: TokenResponse = response
            .json()
            .await
            .context("Failed to parse token response")?;

        let expires_at = token_response
            .expires_in
            .map(|seconds| chrono::Utc::now() + chrono::Duration::seconds(seconds as i64));

        Ok(OAuthTokens {
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token.unwrap_or_default(),
            expires_at,
        })
    }

    /// Normalize host URL
    fn normalize_host(mut host: Url) -> Result<Url> {
        if host.scheme() != "https" {
            return Err(anyhow!("GitHub OAuth requires an HTTPS host"));
        }

        if host.host_str() != Some("github.com") || host.port().is_some() {
            return Err(anyhow!("The Windows preview supports GitHub.com only"));
        }

        // Clear path, query, fragment
        host.set_path("");
        host.set_query(None);
        host.set_fragment(None);

        Ok(host)
    }

    /// Open URL in default browser
    fn open_browser(url: &Url) -> Result<()> {
        #[cfg(target_os = "windows")]
        {
            std::process::Command::new("cmd")
                .args(["/C", "start", url.as_str()])
                .spawn()
                .context("Failed to open browser")?;
        }

        #[cfg(not(target_os = "windows"))]
        {
            // Fallback for development on other platforms
            println!("Open this URL in your browser: {}", url);
        }

        Ok(())
    }

    /// Load saved tokens
    pub fn load_tokens(&self) -> Result<Option<OAuthTokens>> {
        self.token_storage.load_tokens()
    }

    /// Load saved client credentials
    pub fn load_client_credentials(&self) -> Result<Option<OAuthClientCredentials>> {
        self.token_storage.load_client_credentials()
    }

    /// Clear all stored tokens and credentials
    pub fn logout(&self) -> Result<()> {
        self.token_storage.clear()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_host_rejects_non_https() {
        let host = Url::parse("http://github.com").unwrap();
        assert!(OAuthLoginFlow::normalize_host(host).is_err());
    }

    #[test]
    fn test_normalize_host_rejects_non_github_hosts() {
        let host = Url::parse("https://example.com").unwrap();
        assert!(OAuthLoginFlow::normalize_host(host).is_err());
    }

    #[test]
    fn test_normalize_host_accepts_github_com() {
        let host = Url::parse("https://github.com/some/path?query=1#fragment").unwrap();
        let normalized = OAuthLoginFlow::normalize_host(host).unwrap();
        assert_eq!(normalized.as_str(), "https://github.com/");
    }
}

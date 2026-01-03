use anyhow::{anyhow, Context, Result};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tiny_http::{Response, Server};
use url::Url;

/// OAuth callback server using tiny_http
pub struct CallbackServer {
    port: u16,
    server_handle: Option<thread::JoinHandle<()>>,
    result: Arc<Mutex<Option<(String, String)>>>,
}

impl CallbackServer {
    pub fn new(port: u16) -> Self {
        Self {
            port,
            server_handle: None,
            result: Arc::new(Mutex::new(None)),
        }
    }

    /// Start the HTTP server and return the callback URL
    pub fn start(&mut self) -> Result<String> {
        let addr = format!("127.0.0.1:{}", self.port);
        let server = Server::http(&addr)
            .with_context(|| format!("Failed to start HTTP server on {}", addr))?;

        let callback_url = format!("http://127.0.0.1:{}/callback", self.port);
        let result = self.result.clone();

        // Spawn server thread
        let handle = thread::spawn(move || {
            if let Some(request) = server.incoming_requests().next() {
                // Parse the request URL
                if let Some(parsed) = Self::parse_callback(request.url()) {
                    let mut result_lock = result.lock().unwrap();
                    *result_lock = Some(parsed);

                    // Send success response
                    let response = Response::from_string(
                        "Authentication successful! You can close this window."
                    )
                    .with_status_code(200);
                    let _ = request.respond(response);
                }
            }
        });

        self.server_handle = Some(handle);
        Ok(callback_url)
    }

    /// Wait for the OAuth callback with timeout
    pub fn wait_for_callback(&self, timeout_secs: u64) -> Result<(String, String)> {
        let start = std::time::Instant::now();
        let timeout = Duration::from_secs(timeout_secs);

        loop {
            // Check if we have a result
            if let Ok(result_lock) = self.result.lock() {
                if let Some((code, state)) = result_lock.as_ref() {
                    return Ok((code.clone(), state.clone()));
                }
            }

            // Check timeout
            if start.elapsed() > timeout {
                return Err(anyhow!("OAuth callback timeout after {} seconds", timeout_secs));
            }

            // Sleep briefly before checking again
            thread::sleep(Duration::from_millis(100));
        }
    }

    /// Stop the server
    pub fn stop(&mut self) {
        if let Some(handle) = self.server_handle.take() {
            // The server will stop after receiving one request
            // We just need to make sure the thread is joined
            let _ = handle.join();
        }
    }

    /// Parse callback URL to extract code and state
    fn parse_callback(url_str: &str) -> Option<(String, String)> {
        // Parse the URL
        let full_url = format!("http://localhost{}", url_str);
        let url = Url::parse(&full_url).ok()?;

        // Extract query parameters
        let mut code = None;
        let mut state = None;

        for (key, value) in url.query_pairs() {
            match key.as_ref() {
                "code" => code = Some(value.to_string()),
                "state" => state = Some(value.to_string()),
                _ => {}
            }
        }

        match (code, state) {
            (Some(c), Some(s)) => Some((c, s)),
            _ => None,
        }
    }
}

impl Drop for CallbackServer {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_callback() {
        let result = CallbackServer::parse_callback(
            "/callback?code=test_code&state=test_state"
        );
        assert_eq!(
            result,
            Some(("test_code".to_string(), "test_state".to_string()))
        );

        let result = CallbackServer::parse_callback("/callback?code=test");
        assert_eq!(result, None);
    }
}

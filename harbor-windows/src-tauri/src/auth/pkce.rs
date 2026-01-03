use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::Rng;
use sha2::{Digest, Sha256};

/// PKCE (Proof Key for Code Exchange) implementation
/// RFC 7636: https://tools.ietf.org/html/rfc7636
#[derive(Debug, Clone)]
pub struct PKCE {
    pub verifier: String,
    pub challenge: String,
}

impl PKCE {
    /// Generate a new PKCE code verifier and challenge
    pub fn generate() -> Self {
        // Generate 32 random bytes (256 bits)
        let mut rng = rand::thread_rng();
        let random_bytes: [u8; 32] = rng.gen();

        // Base64url encode the random bytes for the verifier
        let verifier = URL_SAFE_NO_PAD.encode(random_bytes);

        // SHA256 hash the verifier
        let mut hasher = Sha256::new();
        hasher.update(verifier.as_bytes());
        let hash = hasher.finalize();

        // Base64url encode the hash for the challenge
        let challenge = URL_SAFE_NO_PAD.encode(hash);

        Self {
            verifier,
            challenge,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pkce_generation() {
        let pkce = PKCE::generate();

        // Verifier should be 43 characters (32 bytes base64url encoded)
        assert_eq!(pkce.verifier.len(), 43);

        // Challenge should be 43 characters (32 bytes hash base64url encoded)
        assert_eq!(pkce.challenge.len(), 43);

        // Verifier and challenge should be different
        assert_ne!(pkce.verifier, pkce.challenge);

        // Should not contain padding
        assert!(!pkce.verifier.contains('='));
        assert!(!pkce.challenge.contains('='));
    }

    #[test]
    fn test_pkce_uniqueness() {
        let pkce1 = PKCE::generate();
        let pkce2 = PKCE::generate();

        // Each generation should produce unique values
        assert_ne!(pkce1.verifier, pkce2.verifier);
        assert_ne!(pkce1.challenge, pkce2.challenge);
    }

    #[test]
    fn test_pkce_challenge_matches_verifier() {
        let pkce = PKCE::generate();

        // Manually verify the challenge matches the verifier
        let mut hasher = Sha256::new();
        hasher.update(pkce.verifier.as_bytes());
        let hash = hasher.finalize();
        let expected_challenge = URL_SAFE_NO_PAD.encode(hash);

        assert_eq!(pkce.challenge, expected_challenge);
    }
}

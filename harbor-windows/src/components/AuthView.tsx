import { useState, useEffect } from 'react';
import { startOAuthLogin, loadClientCredentials } from '../services/auth';

interface AuthViewProps {
  onLoginSuccess: () => void;
}

export default function AuthView({ onLoginSuccess }: AuthViewProps) {
  const [clientId, setClientId] = useState('');
  const [clientSecret, setClientSecret] = useState('');
  const [host, setHost] = useState('https://github.com');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    // Try to load saved credentials
    loadClientCredentials()
      .then((credentials) => {
        if (credentials) {
          setClientId(credentials.client_id);
          setClientSecret(credentials.client_secret);
        }
      })
      .catch(console.error);
  }, []);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);

    try {
      const result = await startOAuthLogin(clientId, clientSecret, host);

      if (result.success) {
        onLoginSuccess();
      } else {
        setError(result.error || 'Login failed');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An unexpected error occurred');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="content">
      <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
        <h1 style={{ marginBottom: '0.5rem' }}>RepoBar</h1>
        <p style={{ color: 'var(--text-secondary)' }}>
          GitHub Repository Manager for Windows
        </p>
      </div>

      <form onSubmit={handleLogin}>
        {error && <div className="error">{error}</div>}

        <div className="form-group">
          <label htmlFor="host">GitHub Host</label>
          <input
            id="host"
            type="text"
            value={host}
            onChange={(e) => setHost(e.target.value)}
            placeholder="https://github.com"
            disabled={isLoading}
          />
        </div>

        <div className="form-group">
          <label htmlFor="clientId">OAuth Client ID</label>
          <input
            id="clientId"
            type="text"
            value={clientId}
            onChange={(e) => setClientId(e.target.value)}
            placeholder="Enter your GitHub OAuth App Client ID"
            required
            disabled={isLoading}
          />
        </div>

        <div className="form-group">
          <label htmlFor="clientSecret">OAuth Client Secret</label>
          <input
            id="clientSecret"
            type="password"
            value={clientSecret}
            onChange={(e) => setClientSecret(e.target.value)}
            placeholder="Enter your GitHub OAuth App Client Secret"
            required
            disabled={isLoading}
          />
        </div>

        <button type="submit" disabled={isLoading} style={{ width: '100%' }}>
          {isLoading ? 'Authenticating...' : 'Sign in with GitHub'}
        </button>

        <div
          style={{
            marginTop: '1.5rem',
            padding: '1rem',
            backgroundColor: 'var(--bg-secondary)',
            borderRadius: '4px',
            fontSize: '0.85rem',
            color: 'var(--text-secondary)',
          }}
        >
          <p style={{ marginBottom: '0.5rem' }}>
            <strong>Need OAuth credentials?</strong>
          </p>
          <p>
            Create a GitHub OAuth App at{' '}
            <a
              href="https://github.com/settings/developers"
              target="_blank"
              rel="noopener noreferrer"
              style={{ color: 'var(--accent)' }}
            >
              GitHub Developer Settings
            </a>
          </p>
          <p style={{ marginTop: '0.5rem', fontSize: '0.8rem' }}>
            Callback URL: <code>http://127.0.0.1:53682/callback</code>
          </p>
        </div>
      </form>
    </div>
  );
}

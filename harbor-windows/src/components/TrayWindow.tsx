import { useState, useEffect } from 'react';
import { listen } from '@tauri-apps/api/event';
import { logout } from '../services/auth';

interface TrayWindowProps {
  onLogout: () => void;
  onShowSettings: () => void;
}

// Placeholder repository data structure
interface Repository {
  id: number;
  name: string;
  full_name: string;
  description?: string;
  html_url: string;
}

export default function TrayWindow({ onLogout, onShowSettings }: TrayWindowProps) {
  const [repositories, setRepositories] = useState<Repository[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    // Listen for refresh events from tray
    const unlistenRefresh = listen('refresh', () => {
      handleRefresh();
    });

    // Initial load
    handleRefresh();

    return () => {
      unlistenRefresh.then((fn) => fn());
    };
  }, []);

  const handleRefresh = async () => {
    setIsLoading(true);
    try {
      // TODO: Implement GitHub API calls to fetch repositories
      // This is a placeholder - in a full implementation, you would:
      // 1. Get the OAuth token
      // 2. Call GitHub API to fetch user repositories
      // 3. Update the repositories state
      console.log('Refreshing repositories...');

      // Placeholder delay
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Placeholder data
      setRepositories([]);
    } catch (error) {
      console.error('Failed to refresh repositories:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleLogout = async () => {
    try {
      await logout();
      onLogout();
    } catch (error) {
      console.error('Logout failed:', error);
    }
  };

  const openRepository = (url: string) => {
    // Open in browser using Tauri shell plugin
    import('@tauri-apps/plugin-shell').then(({ open }) => {
      open(url);
    });
  };

  return (
    <div>
      <div className="header">
        <h1>Repositories</h1>
        <div style={{ display: 'flex', gap: '0.5rem' }}>
          <button
            className="secondary"
            onClick={handleRefresh}
            disabled={isLoading}
            style={{ padding: '0.5rem 1rem' }}
          >
            {isLoading ? '...' : '↻'}
          </button>
          <button
            className="secondary"
            onClick={onShowSettings}
            style={{ padding: '0.5rem 1rem' }}
          >
            ⚙
          </button>
        </div>
      </div>

      <div className="content">
        {isLoading && repositories.length === 0 ? (
          <div className="empty-state">
            <div className="spinner"></div>
            <p>Loading repositories...</p>
          </div>
        ) : repositories.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">📦</div>
            <p>No repositories found</p>
            <button onClick={handleRefresh}>Refresh</button>
          </div>
        ) : (
          <ul className="repo-list">
            {repositories.map((repo) => (
              <li
                key={repo.id}
                className="repo-item"
                onClick={() => openRepository(repo.html_url)}
              >
                <div className="repo-name">{repo.full_name}</div>
                {repo.description && (
                  <div className="repo-description">{repo.description}</div>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="footer">
        <button className="danger" onClick={handleLogout}>
          Sign Out
        </button>
      </div>
    </div>
  );
}

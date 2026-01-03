import { useState, useEffect } from 'react';
import { loadSettings, saveSettings, UserSettings } from '../services/settings';
import { locateGit, GitInfo } from '../services/git';

interface SettingsViewProps {
  onClose: () => void;
}

export default function SettingsView({ onClose }: SettingsViewProps) {
  const [settings, setSettings] = useState<UserSettings | null>(null);
  const [gitInfo, setGitInfo] = useState<GitInfo | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(
    null
  );

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [loadedSettings, git] = await Promise.all([loadSettings(), locateGit()]);
      setSettings(loadedSettings);
      setGitInfo(git);
    } catch (error) {
      console.error('Failed to load settings:', error);
      setMessage({ type: 'error', text: 'Failed to load settings' });
    } finally {
      setIsLoading(false);
    }
  };

  const handleSave = async () => {
    if (!settings) return;

    setIsSaving(true);
    setMessage(null);

    try {
      await saveSettings(settings);
      setMessage({ type: 'success', text: 'Settings saved successfully' });
    } catch (error) {
      console.error('Failed to save settings:', error);
      setMessage({ type: 'error', text: 'Failed to save settings' });
    } finally {
      setIsSaving(false);
    }
  };

  const updateSettings = (updates: Partial<UserSettings>) => {
    if (!settings) return;
    setSettings({ ...settings, ...updates });
  };

  if (isLoading || !settings) {
    return (
      <div className="content" style={{ textAlign: 'center', paddingTop: '2rem' }}>
        <div className="spinner"></div>
        <p>Loading settings...</p>
      </div>
    );
  }

  return (
    <div>
      <div className="header">
        <h1>Settings</h1>
        <button className="secondary" onClick={onClose} style={{ padding: '0.5rem 1rem' }}>
          ✕
        </button>
      </div>

      <div className="content">
        {message && (
          <div className={message.type === 'success' ? 'success' : 'error'}>
            {message.text}
          </div>
        )}

        {/* Appearance */}
        <section style={{ marginBottom: '2rem' }}>
          <h2 style={{ fontSize: '1.1rem', marginBottom: '1rem' }}>Appearance</h2>

          <div className="form-group">
            <label>
              <input
                type="checkbox"
                checked={settings.appearance.show_icons}
                onChange={(e) =>
                  updateSettings({
                    appearance: {
                      ...settings.appearance,
                      show_icons: e.target.checked,
                    },
                  })
                }
                style={{ width: 'auto', marginRight: '0.5rem' }}
              />
              Show repository icons
            </label>
          </div>
        </section>

        {/* Repositories */}
        <section style={{ marginBottom: '2rem' }}>
          <h2 style={{ fontSize: '1.1rem', marginBottom: '1rem' }}>Repositories</h2>

          <div className="form-group">
            <label htmlFor="maxRepos">Maximum repositories to show</label>
            <input
              id="maxRepos"
              type="number"
              min="10"
              max="500"
              value={settings.repositories.max_repos}
              onChange={(e) =>
                updateSettings({
                  repositories: {
                    ...settings.repositories,
                    max_repos: parseInt(e.target.value),
                  },
                })
              }
            />
          </div>

          <div className="form-group">
            <label>
              <input
                type="checkbox"
                checked={settings.repositories.show_private}
                onChange={(e) =>
                  updateSettings({
                    repositories: {
                      ...settings.repositories,
                      show_private: e.target.checked,
                    },
                  })
                }
                style={{ width: 'auto', marginRight: '0.5rem' }}
              />
              Show private repositories
            </label>
          </div>

          <div className="form-group">
            <label>
              <input
                type="checkbox"
                checked={settings.repositories.show_public}
                onChange={(e) =>
                  updateSettings({
                    repositories: {
                      ...settings.repositories,
                      show_public: e.target.checked,
                    },
                  })
                }
                style={{ width: 'auto', marginRight: '0.5rem' }}
              />
              Show public repositories
            </label>
          </div>
        </section>

        {/* Refresh */}
        <section style={{ marginBottom: '2rem' }}>
          <h2 style={{ fontSize: '1.1rem', marginBottom: '1rem' }}>Auto-Refresh</h2>

          <div className="form-group">
            <label>
              <input
                type="checkbox"
                checked={settings.refresh.auto_refresh}
                onChange={(e) =>
                  updateSettings({
                    refresh: {
                      ...settings.refresh,
                      auto_refresh: e.target.checked,
                    },
                  })
                }
                style={{ width: 'auto', marginRight: '0.5rem' }}
              />
              Enable auto-refresh
            </label>
          </div>

          {settings.refresh.auto_refresh && (
            <div className="form-group">
              <label htmlFor="refreshInterval">Refresh interval (minutes)</label>
              <input
                id="refreshInterval"
                type="number"
                min="5"
                max="120"
                value={settings.refresh.refresh_interval_minutes}
                onChange={(e) =>
                  updateSettings({
                    refresh: {
                      ...settings.refresh,
                      refresh_interval_minutes: parseInt(e.target.value),
                    },
                  })
                }
              />
            </div>
          )}
        </section>

        {/* Advanced */}
        <section style={{ marginBottom: '2rem' }}>
          <h2 style={{ fontSize: '1.1rem', marginBottom: '1rem' }}>Advanced</h2>

          <div className="form-group">
            <label htmlFor="gitPath">Git executable path</label>
            <input
              id="gitPath"
              type="text"
              value={settings.advanced.git_path || ''}
              onChange={(e) =>
                updateSettings({
                  advanced: {
                    ...settings.advanced,
                    git_path: e.target.value || undefined,
                  },
                })
              }
              placeholder={gitInfo?.path || 'Auto-detect'}
            />
            {gitInfo?.version && (
              <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginTop: '0.5rem' }}>
                Detected: {gitInfo.version}
              </p>
            )}
          </div>

          <div className="form-group">
            <label>
              <input
                type="checkbox"
                checked={settings.advanced.launch_at_login}
                onChange={(e) =>
                  updateSettings({
                    advanced: {
                      ...settings.advanced,
                      launch_at_login: e.target.checked,
                    },
                  })
                }
                style={{ width: 'auto', marginRight: '0.5rem' }}
              />
              Launch at login
            </label>
          </div>
        </section>
      </div>

      <div className="footer">
        <button className="secondary" onClick={onClose}>
          Cancel
        </button>
        <button onClick={handleSave} disabled={isSaving}>
          {isSaving ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  );
}

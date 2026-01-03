import { useEffect, useState } from 'react';
import { listen } from '@tauri-apps/api/event';
import AuthView from './components/AuthView';
import TrayWindow from './components/TrayWindow';
import SettingsView from './components/SettingsView';
import { isAuthenticated } from './services/auth';

type View = 'auth' | 'main' | 'settings';

function App() {
  const [currentView, setCurrentView] = useState<View>('auth');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    // Check authentication status on mount
    const checkAuth = async () => {
      try {
        const authenticated = await isAuthenticated();
        setCurrentView(authenticated ? 'main' : 'auth');
      } catch (error) {
        console.error('Failed to check authentication:', error);
        setCurrentView('auth');
      } finally {
        setIsLoading(false);
      }
    };

    checkAuth();

    // Listen for navigation events from tray
    const unlistenNavigate = listen<string>('navigate', (event) => {
      if (event.payload === 'settings') {
        setCurrentView('settings');
      }
    });

    return () => {
      unlistenNavigate.then((fn) => fn());
    };
  }, []);

  const handleLoginSuccess = () => {
    setCurrentView('main');
  };

  const handleLogout = () => {
    setCurrentView('auth');
  };

  const handleShowSettings = () => {
    setCurrentView('settings');
  };

  const handleCloseSettings = () => {
    setCurrentView('main');
  };

  if (isLoading) {
    return (
      <div className="app loading">
        <div className="spinner"></div>
        <p>Loading...</p>
      </div>
    );
  }

  return (
    <div className="app">
      {currentView === 'auth' && <AuthView onLoginSuccess={handleLoginSuccess} />}
      {currentView === 'main' && (
        <TrayWindow onLogout={handleLogout} onShowSettings={handleShowSettings} />
      )}
      {currentView === 'settings' && <SettingsView onClose={handleCloseSettings} />}
    </div>
  );
}

export default App;

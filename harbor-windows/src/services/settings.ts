import { invoke } from '@tauri-apps/api/core';

export interface UserSettings {
  appearance: AppearanceSettings;
  repositories: RepositorySettings;
  refresh: RefreshSettings;
  advanced: AdvancedSettings;
}

export interface AppearanceSettings {
  accent_tone: string;
  show_icons: boolean;
}

export interface RepositorySettings {
  max_repos: number;
  show_private: boolean;
  show_public: boolean;
}

export interface RefreshSettings {
  auto_refresh: boolean;
  refresh_interval_minutes: number;
}

export interface AdvancedSettings {
  git_path?: string;
  launch_at_login: boolean;
}

export async function loadSettings(): Promise<UserSettings> {
  return await invoke<UserSettings>('load_settings');
}

export async function saveSettings(settings: UserSettings): Promise<boolean> {
  return await invoke<boolean>('save_settings', { settings });
}

export async function resetSettings(): Promise<UserSettings> {
  return await invoke<UserSettings>('reset_settings');
}

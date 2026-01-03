import { invoke } from '@tauri-apps/api/core';

export interface GitInfo {
  path?: string;
  version?: string;
  error?: string;
}

export async function locateGit(): Promise<GitInfo> {
  return await invoke<GitInfo>('locate_git');
}

export async function getExecutableVersion(path: string): Promise<string> {
  return await invoke<string>('get_executable_version', { path });
}

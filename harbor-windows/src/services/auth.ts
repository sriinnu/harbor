import { invoke } from '@tauri-apps/api/core';

export interface AuthResult {
  success: boolean;
  error?: string;
}

export async function startOAuthLogin(
  clientId: string,
  clientSecret: string
): Promise<AuthResult> {
  return await invoke<AuthResult>('start_oauth_login', {
    clientId,
    clientSecret,
    host: 'https://github.com',
  });
}

export async function logout(): Promise<boolean> {
  return await invoke<boolean>('logout');
}

export async function isAuthenticated(): Promise<boolean> {
  return await invoke<boolean>('is_authenticated');
}

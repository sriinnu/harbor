import { invoke } from '@tauri-apps/api/core';

export interface OAuthTokens {
  access_token: string;
  refresh_token: string;
  expires_at?: string;
}

export interface OAuthClientCredentials {
  client_id: string;
  client_secret: string;
}

export interface AuthResult {
  success: boolean;
  error?: string;
  tokens?: OAuthTokens;
}

export async function startOAuthLogin(
  clientId: string,
  clientSecret: string,
  host: string = 'https://github.com'
): Promise<AuthResult> {
  return await invoke<AuthResult>('start_oauth_login', {
    clientId,
    clientSecret,
    host,
  });
}

export async function loadOAuthTokens(): Promise<OAuthTokens | null> {
  return await invoke<OAuthTokens | null>('load_oauth_tokens');
}

export async function loadClientCredentials(): Promise<OAuthClientCredentials | null> {
  return await invoke<OAuthClientCredentials | null>('load_client_credentials');
}

export async function logout(): Promise<boolean> {
  return await invoke<boolean>('logout');
}

export async function isAuthenticated(): Promise<boolean> {
  return await invoke<boolean>('is_authenticated');
}

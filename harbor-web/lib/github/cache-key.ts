import { createHash } from 'crypto'

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex')
}

/**
 * Keeps OAuth tokens out of Redis keys, logs, metrics, and backup indexes.
 * Cache entries remain scoped to the token that authorized the response.
 */
export function githubCacheTag(accessToken: string): string {
  return `github:${sha256(accessToken)}`
}

export function githubCacheKey(
  accessToken: string,
  namespace: string,
  payload: string
): string {
  return `${githubCacheTag(accessToken)}:${namespace}:${sha256(payload)}`
}

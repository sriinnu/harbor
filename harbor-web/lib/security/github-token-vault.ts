import { createCipheriv, createDecipheriv, randomBytes } from 'crypto'
import { prisma } from '@/lib/db/prisma'

const VERSION = 'v1'
const IV_BYTES = 12
const TAG_BYTES = 16

function key(): Buffer {
  const value = process.env.HARBOR_TOKEN_ENCRYPTION_KEY
  if (!value) {
    throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY is required for GitHub sign-in')
  }

  const decoded = Buffer.from(value, 'base64')
  if (decoded.length !== 32) {
    throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY must be a base64-encoded 32-byte key')
  }
  return decoded
}

function encode(value: Buffer): string {
  return value.toString('base64url')
}

function decode(value: string): Buffer {
  return Buffer.from(value, 'base64url')
}

export function isEncryptedGitHubToken(value: string): boolean {
  return value.startsWith(`${VERSION}.`)
}

export function encryptGitHubToken(token: string): string {
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv('aes-256-gcm', key(), iv)
  const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return [VERSION, encode(iv), encode(tag), encode(ciphertext)].join('.')
}

export function decryptGitHubToken(value: string): string {
  const [version, ivValue, tagValue, ciphertextValue, extra] = value.split('.')
  if (
    version !== VERSION ||
    !ivValue ||
    !tagValue ||
    !ciphertextValue ||
    extra ||
    decode(ivValue).length !== IV_BYTES ||
    decode(tagValue).length !== TAG_BYTES
  ) {
    throw new Error('Stored GitHub token has an invalid encryption format')
  }

  const decipher = createDecipheriv('aes-256-gcm', key(), decode(ivValue))
  decipher.setAuthTag(decode(tagValue))
  return Buffer.concat([
    decipher.update(decode(ciphertextValue)),
    decipher.final(),
  ]).toString('utf8')
}

/**
 * Persists only ciphertext in User.githubToken and removes raw provider-token
 * copies created by earlier versions of the Prisma adapter.
 */
export async function storeGitHubToken(
  userId: string,
  accessToken: string,
  expiresAt?: number | null
): Promise<void> {
  await prisma.$transaction([
    prisma.user.update({
      where: { id: userId },
      data: {
        githubToken: encryptGitHubToken(accessToken),
        githubTokenExp: expiresAt ? new Date(expiresAt * 1000) : null,
      },
    }),
    prisma.account.updateMany({
      where: { userId, provider: 'github' },
      data: {
        access_token: null,
        refresh_token: null,
        id_token: null,
      },
    }),
  ])
}

/**
 * Reads the token only on the server. A legacy plaintext value is encrypted in
 * place on first use and raw Account copies are cleared.
 */
export async function getGitHubToken(userId: string): Promise<string | null> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { githubToken: true, githubTokenExp: true },
  })
  if (!user?.githubToken) return null

  if (!isEncryptedGitHubToken(user.githubToken)) {
    const legacyToken = user.githubToken
    await storeGitHubToken(
      userId,
      legacyToken,
      user.githubTokenExp
        ? Math.floor(user.githubTokenExp.getTime() / 1000)
        : null
    )
    return legacyToken
  }

  return decryptGitHubToken(user.githubToken)
}

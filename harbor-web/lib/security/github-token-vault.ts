import { createCipheriv, createDecipheriv, randomBytes } from 'crypto'
import { prisma } from '@/lib/db/prisma'

const VERSION = 'v1'
const IV_BYTES = 12
const TAG_BYTES = 16
type TokenField = 'access_token' | 'refresh_token' | 'id_token' | 'session_state'

type AccountContext = {
  userId: string
  provider: string
  providerAccountId: string
}

type TokenBearingAccount = AccountContext & {
  access_token?: string | null
  refresh_token?: string | null
  id_token?: string | null
  session_state?: string | null
}

function key(): Buffer {
  const value = process.env.HARBOR_TOKEN_ENCRYPTION_KEY
  if (!value) throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY is required for GitHub sign-in')

  const decoded = Buffer.from(value, 'base64')
  if (decoded.length !== 32) {
    throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY must be a base64-encoded 32-byte key')
  }
  return decoded
}

function aad(context: AccountContext, field: TokenField): Buffer {
  return Buffer.from(
    ['harbor-oauth-token', context.userId, context.provider, context.providerAccountId, field].join(':'),
    'utf8'
  )
}

function encode(value: Buffer): string {
  return value.toString('base64url')
}

function decode(value: string): Buffer {
  return Buffer.from(value, 'base64url')
}

export function isEncryptedOAuthToken(value: string): boolean {
  return value.startsWith(`${VERSION}.`)
}

export function encryptOAuthToken(
  token: string,
  context: AccountContext,
  field: TokenField
): string {
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv('aes-256-gcm', key(), iv)
  cipher.setAAD(aad(context, field))
  const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()])
  return [VERSION, encode(iv), encode(cipher.getAuthTag()), encode(ciphertext)].join('.')
}

export function decryptOAuthToken(
  value: string,
  context: AccountContext,
  field: TokenField
): string {
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
    throw new Error('Stored OAuth token has an invalid encryption format')
  }

  const decipher = createDecipheriv('aes-256-gcm', key(), decode(ivValue))
  decipher.setAAD(aad(context, field))
  decipher.setAuthTag(decode(tagValue))
  return Buffer.concat([
    decipher.update(decode(ciphertextValue)),
    decipher.final(),
  ]).toString('utf8')
}

export function encryptAccountTokens<T extends TokenBearingAccount>(account: T): T {
  const context: AccountContext = {
    userId: account.userId,
    provider: account.provider,
    providerAccountId: account.providerAccountId,
  }
  const encrypt = (value: string | null | undefined, field: TokenField) => {
    if (!value) return value
    if (isEncryptedOAuthToken(value)) {
      decryptOAuthToken(value, context, field)
      return value
    }
    return encryptOAuthToken(value, context, field)
  }

  return {
    ...account,
    access_token: encrypt(account.access_token, 'access_token'),
    refresh_token: encrypt(account.refresh_token, 'refresh_token'),
    id_token: encrypt(account.id_token, 'id_token'),
    session_state: encrypt(account.session_state, 'session_state'),
  }
}

/**
 * Returns a plaintext token only inside server code. Legacy raw rows are
 * encrypted in place and duplicate User.githubToken values are cleared.
 */
export async function getGitHubToken(userId: string): Promise<string | null> {
  const account = await prisma.account.findFirst({
    where: { userId, provider: 'github' },
    select: {
      id: true,
      userId: true,
      provider: true,
      providerAccountId: true,
      access_token: true,
      refresh_token: true,
      id_token: true,
      session_state: true,
    },
  })
  if (!account?.access_token) return null

  const context: AccountContext = {
    userId: account.userId,
    provider: account.provider,
    providerAccountId: account.providerAccountId,
  }
  const rawAccessToken = isEncryptedOAuthToken(account.access_token)
    ? decryptOAuthToken(account.access_token, context, 'access_token')
    : account.access_token
  const encrypted = encryptAccountTokens(account)

  const needsMigration = [
    account.access_token,
    account.refresh_token,
    account.id_token,
    account.session_state,
  ].some((value) => value && !isEncryptedOAuthToken(value))

  if (needsMigration) {
    await prisma.$transaction([
      prisma.account.update({
        where: { id: account.id },
        data: {
          access_token: encrypted.access_token,
          refresh_token: encrypted.refresh_token,
          id_token: encrypted.id_token,
          session_state: encrypted.session_state,
        },
      }),
      prisma.user.update({
        where: { id: userId },
        data: { githubToken: null, githubTokenExp: null },
      }),
    ])
  }

  return rawAccessToken
}

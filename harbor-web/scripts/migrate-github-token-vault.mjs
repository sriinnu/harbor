#!/usr/bin/env node
import { PrismaClient } from '@prisma/client'
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto'

const prisma = new PrismaClient()
const apply = process.argv.includes('--apply')
const VERSION = 'v1'
const IV_BYTES = 12
const TAG_BYTES = 16
const tokenFields = ['access_token', 'refresh_token', 'id_token', 'session_state']

function encryptionKey() {
  const value = process.env.HARBOR_TOKEN_ENCRYPTION_KEY
  if (!value) throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY is required')

  const key = Buffer.from(value, 'base64')
  if (key.length !== 32) {
    throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY must decode to 32 bytes')
  }
  return key
}

function aad(account, field) {
  return Buffer.from(
    ['harbor-oauth-token', account.userId, account.provider, account.providerAccountId, field].join(':'),
    'utf8'
  )
}

function encrypt(value, account, field) {
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv)
  cipher.setAAD(aad(account, field))
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()])
  return [VERSION, iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.')
}

function validateEncrypted(value, account, field) {
  const [version, ivValue, tagValue, ciphertextValue, extra] = value.split('.')
  if (
    version !== VERSION ||
    !ivValue ||
    !tagValue ||
    !ciphertextValue ||
    extra ||
    Buffer.from(ivValue, 'base64url').length !== IV_BYTES ||
    Buffer.from(tagValue, 'base64url').length !== TAG_BYTES
  ) {
    throw new Error('Found an invalid encrypted OAuth token envelope; reconnect the affected account before retrying')
  }

  const decipher = createDecipheriv('aes-256-gcm', encryptionKey(), Buffer.from(ivValue, 'base64url'))
  decipher.setAAD(aad(account, field))
  decipher.setAuthTag(Buffer.from(tagValue, 'base64url'))
  decipher.update(Buffer.from(ciphertextValue, 'base64url'))
  decipher.final()
}

function encrypted(value) {
  return !value || value.startsWith(`${VERSION}.`)
}

async function main() {
  const accounts = await prisma.account.findMany({
    where: { provider: 'github' },
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

  let pending = 0
  let migrated = 0
  let validatedEncryptedAccounts = 0

  for (const account of accounts) {
    const hasRawToken = tokenFields.some((field) => account[field] && !encrypted(account[field]))
    const hasEncryptedToken = tokenFields.some((field) => account[field] && encrypted(account[field]))

    if (hasEncryptedToken) {
      for (const field of tokenFields) {
        const value = account[field]
        if (value && encrypted(value)) validateEncrypted(value, account, field)
      }
      validatedEncryptedAccounts += 1
    }

    if (!hasRawToken) continue
    pending += 1
    if (!apply) continue

    const data = Object.fromEntries(tokenFields.map((field) => {
      const value = account[field]
      return [field, encrypted(value) ? value : encrypt(value, account, field)]
    }))

    await prisma.$transaction([
      prisma.account.update({ where: { id: account.id }, data }),
      prisma.user.update({
        where: { id: account.userId },
        data: { githubToken: null, githubTokenExp: null },
      }),
    ])
    migrated += 1
  }

  const legacyUsers = await prisma.user.count({
    where: { githubToken: { not: null } },
  })

  console.log(JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    githubAccounts: accounts.length,
    validatedEncryptedAccounts,
    pendingAccountMigrations: pending,
    migratedAccounts: migrated,
    legacyUserTokenRows: legacyUsers,
  }))

  if (legacyUsers > 0) {
    console.error('Legacy User.githubToken rows remain; revoke/reconnect those users before dropping the legacy columns.')
    process.exitCode = 2
  }
}

main()
  .catch(() => {
    console.error('GitHub token vault migration failed. No token values were printed.')
    process.exitCode = 1
  })
  .finally(async () => prisma.$disconnect())

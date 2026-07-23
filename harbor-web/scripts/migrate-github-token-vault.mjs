#!/usr/bin/env node
import { PrismaClient } from '@prisma/client'
import { createCipheriv, randomBytes } from 'node:crypto'

const prisma = new PrismaClient()
const apply = process.argv.includes('--apply')
const VERSION = 'v1'
const IV_BYTES = 12

function encryptionKey() {
  const value = process.env.HARBOR_TOKEN_ENCRYPTION_KEY
  if (!value) throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY is required')

  const key = Buffer.from(value, 'base64')
  if (key.length !== 32) {
    throw new Error('HARBOR_TOKEN_ENCRYPTION_KEY must decode to 32 bytes')
  }
  return key
}

function encrypt(value, account, field) {
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv)
  cipher.setAAD(Buffer.from(
    ['harbor-oauth-token', account.userId, account.provider, account.providerAccountId, field].join(':'),
    'utf8'
  ))
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()])
  return [VERSION, iv.toString('base64url'), cipher.getAuthTag().toString('base64url'), ciphertext.toString('base64url')].join('.')
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
  let orphaned = 0

  for (const account of accounts) {
    if (!account.access_token) continue

    if (encrypted(account.access_token)) {
      if (apply) {
        await prisma.user.update({
          where: { id: account.userId },
          data: { githubToken: null, githubTokenExp: null },
        })
      }
      continue
    }

    pending += 1
    if (!apply) continue

    await prisma.$transaction([
      prisma.account.update({
        where: { id: account.id },
        data: {
          access_token: encrypt(account.access_token, account, 'access_token'),
          refresh_token: encrypted(account.refresh_token) ? account.refresh_token : encrypt(account.refresh_token, account, 'refresh_token'),
          id_token: encrypted(account.id_token) ? account.id_token : encrypt(account.id_token, account, 'id_token'),
          session_state: encrypted(account.session_state) ? account.session_state : encrypt(account.session_state, account, 'session_state'),
        },
      }),
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
  orphaned = legacyUsers

  console.log(JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    githubAccounts: accounts.length,
    pendingAccountMigrations: pending,
    migratedAccounts: migrated,
    legacyUserTokenRows: orphaned,
  }))

  if (orphaned > 0) {
    console.error('Some legacy User.githubToken rows have no usable GitHub Account record; revoke/reconnect those users before dropping the legacy columns.')
    process.exitCode = 2
  }
}

main()
  .catch((error) => {
    console.error('GitHub token vault migration failed:', error.message)
    process.exitCode = 1
  })
  .finally(async () => prisma.$disconnect())

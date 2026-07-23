import { NextAuthOptions } from 'next-auth'
import { PrismaAdapter } from '@auth/prisma-adapter'
import GithubProvider from 'next-auth/providers/github'
import { prisma } from '@/lib/db/prisma'
import type { Adapter } from 'next-auth/adapters'
import { storeGitHubToken } from '@/lib/security/github-token-vault'

const baseAdapter = PrismaAdapter(prisma) as Adapter
const baseLinkAccount = baseAdapter.linkAccount

if (!baseLinkAccount) {
  throw new Error('Prisma adapter must implement linkAccount')
}

const encryptedTokenAdapter: Adapter = {
  ...baseAdapter,
  async linkAccount(account) {
    if (account.provider === 'github' && account.access_token) {
      await storeGitHubToken(
        account.userId,
        account.access_token,
        account.expires_at ?? null
      )
    }

    const linkedAccount = await baseLinkAccount({
      ...account,
      access_token: undefined,
      refresh_token: undefined,
      id_token: undefined,
    })

    if (account.provider === 'github') {
      await prisma.user.update({
        where: { id: account.userId },
        data: { githubId: account.providerAccountId },
      })
      await prisma.userPreferences.upsert({
        where: { userId: account.userId },
        create: { userId: account.userId },
        update: {},
      })
    }

    return linkedAccount
  },
}

export const authOptions: NextAuthOptions = {
  adapter: encryptedTokenAdapter,
  providers: [
    GithubProvider({
      clientId: process.env.GITHUB_CLIENT_ID!,
      clientSecret: process.env.GITHUB_CLIENT_SECRET!,
      authorization: {
        params: {
          scope: 'read:user user:email repo read:org',
        },
      },
    }),
  ],
  callbacks: {
    async session({ session, user }) {
      if (session.user) {
        session.user.id = user.id

        // Add GitHub data to session
        const dbUser = await prisma.user.findUnique({
          where: { id: user.id },
          select: {
            githubUsername: true,
            githubId: true,
          },
        })

        if (dbUser) {
          session.user.githubUsername = dbUser.githubUsername
          session.user.githubId = dbUser.githubId
        }
      }
      return session
    },
  },
  session: {
    strategy: 'database',
    maxAge: 30 * 24 * 60 * 60, // 30 days
  },
  pages: {
    signIn: '/auth/signin',
    error: '/auth/error',
  },
  debug: process.env.NODE_ENV === 'development',
}

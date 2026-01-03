import { NextAuthOptions } from 'next-auth'
import { PrismaAdapter } from '@auth/prisma-adapter'
import GithubProvider from 'next-auth/providers/github'
import { prisma } from '@/lib/db/prisma'
import type { Adapter } from 'next-auth/adapters'

export const authOptions: NextAuthOptions = {
  adapter: PrismaAdapter(prisma) as Adapter,
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
    async signIn({ user, account, profile }) {
      if (account?.provider === 'github' && profile) {
        // Update user with GitHub information
        await prisma.user.update({
          where: { id: user.id },
          data: {
            githubId: String(profile.id),
            githubUsername: (profile as any).login,
            githubToken: account.access_token,
            githubTokenExp: account.expires_at
              ? new Date(account.expires_at * 1000)
              : null,
          },
        })

        // Create default preferences
        await prisma.userPreferences.upsert({
          where: { userId: user.id },
          create: { userId: user.id },
          update: {},
        })
      }
      return true
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

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth/options'
import { getGitHubToken } from '@/lib/security/github-token-vault'
import { createGitHubClient } from '@/lib/github/client'
import { z } from 'zod'

const repositoryQuerySchema = z.object({
  type: z.enum(['all', 'owner', 'public', 'private', 'member']).default('all'),
  sort: z.enum(['created', 'updated', 'pushed', 'full_name']).default('updated'),
  direction: z.enum(['asc', 'desc']).default('desc'),
  per_page: z.coerce.number().int().min(1).max(100).default(30),
  page: z.coerce.number().int().min(1).max(1_000).default(1),
  include_archived: z.enum(['true', 'false']).optional(),
})

export const runtime = 'nodejs'

export async function GET(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions)

    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const accessToken = await getGitHubToken(session.user.id)

    if (!accessToken) {
      return NextResponse.json(
        { error: 'GitHub token not found. Please reconnect your GitHub account.' },
        { status: 401 }
      )
    }

    const query = repositoryQuerySchema.safeParse(
      Object.fromEntries(request.nextUrl.searchParams.entries())
    )
    if (!query.success) {
      return NextResponse.json(
        { error: 'Invalid repository query', details: query.error.flatten() },
        { status: 400 }
      )
    }

    const { type, sort, direction, per_page: perPage, page, include_archived } = query.data
    const includeArchived = include_archived === 'true'

    // Create GitHub client
    const github = createGitHubClient(accessToken)

    // Fetch repositories
    let repos = await github.getRepositories({
      type,
      sort,
      direction,
      per_page: perPage,
      page,
    })

    // Filter out archived repos if needed
    if (!includeArchived) {
      repos = repos.filter((repo) => !repo.archived)
    }

    return NextResponse.json({
      repositories: repos,
      pagination: {
        page,
        per_page: perPage,
        total: repos.length,
      },
    })
  } catch (error) {
    console.error('Error fetching repositories:', error)
    return NextResponse.json(
      { error: 'Failed to fetch repositories' },
      { status: 500 }
    )
  }
}

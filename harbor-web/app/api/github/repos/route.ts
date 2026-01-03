import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth/options'
import { prisma } from '@/lib/db/prisma'
import { createGitHubClient } from '@/lib/github/client'

export async function GET(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions)

    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    // Get user's GitHub token
    const user = await prisma.user.findUnique({
      where: { id: session.user.id },
      select: { githubToken: true },
    })

    if (!user?.githubToken) {
      return NextResponse.json(
        { error: 'GitHub token not found. Please reconnect your GitHub account.' },
        { status: 401 }
      )
    }

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams
    const type = (searchParams.get('type') as any) || 'all'
    const sort = (searchParams.get('sort') as any) || 'updated'
    const direction = (searchParams.get('direction') as any) || 'desc'
    const perPage = parseInt(searchParams.get('per_page') || '30', 10)
    const page = parseInt(searchParams.get('page') || '1', 10)
    const includeArchived = searchParams.get('include_archived') === 'true'

    // Create GitHub client
    const github = createGitHubClient(user.githubToken)

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

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth/options'
import { prisma } from '@/lib/db/prisma'
import { pinRepoSchema } from '@/lib/validations/repo'

export async function GET(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions)

    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const pinnedRepos = await prisma.pinnedRepository.findMany({
      where: { userId: session.user.id },
      orderBy: { order: 'asc' },
    })

    return NextResponse.json({ pinnedRepos })
  } catch (error) {
    console.error('Error fetching pinned repositories:', error)
    return NextResponse.json(
      { error: 'Failed to fetch pinned repositories' },
      { status: 500 }
    )
  }
}

export async function POST(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions)

    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const body = await request.json()
    const validatedData = pinRepoSchema.parse(body)

    // Check if already pinned
    const existing = await prisma.pinnedRepository.findUnique({
      where: {
        userId_githubId: {
          userId: session.user.id,
          githubId: validatedData.githubId,
        },
      },
    })

    if (existing) {
      return NextResponse.json(
        { error: 'Repository already pinned' },
        { status: 400 }
      )
    }

    // Get the next order number
    const maxOrder = await prisma.pinnedRepository.findFirst({
      where: { userId: session.user.id },
      orderBy: { order: 'desc' },
      select: { order: true },
    })

    const pinnedRepo = await prisma.pinnedRepository.create({
      data: {
        userId: session.user.id,
        githubId: validatedData.githubId,
        name: validatedData.name,
        owner: validatedData.owner,
        fullName: validatedData.fullName,
        description: validatedData.description,
        url: validatedData.url,
        stars: validatedData.stars,
        language: validatedData.language,
        isPrivate: validatedData.isPrivate,
        notes: validatedData.notes,
        tags: validatedData.tags,
        order: (maxOrder?.order || 0) + 1,
      },
    })

    return NextResponse.json({ pinnedRepo }, { status: 201 })
  } catch (error) {
    console.error('Error pinning repository:', error)
    return NextResponse.json(
      { error: 'Failed to pin repository' },
      { status: 500 }
    )
  }
}

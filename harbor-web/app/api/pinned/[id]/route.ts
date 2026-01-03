import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth/options'
import { prisma } from '@/lib/db/prisma'
import { updatePinnedRepoSchema } from '@/lib/validations/repo'

export async function PATCH(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const session = await getServerSession(authOptions)

    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const body = await request.json()
    const validatedData = updatePinnedRepoSchema.parse(body)

    // Check if the pinned repo belongs to the user
    const pinnedRepo = await prisma.pinnedRepository.findUnique({
      where: { id: params.id },
    })

    if (!pinnedRepo || pinnedRepo.userId !== session.user.id) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 })
    }

    const updated = await prisma.pinnedRepository.update({
      where: { id: params.id },
      data: validatedData,
    })

    return NextResponse.json({ pinnedRepo: updated })
  } catch (error) {
    console.error('Error updating pinned repository:', error)
    return NextResponse.json(
      { error: 'Failed to update pinned repository' },
      { status: 500 }
    )
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const session = await getServerSession(authOptions)

    if (!session?.user?.id) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    // Check if the pinned repo belongs to the user
    const pinnedRepo = await prisma.pinnedRepository.findUnique({
      where: { id: params.id },
    })

    if (!pinnedRepo || pinnedRepo.userId !== session.user.id) {
      return NextResponse.json({ error: 'Not found' }, { status: 404 })
    }

    await prisma.pinnedRepository.delete({
      where: { id: params.id },
    })

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('Error deleting pinned repository:', error)
    return NextResponse.json(
      { error: 'Failed to delete pinned repository' },
      { status: 500 }
    )
  }
}

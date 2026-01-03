'use client'

import { RepoCard } from './RepoCard'
import type { GitHubRepository } from '@/lib/github/client'

interface RepoGridProps {
  repositories: GitHubRepository[]
  isLoading?: boolean
}

export function RepoGrid({ repositories, isLoading }: RepoGridProps) {
  if (isLoading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <div
            key={i}
            className="h-64 rounded-lg border bg-card animate-pulse"
          />
        ))}
      </div>
    )
  }

  if (repositories.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center">
        <div className="rounded-full bg-muted p-6 mb-4">
          <svg
            className="w-12 h-12 text-muted-foreground"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"
            />
          </svg>
        </div>
        <h3 className="text-lg font-semibold mb-2">No repositories found</h3>
        <p className="text-muted-foreground max-w-md">
          We couldn&apos;t find any repositories matching your criteria. Try
          adjusting your filters or create a new repository on GitHub.
        </p>
      </div>
    )
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {repositories.map((repo) => (
        <RepoCard key={repo.id} repository={repo} />
      ))}
    </div>
  )
}

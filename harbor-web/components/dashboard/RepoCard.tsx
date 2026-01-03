'use client'

import Link from 'next/link'
import { Star, GitFork, Eye, Circle } from 'lucide-react'
import { Card, CardContent, CardHeader } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { formatNumber, formatRelativeTime, getLanguageColor } from '@/lib/utils'
import type { GitHubRepository } from '@/lib/github/client'

interface RepoCardProps {
  repository: GitHubRepository
}

export function RepoCard({ repository }: RepoCardProps) {
  const languageColor = getLanguageColor(repository.language)

  return (
    <Card className="group hover:border-primary/50 transition-all duration-200 hover:shadow-md">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between gap-2">
          <div className="flex-1 min-w-0">
            <Link
              href={repository.html_url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-block max-w-full"
            >
              <h3 className="font-semibold text-lg truncate group-hover:text-primary transition-colors">
                {repository.name}
              </h3>
            </Link>
            <p className="text-xs text-muted-foreground mt-0.5">
              {repository.owner.login}
            </p>
          </div>
          {repository.private && (
            <Badge variant="secondary" className="shrink-0">
              Private
            </Badge>
          )}
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {/* Description */}
        {repository.description && (
          <p className="text-sm text-muted-foreground line-clamp-2">
            {repository.description}
          </p>
        )}

        {/* Topics */}
        {repository.topics && repository.topics.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {repository.topics.slice(0, 3).map((topic) => (
              <Badge key={topic} variant="outline" className="text-xs">
                {topic}
              </Badge>
            ))}
            {repository.topics.length > 3 && (
              <Badge variant="outline" className="text-xs">
                +{repository.topics.length - 3}
              </Badge>
            )}
          </div>
        )}

        {/* Stats */}
        <div className="flex items-center gap-4 text-sm text-muted-foreground">
          {repository.language && (
            <div className="flex items-center gap-1.5">
              <Circle
                className="w-3 h-3 fill-current"
                style={{ color: languageColor }}
              />
              <span>{repository.language}</span>
            </div>
          )}

          <div className="flex items-center gap-1">
            <Star className="w-4 h-4" />
            <span>{formatNumber(repository.stargazers_count)}</span>
          </div>

          <div className="flex items-center gap-1">
            <GitFork className="w-4 h-4" />
            <span>{formatNumber(repository.forks_count)}</span>
          </div>

          {repository.watchers_count > 0 && (
            <div className="flex items-center gap-1">
              <Eye className="w-4 h-4" />
              <span>{formatNumber(repository.watchers_count)}</span>
            </div>
          )}
        </div>

        {/* Updated time */}
        <div className="text-xs text-muted-foreground">
          Updated {formatRelativeTime(repository.updated_at)}
        </div>
      </CardContent>
    </Card>
  )
}

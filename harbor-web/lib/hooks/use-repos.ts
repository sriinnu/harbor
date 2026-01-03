'use client'

import useSWR from 'swr'
import type { GitHubRepository } from '@/lib/github/client'

interface UseReposOptions {
  type?: 'all' | 'owner' | 'public' | 'private' | 'member'
  sort?: 'created' | 'updated' | 'pushed' | 'full_name'
  direction?: 'asc' | 'desc'
  per_page?: number
  page?: number
  include_archived?: boolean
}

interface ReposResponse {
  repositories: GitHubRepository[]
  pagination: {
    page: number
    per_page: number
    total: number
  }
}

const fetcher = (url: string) => fetch(url).then((res) => res.json())

export function useRepos(options: UseReposOptions = {}) {
  const params = new URLSearchParams()
  if (options.type) params.set('type', options.type)
  if (options.sort) params.set('sort', options.sort)
  if (options.direction) params.set('direction', options.direction)
  if (options.per_page) params.set('per_page', String(options.per_page))
  if (options.page) params.set('page', String(options.page))
  if (options.include_archived)
    params.set('include_archived', String(options.include_archived))

  const { data, error, isLoading, mutate } = useSWR<ReposResponse>(
    `/api/github/repos?${params.toString()}`,
    fetcher,
    {
      refreshInterval: 60000, // Refresh every minute
      revalidateOnFocus: true,
    }
  )

  return {
    repositories: data?.repositories || [],
    pagination: data?.pagination,
    isLoading,
    isError: error,
    mutate,
  }
}

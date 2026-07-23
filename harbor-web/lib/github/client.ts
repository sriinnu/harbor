import { RedisCache } from '@/lib/redis/cache'
import { githubCacheKey, githubCacheTag } from '@/lib/github/cache-key'

export interface GitHubRepository {
  id: number
  node_id: string
  name: string
  full_name: string
  owner: {
    login: string
    avatar_url: string
    type: string
  }
  private: boolean
  description: string | null
  fork: boolean
  url: string
  html_url: string
  homepage: string | null
  language: string | null
  stargazers_count: number
  watchers_count: number
  forks_count: number
  open_issues_count: number
  created_at: string
  updated_at: string
  pushed_at: string
  archived: boolean
  disabled: boolean
  topics: string[]
}

export interface GitHubUser {
  login: string
  id: number
  avatar_url: string
  name: string
  email: string | null
  bio: string | null
  company: string | null
  location: string | null
  public_repos: number
  followers: number
  following: number
}

export class GitHubClient {
  private accessToken: string
  private baseUrl = 'https://api.github.com'

  constructor(accessToken: string) {
    this.accessToken = accessToken
  }

  private async fetch<T>(
    endpoint: string,
    options: RequestInit = {},
    useCache = true
  ): Promise<T> {
    const url = `${this.baseUrl}${endpoint}`
    const cacheKey = githubCacheKey(this.accessToken, 'rest', endpoint)

    // Try to get from cache first
    if (useCache) {
      const cached = await RedisCache.get<T>(cacheKey)
      if (cached) {
        return cached
      }
    }

    const headers: HeadersInit = {
      Authorization: `Bearer ${this.accessToken}`,
      Accept: 'application/vnd.github.v3+json',
      'User-Agent': 'Harbor',
      ...options.headers,
    }

    const response = await fetch(url, {
      ...options,
      headers,
    })

    if (!response.ok) {
      const error = await response.json().catch(() => ({}))
      throw new Error(
        `GitHub API error: ${response.status} ${response.statusText} - ${JSON.stringify(error)}`
      )
    }

    const data = await response.json()

    // Cache the response
    if (useCache) {
      const ttl = this.getTTLFromHeaders(response.headers)
      await RedisCache.set(cacheKey, data, { ttl, tags: [githubCacheTag(this.accessToken)] })
    }

    return data
  }

  private getTTLFromHeaders(headers: Headers): number {
    const cacheControl = headers.get('cache-control')
    if (cacheControl) {
      const maxAge = cacheControl.match(/max-age=(\d+)/)
      if (maxAge) {
        return parseInt(maxAge[1], 10)
      }
    }
    return 300 // Default 5 minutes
  }

  /**
   * Get authenticated user
   */
  async getUser(): Promise<GitHubUser> {
    return this.fetch<GitHubUser>('/user')
  }

  /**
   * Get user repositories
   */
  async getRepositories(options: {
    type?: 'all' | 'owner' | 'public' | 'private' | 'member'
    sort?: 'created' | 'updated' | 'pushed' | 'full_name'
    direction?: 'asc' | 'desc'
    per_page?: number
    page?: number
  } = {}): Promise<GitHubRepository[]> {
    const params = new URLSearchParams()
    if (options.type) params.set('type', options.type)
    if (options.sort) params.set('sort', options.sort)
    if (options.direction) params.set('direction', options.direction)
    if (options.per_page) params.set('per_page', String(options.per_page))
    if (options.page) params.set('page', String(options.page))

    const endpoint = `/user/repos?${params.toString()}`
    return this.fetch<GitHubRepository[]>(endpoint)
  }

  /**
   * Get starred repositories
   */
  async getStarredRepos(options: {
    sort?: 'created' | 'updated'
    direction?: 'asc' | 'desc'
    per_page?: number
    page?: number
  } = {}): Promise<GitHubRepository[]> {
    const params = new URLSearchParams()
    if (options.sort) params.set('sort', options.sort)
    if (options.direction) params.set('direction', options.direction)
    if (options.per_page) params.set('per_page', String(options.per_page))
    if (options.page) params.set('page', String(options.page))

    const endpoint = `/user/starred?${params.toString()}`
    return this.fetch<GitHubRepository[]>(endpoint)
  }

  /**
   * Get a specific repository
   */
  async getRepository(owner: string, repo: string): Promise<GitHubRepository> {
    return this.fetch<GitHubRepository>(`/repos/${owner}/${repo}`)
  }

  /**
   * Search repositories
   */
  async searchRepositories(query: string, options: {
    sort?: 'stars' | 'forks' | 'help-wanted-issues' | 'updated'
    order?: 'desc' | 'asc'
    per_page?: number
    page?: number
  } = {}): Promise<{ items: GitHubRepository[]; total_count: number }> {
    const params = new URLSearchParams({ q: query })
    if (options.sort) params.set('sort', options.sort)
    if (options.order) params.set('order', options.order)
    if (options.per_page) params.set('per_page', String(options.per_page))
    if (options.page) params.set('page', String(options.page))

    const endpoint = `/search/repositories?${params.toString()}`
    return this.fetch(endpoint)
  }

  /**
   * Get repository languages
   */
  async getRepositoryLanguages(
    owner: string,
    repo: string
  ): Promise<Record<string, number>> {
    return this.fetch<Record<string, number>>(`/repos/${owner}/${repo}/languages`)
  }

  /**
   * Invalidate cache for a specific endpoint or all GitHub caches
   */
  async invalidateCache(endpoint?: string): Promise<void> {
    if (endpoint) {
      const cacheKey = githubCacheKey(this.accessToken, 'rest', endpoint)
      await RedisCache.delete(cacheKey)
    } else {
      await RedisCache.invalidateByTag(githubCacheTag(this.accessToken))
    }
  }
}

/**
 * Create a GitHub client instance
 */
export function createGitHubClient(accessToken: string): GitHubClient {
  return new GitHubClient(accessToken)
}

export default GitHubClient

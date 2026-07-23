import { RedisCache } from '@/lib/redis/cache'
import { githubCacheKey, githubCacheTag } from '@/lib/github/cache-key'

const GITHUB_GRAPHQL_ENDPOINT = 'https://api.github.com/graphql'

export interface GraphQLResponse<T> {
  data: T
  errors?: Array<{
    message: string
    locations?: Array<{ line: number; column: number }>
    path?: string[]
  }>
}

export class GitHubGraphQLClient {
  private accessToken: string

  constructor(accessToken: string) {
    this.accessToken = accessToken
  }

  async query<T>(
    query: string,
    variables: Record<string, any> = {},
    useCache = true
  ): Promise<T> {
    const cacheKey = githubCacheKey(this.accessToken, 'graphql', JSON.stringify({ query, variables }))

    // Try cache first
    if (useCache) {
      const cached = await RedisCache.get<T>(cacheKey)
      if (cached) {
        return cached
      }
    }

    const response = await fetch(GITHUB_GRAPHQL_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
        'User-Agent': 'Harbor',
      },
      body: JSON.stringify({ query, variables }),
    })

    if (!response.ok) {
      throw new Error(`GraphQL request failed: ${response.statusText}`)
    }

    const json = (await response.json()) as GraphQLResponse<T>

    if (json.errors) {
      throw new Error(
        `GraphQL errors: ${json.errors.map((e) => e.message).join(', ')}`
      )
    }

    // Cache the result
    if (useCache) {
      await RedisCache.set(cacheKey, json.data, { ttl: 300, tags: [githubCacheTag(this.accessToken)] }) // 5 minutes
    }

    return json.data
  }
}

// GraphQL query templates
export const QUERIES = {
  /**
   * Get viewer (authenticated user) with repositories
   */
  GET_VIEWER_REPOS: `
    query GetViewerRepos($first: Int!, $after: String) {
      viewer {
        login
        name
        avatarUrl
        repositories(
          first: $first
          after: $after
          orderBy: { field: UPDATED_AT, direction: DESC }
          ownerAffiliations: [OWNER, COLLABORATOR]
        ) {
          totalCount
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            name
            nameWithOwner
            description
            url
            homepageUrl
            isPrivate
            isFork
            isArchived
            primaryLanguage {
              name
              color
            }
            stargazerCount
            forkCount
            watchers {
              totalCount
            }
            issues(states: OPEN) {
              totalCount
            }
            pullRequests(states: OPEN) {
              totalCount
            }
            updatedAt
            pushedAt
            createdAt
          }
        }
      }
    }
  `,

  /**
   * Get repository details
   */
  GET_REPOSITORY: `
    query GetRepository($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        id
        name
        nameWithOwner
        description
        url
        homepageUrl
        isPrivate
        isFork
        isArchived
        primaryLanguage {
          name
          color
        }
        languages(first: 10, orderBy: { field: SIZE, direction: DESC }) {
          edges {
            node {
              name
              color
            }
            size
          }
        }
        stargazerCount
        forkCount
        watchers {
          totalCount
        }
        issues(states: OPEN) {
          totalCount
        }
        pullRequests(states: OPEN) {
          totalCount
        }
        defaultBranchRef {
          name
          target {
            ... on Commit {
              history(first: 1) {
                nodes {
                  message
                  committedDate
                  author {
                    name
                    email
                  }
                }
              }
            }
          }
        }
        licenseInfo {
          name
          spdxId
        }
        repositoryTopics(first: 10) {
          nodes {
            topic {
              name
            }
          }
        }
        updatedAt
        pushedAt
        createdAt
      }
    }
  `,

  /**
   * Get user's starred repositories
   */
  GET_STARRED_REPOS: `
    query GetStarredRepos($first: Int!, $after: String) {
      viewer {
        starredRepositories(
          first: $first
          after: $after
          orderBy: { field: STARRED_AT, direction: DESC }
        ) {
          totalCount
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            name
            nameWithOwner
            description
            url
            isPrivate
            primaryLanguage {
              name
              color
            }
            stargazerCount
            forkCount
            updatedAt
          }
        }
      }
    }
  `,

  /**
   * Search repositories
   */
  SEARCH_REPOSITORIES: `
    query SearchRepositories($query: String!, $first: Int!, $after: String) {
      search(query: $query, type: REPOSITORY, first: $first, after: $after) {
        repositoryCount
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          ... on Repository {
            id
            name
            nameWithOwner
            description
            url
            isPrivate
            primaryLanguage {
              name
              color
            }
            stargazerCount
            forkCount
            updatedAt
          }
        }
      }
    }
  `,

  /**
   * Get contribution activity
   */
  GET_CONTRIBUTION_ACTIVITY: `
    query GetContributionActivity($username: String!, $from: DateTime!, $to: DateTime!) {
      user(login: $username) {
        contributionsCollection(from: $from, to: $to) {
          totalCommitContributions
          totalIssueContributions
          totalPullRequestContributions
          totalPullRequestReviewContributions
          contributionCalendar {
            totalContributions
            weeks {
              contributionDays {
                contributionCount
                date
              }
            }
          }
        }
      }
    }
  `,
}

export function createGraphQLClient(accessToken: string): GitHubGraphQLClient {
  return new GitHubGraphQLClient(accessToken)
}

export default GitHubGraphQLClient

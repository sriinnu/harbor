import { z } from 'zod'

export const pinRepoSchema = z.object({
  githubId: z.number(),
  name: z.string().min(1),
  owner: z.string().min(1),
  fullName: z.string().min(1),
  description: z.string().nullable(),
  url: z.string().url(),
  stars: z.number().default(0),
  language: z.string().nullable(),
  isPrivate: z.boolean().default(false),
  notes: z.string().optional(),
  tags: z.array(z.string()).default([]),
})

export const updatePinnedRepoSchema = z.object({
  notes: z.string().optional(),
  tags: z.array(z.string()).optional(),
  order: z.number().optional(),
})

export const repoFiltersSchema = z.object({
  type: z.enum(['all', 'owner', 'public', 'private', 'member']).optional(),
  sort: z.enum(['created', 'updated', 'pushed', 'full_name']).optional(),
  direction: z.enum(['asc', 'desc']).optional(),
  language: z.string().optional(),
  search: z.string().optional(),
  per_page: z.number().min(1).max(100).default(30),
  page: z.number().min(1).default(1),
})

export type PinRepoInput = z.infer<typeof pinRepoSchema>
export type UpdatePinnedRepoInput = z.infer<typeof updatePinnedRepoSchema>
export type RepoFilters = z.infer<typeof repoFiltersSchema>

# RepoBar Web - Project Structure

This document explains the organization and architecture of the RepoBar web application.

## Directory Structure

```
repobar-web/
├── app/                          # Next.js 14 App Router
│   ├── (dashboard)/             # Dashboard route group (protected)
│   │   ├── layout.tsx          # Dashboard layout with Header
│   │   └── page.tsx            # Main dashboard page
│   ├── api/                     # API routes
│   │   ├── auth/               # NextAuth endpoints
│   │   ├── github/             # GitHub API proxy
│   │   ├── pinned/             # Pinned repos management
│   │   └── user/               # User preferences
│   ├── auth/                    # Authentication pages
│   │   ├── signin/             # Sign in page
│   │   └── error/              # Auth error page
│   ├── globals.css             # Global styles
│   ├── layout.tsx              # Root layout
│   ├── page.tsx                # Home page (redirects)
│   └── providers.tsx           # Client-side providers
│
├── components/                  # React components
│   ├── dashboard/              # Dashboard-specific components
│   │   ├── Header.tsx         # App header with user menu
│   │   ├── RepoCard.tsx       # Repository card component
│   │   └── RepoGrid.tsx       # Grid layout for repos
│   ├── providers/              # Provider components
│   │   └── session-provider.tsx
│   └── ui/                     # shadcn/ui components
│       ├── avatar.tsx
│       ├── badge.tsx
│       ├── button.tsx
│       ├── card.tsx
│       ├── dropdown-menu.tsx
│       ├── input.tsx
│       └── select.tsx
│
├── lib/                         # Utility libraries
│   ├── auth/                   # Authentication
│   │   └── options.ts         # NextAuth configuration
│   ├── db/                     # Database
│   │   └── prisma.ts          # Prisma client singleton
│   ├── github/                 # GitHub API integration
│   │   ├── client.ts          # REST API client
│   │   └── graphql.ts         # GraphQL client
│   ├── hooks/                  # Custom React hooks
│   │   └── use-repos.ts       # Repository data hook
│   ├── redis/                  # Redis caching
│   │   ├── cache.ts           # Cache utilities
│   │   └── client.ts          # Redis client
│   ├── validations/            # Zod schemas
│   │   └── repo.ts            # Repository validations
│   └── utils.ts                # Utility functions
│
├── prisma/                      # Prisma ORM
│   └── schema.prisma           # Database schema
│
├── config/                      # Configuration
│   └── site.ts                 # Site configuration
│
├── types/                       # TypeScript types
│   └── next-auth.d.ts          # NextAuth type extensions
│
├── scripts/                     # Utility scripts
│   └── setup.sh                # Setup script
│
├── .env.example                # Environment variables template
├── .eslintrc.json              # ESLint configuration
├── .gitignore                  # Git ignore rules
├── .prettierrc                 # Prettier configuration
├── components.json             # shadcn/ui config
├── docker-compose.yml          # Docker services
├── Dockerfile                  # Production Docker image
├── middleware.ts               # Next.js middleware
├── next.config.js              # Next.js configuration
├── package.json                # Dependencies
├── postcss.config.js           # PostCSS configuration
├── README.md                   # Main documentation
├── SETUP.md                    # Setup guide
├── tailwind.config.ts          # Tailwind CSS configuration
└── tsconfig.json               # TypeScript configuration
```

## Architecture Overview

### Frontend (Next.js 14)

- **App Router**: Uses Next.js 14's app directory with React Server Components
- **Server Components**: Default components are server-rendered for better performance
- **Client Components**: Interactive components use 'use client' directive
- **Route Groups**: `(dashboard)` group for protected routes with shared layout

### Backend (API Routes)

- **RESTful API**: API routes in `/app/api`
- **Route Handlers**: GET, POST, PATCH, DELETE methods
- **Server-Side**: Run on the server with access to database and external APIs

### Authentication (NextAuth)

- **GitHub OAuth**: Primary authentication method
- **Session Management**: Database sessions with Prisma adapter
- **Middleware**: Protects routes automatically
- **Type Safety**: Extended types for user session data

### Database (Prisma + PostgreSQL)

- **ORM**: Prisma for type-safe database access
- **Migrations**: Version-controlled schema changes
- **Models**: User, Account, Session, PinnedRepository, Team, Subscription
- **Relations**: Foreign keys and indexes for performance

### Caching (Redis)

- **API Cache**: Cache GitHub API responses
- **ETag Support**: Conditional requests to save bandwidth
- **TTL**: Time-based expiration
- **Tag-based Invalidation**: Invalidate related cache entries

### Styling (Tailwind CSS + shadcn/ui)

- **Utility-First**: Tailwind CSS for styling
- **Component Library**: shadcn/ui for pre-built components
- **Dark Mode**: CSS variables for theme switching
- **Responsive**: Mobile-first responsive design

## Key Features Implementation

### Repository Management

1. **Fetching Repos**:
   - API route: `/api/github/repos`
   - GitHub client: `lib/github/client.ts`
   - Caching: Redis with ETag support

2. **Displaying Repos**:
   - Component: `components/dashboard/RepoCard.tsx`
   - Grid layout: `components/dashboard/RepoGrid.tsx`
   - Hook: `lib/hooks/use-repos.ts` (SWR)

3. **Filtering/Sorting**:
   - Client-side: Search query filtering
   - Server-side: GitHub API parameters
   - State management: React useState

### Pinned Repositories

1. **Pin a Repo**:
   - API: `POST /api/pinned`
   - Database: PinnedRepository model
   - Validation: Zod schema

2. **Manage Pins**:
   - API: `PATCH/DELETE /api/pinned/[id]`
   - Order tracking: Sequential ordering
   - Custom metadata: Notes and tags

### User Preferences

1. **Store Preferences**:
   - API: `PATCH /api/user/preferences`
   - Model: UserPreferences
   - Auto-created: On first sign in

2. **Apply Preferences**:
   - Theme: CSS variables
   - Filters: Default sort/filter values
   - Display: Grid/list view toggle

## Data Flow

### Authentication Flow

```
1. User clicks "Sign in with GitHub"
2. NextAuth redirects to GitHub OAuth
3. User authorizes application
4. GitHub redirects back with code
5. NextAuth exchanges code for token
6. User and Account records created
7. Session established
8. User redirected to dashboard
```

### Repository Fetching Flow

```
1. Dashboard page loads
2. useRepos hook triggers SWR fetch
3. Request sent to /api/github/repos
4. API checks Redis cache
5. If miss, fetch from GitHub API
6. Store in Redis with TTL
7. Return to client
8. RepoGrid renders cards
```

### Pinning Flow

```
1. User clicks "Pin" on repo
2. POST request to /api/pinned
3. Validate repo data with Zod
4. Check if already pinned
5. Calculate next order number
6. Create PinnedRepository record
7. Return success
8. Client updates UI
```

## Performance Optimizations

1. **Server Components**: Default to SSR for better initial load
2. **Redis Caching**: Reduce GitHub API calls
3. **SWR**: Client-side caching and revalidation
4. **Image Optimization**: Next.js Image component
5. **Code Splitting**: Automatic with Next.js App Router
6. **Database Indexes**: On frequently queried fields

## Security Measures

1. **Authentication Required**: Middleware protects routes
2. **CSRF Protection**: Built into NextAuth
3. **SQL Injection**: Prevented by Prisma
4. **XSS Protection**: React auto-escapes
5. **Environment Variables**: Never exposed to client
6. **GitHub Token**: Stored encrypted in database

## Development Workflow

1. **Local Development**:
   ```bash
   npm run dev
   ```

2. **Database Changes**:
   ```bash
   # Edit schema
   npx prisma migrate dev --name description
   ```

3. **Adding Components**:
   ```bash
   # Using shadcn CLI (optional)
   npx shadcn-ui@latest add [component-name]
   ```

4. **Type Checking**:
   ```bash
   npx tsc --noEmit
   ```

## Deployment Considerations

1. **Environment Variables**: Set in hosting platform
2. **Database**: Use managed PostgreSQL (Vercel Postgres, Supabase, etc.)
3. **Redis**: Optional but recommended (Upstash, Redis Cloud)
4. **Build**: `npm run build` for production
5. **Monitoring**: Built-in Vercel Analytics support

## Future Enhancements

- [ ] Team collaboration features
- [ ] Advanced repository analytics
- [ ] Custom tags and collections
- [ ] Export/import functionality
- [ ] Chrome extension integration
- [ ] Webhook support for real-time updates
- [ ] GraphQL API endpoint
- [ ] Mobile app (React Native)

## Contributing

When adding new features:

1. Follow the existing directory structure
2. Use TypeScript for type safety
3. Add Zod schemas for validation
4. Create API routes for data operations
5. Use server components when possible
6. Add proper error handling
7. Update this documentation

## References

- [Next.js Documentation](https://nextjs.org/docs)
- [Prisma Documentation](https://www.prisma.io/docs)
- [NextAuth Documentation](https://next-auth.js.org)
- [Tailwind CSS](https://tailwindcss.com/docs)
- [shadcn/ui](https://ui.shadcn.com)

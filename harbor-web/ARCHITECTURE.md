# RepoBar Web - Architecture Diagram

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client (Browser)                         │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Next.js 14 App Router (React)                │  │
│  │                                                            │  │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │  │
│  │  │   Pages     │  │  Components  │  │     Hooks      │  │  │
│  │  │             │  │              │  │                │  │  │
│  │  │ • Dashboard │  │ • RepoCard   │  │ • use-repos    │  │  │
│  │  │ • Sign In   │  │ • RepoGrid   │  │ • SWR          │  │  │
│  │  │ • Settings  │  │ • Header     │  │                │  │  │
│  │  └─────────────┘  └──────────────┘  └────────────────┘  │  │
│  │                                                            │  │
│  └────────────────────────────┬───────────────────────────────┘  │
│                               │                                   │
└───────────────────────────────┼───────────────────────────────────┘
                                │
                    HTTP Requests (API Routes)
                                │
┌───────────────────────────────┼───────────────────────────────────┐
│                               ▼                                   │
│                    Next.js Server (Node.js)                       │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                      Middleware                              │ │
│  │              (Authentication & Route Protection)             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                               │                                  │
│  ┌────────────────────────────┴──────────────────────────────┐  │
│  │                      API Routes                            │  │
│  │                                                             │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │  │
│  │  │   /api/auth  │  │ /api/github  │  │  /api/pinned    │ │  │
│  │  │              │  │              │  │                 │ │  │
│  │  │ • NextAuth   │  │ • repos      │  │ • GET/POST     │ │  │
│  │  │ • [...auth]  │  │              │  │ • PATCH/DELETE │ │  │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘ │  │
│  │                                                             │  │
│  └─────────────────────────────────────────────────────────────┘ │
│                               │                                  │
│  ┌────────────────────────────┴──────────────────────────────┐  │
│  │                     Business Logic                         │  │
│  │                                                             │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐ │  │
│  │  │   Prisma     │  │    GitHub    │  │     Redis       │ │  │
│  │  │   Client     │  │    Client    │  │     Cache       │ │  │
│  │  │              │  │              │  │                 │ │  │
│  │  │ • User       │  │ • REST API   │  │ • ETag Cache   │ │  │
│  │  │ • Repo       │  │ • GraphQL    │  │ • TTL          │ │  │
│  │  │ • Prefs      │  │              │  │                 │ │  │
│  │  └──────┬───────┘  └──────┬───────┘  └────────┬────────┘ │  │
│  │         │                  │                    │          │  │
│  └─────────┼──────────────────┼────────────────────┼──────────┘  │
│            │                  │                    │             │
└────────────┼──────────────────┼────────────────────┼─────────────┘
             │                  │                    │
   ┌─────────▼────────┐  ┌──────▼────────┐  ┌────────▼────────┐
   │   PostgreSQL     │  │   GitHub API   │  │     Redis       │
   │                  │  │                │  │                 │
   │ • Users          │  │ • Repos        │  │ • Cache Layer   │
   │ • Sessions       │  │ • OAuth        │  │ • Sessions      │
   │ • Pinned Repos   │  │ • GraphQL      │  │                 │
   │ • Preferences    │  │                │  │                 │
   └──────────────────┘  └────────────────┘  └─────────────────┘
```

## Data Flow Diagrams

### 1. User Authentication Flow

```
User Browser                Next.js Server              GitHub
     │                            │                        │
     │ 1. Click "Sign In"         │                        │
     ├───────────────────────────>│                        │
     │                            │                        │
     │ 2. Redirect to GitHub      │                        │
     │<───────────────────────────┤                        │
     │                            │                        │
     │ 3. Authorize App           │                        │
     ├─────────────────────────────────────────────────────>│
     │                            │                        │
     │ 4. Return with code        │                        │
     │<──────────────────────────────────────────────────────┤
     │                            │                        │
     │ 5. Exchange code for token │                        │
     │                            ├───────────────────────>│
     │                            │                        │
     │                            │ 6. Return access token │
     │                            │<───────────────────────┤
     │                            │                        │
     │                            │ 7. Store in DB         │
     │                            │ (User + Account)       │
     │                            │                        │
     │ 8. Create session          │                        │
     │<───────────────────────────┤                        │
     │                            │                        │
     │ 9. Redirect to Dashboard   │                        │
     │<───────────────────────────┤                        │
     │                            │                        │
```

### 2. Repository Fetching Flow

```
Browser              Next.js API          Redis Cache       GitHub API
   │                      │                     │                 │
   │ 1. Load Dashboard    │                     │                 │
   ├─────────────────────>│                     │                 │
   │                      │                     │                 │
   │                      │ 2. Check cache      │                 │
   │                      ├────────────────────>│                 │
   │                      │                     │                 │
   │                      │ 3. Cache MISS       │                 │
   │                      │<────────────────────┤                 │
   │                      │                     │                 │
   │                      │ 4. Fetch from GitHub│                 │
   │                      ├─────────────────────────────────────>│
   │                      │                     │                 │
   │                      │ 5. Return repos data│                 │
   │                      │<──────────────────────────────────────┤
   │                      │                     │                 │
   │                      │ 6. Store in cache   │                 │
   │                      ├────────────────────>│                 │
   │                      │                     │                 │
   │ 7. Return to client  │                     │                 │
   │<─────────────────────┤                     │                 │
   │                      │                     │                 │
   │ 8. Render RepoGrid   │                     │                 │
   │                      │                     │                 │
```

### 3. Pin Repository Flow

```
Browser              Next.js API          PostgreSQL
   │                      │                     │
   │ 1. Click "Pin Repo"  │                     │
   ├─────────────────────>│                     │
   │                      │                     │
   │                      │ 2. Validate data    │
   │                      │ (Zod schema)        │
   │                      │                     │
   │                      │ 3. Check if exists  │
   │                      ├────────────────────>│
   │                      │                     │
   │                      │ 4. Not found        │
   │                      │<────────────────────┤
   │                      │                     │
   │                      │ 5. Get max order    │
   │                      ├────────────────────>│
   │                      │                     │
   │                      │ 6. Return order: 5  │
   │                      │<────────────────────┤
   │                      │                     │
   │                      │ 7. Insert new pin   │
   │                      │    order: 6         │
   │                      ├────────────────────>│
   │                      │                     │
   │                      │ 8. Return success   │
   │                      │<────────────────────┤
   │                      │                     │
   │ 9. Return pinned repo│                     │
   │<─────────────────────┤                     │
   │                      │                     │
   │ 10. Update UI        │                     │
   │ (show pinned badge)  │                     │
   │                      │                     │
```

## Component Hierarchy

```
App (Root Layout)
│
├── Providers (SessionProvider)
│   │
│   └── Dashboard Layout (Protected)
│       │
│       ├── Header
│       │   ├── Logo
│       │   └── UserMenu (DropdownMenu)
│       │       ├── Avatar
│       │       ├── Profile Link
│       │       ├── Settings Link
│       │       └── Sign Out Button
│       │
│       └── Dashboard Page
│           │
│           ├── Search Bar (Input)
│           │
│           ├── Filters
│           │   ├── Type Select
│           │   └── Sort Select
│           │
│           └── RepoGrid
│               │
│               └── RepoCard (multiple)
│                   ├── Card
│                   │   ├── CardHeader
│                   │   │   ├── Repo Name
│                   │   │   └── Private Badge
│                   │   │
│                   │   └── CardContent
│                   │       ├── Description
│                   │       ├── Topics (Badges)
│                   │       ├── Stats
│                   │       │   ├── Language (w/ color)
│                   │       │   ├── Stars
│                   │       │   ├── Forks
│                   │       │   └── Watchers
│                   │       │
│                   │       └── Updated Time
│                   │
│                   └── Actions (Pin/Unpin)
```

## Database Schema Relationships

```
┌──────────────┐
│     User     │
│──────────────│
│ id (PK)      │◄────────┐
│ email        │         │
│ name         │         │
│ githubId     │         │
│ githubToken  │         │
└──────────────┘         │
       │                 │
       │ 1:N             │ 1:1
       │                 │
       ▼                 │
┌──────────────┐  ┌──────────────────┐
│   Account    │  │ UserPreferences  │
│──────────────│  │──────────────────│
│ id (PK)      │  │ id (PK)          │
│ userId (FK)  │  │ userId (FK)      │
│ provider     │  │ theme            │
│ access_token │  │ itemsPerPage     │
└──────────────┘  │ defaultView      │
                  │ showPrivateRepos │
       │          └──────────────────┘
       │ 1:N
       │
       ▼
┌──────────────┐
│   Session    │
│──────────────│
│ id (PK)      │
│ userId (FK)  │
│ expires      │
└──────────────┘

       │
       │ 1:N
       │
       ▼
┌─────────────────────┐
│ PinnedRepository    │
│─────────────────────│
│ id (PK)             │
│ userId (FK)         │
│ githubId            │
│ name                │
│ fullName            │
│ description         │
│ url                 │
│ stars               │
│ language            │
│ order               │
│ notes               │
│ tags[]              │
└─────────────────────┘

       │
       │ N:M
       │
       ▼
┌──────────────┐      ┌──────────────┐
│     Team     │      │ TeamMember   │
│──────────────│◄─────│──────────────│
│ id (PK)      │  1:N │ id (PK)      │
│ name         │      │ teamId (FK)  │
│ slug         │      │ userId (FK)  │
│ description  │      │ role         │
└──────────────┘      └──────────────┘

       │
       │ 1:1
       │
       ▼
┌─────────────────────┐
│   Subscription      │
│─────────────────────│
│ id (PK)             │
│ userId (FK)         │
│ stripeCustomerId    │
│ stripeSubscriptionId│
│ plan                │
│ status              │
└─────────────────────┘
```

## Request/Response Flow

### GET /api/github/repos

**Request:**
```http
GET /api/github/repos?type=owner&sort=updated&per_page=30
Authorization: Session Cookie
```

**Flow:**
1. Middleware validates session
2. API route extracts query params
3. Fetch user's GitHub token from DB
4. Check Redis cache for response
5. On cache miss, call GitHub API
6. Store response in Redis
7. Filter results (if needed)
8. Return JSON response

**Response:**
```json
{
  "repositories": [
    {
      "id": 123456,
      "name": "awesome-repo",
      "full_name": "user/awesome-repo",
      "description": "An awesome repository",
      "private": false,
      "language": "TypeScript",
      "stargazers_count": 150,
      "forks_count": 25,
      "updated_at": "2024-01-15T10:30:00Z",
      ...
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 30,
    "total": 42
  }
}
```

## Security Architecture

```
┌─────────────────────────────────────────────────────┐
│              Security Layers                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. HTTPS/TLS                                       │
│     └─> All traffic encrypted                      │
│                                                     │
│  2. NextAuth Middleware                             │
│     ├─> Session validation                         │
│     ├─> Route protection                           │
│     └─> CSRF protection                            │
│                                                     │
│  3. API Route Guards                                │
│     ├─> User authentication check                  │
│     ├─> User authorization check                   │
│     └─> Input validation (Zod)                     │
│                                                     │
│  4. Prisma ORM                                      │
│     ├─> SQL injection prevention                   │
│     ├─> Type safety                                │
│     └─> Parameterized queries                      │
│                                                     │
│  5. Environment Variables                           │
│     ├─> Secrets never exposed to client            │
│     ├─> .env files not committed                   │
│     └─> Runtime validation                         │
│                                                     │
│  6. React XSS Protection                            │
│     ├─> Auto-escaping                              │
│     └─> Sanitization                               │
│                                                     │
│  7. GitHub Token Storage                            │
│     ├─> Encrypted in database                      │
│     ├─> Never exposed to client                    │
│     └─> Scoped permissions                         │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Deployment Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Production                         │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌────────────────────────────────────────────┐     │
│  │           Vercel Edge Network              │     │
│  │  (CDN, Static Assets, Edge Functions)      │     │
│  └───────────────────┬────────────────────────┘     │
│                      │                               │
│  ┌───────────────────▼────────────────────────┐     │
│  │         Vercel Serverless Functions        │     │
│  │      (Next.js App, API Routes, SSR)        │     │
│  └───────────────────┬────────────────────────┘     │
│                      │                               │
│         ┌────────────┼────────────┐                 │
│         │            │            │                 │
│    ┌────▼─────┐ ┌───▼────┐ ┌─────▼──────┐         │
│    │ Vercel   │ │ Upstash│ │  GitHub    │         │
│    │ Postgres │ │ Redis  │ │  API       │         │
│    │          │ │        │ │            │         │
│    └──────────┘ └────────┘ └────────────┘         │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## Performance Optimizations

```
1. Server-Side Rendering (SSR)
   └─> Fast initial page loads

2. React Server Components
   └─> Reduced JavaScript bundle size

3. Automatic Code Splitting
   └─> Load only what's needed

4. Image Optimization
   └─> Next.js Image component with WebP

5. Redis Caching
   ├─> GitHub API responses
   └─> Reduced API calls

6. SWR Client Caching
   ├─> Stale-while-revalidate
   └─> Optimistic updates

7. Database Indexes
   ├─> Indexed foreign keys
   └─> Composite indexes on queries

8. Edge Functions
   └─> Low latency global deployment
```

This architecture provides a scalable, secure, and performant foundation for the RepoBar web application.

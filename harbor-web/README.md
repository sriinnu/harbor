# RepoBar Web

A modern web application for organizing and managing your GitHub repositories, built with Next.js 14, Prisma, and NextAuth.

## Features

- **GitHub OAuth Authentication** - Secure authentication using GitHub
- **Repository Management** - View, search, and filter all your GitHub repositories
- **Pin Repositories** - Pin your favorite repositories for quick access
- **Team Collaboration** - Share repository collections with your team
- **Advanced Search** - Filter by language, type, stars, and more
- **Real-time Sync** - Keep your repositories in sync with GitHub
- **Responsive Design** - Works on desktop, tablet, and mobile

## Tech Stack

- **Framework**: Next.js 14 with App Router
- **Database**: PostgreSQL with Prisma ORM
- **Authentication**: NextAuth.js with GitHub provider
- **Styling**: TailwindCSS with shadcn/ui components
- **Caching**: Redis for API response caching
- **Data Fetching**: SWR for client-side data fetching
- **Type Safety**: TypeScript throughout
- **Validation**: Zod for schema validation

## Getting Started

### Prerequisites

- Node.js 18.17 or later
- PostgreSQL database
- Redis (optional, for caching)
- GitHub OAuth App credentials

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/repobar.git
cd repobar/repobar-web
```

2. Install dependencies:
```bash
npm install
# or
pnpm install
# or
yarn install
```

3. Set up environment variables:
```bash
cp .env.example .env
```

Edit `.env` and add your credentials:
- `DATABASE_URL`: PostgreSQL connection string
- `NEXTAUTH_SECRET`: Generate with `openssl rand -base64 32`
- `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET`: From GitHub OAuth App
- `REDIS_URL`: Redis connection string (optional)

4. Set up the database:
```bash
npx prisma generate
npx prisma db push
```

5. Run the development server:
```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## Project Structure

```
repobar-web/
├── app/                      # Next.js App Router
│   ├── (dashboard)/         # Dashboard pages
│   ├── api/                 # API routes
│   ├── auth/                # Authentication pages
│   └── layout.tsx           # Root layout
├── components/              # React components
│   ├── dashboard/          # Dashboard-specific components
│   └── ui/                 # shadcn/ui components
├── lib/                     # Utility libraries
│   ├── auth/               # Authentication configuration
│   ├── db/                 # Database client
│   ├── github/             # GitHub API client
│   └── redis/              # Redis client
├── prisma/                  # Prisma schema
├── config/                  # App configuration
└── types/                   # TypeScript type definitions
```

## GitHub OAuth Setup

1. Go to [GitHub Settings > Developer settings > OAuth Apps](https://github.com/settings/developers)
2. Click "New OAuth App"
3. Fill in the details:
   - **Application name**: RepoBar (or your preferred name)
   - **Homepage URL**: `http://localhost:3000` (for development)
   - **Authorization callback URL**: `http://localhost:3000/api/auth/callback/github`
4. Copy the Client ID and generate a Client Secret
5. Add them to your `.env` file

## Database Schema

The application uses Prisma with PostgreSQL. Key models include:

- **User**: User accounts and GitHub integration
- **Account/Session**: NextAuth session management
- **UserPreferences**: User settings and preferences
- **PinnedRepository**: User's pinned repositories
- **Team/TeamMember**: Team collaboration features
- **Subscription**: Stripe subscription management
- **GitHubCache**: API response caching

Run migrations:
```bash
npx prisma migrate dev
```

View database:
```bash
npx prisma studio
```

## API Routes

- `GET /api/github/repos` - Fetch user repositories
- `POST /api/auth/[...nextauth]` - NextAuth authentication

## Deployment

### Vercel (Recommended)

1. Push your code to GitHub
2. Import the project in Vercel
3. Add environment variables
4. Deploy

### Docker

```bash
docker build -t repobar-web .
docker run -p 3000:3000 repobar-web
```

## Environment Variables

See `.env.example` for all required environment variables.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Support

For support, please open an issue on GitHub or contact us at support@repobar.com

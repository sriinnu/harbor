# RepoBar Web - Setup Guide

This guide will walk you through setting up the RepoBar web application from scratch.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Node.js** 18.17 or later ([Download](https://nodejs.org/))
- **PostgreSQL** 14 or later ([Download](https://www.postgresql.org/download/))
- **Redis** 7 or later (optional, for caching) ([Download](https://redis.io/download/))
- **Git** ([Download](https://git-scm.com/downloads))

## Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/repobar.git
cd repobar/repobar-web
```

## Step 2: Install Dependencies

Using npm:
```bash
npm install
```

Using pnpm (recommended):
```bash
pnpm install
```

Using yarn:
```bash
yarn install
```

## Step 3: Set Up PostgreSQL Database

### Option A: Local PostgreSQL

1. Create a new database:
```bash
createdb repobar
```

2. Your connection string will be:
```
postgresql://username:password@localhost:5432/repobar
```

### Option B: Docker PostgreSQL

```bash
docker run --name repobar-postgres \
  -e POSTGRES_USER=repobar \
  -e POSTGRES_PASSWORD=your_password \
  -e POSTGRES_DB=repobar \
  -p 5432:5432 \
  -d postgres:16-alpine
```

### Option C: Docker Compose (Recommended)

Use the included docker-compose.yml:
```bash
docker-compose up -d postgres redis
```

## Step 4: Set Up GitHub OAuth App

1. Go to GitHub Settings > Developer settings > OAuth Apps
   - URL: https://github.com/settings/developers

2. Click "New OAuth App"

3. Fill in the application details:
   - **Application name**: RepoBar Dev (or your preferred name)
   - **Homepage URL**: `http://localhost:3000`
   - **Application description**: (optional)
   - **Authorization callback URL**: `http://localhost:3000/api/auth/callback/github`

4. Click "Register application"

5. Copy the **Client ID**

6. Click "Generate a new client secret" and copy the **Client Secret**

7. Keep these credentials safe - you'll need them in the next step

## Step 5: Configure Environment Variables

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Edit `.env` and fill in the values:

```bash
# Database - Use your PostgreSQL connection string
DATABASE_URL="postgresql://repobar:your_password@localhost:5432/repobar?schema=public"

# NextAuth - Generate a secure secret
NEXTAUTH_URL="http://localhost:3000"
NEXTAUTH_SECRET="your-nextauth-secret-here"

# GitHub OAuth - From Step 4
GITHUB_CLIENT_ID="your_github_client_id"
GITHUB_CLIENT_SECRET="your_github_client_secret"

# GitHub PAT (optional but recommended)
GITHUB_PAT="ghp_your_personal_access_token"

# Redis (optional)
REDIS_URL="redis://localhost:6379"

# App Configuration
NEXT_PUBLIC_APP_URL="http://localhost:3000"
NODE_ENV="development"
```

### Generate NEXTAUTH_SECRET

Run this command to generate a secure secret:
```bash
openssl rand -base64 32
```

### Create GitHub Personal Access Token (Optional)

This helps with GitHub API rate limits:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo`, `read:user`, `user:email`, `read:org`
4. Generate and copy the token

## Step 6: Set Up Prisma

1. Generate Prisma client:
```bash
npx prisma generate
```

2. Push the schema to your database:
```bash
npx prisma db push
```

3. (Optional) Seed the database:
```bash
npx prisma db seed
```

## Step 7: Run the Development Server

Start the development server:
```bash
npm run dev
```

The application will be available at http://localhost:3000

## Step 8: Verify the Setup

1. Open http://localhost:3000 in your browser
2. Click "Sign in with GitHub"
3. Authorize the application
4. You should see your GitHub repositories

## Troubleshooting

### Database Connection Issues

If you can't connect to PostgreSQL:
```bash
# Check if PostgreSQL is running
pg_isready

# Check your connection string format
# It should be: postgresql://USER:PASSWORD@HOST:PORT/DATABASE
```

### GitHub OAuth Issues

Common issues:
- **"Redirect URI mismatch"**: Make sure the callback URL in GitHub matches exactly: `http://localhost:3000/api/auth/callback/github`
- **"Invalid client"**: Double-check your Client ID and Secret in `.env`

### Prisma Issues

Reset the database if needed:
```bash
npx prisma migrate reset
npx prisma db push
```

### Redis Connection Issues (Optional)

If Redis is not required for development, you can comment out Redis-related code or ensure Redis is running:
```bash
# Check if Redis is running
redis-cli ping
# Should return: PONG
```

## Development Tools

### Prisma Studio

View and edit your database:
```bash
npx prisma studio
```

### Database Migrations

Create a new migration:
```bash
npx prisma migrate dev --name description_of_changes
```

### View Logs

The application logs to the console. Check for:
- Database connection status
- GitHub API requests
- Authentication events

## Next Steps

- Explore the code in `/app` and `/components`
- Customize the UI in `/components/ui`
- Add new API routes in `/app/api`
- Modify the database schema in `/prisma/schema.prisma`

## Production Deployment

See the [README.md](./README.md) file for production deployment instructions.

## Getting Help

- Check the [README.md](./README.md) for general documentation
- Review the code comments for implementation details
- Open an issue on GitHub for bugs or questions

## Useful Commands

```bash
# Development
npm run dev              # Start development server
npm run build           # Build for production
npm run start           # Start production server

# Database
npx prisma studio       # Open Prisma Studio
npx prisma generate     # Generate Prisma client
npx prisma db push      # Push schema to database
npx prisma migrate dev  # Create and apply migration

# Code Quality
npm run lint           # Run ESLint
npm run format         # Format with Prettier

# Docker
docker-compose up -d   # Start all services
docker-compose down    # Stop all services
docker-compose logs -f # View logs
```

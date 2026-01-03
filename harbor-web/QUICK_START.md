# RepoBar Web - Quick Start Guide

Get up and running with RepoBar in 5 minutes!

## Prerequisites

- Node.js 18+ installed
- PostgreSQL running (or use Docker)
- GitHub account

## Option 1: Docker Quick Start (Fastest)

```bash
# 1. Create .env file
cp .env.example .env

# 2. Edit .env and add GitHub OAuth credentials
# (See "Get GitHub OAuth Credentials" section below)

# 3. Start everything with Docker
docker-compose up -d

# 4. Run database migrations
npx prisma generate
npx prisma db push

# 5. Open browser
# http://localhost:3000
```

## Option 2: Manual Setup

```bash
# 1. Install dependencies
npm install

# 2. Create .env file
cp .env.example .env

# 3. Edit .env with your credentials
# (See sections below)

# 4. Setup database
npx prisma generate
npx prisma db push

# 5. Run development server
npm run dev

# 6. Open browser
# http://localhost:3000
```

## Get GitHub OAuth Credentials

### Step 1: Create OAuth App

1. Go to: https://github.com/settings/developers
2. Click "New OAuth App"
3. Fill in:
   - **Name**: RepoBar Dev
   - **Homepage URL**: `http://localhost:3000`
   - **Callback URL**: `http://localhost:3000/api/auth/callback/github`
4. Click "Register application"

### Step 2: Get Credentials

1. Copy **Client ID**
2. Click "Generate a new client secret"
3. Copy **Client Secret**

### Step 3: Update .env

```bash
GITHUB_CLIENT_ID="your_client_id_here"
GITHUB_CLIENT_SECRET="your_client_secret_here"
```

## Configure Environment Variables

Edit your `.env` file:

```bash
# Database (Local PostgreSQL)
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/repobar"

# Or use Docker PostgreSQL
DATABASE_URL="postgresql://repobar:repobar_dev_password@localhost:5432/repobar"

# NextAuth Secret (generate new one)
NEXTAUTH_SECRET="run: openssl rand -base64 32"
NEXTAUTH_URL="http://localhost:3000"

# GitHub OAuth (from steps above)
GITHUB_CLIENT_ID="your_github_client_id"
GITHUB_CLIENT_SECRET="your_github_client_secret"

# Redis (optional for development)
REDIS_URL="redis://localhost:6379"

# App URL
NEXT_PUBLIC_APP_URL="http://localhost:3000"
NODE_ENV="development"
```

## Generate NextAuth Secret

Run this command and copy the output to your `.env`:

```bash
openssl rand -base64 32
```

## Database Setup Options

### Option A: Use Docker (Easiest)

```bash
docker-compose up -d postgres
```

### Option B: Local PostgreSQL

```bash
# Create database
createdb repobar

# Connection string
postgresql://YOUR_USER:YOUR_PASSWORD@localhost:5432/repobar
```

### Option C: Cloud Database

Use any PostgreSQL provider:
- Vercel Postgres
- Supabase
- Railway
- Neon

## Redis Setup (Optional)

Redis is optional but recommended for production.

### Skip Redis for Development

Comment out Redis imports if not needed:

```typescript
// lib/github/client.ts
// import { RedisCache } from '@/lib/redis/cache'

// Use in-memory cache instead
const cache = new Map()
```

### Use Docker Redis

```bash
docker-compose up -d redis
```

### Use Cloud Redis

- Upstash (free tier)
- Redis Cloud
- Railway

## Verify Installation

1. **Start the app:**
   ```bash
   npm run dev
   ```

2. **Check these URLs:**
   - http://localhost:3000 - Should redirect to sign in
   - http://localhost:3000/auth/signin - Sign in page

3. **Sign in with GitHub:**
   - Click "Sign in with GitHub"
   - Authorize the app
   - Should redirect to dashboard

4. **Check database:**
   ```bash
   npx prisma studio
   # Opens at http://localhost:5555
   # You should see your user record
   ```

## Common Issues

### "Invalid client" error

- Double-check GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET
- Make sure no extra spaces in .env file

### "Redirect URI mismatch"

- Callback URL must be: `http://localhost:3000/api/auth/callback/github`
- Must match exactly in GitHub OAuth App settings

### Database connection error

- Check DATABASE_URL format
- Make sure PostgreSQL is running
- Test connection: `psql $DATABASE_URL`

### Prisma errors

```bash
# Reset everything
npx prisma migrate reset
npx prisma generate
npx prisma db push
```

### Port 3000 already in use

```bash
# Use different port
PORT=3001 npm run dev
# Update NEXTAUTH_URL and callback URL accordingly
```

## Development Workflow

```bash
# Start development server
npm run dev

# View database
npx prisma studio

# Check TypeScript
npx tsc --noEmit

# Lint code
npm run lint

# Format code
npx prettier --write .
```

## Project Structure Quick Reference

```
repobar-web/
├── app/
│   ├── (dashboard)/page.tsx    # Main dashboard
│   ├── api/                    # API routes
│   └── auth/                   # Auth pages
│
├── components/
│   ├── dashboard/              # Dashboard components
│   └── ui/                     # UI components
│
├── lib/
│   ├── auth/                   # NextAuth config
│   ├── github/                 # GitHub API
│   └── db/                     # Database
│
├── prisma/
│   └── schema.prisma           # Database schema
│
└── .env                        # Your secrets
```

## Next Steps

### Customize the App

1. **Change colors**: Edit `app/globals.css`
2. **Add features**: Create new API routes in `app/api/`
3. **Modify UI**: Edit components in `components/`
4. **Update schema**: Edit `prisma/schema.prisma`

### Deploy to Production

See deployment guides:
- **Vercel**: Easiest, automatic deployments
- **Docker**: Use provided Dockerfile
- **Other**: Standard Node.js hosting

### Add Features

Common next features:
- Repository analytics
- Team sharing
- Custom collections
- Browser extension
- Mobile app

## Helpful Commands

```bash
# Development
npm run dev              # Start dev server
npm run build            # Build for production
npm start                # Start production server

# Database
npx prisma studio        # GUI for database
npx prisma generate      # Generate Prisma client
npx prisma db push       # Push schema changes
npx prisma migrate dev   # Create migration

# Code Quality
npm run lint             # Run ESLint
npx prettier --write .   # Format all files

# Docker
docker-compose up -d     # Start services
docker-compose down      # Stop services
docker-compose logs -f   # View logs
```

## Getting Help

- **Documentation**: Check README.md, SETUP.md, PROJECT_STRUCTURE.md
- **Architecture**: See ARCHITECTURE.md for diagrams
- **Issues**: Open GitHub issue
- **Logs**: Check terminal output for errors

## Success Checklist

- [ ] Node.js 18+ installed
- [ ] PostgreSQL running
- [ ] .env file configured
- [ ] GitHub OAuth app created
- [ ] Dependencies installed (`npm install`)
- [ ] Database initialized (`npx prisma db push`)
- [ ] Dev server running (`npm run dev`)
- [ ] Can access http://localhost:3000
- [ ] Can sign in with GitHub
- [ ] Can see repositories on dashboard

If all checked, you're ready to develop!

## Tips

1. **Use Prisma Studio** to inspect your database data
2. **Enable Hot Reload** - It's automatic in Next.js dev mode
3. **Check Console** - Errors show in terminal and browser console
4. **Use TypeScript** - IntelliSense helps catch errors early
5. **Read the Code** - Comments explain what each part does

## Support

Need help? Check these resources:

- Next.js Docs: https://nextjs.org/docs
- Prisma Docs: https://www.prisma.io/docs
- NextAuth Docs: https://next-auth.js.org
- TailwindCSS: https://tailwindcss.com/docs

Happy coding!

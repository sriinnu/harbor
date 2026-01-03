#!/bin/bash

# RepoBar Web - Quick Setup Script
# This script helps you set up the development environment

set -e

echo "========================================="
echo "RepoBar Web - Setup Script"
echo "========================================="
echo ""

# Check Node.js
echo "Checking Node.js installation..."
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed. Please install Node.js 18.17 or later."
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "Error: Node.js version must be 18 or later. Current version: $(node -v)"
    exit 1
fi
echo "✓ Node.js $(node -v) found"

# Check if .env exists
if [ ! -f .env ]; then
    echo ""
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo "✓ .env file created"
    echo ""
    echo "IMPORTANT: Please edit .env file and add your credentials:"
    echo "  - DATABASE_URL"
    echo "  - NEXTAUTH_SECRET (generate with: openssl rand -base64 32)"
    echo "  - GITHUB_CLIENT_ID"
    echo "  - GITHUB_CLIENT_SECRET"
    echo ""
    read -p "Press Enter when you've configured .env..."
else
    echo "✓ .env file already exists"
fi

# Install dependencies
echo ""
echo "Installing dependencies..."
if command -v pnpm &> /dev/null; then
    pnpm install
elif command -v yarn &> /dev/null; then
    yarn install
else
    npm install
fi
echo "✓ Dependencies installed"

# Check PostgreSQL
echo ""
echo "Checking PostgreSQL connection..."
if ! command -v psql &> /dev/null; then
    echo "⚠ PostgreSQL client not found. Make sure PostgreSQL is running."
    echo "  You can use Docker: docker-compose up -d postgres"
else
    echo "✓ PostgreSQL client found"
fi

# Check Redis (optional)
echo ""
echo "Checking Redis connection (optional)..."
if command -v redis-cli &> /dev/null; then
    if redis-cli ping &> /dev/null; then
        echo "✓ Redis is running"
    else
        echo "⚠ Redis is not running. You can start it with: docker-compose up -d redis"
    fi
else
    echo "⚠ Redis client not found (optional for development)"
fi

# Setup Prisma
echo ""
echo "Setting up Prisma..."
npx prisma generate
echo "✓ Prisma client generated"

echo ""
read -p "Do you want to push the database schema now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    npx prisma db push
    echo "✓ Database schema pushed"
fi

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Make sure your .env file is configured correctly"
echo "  2. Start the development server: npm run dev"
echo "  3. Open http://localhost:3000 in your browser"
echo ""
echo "Useful commands:"
echo "  npm run dev          - Start development server"
echo "  npx prisma studio    - Open database UI"
echo "  docker-compose up -d - Start PostgreSQL and Redis"
echo ""
echo "For more information, see SETUP.md"
echo ""

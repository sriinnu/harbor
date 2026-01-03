'use client'

import { signIn } from 'next-auth/react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Github } from 'lucide-react'

export default function SignInPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-background to-muted p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="flex justify-center mb-4">
            <div className="rounded-full bg-primary p-3">
              <Github className="h-8 w-8 text-primary-foreground" />
            </div>
          </div>
          <CardTitle className="text-3xl font-bold">Welcome to RepoBar</CardTitle>
          <CardDescription className="text-base">
            Organize and manage your GitHub repositories with ease
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <Button
            className="w-full"
            size="lg"
            onClick={() => signIn('github', { callbackUrl: '/' })}
          >
            <Github className="mr-2 h-5 w-5" />
            Sign in with GitHub
          </Button>

          <div className="text-center text-sm text-muted-foreground">
            <p>
              By signing in, you agree to our{' '}
              <a href="#" className="underline hover:text-foreground">
                Terms of Service
              </a>{' '}
              and{' '}
              <a href="#" className="underline hover:text-foreground">
                Privacy Policy
              </a>
            </p>
          </div>

          <div className="space-y-2 rounded-lg bg-muted p-4">
            <h3 className="font-semibold text-sm">What you get:</h3>
            <ul className="space-y-2 text-sm text-muted-foreground">
              <li className="flex items-start">
                <span className="mr-2">✓</span>
                <span>Access to all your GitHub repositories</span>
              </li>
              <li className="flex items-start">
                <span className="mr-2">✓</span>
                <span>Pin and organize your favorite repos</span>
              </li>
              <li className="flex items-start">
                <span className="mr-2">✓</span>
                <span>Advanced search and filtering</span>
              </li>
              <li className="flex items-start">
                <span className="mr-2">✓</span>
                <span>Team collaboration features</span>
              </li>
            </ul>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

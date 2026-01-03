import 'next-auth'

declare module 'next-auth' {
  interface Session {
    user: {
      id: string
      name?: string | null
      email?: string | null
      image?: string | null
      githubUsername?: string | null
      githubId?: string | null
    }
  }

  interface User {
    githubUsername?: string | null
    githubId?: string | null
  }
}

declare module 'next-auth/jwt' {
  interface JWT {
    id: string
    githubUsername?: string | null
    githubId?: string | null
  }
}

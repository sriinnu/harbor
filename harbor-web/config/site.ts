export const siteConfig = {
  name: 'RepoBar',
  description: 'Organize and manage your GitHub repositories with ease',
  url: process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000',
  ogImage: '/og-image.png',
  links: {
    twitter: 'https://twitter.com/repobar',
    github: 'https://github.com/yourusername/repobar',
  },
}

export const dashboardConfig = {
  mainNav: [
    {
      title: 'Dashboard',
      href: '/',
    },
    {
      title: 'Pinned',
      href: '/pinned',
    },
    {
      title: 'Teams',
      href: '/teams',
    },
  ],
  sidebarNav: [
    {
      title: 'Repositories',
      href: '/',
      icon: 'repository',
    },
    {
      title: 'Pinned',
      href: '/pinned',
      icon: 'pin',
    },
    {
      title: 'Teams',
      href: '/teams',
      icon: 'users',
    },
    {
      title: 'Settings',
      href: '/settings',
      icon: 'settings',
    },
  ],
}

export const subscriptionPlans = {
  free: {
    name: 'Free',
    description: 'Perfect for personal use',
    price: 0,
    features: [
      'Up to 50 pinned repositories',
      'Basic repository management',
      'GitHub OAuth integration',
    ],
  },
  pro: {
    name: 'Pro',
    description: 'For power users',
    price: 9,
    stripePriceId: process.env.STRIPE_PRO_PRICE_ID,
    features: [
      'Unlimited pinned repositories',
      'Advanced filtering and search',
      'Custom tags and notes',
      'Priority support',
    ],
  },
  team: {
    name: 'Team',
    description: 'For teams and organizations',
    price: 29,
    stripePriceId: process.env.STRIPE_TEAM_PRICE_ID,
    features: [
      'Everything in Pro',
      'Shared team repositories',
      'Team collaboration features',
      'Advanced analytics',
      'Dedicated support',
    ],
  },
}

import { betterAuth } from 'better-auth';
import { createD1Adapter } from './d1-adapter';
import type { D1Database } from '@cloudflare/workers-types';

export function createAuth(
  db: D1Database,
  secret: string,
  baseURL: string,
  githubClientId: string,
  githubClientSecret: string
) {
  return betterAuth({
    database: createD1Adapter(db)({}),
    secret,
    baseURL,
    socialProviders: {
      github: {
        clientId: githubClientId,
        clientSecret: githubClientSecret,
      },
    },
    // Use snake_case for database columns (matches our schema)
    advanced: {
      useSecureCookies: baseURL.startsWith('https://'),
      cookiePrefix: 'beadster_',
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;

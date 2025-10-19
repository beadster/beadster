import { betterAuth } from 'better-auth';
import { createD1Adapter } from '@systemoperator/common/lib/d1-adapter';
import { generateId } from '@systemoperator/common/id';
import type { D1Database } from '@cloudflare/workers-types';

export function createAuth(
  db: D1Database,
  secret: string,
  baseURL: string,
  githubClientId: string,
  githubClientSecret: string
) {
  return betterAuth({
    database: createD1Adapter(db),
    secret,
    baseURL,
    trustedOrigins: [baseURL, 'https://beadster.ai'],
    socialProviders: {
      github: {
        clientId: githubClientId,
        clientSecret: githubClientSecret,
      },
    },
    // Database hooks to add API key and GitHub fields on signup
    databaseHooks: {
      user: {
        create: {
          async before(user: any) {
            // Generate API key for CLI/MCP access
            if (!user.api_key) {
              user.api_key = generateId();
            }
            return user;
          },
        },
      },
      account: {
        create: {
          async after(account: any) {
            // If this is GitHub OAuth, copy GitHub fields to user
            if (account.providerId === 'github' && account.accountId) {
              console.log('[auth] Copying GitHub data to user');
              await db
                .prepare(`UPDATE users SET
                  github_id = ?,
                  github_login = ?,
                  github_name = ?,
                  github_email = ?,
                  github_avatar_url = ?
                  WHERE id = ?`)
                .bind(
                  account.accountId,
                  account.username || null,
                  account.name || null,
                  account.email || null,
                  account.avatar || null,
                  account.userId
                )
                .run();
            }
            return account;
          },
        },
      },
    },
    advanced: {
      useSecureCookies: baseURL.startsWith('https://'),
      cookiePrefix: 'beadster_',
    },
  });
}

export type Auth = ReturnType<typeof createAuth>;

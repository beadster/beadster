import { betterAuth } from 'better-auth';
import type { D1Database } from '@cloudflare/workers-types';
import { configureTimestampFormat } from '@systemoperator/common/dates';
import { createD1Adapter } from '@systemoperator/common/lib/d1-adapter';
import { generateId } from '@systemoperator/common/id';

// Configure timestamp format for beadster (seconds - matches bd tool)
configureTimestampFormat('seconds');

export function createAuth(db: D1Database, secret?: string, env?: any) {
	return betterAuth({
		database: createD1Adapter(db),

		secret: secret || 'temp-secret-for-dev',

		baseURL: env?.BASE_URL || 'https://beadster.ai',

		socialProviders: {
			github: {
				clientId: env?.GITHUB_CLIENT_ID || '',
				clientSecret: env?.GITHUB_CLIENT_SECRET || '',
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
			useSecureCookies: true,
			cookiePrefix: 'beadster_',
		},
	});
}

export type AuthInstance = ReturnType<typeof createAuth>;

/**
 * ID generation utilities
 * Using ULID (Universally Unique Lexicographically Sortable Identifier)
 * for better database performance and sortability
 */

import { ulid } from 'ulid';

/**
 * Generates a new ULID in lowercase format
 *
 * ULIDs are:
 * - 26 characters (base32 encoded)
 * - Lexicographically sortable
 * - Case-insensitive (we use lowercase for consistency)
 * - URL-safe
 * - 128-bit (same as UUID)
 *
 * Format: 01ARZ3NDEKTSV4RRFFQ69G5FAV (but lowercase)
 * - First 10 chars: timestamp (milliseconds)
 * - Last 16 chars: cryptographically secure randomness
 *
 * @returns A lowercase ULID string
 * @example
 * generateId() // "01arz3ndektsv4rrffq69g5fav"
 */
export function generateId(): string {
	return ulid().toLowerCase();
}

/**
 * Date and timestamp utilities
 * All database timestamps use UNIX format (configurable: seconds or milliseconds)
 */

export type TimestampFormat = 'seconds' | 'milliseconds';

// Default to seconds for consistency with most System Operator products
let timestampFormat: TimestampFormat = 'seconds';

/**
 * Configure timestamp format (seconds or milliseconds)
 * Call this at the start of your application to set the format
 *
 * @param format - 'seconds' or 'milliseconds'
 * @example
 * configureTimestampFormat('milliseconds') // for tinysend, patronat
 * configureTimestampFormat('seconds') // for deepcalc, ultrathink (default)
 */
export function configureTimestampFormat(format: TimestampFormat): void {
	timestampFormat = format;
}

/**
 * Returns current UNIX timestamp in configured format
 * Use this for all database timestamp fields (created_at, updated_at, etc.)
 *
 * @returns Current time as UNIX timestamp (seconds or milliseconds based on config)
 * @example
 * now() // 1728825600 (seconds) or 1728825600000 (milliseconds)
 */
export function now(): number {
	if (timestampFormat === 'milliseconds') {
		return Date.now();
	}
	return Math.floor(Date.now() / 1000);
}

/**
 * Converts a UNIX timestamp to Date object
 * Automatically detects format based on configuration
 *
 * @param timestamp - UNIX timestamp
 * @returns Date object
 * @example
 * fromUnixTimestamp(1728825600) // Date object (if configured for seconds)
 * fromUnixTimestamp(1728825600000) // Date object (if configured for milliseconds)
 */
export function fromUnixTimestamp(timestamp: number): Date {
	if (timestampFormat === 'milliseconds') {
		return new Date(timestamp);
	}
	return new Date(timestamp * 1000);
}

/**
 * Converts a Date object to UNIX timestamp
 * Uses configured format
 *
 * @param date - Date object
 * @returns UNIX timestamp in configured format
 * @example
 * toUnixTimestamp(new Date()) // 1728825600 or 1728825600000 based on config
 */
export function toUnixTimestamp(date: Date): number {
	if (timestampFormat === 'milliseconds') {
		return date.getTime();
	}
	return Math.floor(date.getTime() / 1000);
}

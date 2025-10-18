/**
 * Better Auth adapter for Cloudflare D1
 * Handles table/column name mapping and timestamp conversions
 *
 * Extracted from patronat (most mature implementation)
 */

import type { D1Database } from "@cloudflare/workers-types";
import { generateId } from "./id";
import { now } from "./dates";

// Table name mapping: singular -> plural (Better Auth uses singular, our D1 uses plural)
const TABLE_MAP: Record<string, string> = {
  user: "users",
  session: "sessions",
  account: "accounts",
  verification: "verifications",
};

// Column name mapping: camelCase -> snake_case
const COLUMN_MAP: Record<string, string> = {
  userId: "user_id",
  accountId: "account_id",
  providerId: "provider_id",
  accessToken: "access_token",
  refreshToken: "refresh_token",
  idToken: "id_token",
  accessTokenExpiresAt: "access_token_expires_at",
  refreshTokenExpiresAt: "refresh_token_expires_at",
  emailVerified: "email_verified",
  createdAt: "created_at",
  updatedAt: "updated_at",
  expiresAt: "expires_at",
  ipAddress: "ip_address",
  userAgent: "user_agent",
};

function toSnakeCase(obj: any, model?: string): any {
  if (!obj || typeof obj !== "object") return obj;
  if (Array.isArray(obj)) return obj.map((item) => toSnakeCase(item, model));
  if (obj instanceof Date) return Math.floor(obj.getTime() / 1000); // Convert Date to UNIX timestamp

  const result: any = {};
  for (const [key, value] of Object.entries(obj)) {
    const snakeKey = COLUMN_MAP[key] || key;

    // Skip undefined values entirely - don't add them to the result
    if (value === undefined) {
      continue;
    }

    // Convert Date objects to UNIX timestamps for D1 INTEGER columns
    // Better Auth passes Date objects, we store as INTEGER (UNIX seconds)
    if (value instanceof Date) {
      result[snakeKey] = Math.floor(value.getTime() / 1000);
    } else {
      result[snakeKey] = value;
    }
  }
  return result;
}

function toCamelCase(obj: any): any {
  if (!obj || typeof obj !== "object") return obj;
  if (Array.isArray(obj)) return obj.map(toCamelCase);

  const result: any = {};
  for (const [key, value] of Object.entries(obj)) {
    // Reverse lookup: user_id -> userId, etc.
    const camelKey =
      Object.entries(COLUMN_MAP).find(([k, v]) => v === key)?.[0] || key;

    // Convert UNIX timestamps (stored as INTEGER) back to Date objects for Better Auth
    // Better Auth expects Date objects for timestamp fields
    // Only convert if value is a positive number (null/0 stays as is)
    if (
      (key === "created_at" ||
        key === "updated_at" ||
        key === "expires_at" ||
        key.endsWith("_at")) &&
      typeof value === "number" &&
      value > 0
    ) {
      // UNIX timestamp (seconds) -> Date object
      result[camelKey] = new Date(value * 1000);
    } else {
      // Keep null/undefined/0 as is for timestamp fields
      result[camelKey] = value;
    }
  }

  return result;
}

function mapTable(model: string): string {
  return TABLE_MAP[model] || model;
}

function mapColumn(field: string): string {
  return COLUMN_MAP[field] || field;
}

export function createD1Adapter(db: D1Database) {
  return (options: any) => ({
    id: "d1-adapter",

    // D1 doesn't support transactions, but Better Auth requires this method
    async transaction(fn: any) {
      console.log(
        "[D1 TRANSACTION] Starting transaction (not supported, executing without transaction)",
      );
      try {
        const result = await fn(this);
        console.log("[D1 TRANSACTION] Transaction completed successfully");
        return result;
      } catch (error) {
        console.error("[D1 TRANSACTION] Transaction failed:", error);
        throw error;
      }
    },

    async create({ model, data }: any) {
      const table = mapTable(model);
      const mappedData = toSnakeCase(data, model);

      // Generate ID if needed (lowercase ULID to match project convention)
      if (!mappedData.id) {
        mappedData.id = generateId();
      }

      // Set timestamps (UNIX timestamps for our D1 schema)
      const timestamp = now();
      mappedData.created_at = mappedData.created_at || timestamp;
      mappedData.updated_at = mappedData.updated_at || timestamp;

      // Filter out undefined values
      const filteredData: any = {};
      for (const [key, value] of Object.entries(mappedData)) {
        if (value !== undefined) {
          filteredData[key] = value === null ? null : value;
        }
      }

      const columns = Object.keys(filteredData);
      const placeholders = columns.map(() => "?");
      const values = columns.map((col) => filteredData[col]);

      const sql = `INSERT INTO ${table} (${columns.join(", ")}) VALUES (${placeholders.join(", ")})`;
      console.log(
        "[D1 CREATE]",
        JSON.stringify({
          table,
          model,
          data: filteredData,
          sql,
          values,
        }),
      );

      const insertResult = await db
        .prepare(sql)
        .bind(...values)
        .run();
      console.log("[D1 CREATE RESULT]", JSON.stringify(insertResult));

      // Return the created record
      const result = await db
        .prepare(`SELECT * FROM ${table} WHERE id = ?`)
        .bind(mappedData.id)
        .first();
      return toCamelCase(result);
    },

    async findOne({ model, where }: any) {
      console.log(`[D1 FIND ONE CALLED] model=${model}`);
      const table = mapTable(model);
      const conditions: string[] = [];
      const values: any[] = [];

      where.forEach((w: any) => {
        const col = mapColumn(w.field);
        if (w.operator === "eq" || !w.operator) {
          conditions.push(`${col} = ?`);
          values.push(w.value);
        }
      });

      const sql = `SELECT * FROM ${table} WHERE ${conditions.join(" AND ")} LIMIT 1`;
      console.log("[D1 FIND ONE]", {
        table,
        model,
        where,
        sql,
        values,
      });

      const result = await db
        .prepare(sql)
        .bind(...values)
        .first();
      console.log("[D1 FIND ONE RESULT]", result);
      return result ? toCamelCase(result) : null;
    },

    async findMany({ model, where, limit, offset, sortBy }: any) {
      const table = mapTable(model);
      let sql = `SELECT * FROM ${table}`;
      const values: any[] = [];

      if (where && where.length > 0) {
        const conditions: string[] = [];
        where.forEach((w: any) => {
          const col = mapColumn(w.field);
          if (w.operator === "eq" || !w.operator) {
            conditions.push(`${col} = ?`);
            values.push(w.value);
          }
        });
        sql += ` WHERE ${conditions.join(" AND ")}`;
      }

      if (sortBy) {
        sql += ` ORDER BY ${mapColumn(sortBy.field)} ${sortBy.direction.toUpperCase()}`;
      }

      if (limit) sql += ` LIMIT ${limit}`;
      if (offset) sql += ` OFFSET ${offset}`;

      console.log("[D1 FIND MANY]", {
        table,
        model,
        where,
        sql,
        values,
      });

      const result = await db
        .prepare(sql)
        .bind(...values)
        .all();
      console.log(
        "[D1 FIND MANY RESULT]",
        result.results?.length || 0,
        "records",
      );
      return result.results ? result.results.map(toCamelCase) : [];
    },

    async update({ model, where, update }: any) {
      console.log(`[D1 UPDATE CALLED] model=${model}`);
      const table = mapTable(model);

      console.log(
        "[D1 UPDATE] Input update object:",
        JSON.stringify(update, null, 2),
      );
      const mappedUpdate = toSnakeCase(update, model);
      console.log(
        "[D1 UPDATE] After toSnakeCase:",
        JSON.stringify(mappedUpdate, null, 2),
      );

      // Update timestamp (UNIX timestamp for our D1 schema)
      mappedUpdate.updated_at = now();

      // Filter out undefined values
      const filteredUpdate: any = {};
      for (const [key, value] of Object.entries(mappedUpdate)) {
        if (value !== undefined) {
          filteredUpdate[key] = value === null ? null : value;
        }
      }
      console.log("[D1 UPDATE] After filtering undefined:", filteredUpdate);

      const setClauses = Object.keys(filteredUpdate).map((col) => `${col} = ?`);
      const setValues = Object.values(filteredUpdate);

      const conditions: string[] = [];
      const whereValues: any[] = [];

      where.forEach((w: any) => {
        const col = mapColumn(w.field);
        conditions.push(`${col} = ?`);
        whereValues.push(w.value);
      });

      const sql = `UPDATE ${table} SET ${setClauses.join(", ")} WHERE ${conditions.join(" AND ")}`;
      const allValues = [...setValues, ...whereValues];

      console.log("[D1 UPDATE]", {
        table,
        model,
        where,
        update: filteredUpdate,
        sql,
        values: allValues,
      });

      const updateResult = await db
        .prepare(sql)
        .bind(...allValues)
        .run();
      console.log("[D1 UPDATE RESULT]", updateResult);

      // Return updated record
      const selectSql = `SELECT * FROM ${table} WHERE ${conditions.join(" AND ")} LIMIT 1`;
      const result = await db
        .prepare(selectSql)
        .bind(...whereValues)
        .first();
      return result ? toCamelCase(result) : null;
    },

    async updateMany({ model, where, update }: any) {
      const table = mapTable(model);
      const mappedUpdate = toSnakeCase(update, model);

      mappedUpdate.updated_at = now();

      // Filter out undefined values
      const filteredUpdate: any = {};
      for (const [key, value] of Object.entries(mappedUpdate)) {
        if (value !== undefined) {
          filteredUpdate[key] = value === null ? null : value;
        }
      }

      const setClauses = Object.keys(filteredUpdate).map((col) => `${col} = ?`);
      const setValues = Object.values(filteredUpdate);

      const conditions: string[] = [];
      const whereValues: any[] = [];

      where.forEach((w: any) => {
        const col = mapColumn(w.field);
        conditions.push(`${col} = ?`);
        whereValues.push(w.value);
      });

      const sql = `UPDATE ${table} SET ${setClauses.join(", ")} WHERE ${conditions.join(" AND ")}`;
      const allValues = [...setValues, ...whereValues];

      console.log("UPDATE MANY:", sql, allValues);

      const result = await db
        .prepare(sql)
        .bind(...allValues)
        .run();
      return result.meta.changes || 0;
    },

    async delete({ model, where }: any) {
      const table = mapTable(model);
      const conditions: string[] = [];
      const values: any[] = [];

      where.forEach((w: any) => {
        const col = mapColumn(w.field);
        conditions.push(`${col} = ?`);
        // Convert Date objects to UNIX timestamps for comparison
        const value =
          w.value instanceof Date
            ? Math.floor(w.value.getTime() / 1000)
            : w.value;
        values.push(value);
      });

      const sql = `DELETE FROM ${table} WHERE ${conditions.join(" AND ")}`;
      console.log("[D1 DELETE]", {
        table,
        model,
        where,
        sql,
        values,
      });

      const deleteResult = await db
        .prepare(sql)
        .bind(...values)
        .run();
      console.log("[D1 DELETE RESULT]", deleteResult);
    },

    async deleteMany({ model, where }: any) {
      const table = mapTable(model);
      const conditions: string[] = [];
      const values: any[] = [];

      where.forEach((w: any) => {
        const col = mapColumn(w.field);
        conditions.push(`${col} = ?`);
        // Convert Date objects to UNIX timestamps for comparison
        const value =
          w.value instanceof Date
            ? Math.floor(w.value.getTime() / 1000)
            : w.value;
        values.push(value);
      });

      const sql = `DELETE FROM ${table} WHERE ${conditions.join(" AND ")}`;
      console.log("DELETE MANY:", sql, values);

      const result = await db
        .prepare(sql)
        .bind(...values)
        .run();
      return result.meta.changes || 0;
    },
  });
}

/// <reference path="../.astro/types.d.ts" />

interface Env {
  DB: D1Database;
  API: any;
  BEADSTER_API_URL: string;
  BEADSTER_API_KEY: string;
}

type Runtime = import("@astrojs/cloudflare").Runtime<Env>;

declare namespace App {
  interface Locals extends Runtime {}
}

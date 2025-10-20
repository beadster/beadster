/// <reference path="../.astro/types.d.ts" />

interface Env {
  DB: D1Database;
  API: any;
}

type Runtime = import("@astrojs/cloudflare").Runtime<Env>;

declare namespace App {
  interface Locals extends Runtime {}
}

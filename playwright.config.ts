import { defineConfig, devices } from '@playwright/test';
import { readLocalSupabaseEnv } from './scripts/local-supabase-env.mjs';

export default defineConfig({
  testDir: './tests-e2e',
  // Auth fixtures and PostgreSQL rate-limit buckets are shared by the local suite.
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: process.env.CI ? [['list'], ['html']] : 'html',
  expect: {
    timeout: 15000,
  },
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      testIgnore: '**/phase13-delivery.spec.ts',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'phase13',
      testMatch: '**/phase13-delivery.spec.ts',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: process.env.PLAYWRIGHT_START_COMMAND ?? 'npm run dev',
    url: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:3000',
    reuseExistingServer: process.env.PLAYWRIGHT_REUSE_SERVER === 'true',
    env: (() => {
      const { API_URL, ANON_KEY, SERVICE_ROLE_KEY } =
        readLocalSupabaseEnv() as Record<string, string | undefined>;
      return {
        NEXT_PUBLIC_SUPABASE_URL:
          API_URL ||
          process.env.NEXT_PUBLIC_SUPABASE_URL ||
          'http://127.0.0.1:54321',
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
          ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || '',
        SUPABASE_SERVICE_ROLE_KEY:
          SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '',
      };
    })(),
  },
});

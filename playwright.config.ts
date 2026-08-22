import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests-e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  expect: {
    timeout: 15000,
  },
  use: {
    baseURL: 'http://127.0.0.1:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: process.env.PLAYWRIGHT_START_COMMAND ?? 'npm run dev',
    url: 'http://127.0.0.1:3000',
    reuseExistingServer: process.env.PLAYWRIGHT_REUSE_SERVER === 'true',
    env: {
      NODE_OPTIONS: '--dns-result-order=ipv4first',
    },
  },
});

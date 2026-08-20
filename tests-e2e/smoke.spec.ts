import { test, expect } from '@playwright/test';

test('Página inicial abre e contém o título correto', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('h1')).toHaveText('Juridico');
});

test('Endpoint de health check responde corretamente', async ({ request }) => {
  const response = await request.get('/api/health');
  expect(response.ok()).toBeTruthy();
  const data = await response.json();
  expect(data).toEqual({ status: 'ok' });
});

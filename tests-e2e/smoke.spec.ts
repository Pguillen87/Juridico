import { expect, test } from '@playwright/test';

test('Página inicial redireciona para o login do Juridico', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByText('Juridico').first()).toBeVisible();
});

test('Endpoint de health check responde corretamente', async ({ request }) => {
  const response = await request.get('/api/health');
  expect(response.ok()).toBeTruthy();
  const data = await response.json();
  expect(data).toEqual({ status: 'ok' });
});

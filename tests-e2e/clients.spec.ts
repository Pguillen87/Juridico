import { expect, test, type Page } from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

async function openClients(page: Page) {
  await page.goto('/app/clientes', { waitUntil: 'networkidle' });
  await expect(
    page.getByRole('heading', { name: 'Clientes', exact: true })
  ).toBeVisible();
}

async function createClient(page: Page, name: string) {
  await page.getByLabel('Nome do cliente').fill(name);
  await page.getByRole('button', { name: 'Criar cliente' }).click();
  const card = page.locator('article').filter({ hasText: name }).first();
  await expect(card.getByText(name, { exact: true })).toBeVisible();
  return card;
}

test.describe('Clientes — carteira simples', () => {
  test.describe.configure({ mode: 'serial' });

  test('lawyer cria cliente e acessa sua carteira', async ({ page }) => {
    const clientName = `Cliente E2E ${Date.now()}`;
    await login(page, 'lawyer@example.test');
    await openClients(page);

    const card = await createClient(page, clientName);
    await expect(card.getByText(/0 processo\(s\)/)).toBeVisible();
    await expect(
      card.getByRole('link', { name: 'Abrir carteira' })
    ).toBeVisible();
    await expect(page.getByText(/Partes|vínculos/i)).toHaveCount(0);

    await card.getByRole('link', { name: 'Abrir carteira' }).click();
    await expect(
      page.getByRole('heading', { name: `Processos de ${clientName}` })
    ).toBeVisible();
  });

  test('reviewer vê clientes mas não recebe cadastro', async ({ page }) => {
    await login(page, 'reviewer@example.test');
    await openClients(page);
    await expect(
      page.getByRole('button', { name: 'Criar cliente' })
    ).toHaveCount(0);
    await expect(page.getByText(/Partes|vínculos/i)).toHaveCount(0);
  });

  test('auditor não acessa a área operacional', async ({ page }) => {
    await login(page, 'auditor@example.test');
    await page.goto('/app/clientes');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });

  test('nomes iguais continuam sendo carteiras separadas sem UUID na tela', async ({
    page,
  }) => {
    const name = `Cliente repetido ${Date.now()}`;
    await login(page, 'lawyer@example.test');
    await openClients(page);
    await createClient(page, name);
    await createClient(page, name);

    await expect(page.locator('article').filter({ hasText: name })).toHaveCount(
      2
    );
    await expect(page.locator('body')).not.toContainText(
      /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i
    );
  });
});

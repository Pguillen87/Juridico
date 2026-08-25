import { expect, test, type Page } from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

test.describe('Clientes e partes — Fase 5', () => {
  test.describe.configure({ mode: 'serial' });
  test('lawyer acessa clientes e vê controles de mutação', async ({ page }) => {
    await login(page, 'owner@example.test');
    await page.goto('/app/clientes');
    await expect(
      page.getByRole('heading', { name: 'Clientes, partes e vínculos' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar cliente' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar parte' })
    ).toBeVisible();
  });

  test('operator acessa clientes e pode iniciar cadastro', async ({ page }) => {
    await login(page, 'operator@example.test');
    await page.goto('/app/clientes');
    await expect(
      page.getByRole('heading', { name: 'Clientes, partes e vínculos' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar cliente' })
    ).toBeVisible();
  });

  test('reviewer acessa em leitura sem controles de mutação', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await page.goto('/app/clientes');
    await expect(
      page.getByRole('heading', { name: 'Clientes, partes e vínculos' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar cliente' })
    ).not.toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar parte' })
    ).not.toBeVisible();
  });

  test('auditor não acessa o fluxo operacional', async ({ page }) => {
    await login(page, 'auditor@example.test');
    await page.goto('/app/clientes');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });

  test('homônimos são explicitamente mantidos como entidades distintas', async ({
    page,
  }) => {
    await login(page, 'owner@example.test');
    await page.goto('/app/clientes');
    await expect(
      page.getByText(/Nomes iguais permanecem registros distintos/)
    ).toBeVisible();
  });
});

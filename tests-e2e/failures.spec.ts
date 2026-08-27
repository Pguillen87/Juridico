import { expect, test, type Page } from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

test.describe('Fase 11 — central de falhas', () => {
  test('lawyer acessa a central vazia e aplica filtro server-side por tentativa', async ({
    page,
  }) => {
    await login(page, 'lawyer@example.test');
    await page.goto('/app/falhas');
    await expect(
      page.getByRole('heading', { name: 'Central de falhas' })
    ).toBeVisible();
    await expect(page.getByLabel('Tentativa')).toBeVisible();
    await expect(
      page.getByText('Nenhuma falha corresponde aos filtros informados.')
    ).toBeVisible();

    await page.getByLabel('Tentativa').selectOption('2');
    await page.getByRole('button', { name: 'Aplicar filtros' }).click();
    await expect(page).toHaveURL(/\/app\/falhas\?.*attempt=2/);
    await expect(page.getByLabel('Tentativa')).toHaveValue('2');
    await expect(
      page.getByText('Nenhuma falha corresponde aos filtros informados.')
    ).toBeVisible();
  });

  test('reviewer consulta a central sem controles de tratamento', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await page.goto('/app/falhas');
    await expect(
      page.getByRole('heading', { name: 'Central de falhas' })
    ).toBeVisible();
    await expect(
      page.getByText('Tratamento operacional disponível no detalhe;')
    ).toHaveCount(0);
  });

  test('auditor não acessa a central operacional', async ({ page }) => {
    await login(page, 'auditor@example.test');
    await page.goto('/app/falhas');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });
});

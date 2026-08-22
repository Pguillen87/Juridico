import { expect, test, type Page } from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app$/);
}

function acceptNextConfirmation(page: Page) {
  page.once('dialog', (dialog) => dialog.accept());
}

function userRow(page: Page, name: string) {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return page.getByRole('row').filter({
    has: page.getByRole('cell', {
      name: new RegExp(`^${escapedName}(?: \\(Você\\))?$`),
    }),
  });
}

test.describe('Administração 4C local', () => {
  test.describe.configure({ mode: 'serial' });

  test('owner acessa usuários, configurações e auditoria administrativa', async ({
    page,
  }) => {
    await login(page, 'owner@example.test');

    await page.getByRole('link', { name: 'Gerenciar usuários' }).click();
    await expect(page).toHaveURL(/\/app\/usuarios$/);
    await expect(
      page.getByRole('heading', { name: 'Usuários do escritório' })
    ).toBeVisible();
    await expect(page.getByText('Lawyer E2E')).toBeVisible();
    await expect(page.getByText('Owner Operator E2E')).toBeVisible();
    await expect(userRow(page, 'Auditor E2E')).toBeVisible();

    await page
      .getByRole('link', { name: 'Configurações do escritório' })
      .first()
      .click();
    await expect(page).toHaveURL(/\/app\/configuracoes$/);
    await expect(
      page.getByRole('heading', { name: 'Configurações do escritório' })
    ).toBeVisible();

    await page
      .getByRole('link', { name: 'Auditoria administrativa' })
      .first()
      .click();
    await expect(page).toHaveURL(/\/app\/auditoria-administrativa$/);
    await expect(
      page.getByRole('heading', { name: 'Auditoria administrativa' })
    ).toBeVisible();
  });

  test('non-owner recebe deny nas telas de gestão, mas auditor lê audit administrativo', async ({
    page,
  }) => {
    await login(page, 'operator@example.test');
    await page.goto('/app/usuarios');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
    await page.goto('/app/configuracoes');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);

    await page.getByRole('button', { name: 'Sair' }).click();
    await expect(page).toHaveURL(/\/login$/);
    await login(page, 'auditor@example.test');
    await expect(
      page.getByRole('link', { name: 'Auditoria administrativa' })
    ).toBeVisible();
    await page.goto('/app/auditoria-administrativa');
    await expect(page).toHaveURL(/\/app\/auditoria-administrativa$/);
    await expect(
      page.getByRole('heading', { name: 'Auditoria administrativa' })
    ).toBeVisible();
  });

  test('owner altera role, status e capacidade sem alterar o próprio perfil', async ({
    page,
  }) => {
    await login(page, 'owner@example.test');
    await page.goto('/app/usuarios');

    const lawyerRow = userRow(page, 'Lawyer E2E');
    acceptNextConfirmation(page);
    await lawyerRow
      .getByLabel('Alterar papel funcional')
      .selectOption('reviewer');
    await expect(lawyerRow.getByText('Alteração salva.')).toBeVisible();

    const reviewerRow = userRow(page, 'Reviewer E2E');
    acceptNextConfirmation(page);
    await reviewerRow.getByRole('button', { name: 'Inativar' }).click();
    await expect(reviewerRow.getByText('Alteração salva.')).toBeVisible();

    const auditorRow = userRow(page, 'Auditor E2E');
    acceptNextConfirmation(page);
    await auditorRow.getByRole('button', { name: 'Conceder owner' }).click();
    await expect(auditorRow.getByText('Alteração salva.')).toBeVisible();

    const ownerRow = userRow(page, 'Owner E2E');
    await expect(
      ownerRow.getByRole('button', { name: /owner/ })
    ).toBeDisabled();
    await expect(ownerRow.getByLabel('Alterar papel funcional')).toBeDisabled();
  });

  test('owner altera somente o nome do office e exporta audit com confirmação', async ({
    page,
  }) => {
    await login(page, 'owner@example.test');
    await page.goto('/app/configuracoes');
    const name = `Escritório E2E Atualizado ${Date.now()}`;
    await page.getByLabel('Nome do escritório').fill(name);
    await page.getByRole('button', { name: 'Salvar nome' }).click();
    await expect(page.getByRole('status')).toContainText(
      'Nome do escritório atualizado'
    );

    await page.goto('/app/auditoria-administrativa');
    await expect(page.getByText('office.rename')).toBeVisible();
    acceptNextConfirmation(page);
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Exportar CSV' }).click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toBe('auditoria-administrativa.csv');
  });
});

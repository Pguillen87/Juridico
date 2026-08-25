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
  await page.goto('/app/clientes');
  await expect(
    page.getByRole('heading', { name: 'Clientes, partes e vínculos' })
  ).toBeVisible();
}

test.describe('Clientes e vínculos — fluxos reais Phase 5', () => {
  test.describe.configure({ mode: 'serial' });

  test('lawyer cria cliente, party, relação pending, confirma e rejeita outra', async ({
    page,
  }) => {
    const suffix = Date.now().toString();
    const clientName = `Cliente E2E ${suffix}`;
    const partyName = `Relacionado E2E ${suffix}`;
    const rejectedName = `Rejeitado E2E ${suffix}`;
    await login(page, 'lawyer@example.test');
    await openClients(page);

    await page.getByRole('button', { name: 'Criar cliente' }).click();
    await page.getByLabel('Nome').first().fill(clientName);
    await page.getByLabel('Tipo').first().selectOption('person');
    await page.getByRole('button', { name: 'Criar cliente' }).click();
    const clientArticle = page
      .locator('article')
      .filter({ hasText: clientName })
      .first();
    await expect(
      clientArticle.getByText(clientName, { exact: true })
    ).toBeVisible();

    await page.getByRole('button', { name: 'Criar parte' }).click();
    await page.getByLabel('Nome').nth(1).fill(partyName);
    await page.getByLabel('Tipo').nth(1).selectOption('person');
    await page.getByRole('button', { name: 'Criar parte' }).click();
    await expect(page.getByText(partyName, { exact: true })).toBeVisible();

    const partyOption = clientArticle
      .getByLabel('Parte relacionada')
      .locator('option')
      .filter({ hasText: partyName })
      .first();
    await clientArticle
      .getByLabel('Parte relacionada')
      .selectOption((await partyOption.getAttribute('value')) as string);
    await clientArticle
      .getByRole('button', { name: 'Criar relação pendente' })
      .click();
    await expect(
      clientArticle.getByText('confirmação: Pendente')
    ).toBeVisible();
    await clientArticle.getByRole('button', { name: 'Confirmar' }).click();
    await expect(
      clientArticle.getByText('confirmação: Confirmada')
    ).toBeVisible();

    await page.getByRole('button', { name: 'Criar parte' }).click();
    await page.getByLabel('Nome').nth(1).fill(rejectedName);
    await page.getByLabel('Tipo').nth(1).selectOption('person');
    await page.getByRole('button', { name: 'Criar parte' }).click();
    await expect(page.getByText(rejectedName, { exact: true })).toBeVisible();
    const rejectedOption = clientArticle
      .getByLabel('Parte relacionada')
      .locator('option')
      .filter({ hasText: rejectedName })
      .first();
    await clientArticle
      .getByLabel('Parte relacionada')
      .selectOption((await rejectedOption.getAttribute('value')) as string);
    await clientArticle
      .getByRole('button', { name: 'Criar relação pendente' })
      .click();
    await expect(
      clientArticle.getByText('confirmação: Pendente')
    ).toBeVisible();
    await clientArticle.getByRole('button', { name: 'Rejeitar' }).click();
    await expect(
      clientArticle.getByText('confirmação: Rejeitada')
    ).toBeVisible();
  });

  test('operator pode criar relação mas não recebe confirmação/rejeição', async ({
    page,
  }) => {
    await login(page, 'operator@example.test');
    await openClients(page);
    await expect(
      page.getByRole('button', { name: 'Criar cliente' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar relação pendente' }).first()
    ).toBeVisible();
    await expect(page.getByRole('button', { name: 'Confirmar' })).toHaveCount(
      0
    );
    await expect(page.getByRole('button', { name: 'Rejeitar' })).toHaveCount(0);
  });

  test('reviewer lê dados mas não possui controles de mutação', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await openClients(page);
    await expect(
      page.getByRole('button', { name: 'Criar cliente' })
    ).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Criar parte' })).toHaveCount(
      0
    );
    await expect(
      page.getByRole('button', { name: 'Criar relação pendente' })
    ).toHaveCount(0);
    await expect(page.getByRole('button', { name: 'Confirmar' })).toHaveCount(
      0
    );
    await expect(page.getByRole('button', { name: 'Rejeitar' })).toHaveCount(0);
  });

  test('auditor não acessa o fluxo operacional', async ({ page }) => {
    await login(page, 'auditor@example.test');
    await page.goto('/app/clientes');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });

  test('homônimos são parties distintas apresentadas com IDs diferentes', async ({
    page,
  }) => {
    const name = `Homônimo E2E ${Date.now()}`;
    await login(page, 'lawyer@example.test');
    await openClients(page);
    for (let i = 0; i < 2; i += 1) {
      await page.getByLabel('Nome').nth(1).fill(name);
      await page.getByLabel('Tipo').nth(1).selectOption('person');
      await page.getByRole('button', { name: 'Criar parte' }).click();
      await expect(
        page.locator('tbody tr td:first-child').filter({ hasText: name })
      ).toHaveCount(i + 1);
    }
    const nameCells = page
      .locator('tbody tr td:first-child')
      .filter({ hasText: name });
    await expect(nameCells).toHaveCount(2);
    const matchingIds = await nameCells.evaluateAll((cells) =>
      cells.map((cell) =>
        cell.parentElement?.querySelectorAll('td')[1]?.textContent?.trim()
      )
    );
    expect(matchingIds[0]).toBeTruthy();
    expect(matchingIds[1]).toBeTruthy();
    expect(matchingIds[0]).not.toBe(matchingIds[1]);
  });
});

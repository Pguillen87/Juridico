import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { expect, test, type Page } from '@playwright/test';

const phase12FixturePath = path.resolve(
  process.cwd(),
  'scripts/bootstrap-phase12-e2e-fixture.mjs'
);

function resetPhase12Fixture() {
  execFileSync(process.execPath, [phase12FixturePath], {
    stdio: 'inherit',
    env: process.env,
  });
}

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';
const clientIds = {
  list: 'd1200000-0000-4000-b000-000000000001',
  review: 'd1200000-0000-4000-b000-000000000002',
  approve: 'd1200000-0000-4000-b000-000000000003',
  cancel: 'd1200000-0000-4000-b000-000000000004',
};

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

async function logout(page: Page) {
  await page.getByRole('button', { name: 'Sair' }).click();
  await expect(page).toHaveURL(/\/login/);
}

test.describe('Relatórios semanais — Fase 12', () => {
  test.beforeEach(() => {
    resetPhase12Fixture();
  });

  test('lawyer filtra server-side por cliente e vê os limites da fase', async ({
    page,
  }) => {
    await login(page, 'lawyer@example.test');
    await page.goto('/app/relatorios');
    await page.getByLabel('Cliente por ID').fill(clientIds.list);
    await page.getByLabel('Status').selectOption('draft');
    await page.getByRole('button', { name: 'Aplicar filtros' }).click();
    await expect(page).toHaveURL(
      /clientId=d1200000-0000-4000-b000-000000000001/
    );
    await expect(
      page.getByText('Cliente d1200000 · período semanal')
    ).toBeVisible();
    await expect(page.locator('article').getByText('Rascunho')).toBeVisible();
    await expect(
      page.getByText('Aprovação não significa envio.')
    ).toBeVisible();
    await expect(page.getByText('PDF')).toHaveCount(0);
    await expect(page.getByText('Enviar')).toHaveCount(0);
  });

  test('reviewer edita, submete, devolve e restaura conteúdo editorial', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await page.goto(`/app/relatorios?clientId=${clientIds.review}`);
    await page.getByRole('link', { name: 'Ver detalhe' }).click();
    await expect(
      page.getByRole('heading', { name: 'Editar conteúdo editorial' })
    ).toBeVisible();
    await page.getByLabel('Observação geral').fill('Nota E2E revisável.');
    await page
      .getByRole('button', { name: 'Criar nova versão editorial' })
      .click();
    await expect(
      page.getByText('Nova versão editorial criada.', { exact: false })
    ).toBeVisible();
    await page.getByRole('button', { name: 'Submeter para revisão' }).click();
    await expect(
      page.getByText('Relatório enviado para revisão.')
    ).toBeVisible();
    await page.getByRole('button', { name: 'Devolver para edição' }).click();
    await expect(
      page.getByText('Relatório devolvido para edição.')
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Histórico de versões' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Restaurar conteúdo editorial' })
    ).toBeVisible();
    await page
      .getByRole('button', { name: 'Restaurar conteúdo editorial' })
      .last()
      .click();
    await expect(
      page.getByText('Conteúdo editorial restaurado em uma nova versão.')
    ).toBeVisible();
  });

  test('reviewer não recebe aprovação ou cancelamento', async ({ page }) => {
    await login(page, 'reviewer@example.test');
    await page.goto(`/app/relatorios?clientId=${clientIds.approve}`);
    await page.getByRole('link', { name: 'Ver detalhe' }).click();
    await expect(
      page.getByRole('button', { name: 'Aprovar esta versão' })
    ).toHaveCount(0);
    await expect(
      page.getByRole('button', { name: 'Cancelar relatório' })
    ).toHaveCount(0);
  });

  test('lawyer submete, aprova a versão exata e não envia', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await page.goto(`/app/relatorios?clientId=${clientIds.approve}`);
    await page.getByRole('link', { name: 'Ver detalhe' }).click();
    await page.getByRole('button', { name: 'Submeter para revisão' }).click();
    await expect(
      page.getByText('Relatório enviado para revisão.')
    ).toBeVisible();
    await logout(page);
    await login(page, 'lawyer@example.test');
    await page.goto(`/app/relatorios?clientId=${clientIds.approve}`);
    await page.getByRole('link', { name: 'Ver detalhe' }).click();
    await page.getByRole('button', { name: 'Aprovar esta versão' }).click();
    await expect(
      page.getByText('Versão aprovada com hash recalculado.', { exact: false })
    ).toBeVisible();
    await expect(
      page.getByText('Aprovação registrada para a versão')
    ).toBeVisible();
    await expect(
      page.getByText('Aprovação não significa envio.')
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Aprovar esta versão' })
    ).toHaveCount(0);
  });

  test('lawyer cancela terminalmente e o detalhe bloqueia novas mutações', async ({
    page,
  }) => {
    await login(page, 'lawyer@example.test');
    await page.goto(`/app/relatorios?clientId=${clientIds.cancel}`);
    await page.getByRole('link', { name: 'Ver detalhe' }).click();
    await page.getByLabel('Motivo do cancelamento').selectOption('other');
    await page.getByRole('button', { name: 'Cancelar relatório' }).click();
    await expect(
      page.getByText('Relatório cancelado. O estado é terminal nesta fase.')
    ).toBeVisible();
    await expect(
      page.getByText('Este relatório está cancelado e é terminal nesta fase.')
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Criar nova versão editorial' })
    ).toHaveCount(0);
    await expect(
      page.getByRole('button', { name: 'Cancelar relatório' })
    ).toHaveCount(0);
  });

  test('auditor não acessa a central de relatórios', async ({ page }) => {
    await login(page, 'auditor@example.test');
    await page.goto('/app/relatorios');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });
});

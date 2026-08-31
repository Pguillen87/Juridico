import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { expect, test, type Page } from '@playwright/test';

// Opt-in only: fixture creation is local Supabase/Auth and never contacts a provider.
const enabled = process.env.PHASE13_E2E_FIXTURE === '1';
const reportId =
  process.env.PHASE13_E2E_REPORT_ID ?? 'f1300000-0000-4000-c000-000000000101';
const artifactId =
  process.env.PHASE13_E2E_ARTIFACT_ID ?? 'f1300000-0000-4000-e000-000000000101';
const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';
const fixtureScript = path.resolve(
  process.cwd(),
  'scripts/bootstrap-phase13-e2e-fixture.mjs'
);

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

test.describe('Fase 13 — entrega PDF local', () => {
  test.beforeAll(() => {
    if (enabled)
      execFileSync(process.execPath, [fixtureScript], {
        stdio: 'inherit',
        env: process.env,
      });
  });

  test.beforeEach(({}, testInfo) => {
    if (testInfo.project.name === 'phase13' && !enabled)
      throw new Error('The phase13 project requires PHASE13_E2E_FIXTURE=1.');
    testInfo.skip(
      !enabled,
      'Set PHASE13_E2E_FIXTURE=1 for explicit local synthetic fixtures.'
    );
  });

  test('lawyer sees approved PDF controls and can download the private artifact', async ({
    page,
  }) => {
    await login(page, 'lawyer@example.test');
    await page.goto(`/app/relatorios/${reportId}`);
    await expect(
      page.getByRole('heading', { name: 'Artefato PDF aprovado' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Gerar PDF local' })
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Entrega PDF (F13)' })
    ).toBeVisible();
    await expect(page.getByLabel('Status: pending')).toHaveText('pending');
    await expect(page.getByLabel('Nome exibido')).toBeVisible();
    await expect(page.getByLabel('ID da entrega')).toHaveCount(4);
    await expect(
      page.getByRole('region', { name: 'Entrega PDF (F13)' }).getByRole('alert')
    ).toHaveCount(0);
    const download = await page.evaluate(async (url) => {
      const response = await fetch(url);
      return {
        status: response.status,
        contentType: response.headers.get('content-type'),
      };
    }, `/app/relatorios/${reportId}/artifact/${artifactId}`);
    expect(download.status).toBe(200);
    expect(download.contentType).toContain('application/pdf');
  });

  test('delivery forms expose accessible labels and live status/error regions', async ({
    page,
  }) => {
    await login(page, 'lawyer@example.test');
    await page.goto(`/app/relatorios/${reportId}`);
    const panel = page.getByRole('region', { name: 'Entrega PDF (F13)' });
    await expect(panel.getByLabel('E-mail')).toBeVisible();
    await expect(panel.getByLabel('Resultado confirmado')).toBeVisible();
    await expect(panel.getByLabel('Motivo obrigatório')).toBeVisible();
    await expect(panel.locator('[aria-live="polite"]')).toHaveCount(1);
    await expect(panel.getByText('unknown_outcome')).toBeVisible();
    await expect(
      panel.getByRole('button', { name: 'Confirmar operação' }).first()
    ).toBeEnabled();
  });

  for (const email of [
    'reviewer@example.test',
    'operator@example.test',
    'auditor@example.test',
    'owner-operator@example.test',
    'owner-reviewer@example.test',
    'owner-auditor@example.test',
  ]) {
    test(`${email} cannot see lawyer-only PDF or delivery controls`, async ({
      page,
    }) => {
      await login(page, email);
      await page.goto(`/app/relatorios/${reportId}`);
      await expect(
        page.getByRole('heading', { name: 'Artefato PDF aprovado' })
      ).toHaveCount(0);
      await expect(
        page.getByRole('heading', { name: 'Entrega PDF (F13)' })
      ).toHaveCount(0);
      await expect(
        page.getByRole('button', { name: 'Gerar PDF local' })
      ).toHaveCount(0);
      await expect(page.getByText('Confirmar operação')).toHaveCount(0);
    });
  }
});

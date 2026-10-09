import { expect, test, type Locator, type Page } from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';
let sequence = 0;

async function login(page: Page, email = 'lawyer@example.test') {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

function formatSyntheticCnj(clean: string) {
  return `${clean.slice(0, 7)}-${clean.slice(7, 9)}.${clean.slice(9, 13)}.${clean.slice(13, 14)}.${clean.slice(14, 16)}.${clean.slice(16)}`;
}

function syntheticCnj(origin = '0001') {
  sequence += 1;
  const processSequence = String(
    1000000 + ((Date.now() + sequence) % 8000000)
  ).padStart(7, '0');
  const base = `${processSequence}2026816${origin.padStart(4, '0')}`;
  const checkDigits = String(
    98 - Number((BigInt(base) * BigInt(100)) % BigInt(97))
  ).padStart(2, '0');
  return formatSyntheticCnj(`${processSequence}${checkDigits}${base.slice(7)}`);
}

async function createClient(page: Page, name: string) {
  await page.goto('/app/clientes', { waitUntil: 'networkidle' });
  await page.getByLabel('Nome do cliente').fill(name);
  await page.getByRole('button', { name: 'Criar cliente' }).click();
  const card = page.locator('article').filter({ hasText: name }).first();
  await expect(card.getByText(name, { exact: true })).toBeVisible();
  const href = await card
    .getByRole('link', { name: 'Abrir carteira' })
    .getAttribute('href');
  if (!href) throw new Error(`Carteira não encontrada para ${name}.`);
  const clientId = new URL(href, 'http://localhost').searchParams.get(
    'clientId'
  );
  if (!clientId) throw new Error(`Cliente sem identificador: ${name}.`);
  return { card, clientId };
}

async function openProcessForm(page: Page, clientId: string) {
  await page.goto(`/app/processos?clientId=${clientId}&add=1`, {
    waitUntil: 'networkidle',
  });
  const form = page.getByTestId('process-create-form');
  await expect(form.locator('select[name="clientId"]')).toHaveValue(clientId);
  return form;
}

async function createProcess(
  page: Page,
  clientId: string,
  cnj: string,
  isPublic = true
) {
  const form = await openProcessForm(page, clientId);
  await form.getByLabel('Número CNJ').fill(cnj);
  await form.getByLabel('Tribunal').fill('TJSP');
  await form.getByLabel('Sistema').fill('PJe');
  if (!isPublic) {
    await form.locator('select[name="isPublic"]').selectOption('private');
  }
  await form.getByRole('button', { name: 'Cadastrar processo' }).click();
  const row = page
    .locator(`tr[data-process-cnj="${cnj.replace(/\D/g, '')}"]`)
    .first();
  await expect(row).toBeVisible();
  return row;
}

function processRow(page: Page, cnj: string): Locator {
  return page
    .locator(`tr[data-process-cnj="${cnj.replace(/\D/g, '')}"]`)
    .first();
}

test.describe('Processos — carteira operacional', () => {
  test.describe.configure({ mode: 'serial', timeout: 120_000 });

  test('apresenta a grade como planilha, com células sem agrupamento', async ({
    page,
  }) => {
    await login(page);
    const client = await createClient(page, `Cliente grade ${Date.now()}`);
    const cnj = syntheticCnj('0031');
    await createProcess(page, client.clientId, cnj);

    const table = page.getByTestId('processes-spreadsheet');
    const visibleHeaders = table.locator('thead th:not([hidden])');
    await expect(visibleHeaders).toHaveText([
      'Selecionar',
      'Processo',
      'Cliente',
      'Status do cadastro',
      'Visibilidade',
      'Estado da consulta',
      'Tribunal',
      'Tipo do andamento',
      'Data do andamento',
      'Descrição do andamento',
      'Última consulta',
      'Atualização da fonte',
      'Novas movimentações',
      'Ações',
    ]);

    const row = processRow(page, cnj);
    await expect(row.getByText('Ativo', { exact: true })).toHaveCount(1);
    await expect(row.getByText('Público', { exact: true })).toHaveCount(1);
    await expect(
      row.getByText('Ainda não consultado', { exact: true })
    ).toHaveCount(1);
    await expect(page.getByText(/Partes|vínculos/i)).toHaveCount(0);
    await expect(table.locator('tbody .sticky')).toHaveCount(0);
    await expect(page.getByText('Ver detalhes e movimentações')).toHaveCount(0);

    await page.locator('summary').filter({ hasText: 'Colunas' }).click();
    const systemToggle = page.locator(
      'input[data-portfolio-column-toggle="system"]'
    );
    await expect(systemToggle).not.toBeChecked();
    await systemToggle.check();
    await expect(
      table.locator('thead th[data-portfolio-column="system"]')
    ).toBeVisible();

    await row
      .getByRole('checkbox', { name: `Selecionar processo ${cnj}` })
      .check();
    await expect(
      page.getByText('1 processo(s) selecionado(s)', { exact: true })
    ).toBeVisible();
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Exportar para Excel' }).click();
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toMatch(
      /^carteira-processos-\d{4}-\d{2}-\d{2}\.csv$/
    );

    const viewport = page.getByTestId('processes-spreadsheet-viewport');
    await expect(viewport).toHaveCSS('overflow-x', 'scroll');
    await expect(viewport).toHaveCSS('overflow-y', 'scroll');
    await expect(
      page.getByTestId('processes-spreadsheet-top-scroll')
    ).toBeVisible();

    await row
      .getByRole('link', {
        name: `Abrir histórico do processo ${cnj}`,
      })
      .click();
    await expect(page).toHaveURL(/\/app\/processos\/historico\?cnj=/);
    await expect(
      page.getByRole('heading', { name: 'Histórico do processo', exact: true })
    ).toBeVisible();
    await expect(
      page.getByText('Nenhuma movimentação disponível')
    ).toBeVisible();
    await expect(page.getByText(/Partes|vínculos/i)).toHaveCount(0);
    await page.getByRole('link', { name: 'Voltar para a carteira' }).click();
    await expect(page).toHaveURL(/\/app\/processos$/);
  });

  test('busca, filtra, cadastra sigiloso e mantém ações na última coluna', async ({
    page,
  }) => {
    await login(page);
    const client = await createClient(page, `Cliente filtros ${Date.now()}`);
    const publicCnj = syntheticCnj('0041');
    const privateCnj = syntheticCnj('0042');
    await createProcess(page, client.clientId, publicCnj);
    await createProcess(page, client.clientId, privateCnj, false);

    await page.goto(`/app/processos?clientId=${client.clientId}`, {
      waitUntil: 'networkidle',
    });
    const table = page.getByTestId('processes-spreadsheet');
    await expect(table.locator('tbody tr[data-process-row]')).toHaveCount(2);

    await page.getByLabel('Buscar processo ou cliente').fill(publicCnj);
    await page.getByRole('button', { name: 'Buscar' }).click();
    await expect(table.locator('tbody tr[data-process-row]')).toHaveCount(1);
    await expect(processRow(page, publicCnj)).toBeVisible();

    await page.getByRole('link', { name: 'Limpar' }).click();
    await expect(page).toHaveURL(/\/app\/processos$/);
    const filterForm = page.getByTestId('client-portfolio-filter');
    await filterForm.locator('input[name="q"]').fill('');
    await filterForm
      .locator('select[name="clientId"]')
      .selectOption(client.clientId);
    await filterForm
      .locator('select[name="visibility"]')
      .selectOption('private');
    await page.getByRole('button', { name: 'Buscar' }).click();
    await expect(table.locator('tbody tr[data-process-row]')).toHaveCount(1);
    await expect(processRow(page, privateCnj)).toBeVisible();
    await expect(
      processRow(page, privateCnj).getByRole('button', {
        name: 'Atualizar agora',
      })
    ).toHaveCount(0);
    await expect(
      processRow(page, privateCnj).getByRole('cell', {
        name: 'Sigiloso',
        exact: true,
      })
    ).toBeVisible();
    await expect(
      processRow(page, privateCnj).getByRole('button', {
        name: 'Excluir processo',
      })
    ).toBeVisible();
  });

  test('importação CSV fica em uma área secundária', async ({ page }) => {
    await login(page);
    await page.goto('/app/processos');
    await expect(
      page.getByRole('heading', { name: 'Importar carteira CSV' })
    ).toHaveCount(0);
    await page.getByRole('link', { name: 'Importar carteira' }).click();
    await expect(
      page.getByRole('heading', { name: 'Importar carteira CSV' })
    ).toBeVisible();
    await expect(
      page.getByRole('link', { name: 'Voltar para a carteira' })
    ).toBeVisible();
  });

  test('mostra atualização de todos ao filtrar um cliente', async ({
    page,
  }) => {
    await login(page);
    const client = await createClient(
      page,
      `Cliente atualizar tudo ${Date.now()}`
    );
    await page.goto(`/app/processos?clientId=${client.clientId}`, {
      waitUntil: 'networkidle',
    });
    await expect(
      page.getByRole('button', { name: 'Atualizar todos' })
    ).toBeVisible();
  });

  test('reviewer lê processos sem controles de mutação e auditor é bloqueado', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await page.goto('/app/processos');
    await expect(
      page.getByRole('heading', { name: 'Processos', exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Cadastrar processo' })
    ).toHaveCount(0);
    await expect(
      page.getByRole('link', { name: 'Importar carteira' })
    ).toHaveCount(0);

    await login(page, 'auditor@example.test');
    await page.goto('/app/processos');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });

  test('processo pode ser excluído da carteira sem apagar o histórico', async ({
    page,
  }) => {
    await login(page);
    const client = await createClient(page, `Cliente exclusão ${Date.now()}`);
    const cnj = syntheticCnj('0051');
    const row = await createProcess(page, client.clientId, cnj);

    page.once('dialog', (dialog) => dialog.accept());
    await row.getByRole('button', { name: 'Excluir processo' }).click();
    await expect(row.getByText('Inativo', { exact: true })).toBeVisible();
    await page.reload({ waitUntil: 'networkidle' });
    await expect(processRow(page, cnj)).toBeVisible();
    await expect(
      processRow(page, cnj).getByText('Inativo', { exact: true })
    ).toBeVisible();
    await expect(
      processRow(page, cnj).getByRole('button', { name: 'Atualizar agora' })
    ).toHaveCount(0);
  });
});

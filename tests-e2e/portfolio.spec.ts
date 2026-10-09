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

function syntheticCnj(origin: string) {
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
  await page.locator('input[name="displayName"]').first().fill(name);
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
  if (!clientId)
    throw new Error(`Cliente sem identificador de navegação: ${name}.`);
  return { card, clientId };
}

async function createProcess(
  page: Page,
  clientId: string,
  cnj: string,
  isPublic = true
) {
  await page.goto(`/app/processos?clientId=${clientId}&add=1`, {
    waitUntil: 'networkidle',
  });
  const form = page.getByTestId('process-create-form');
  await expect(form.locator('select[name="clientId"]')).toHaveValue(clientId);
  await form.getByLabel('Número CNJ').fill(cnj);
  await form.getByLabel('Tribunal').fill('TJSP');
  await form.getByLabel('Sistema').fill('PJe');
  if (!isPublic) {
    await page.locator('select[name="isPublic"]').selectOption('private');
  }
  await page.getByRole('button', { name: 'Cadastrar processo' }).click();
  const canonical = cnj.replace(/\D/g, '');
  const card = page.locator(`tr[data-process-cnj="${canonical}"]`).first();
  await expect(card).toBeVisible();
  return card;
}

function processCard(page: Page, cnj: string): Locator {
  return page
    .locator(`tr[data-process-cnj="${cnj.replace(/\D/g, '')}"]`)
    .first();
}

async function refreshUntilState(card: Locator, stateText: string | RegExp) {
  await card.getByRole('button', { name: 'Atualizar agora' }).click();
  await expect(card.getByText(stateText)).toBeVisible({ timeout: 30_000 });
}

test.describe('Carteira do cliente e consulta individual R1', () => {
  test.describe.configure({ mode: 'serial', timeout: 120_000 });

  test('apresenta a carteira como uma grade comparável com colunas e rolagem', async ({
    page,
  }) => {
    await login(page);
    const suffix = `${Date.now()}-spreadsheet`;
    const { clientId } = await createClient(page, `Carteira grade ${suffix}`);
    const cnj = syntheticCnj('0031');

    await createProcess(page, clientId, cnj);
    await page.goto(`/app/processos?clientId=${clientId}`, {
      waitUntil: 'networkidle',
    });

    const table = page.getByTestId('processes-spreadsheet');
    const expectedHeaders = [
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
    ];

    await expect(table.locator('thead th:not([hidden])')).toHaveText(
      expectedHeaders
    );
    await expect(table.locator('tbody tr[data-process-row]')).toHaveCount(1);
    const row = table.locator('tbody tr[data-process-row]').first();
    await expect(row.getByText('Ativo', { exact: true })).toHaveCount(1);
    await expect(row.getByText('Público', { exact: true })).toHaveCount(1);
    await expect(
      row.getByText('Ainda não consultado', { exact: true })
    ).toHaveCount(1);
    await expect(page.getByText('Criar vínculo pendente')).toHaveCount(0);
    await expect(table.locator('tbody .sticky')).toHaveCount(0);
    await expect(page.getByText('Ver detalhes e movimentações')).toHaveCount(0);

    await row
      .getByRole('checkbox', {
        name: `Selecionar processo ${cnj}`,
      })
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
    await expect(viewport).toBeVisible();
    await expect(viewport).toHaveCSS('overflow-x', 'scroll');
    await expect(viewport).toHaveCSS('overflow-y', 'scroll');
  });

  test('remove um processo da carteira sem apagar seu histórico', async ({
    page,
  }) => {
    await login(page);
    const suffix = `${Date.now()}-deactivation`;
    const clientName = `Carteira exclusão ${suffix}`;
    const { clientId } = await createClient(page, clientName);
    const cnj = syntheticCnj('0044');
    const row = await createProcess(page, clientId, cnj);

    page.once('dialog', (dialog) => dialog.accept());
    await row.getByRole('button', { name: 'Excluir processo' }).click();
    await expect(row.getByText('Inativo', { exact: true })).toBeVisible();

    await page.reload({ waitUntil: 'networkidle' });
    await expect(processCard(page, cnj)).toBeVisible();
    await expect(
      processCard(page, cnj).getByText('Inativo', { exact: true })
    ).toBeVisible();
    await expect(
      processCard(page, cnj).getByRole('button', { name: 'Atualizar agora' })
    ).toHaveCount(0);
    await page.goto(`/app/clientes?clientId=${clientId}`, {
      waitUntil: 'networkidle',
    });
    await expect(
      page
        .locator('article')
        .filter({ hasText: clientName })
        .first()
        .getByText('0 processo(s)', { exact: false })
    ).toBeVisible();
  });

  test('cliente mostra quantidade, lista, isolamento e cadastro pré-selecionado', async ({
    page,
  }) => {
    await login(page);
    const suffix = Date.now().toString();
    const first = await createClient(page, `Carteira principal ${suffix}`);
    await createClient(page, `Carteira isolada ${suffix}`);
    const firstCnj = syntheticCnj('0020');
    const secondCnj = syntheticCnj('0021');

    await createProcess(page, first.clientId, firstCnj);
    await createProcess(page, first.clientId, secondCnj);

    await page.goto('/app/clientes', { waitUntil: 'networkidle' });
    const firstCard = page
      .locator('article')
      .filter({ hasText: `Carteira principal ${suffix}` })
      .first();
    const secondCard = page
      .locator('article')
      .filter({ hasText: `Carteira isolada ${suffix}` })
      .first();
    const secondHref = await secondCard
      .getByRole('link', { name: 'Abrir carteira' })
      .getAttribute('href');
    if (!secondHref) throw new Error('Carteira isolada sem link.');
    await expect(
      firstCard.getByText('2 processo(s)', { exact: false })
    ).toBeVisible();
    await expect(
      secondCard.getByText('0 processo(s)', { exact: false })
    ).toBeVisible();

    await firstCard.getByRole('link', { name: 'Adicionar processo' }).click();
    await expect(page).toHaveURL(
      new RegExp(`/app/processos\\?clientId=${first.clientId}.*add=1`)
    );
    await expect(
      page.getByTestId('process-create-form').locator('select[name="clientId"]')
    ).toHaveValue(first.clientId);

    await page.goto(`/app/processos?clientId=${first.clientId}`, {
      waitUntil: 'networkidle',
    });
    await expect(
      page
        .getByTestId('processes-spreadsheet')
        .locator('tbody tr[data-process-row]')
    ).toHaveCount(2);
    await page.goto(secondHref, { waitUntil: 'networkidle' });
    await expect(
      page
        .getByTestId('processes-spreadsheet')
        .locator('tbody tr[data-process-row]')
    ).toHaveCount(0);

    await page.goto('/app/relatorios', { waitUntil: 'networkidle' });
    await expect(
      page
        .getByLabel('Cliente')
        .locator('option', { hasText: `Carteira principal ${suffix}` })
    ).toHaveCount(1);
  });

  test('consulta individual cobre primeira observação, ausência, novidade, falha, retry e revisão', async ({
    page,
  }) => {
    await login(page);
    const suffix = `${Date.now()}-states`;
    const { clientId } = await createClient(page, `Carteira estados ${suffix}`);
    const unchangedCnj = syntheticCnj('0022');
    const changedCnj = syntheticCnj('0009');
    const failureCnj = syntheticCnj('0007');
    const reviewCnj = syntheticCnj('0003');
    const retryCnj = syntheticCnj('0006');
    const sealedCnj = syntheticCnj('0023');

    await createProcess(page, clientId, unchangedCnj);
    await createProcess(page, clientId, changedCnj);
    await createProcess(page, clientId, failureCnj);
    await createProcess(page, clientId, reviewCnj);
    await createProcess(page, clientId, retryCnj);
    await createProcess(page, clientId, sealedCnj, false);

    await page.goto(`/app/processos?clientId=${clientId}`, {
      waitUntil: 'networkidle',
    });

    const unchangedCard = processCard(page, unchangedCnj);
    await refreshUntilState(unchangedCard, 'Primeira consulta');
    await refreshUntilState(unchangedCard, 'Sem novidade');

    const changedCard = processCard(page, changedCnj);
    await refreshUntilState(changedCard, 'Primeira consulta');
    await refreshUntilState(changedCard, 'Com novidades');

    const failureCard = processCard(page, failureCnj);
    await refreshUntilState(failureCard, 'Falha na consulta');

    const reviewCard = processCard(page, reviewCnj);
    await refreshUntilState(reviewCard, 'Revisão necessária');

    const retryCard = processCard(page, retryCnj);
    await refreshUntilState(retryCard, 'Falha na consulta');
    await expect(
      retryCard.getByText('Sem novidade', { exact: true })
    ).toHaveCount(0);

    const sealedCard = processCard(page, sealedCnj);
    await expect(
      sealedCard.getByRole('button', { name: 'Atualizar agora' })
    ).toHaveCount(0);
    await expect(
      page.getByText(
        /provider_id|datajud_sandbox|Sandbox|query_job|worker|lease|snapshot/i
      )
    ).toHaveCount(0);
  });

  test('atualiza a carteira em lote e exibe metadados e histórico sob demanda', async ({
    page,
  }) => {
    await login(page);
    const suffix = `${Date.now()}-batch`;
    const { clientId } = await createClient(page, `Carteira em lote ${suffix}`);
    const changedCnj = syntheticCnj('0009');
    const exactCnj = syntheticCnj('0024');

    await createProcess(page, clientId, changedCnj);
    await createProcess(page, clientId, exactCnj);
    await page.goto('/app/clientes', { waitUntil: 'networkidle' });

    const card = page
      .locator('article')
      .filter({ hasText: `Carteira em lote ${suffix}` })
      .first();
    await expect(
      card.getByRole('button', { name: 'Atualizar carteira' })
    ).toBeVisible();
    await card.getByRole('button', { name: 'Atualizar carteira' }).click();
    await expect(card.getByText(/Carteira atualizada:/)).toBeVisible({
      timeout: 45_000,
    });
    await expect(card.getByText(/2 processo\(s\)/)).toBeVisible();

    await page.goto(`/app/processos?clientId=${clientId}`, {
      waitUntil: 'networkidle',
    });
    const table = page.getByTestId('processes-spreadsheet');
    await expect(table.locator('tbody tr[data-process-row]')).toHaveCount(2);
    await expect(
      table.getByText('Primeira consulta', { exact: true })
    ).toHaveCount(2);
    await expect(
      table.getByText('Movimentação sintética inicial').first()
    ).toBeVisible();

    await processCard(page, changedCnj)
      .getByRole('link', { name: `Abrir histórico do processo ${changedCnj}` })
      .click();
    await expect(
      page.getByRole('heading', { name: 'Histórico do processo', exact: true })
    ).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Movimentações', exact: true })
    ).toBeVisible();
    await expect(
      page.getByText('Movimentação sintética inicial').first()
    ).toBeVisible();
    await expect(
      page.getByRole('columnheader', { name: 'Tipo do andamento' })
    ).toBeVisible();
    await expect(page.getByText(/Partes|vínculos/i)).toHaveCount(0);
    await page.getByRole('link', { name: 'Voltar para a carteira' }).click();
    await expect(page).toHaveURL(/\/app\/processos$/);

    await page.goto('/app/clientes', { waitUntil: 'networkidle' });
    const refreshedCard = page
      .locator('article')
      .filter({ hasText: `Carteira em lote ${suffix}` })
      .first();

    await refreshedCard
      .getByRole('button', { name: 'Atualizar carteira' })
      .click();
    await expect(
      refreshedCard.getByRole('status').filter({ hasText: /1 com novidade/ })
    ).toBeVisible({
      timeout: 45_000,
    });

    await page.goto(`/app/processos?clientId=${clientId}`, {
      waitUntil: 'networkidle',
    });
    await expect(
      page.getByTestId('processes-spreadsheet').getByText('Com novidades', {
        exact: true,
      })
    ).toHaveCount(1);
    await expect(
      page.getByTestId('processes-spreadsheet').getByText('1', { exact: true })
    ).toBeVisible();
    await expect(
      page.getByText(
        /provider_id|datajud_sandbox|Sandbox|query_job|worker|lease|snapshot|UUID/i
      )
    ).toHaveCount(0);
  });
});

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
  const processSequence = String(1000000 + sequence).padStart(7, '0');
  const base = `${processSequence}2026816${origin.padStart(4, '0')}`;
  const checkDigits = String(
    98 - Number((BigInt(base) * BigInt(100)) % BigInt(97))
  ).padStart(2, '0');
  return formatSyntheticCnj(`${processSequence}${checkDigits}${base.slice(7)}`);
}

async function createClient(page: Page, name: string) {
  await page.goto('/app/clientes', { waitUntil: 'networkidle' });
  await page.locator('input[name="displayName"]').first().fill(name);
  await page.locator('select[name="partyType"]').first().selectOption('person');
  await page.getByRole('button', { name: 'Criar cliente' }).click();

  const card = page.locator('article').filter({ hasText: name }).first();
  await expect(card.getByText(name, { exact: true })).toBeVisible();
  const href = await card
    .getByRole('link', { name: 'Ver processos' })
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
  await page.goto(`/app/processos?clientId=${clientId}`, {
    waitUntil: 'networkidle',
  });
  await expect(page.locator('select[name="clientId"]')).toHaveValue(clientId);
  await page.getByLabel('Número CNJ').fill(cnj);
  await page.getByLabel('Tribunal').fill('TJSP');
  await page.getByLabel('Sistema').fill('PJe');
  if (!isPublic) {
    await page.locator('select[name="isPublic"]').selectOption('private');
  }
  await page.getByRole('button', { name: 'Cadastrar processo' }).click();
  const canonical = cnj.replace(/\D/g, '');
  const card = page.locator('article').filter({ hasText: canonical }).first();
  await expect(card).toBeVisible();
  return card;
}

function processCard(page: Page, cnj: string): Locator {
  return page
    .locator('article')
    .filter({ hasText: cnj.replace(/\D/g, '') })
    .first();
}

async function refreshUntilState(card: Locator, stateText: string | RegExp) {
  await card.getByRole('button', { name: 'Atualizar agora' }).click();
  await expect(card.getByText(stateText)).toBeVisible({ timeout: 30_000 });
}

test.describe('Carteira do cliente e consulta individual R1', () => {
  test.describe.configure({ mode: 'serial' });

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
    await expect(
      firstCard.getByText('2 processo(s)', { exact: false })
    ).toBeVisible();
    await expect(
      firstCard.getByText(firstCnj.replace(/\D/g, ''))
    ).toBeVisible();
    await expect(
      firstCard.getByText(secondCnj.replace(/\D/g, ''))
    ).toBeVisible();
    await expect(
      secondCard.getByText('0 processo(s)', { exact: false })
    ).toBeVisible();

    await firstCard.getByRole('link', { name: 'Adicionar processo' }).click();
    await expect(page).toHaveURL(
      new RegExp(`/app/processos\\?clientId=${first.clientId}`)
    );
    await expect(page.locator('select[name="clientId"]')).toHaveValue(
      first.clientId
    );

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
    await refreshUntilState(
      unchangedCard,
      'Primeira consulta concluída — 1 movimentações disponíveis.'
    );
    await refreshUntilState(
      unchangedCard,
      'Sem novas movimentações desde a última consulta.'
    );

    const changedCard = processCard(page, changedCnj);
    await refreshUntilState(
      changedCard,
      'Primeira consulta concluída — 1 movimentações disponíveis.'
    );
    await refreshUntilState(
      changedCard,
      '1 novas movimentações desde a última consulta.'
    );

    const failureCard = processCard(page, failureCnj);
    await refreshUntilState(
      failureCard,
      'Não foi possível concluir a consulta.'
    );

    const reviewCard = processCard(page, reviewCnj);
    await refreshUntilState(
      reviewCard,
      'Encontramos uma inconsistência nos dados da fonte. É necessária revisão.'
    );

    const retryCard = processCard(page, retryCnj);
    await refreshUntilState(retryCard, 'Não foi possível concluir a consulta.');
    await expect(retryCard.getByText(/Sem novas movimentações/)).toHaveCount(0);

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
});

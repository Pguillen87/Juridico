import { expect, test, type Locator, type Page } from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';

async function login(page: Page, email: string) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).toHaveURL(/\/app/);
}

async function createClientAndParty(
  page: Page,
  clientName: string,
  partyName: string
) {
  await page.goto('/app/clientes');
  await expect(
    page.getByRole('heading', { name: 'Clientes, partes e vínculos' })
  ).toBeVisible();
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
  const partyRow = page
    .locator('tbody tr')
    .filter({ hasText: partyName })
    .first();
  await expect(partyRow.getByText(partyName, { exact: true })).toBeVisible();
}

async function selectOptionByText(select: Locator, text: string) {
  const option = select.locator('option').filter({ hasText: text }).first();
  await expect(option).toHaveCount(1, { timeout: 10_000 });
  const value = await option.getAttribute('value');
  if (!value) throw new Error(`Opção não encontrada: ${text}`);
  await select.selectOption(value);
}

function formatSyntheticCnj(clean: string) {
  return `${clean.slice(0, 7)}-${clean.slice(7, 9)}.${clean.slice(9, 13)}.${clean.slice(13, 14)}.${clean.slice(14, 16)}.${clean.slice(16)}`;
}

function syntheticCnj() {
  const sequence = String(1000000 + (Date.now() % 8000000)).padStart(7, '0');
  const base = `${sequence}20268160000`;
  const digits = String(
    98 - Number((BigInt(base) * BigInt(100)) % BigInt(97))
  ).padStart(2, '0');
  return formatSyntheticCnj(`${sequence}${digits}20268160000`);
}

function invalidSyntheticCnj() {
  const clean = syntheticCnj().replace(/\D/g, '');
  return formatSyntheticCnj(`${clean.slice(0, 7)}00${clean.slice(9)}`);
}

async function openProcesses(page: Page) {
  await page.goto('/app/processos', { waitUntil: 'networkidle' });
  await page.reload({ waitUntil: 'networkidle' });
  await expect(
    page.getByRole('heading', { name: 'Processos e importação CSV' })
  ).toBeVisible();
}

test.describe('Fase 6 — processos, vínculos e CSV', () => {
  test.describe.configure({ mode: 'serial' });

  test('lawyer cria processo, vínculo pending e executa confirmação e rejeição', async ({
    page,
  }) => {
    const suffix = Date.now().toString();
    const clientName = `Cliente Processo E2E ${suffix}`;
    const partyName = `Parte Processo E2E ${suffix}`;
    const rejectedName = `Parte Rejeitada E2E ${suffix}`;
    const processCnj = syntheticCnj();
    const processCanonical = processCnj.replace(/\D/g, '');
    await login(page, 'lawyer@example.test');
    await createClientAndParty(page, clientName, partyName);
    await openProcesses(page);

    await selectOptionByText(
      page.locator('select[name="clientId"]'),
      clientName
    );
    await page.getByLabel('Número CNJ').fill(processCnj);
    await page.getByLabel('Tribunal').fill('TJPR');
    await page.getByLabel('Sistema').fill('PJe');
    await page.getByRole('button', { name: 'Cadastrar processo' }).click();
    const processArticle = page
      .locator('article')
      .filter({ hasText: processCanonical })
      .first();
    await expect(processArticle).toBeVisible();
    await expect(
      processArticle.getByText('Monitoramento: paused')
    ).toBeVisible();

    await selectOptionByText(processArticle.getByLabel('Parte'), partyName);
    await processArticle.getByLabel('Papel').selectOption('plaintiff');
    await processArticle
      .getByRole('button', { name: 'Criar vínculo pendente' })
      .click();
    await expect(
      processArticle.getByText('confirmação: Pendente')
    ).toBeVisible();
    await processArticle.getByRole('button', { name: 'Confirmar' }).click();
    await expect(
      processArticle.getByText('confirmação: Confirmado')
    ).toBeVisible();

    await page.goto('/app/clientes');
    await page.getByRole('button', { name: 'Criar parte' }).click();
    await page.getByLabel('Nome').nth(1).fill(rejectedName);
    await page.getByLabel('Tipo').nth(1).selectOption('person');
    await page.getByRole('button', { name: 'Criar parte' }).click();
    await expect(page.getByText(rejectedName, { exact: true })).toBeVisible();
    await openProcesses(page);
    const refreshedProcess = page
      .locator('article')
      .filter({ hasText: processCanonical })
      .first();
    await selectOptionByText(
      refreshedProcess.getByLabel('Parte'),
      rejectedName
    );
    await refreshedProcess.getByLabel('Papel').selectOption('defendant');
    await refreshedProcess
      .getByRole('button', { name: 'Criar vínculo pendente' })
      .click();
    await expect(
      refreshedProcess.getByText('confirmação: Pendente')
    ).toBeVisible();
    await refreshedProcess.getByRole('button', { name: 'Rejeitar' }).click();
    await expect(
      refreshedProcess.getByText('confirmação: Rejeitado')
    ).toBeVisible();
  });

  test('operator cria processo e vínculo pending sem controles terminais', async ({
    page,
  }) => {
    const suffix = Date.now().toString();
    const clientName = `Operator Processo E2E ${suffix}`;
    const partyName = `Operator Parte E2E ${suffix}`;
    const processCnj = syntheticCnj();
    const processCanonical = processCnj.replace(/\D/g, '');
    await login(page, 'operator@example.test');
    await createClientAndParty(page, clientName, partyName);
    await openProcesses(page);
    await selectOptionByText(
      page.locator('select[name="clientId"]'),
      clientName
    );
    await page.getByLabel('Número CNJ').fill(processCnj);
    await page.getByLabel('Tribunal').fill('TJPR');
    await page.getByRole('button', { name: 'Cadastrar processo' }).click();
    const processArticle = page
      .locator('article')
      .filter({ hasText: processCanonical })
      .first();
    await expect(processArticle).toBeVisible();
    await selectOptionByText(processArticle.getByLabel('Parte'), partyName);
    await processArticle
      .getByRole('button', { name: 'Criar vínculo pendente' })
      .click();
    await expect(
      processArticle.getByText('confirmação: Pendente')
    ).toBeVisible();
    await expect(
      processArticle.getByRole('button', { name: 'Confirmar' })
    ).toHaveCount(0);
    await expect(
      processArticle.getByRole('button', { name: 'Rejeitar' })
    ).toHaveCount(0);
  });

  test('lawyer gera preview CSV, mantém ausência antes da confirmação e confirma o batch', async ({
    page,
  }) => {
    const suffix = Date.now().toString();
    const clientName = `CSV Cliente E2E ${suffix}`;
    const partyName = `CSV Parte E2E ${suffix}`;
    const importCnj = syntheticCnj();
    const invalidCnj = invalidSyntheticCnj();
    const importCanonical = importCnj.replace(/\D/g, '');
    await login(page, 'lawyer@example.test');
    await createClientAndParty(page, clientName, partyName);
    await openProcesses(page);
    const header =
      'cnj,cliente,tribunal,sistema,parte,papel,publicidade,monitoramento,observacoes';
    const invalidCsv = [
      header,
      `${invalidCnj},\"${clientName}\",TJPR,PJe,\"${partyName}\",plaintiff,público,pausado,\"linha inválida\"`,
    ].join('\n');
    await page.getByLabel('Arquivo CSV').setInputFiles({
      name: 'processos-invalid.csv',
      mimeType: 'text/csv',
      buffer: Buffer.from(invalidCsv, 'utf8'),
    });
    await page.getByRole('button', { name: 'Gerar prévia' }).click();
    await expect(
      page.getByText('A prévia encontrou erros; nenhuma linha foi gravada.')
    ).toBeVisible();
    await expect(page.getByText(invalidCnj)).toBeVisible();

    const csv = [
      header,
      `${importCnj},\"${clientName}\",TJPR,PJe,\"${partyName}\",plaintiff,público,pausado,\"importação, validada\"`,
    ].join('\n');
    await page.getByLabel('Arquivo CSV').setInputFiles({
      name: 'processos.csv',
      mimeType: 'text/csv',
      buffer: Buffer.from(csv, 'utf8'),
    });
    await page.getByRole('button', { name: 'Gerar prévia' }).click();
    await expect(page.getByText(/Prévia pronta:/)).toBeVisible();
    await expect(
      page.locator('article').filter({ hasText: importCanonical })
    ).toHaveCount(0);
    await page.getByRole('button', { name: 'Confirmar importação' }).click();
    await expect(
      page.getByText(/Importação concluída: 1 processo/)
    ).toBeVisible();
  });

  test('reviewer lê processos mas não recebe formulário de mutação e auditor é bloqueado', async ({
    page,
  }) => {
    await login(page, 'reviewer@example.test');
    await openProcesses(page);
    await expect(
      page.getByRole('heading', { name: 'Processos cadastrados' })
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: 'Cadastrar processo' })
    ).toHaveCount(0);
    await expect(
      page.getByRole('button', { name: 'Gerar prévia' })
    ).toHaveCount(0);
    await login(page, 'auditor@example.test');
    await page.goto('/app/processos');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });
});

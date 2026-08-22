import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

const password = process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';
const mailBaseUrl =
  process.env.JURIDICO_MAIL_CATCHER_URL ?? 'http://127.0.0.1:54324';

async function login(page: Page, email: string, secret = password) {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(secret);
  await page.getByRole('button', { name: 'Entrar' }).click();
}

async function purgeMailbox(request: APIRequestContext) {
  // Supabase CLI 2.115 uses Mailpit locally. The E2E suite is serial and owns
  // this local catcher, so clearing all messages prevents stale latest-message
  // results without relying on a mailbox route that Mailpit does not expose.
  await request.delete(`${mailBaseUrl}/api/v1/messages`);
}

type MailpitMessage = {
  To?: Array<{ Address?: string }>;
  Text?: string;
  HTML?: string;
  body?: { text?: string; html?: string };
};

async function waitForLatestMessage(request: APIRequestContext, email: string) {
  let latest: MailpitMessage | null = null;
  await expect
    .poll(
      async () => {
        const response = await request.get(
          `${mailBaseUrl}/api/v1/message/latest`
        );
        if (!response.ok()) return null;
        const candidate = (await response.json()) as MailpitMessage;
        const recipients = (candidate.To ?? []).map(
          (recipient) => recipient.Address
        );
        latest = recipients.includes(email) ? candidate : null;
        return latest;
      },
      { timeout: 30_000, intervals: [500, 1000, 2000] }
    )
    .not.toBeNull();

  if (!latest) throw new Error('O mail catcher não trouxe uma mensagem.');
  return latest;
}

function extractLink(message: MailpitMessage) {
  const source =
    `${message.Text ?? message.body?.text ?? ''}\n${message.HTML ?? message.body?.html ?? ''}`
      .replaceAll('&amp;', '&')
      .replaceAll('&#x3D;', '=');
  const match = source.match(/https?:\/\/[^\s"'<>]+/);
  if (!match) throw new Error('O mail catcher não trouxe um link navegável.');
  const link = match[0].replace(/[),.;]+$/, '');
  const parsed = new URL(link);
  return `${parsed.pathname}${parsed.search}`;
}

test.describe('Auth funcional local', () => {
  test.describe.configure({ mode: 'serial' });

  test('A: anônimo em /app vai para login e credencial inválida é genérica', async ({
    page,
  }) => {
    await page.goto('/app');
    await expect(page).toHaveURL(/\/login$/);
    await page.getByLabel('E-mail').fill('owner@example.test');
    await page.getByLabel('Senha').fill('senha-incorreta');
    await page.getByRole('button', { name: 'Entrar' }).click();
    await expect(page.locator('form [role="alert"]')).toHaveText(
      'E-mail ou senha incorretos.'
    );
    // Limpa o form para o próximo teste serial
    await page.getByLabel('Senha').fill('');
  });

  test('B-E: owner entra, vê contexto e mantém sessão no refresh', async ({
    page,
  }) => {
    page.on('console', (msg) => console.log('PAGE CONSOLE:', msg.text()));
    page.on('pageerror', (err) => console.log('PAGE ERROR:', err.message));
    page.on('requestfailed', (req) =>
      console.log('REQUEST FAILED:', req.url(), req.failure()?.errorText)
    );
    await login(page, 'owner@example.test');
    await expect(page).toHaveURL(/\/app$/, { timeout: 15000 });
    await expect(
      page.getByRole('heading', { name: /Bem-vindo, Owner E2E/ })
    ).toBeVisible();
    await expect(page.getByText('Escritório E2E Teste')).toBeVisible();
    await expect(page.getByText('Advogado')).toBeVisible();
    await expect(page.getByText('Administrador')).toBeVisible();
    await page.reload();
    await expect(page).toHaveURL(/\/app$/);
  });

  test('F-G: logout remove acesso à área protegida', async ({ page }) => {
    await login(page, 'owner@example.test');
    await page.getByRole('button', { name: 'Sair' }).click();
    await expect(page).toHaveURL(/\/login$/);
    await page.goto('/app');
    await expect(page).toHaveURL(/\/login$/);
  });

  test('H-I: perfil inativo e office inativo são bloqueados', async ({
    page,
  }) => {
    await login(page, 'inactive@example.test');
    await expect(page).toHaveURL(/\/login\?error=inactive$/);
    await expect(page.locator('form [role="alert"]')).toContainText('inativo');

    await login(page, 'office-inactive@example.test');
    await expect(page).toHaveURL(/\/login\?error=inactive$/);
  });

  test('J-M: recovery tem resposta genérica, mail local e reset funcional', async ({
    page,
    request,
  }) => {
    const email = 'recovery@example.test';
    await purgeMailbox(request);
    await page.goto('/esqueci-minha-senha');
    await page.getByLabel('E-mail').fill(email);
    await page.getByRole('button', { name: 'Enviar instruções' }).click();
    await expect(page.getByRole('status')).toContainText(
      'Se existir uma conta'
    );

    const message = await waitForLatestMessage(request, email);
    const link = extractLink(message);
    await page.goto(link);
    await expect(page).toHaveURL(/\/redefinir-senha/);
    await page
      .getByLabel('Nova senha', { exact: true })
      .fill('TestOnly-Recovery-456!');
    await page
      .getByLabel('Confirmar nova senha')
      .fill('TestOnly-Recovery-456!');
    await page.getByRole('button', { name: 'Atualizar senha' }).click();
    await expect(page.getByRole('status')).toContainText('Senha atualizada');
    await page.waitForURL(/\/login\?success=password-reset$/);
    await login(page, email, 'TestOnly-Recovery-456!');
    await expect(page).toHaveURL(/\/app$/);
  });

  test('N-O: owner acessa usuários e non-owner recebe deny server-side', async ({
    page,
  }) => {
    await login(page, 'owner@example.test');
    await page.getByRole('link', { name: 'Gerenciar usuários' }).click();
    await expect(page).toHaveURL(/\/app\/usuarios$/);
    await expect(
      page.getByRole('heading', { name: 'Usuários do escritório' })
    ).toBeVisible();

    await page.goto('/app');
    await page.getByRole('button', { name: 'Sair' }).click();
    await login(page, 'operator@example.test');
    await page.goto('/app/usuarios');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });

  test('Q-U: signup público é negado pela API e callback não aceita type=signup', async ({
    request,
  }) => {
    // Prova 1: A API pública do Supabase Auth deve rejeitar signup
    const publicUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const publicAnonKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    expect(publicUrl).toBeDefined();
    expect(publicAnonKey).toBeDefined();

    const signupResponse = await request.post(`${publicUrl}/auth/v1/signup`, {
      headers: {
        apikey: publicAnonKey as string,
        'Content-Type': 'application/json',
      },
      data: {
        email: 'public-signup-denied@example.test',
        password: 'TestOnly-Signup-123!',
      },
    });

    expect(signupResponse.status()).toBe(403);
    const body = await signupResponse.json();
    expect(body.msg).toMatch(/Signups not allowed/i);

    // Prova 2: O callback não deve aceitar type=signup
    const callbackResponse = await request.get(
      '/auth/callback?token_hash=fake_hash_123&type=signup&next=/app',
      { maxRedirects: 0 }
    );
    expect(callbackResponse.status()).toBe(307);
    expect(callbackResponse.headers().location).toContain(
      '/login?error=auth-code'
    );
  });

  test('V-W: owner convida operator, mail local traz aceite e operator entra sem owner', async ({
    page,
    request,
  }) => {
    const email = 'invited-operator@example.test';
    await purgeMailbox(request);
    await login(page, 'owner@example.test');
    await page.goto('/app/usuarios');
    await page.getByLabel('Nome').fill('Invited Operator');
    await page.getByLabel('E-mail').fill(email);
    await page.getByLabel('Papel').selectOption('operator');
    await page.getByRole('button', { name: 'Enviar convite' }).click();
    await expect(page.getByRole('status')).toContainText('Convite enviado');

    const message = await waitForLatestMessage(request, email);
    const link = extractLink(message);
    await page.goto(link);
    await expect(page).toHaveURL(/\/redefinir-senha/);
    await page
      .getByLabel('Nova senha', { exact: true })
      .fill('TestOnly-Invite-789!');
    await page.getByLabel('Confirmar nova senha').fill('TestOnly-Invite-789!');
    await page.getByRole('button', { name: 'Atualizar senha' }).click();
    await page.waitForURL(/\/login\?success=password-reset$/);
    await login(page, email, 'TestOnly-Invite-789!');
    await expect(page).toHaveURL(/\/app$/);
    await expect(page.getByText('Operador')).toBeVisible();
    await expect(page.getByText('Usuário')).toBeVisible();
    await page.goto('/app/usuarios');
    await expect(page).toHaveURL(/\/app\?error=forbidden$/);
  });

  test('X: não existe fluxo público funcional de signup na interface', async ({
    page,
  }) => {
    const response = await page.goto('/signup');
    // A rota /signup não existe. O servidor deve retornar 404 (Not Found).
    expect(response?.status()).toBe(404);
  });

  test('Y: convite repetido para o mesmo e-mail não duplica usuário nem eleva privilégios', async ({
    page,
    request,
  }) => {
    const email = 'invited-operator@example.test'; // Mesmo e-mail do cenário V-W
    await purgeMailbox(request);
    await login(page, 'owner@example.test');
    await page.goto('/app/usuarios');

    // Tenta convidar novamente com um papel diferente (advogado)
    await page.getByLabel('Nome').fill('Invited Operator Duplicate Attempt');
    await page.getByLabel('E-mail').fill(email);
    await page.getByLabel('Papel').selectOption('lawyer');
    await page.getByRole('button', { name: 'Enviar convite' }).click();

    // A aplicação deve tratar a falha de forma segura sem expor enumeração
    await expect(page.getByRole('alert')).toContainText(
      'Não foi possível convidar este usuário'
    );

    // O usuário não deve ter sido alterado. Ele deve continuar como operator.
    await page.goto('/app');
    await page.getByRole('button', { name: 'Sair' }).click();
    await login(page, email, 'TestOnly-Invite-789!');
    await expect(page).toHaveURL(/\/app$/);
    await expect(page.getByText('Operador')).toBeVisible();
    await expect(page.getByText('Usuário')).toBeVisible();
    await expect(page.getByText('Advogado')).not.toBeVisible();
    await expect(page.getByText('Administrador')).not.toBeVisible();
  });
});

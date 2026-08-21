import { spawnSync } from 'node:child_process';

export function readLocalSupabaseEnv(cwd = process.cwd()) {
  const isWindows = process.platform === 'win32';
  const command = isWindows ? (process.env.ComSpec ?? 'cmd.exe') : 'npx';
  const args = isWindows
    ? ['/d', '/s', '/c', 'npx --no-install supabase status -o env']
    : ['--no-install', 'supabase', 'status', '-o', 'env'];
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  if (result.status !== 0) {
    throw new Error('Não foi possível consultar o status do Supabase local.');
  }

  const values = {};
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
  for (const line of output.split(/\r?\n/)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match) continue;
    values[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
  }
  return values;
}

export function applyLocalSupabaseEnv(values) {
  const mappings = {
    API_URL: 'NEXT_PUBLIC_SUPABASE_URL',
    ANON_KEY: 'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
    SERVICE_ROLE_KEY: 'SUPABASE_SERVICE_ROLE_KEY',
  };

  for (const [source, target] of Object.entries(mappings)) {
    if (values[source]) process.env[target] = values[source];
  }
  process.env.NEXT_PUBLIC_SITE_URL ??= 'http://localhost:3000';
  if (values.INBUCKET_URL)
    process.env.JURIDICO_MAIL_CATCHER_URL = values.INBUCKET_URL;
}

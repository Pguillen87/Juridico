import {
  cpSync,
  existsSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import {
  applyLocalSupabaseEnv,
  readLocalSupabaseEnv,
} from './local-supabase-env.mjs';

const localEnv = readLocalSupabaseEnv();
applyLocalSupabaseEnv(localEnv);

function run(commandLine, command, args) {
  if (process.platform === 'win32') {
    return spawnSync(
      process.env.ComSpec ?? 'cmd.exe',
      ['/d', '/s', '/c', commandLine],
      {
        cwd: process.cwd(),
        env: process.env,
        stdio: 'inherit',
      }
    );
  }

  return spawnSync(command, args, {
    cwd: process.cwd(),
    env: process.env,
    stdio: 'inherit',
  });
}

const envLocalPath = resolve(process.cwd(), '.env.local');
const hadEnvLocal = existsSync(envLocalPath);
const previousEnvLocal = hadEnvLocal
  ? readFileSync(envLocalPath, 'utf8')
  : null;
const envLocalContents = [
  `NEXT_PUBLIC_SUPABASE_URL=${localEnv.API_URL}`,
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${localEnv.ANON_KEY}`,
  'NEXT_PUBLIC_SITE_URL=http://localhost:3000',
  `JURIDICO_E2E_PASSWORD=${process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!'}`,
  '',
].join('\n');

writeFileSync(envLocalPath, envLocalContents, 'utf8');

try {
  const buildRun = run('npm run build', 'npm', ['run', 'build']);
  if (buildRun.error) {
    process.stderr.write(
      `Falha ao iniciar build Auth E2E: ${buildRun.error.message}\n`
    );
    process.exitCode = 1;
  } else if (buildRun.status !== 0) {
    process.exitCode = buildRun.status ?? 1;
  } else {
    const standaloneRoot = resolve(process.cwd(), '.next/standalone');
    const standaloneStatic = resolve(standaloneRoot, '.next/static');
    const staticSource = resolve(process.cwd(), '.next/static');
    if (existsSync(staticSource)) {
      cpSync(staticSource, standaloneStatic, { recursive: true });
    }
    const publicSource = resolve(process.cwd(), 'public');
    if (existsSync(publicSource)) {
      cpSync(publicSource, resolve(standaloneRoot, 'public'), {
        recursive: true,
      });
    }

    const fixtureRun = run('npm run auth:fixtures', 'npm', [
      'run',
      'auth:fixtures',
    ]);
    if (fixtureRun.error) {
      process.stderr.write(
        `Falha ao iniciar fixtures Auth: ${fixtureRun.error.message}\n`
      );
      process.exitCode = 1;
    } else if (fixtureRun.status !== 0) {
      process.exitCode = fixtureRun.status ?? 1;
    } else {
      const reportsFixtureRun = run(
        'node scripts/bootstrap-phase12-e2e-fixture.mjs',
        'node',
        ['scripts/bootstrap-phase12-e2e-fixture.mjs']
      );
      if (reportsFixtureRun.error) {
        process.stderr.write(
          `Falha ao iniciar fixture de relatórios: ${reportsFixtureRun.error.message}\n`
        );
        process.exitCode = 1;
      } else if (reportsFixtureRun.status !== 0) {
        process.exitCode = reportsFixtureRun.status ?? 1;
      } else {
        process.env.PLAYWRIGHT_START_COMMAND =
          'node .next/standalone/server.js';
        process.env.HOSTNAME = 'localhost';
        process.env.PORT = '3000';
        process.env.PLAYWRIGHT_REUSE_SERVER = 'false';
        process.env.JURIDICO_E2E_PASSWORD =
          process.env.JURIDICO_E2E_PASSWORD ?? 'TestOnly-Local-123!';
        process.env.NEXT_PUBLIC_SUPABASE_URL = localEnv.API_URL;
        process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = localEnv.ANON_KEY;
        const e2eRun = run('npx --no-install playwright test', 'npx', [
          '--no-install',
          'playwright',
          'test',
        ]);
        if (e2eRun.error) {
          process.stderr.write(
            `Falha ao iniciar Auth E2E: ${e2eRun.error.message}\n`
          );
          process.exitCode = 1;
        } else {
          process.exitCode = e2eRun.status ?? 1;
        }
      }
    }
  }
} finally {
  if (hadEnvLocal) {
    writeFileSync(envLocalPath, previousEnvLocal, 'utf8');
  } else if (existsSync(envLocalPath)) {
    unlinkSync(envLocalPath);
  }
}

import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTs from 'eslint-config-next/typescript';

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    'node_modules/**',
    'poc/**',
    '.next/**',
    'out/**',
    'build/**',
    'coverage/**',
    'playwright-report/**',
    'test-results/**',
    'next-env.d.ts',
    // Supabase local runtime artifacts only; do not ignore source, migrations or tests.
    'supabase/.temp/**',
    // Separate local checkouts and generated outputs are not application source.
    'Juridico-git-tmp/**',
    'Juridico-phase3-ci-2/**',
    'Juridico-phase8-run/**',
    'Juridico-phase9-run/**',
    'outputs/**',
  ]),
]);

export default eslintConfig;

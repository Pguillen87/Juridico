import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.{ts,tsx}'],
    exclude: ['node_modules', '.next', 'poc', 'tests-e2e'],
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});

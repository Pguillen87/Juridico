import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['**/*.test.{ts,js,mjs}'],
    exclude: ['node_modules'],
    environment: 'node',
  },
});

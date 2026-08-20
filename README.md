# Juridico

Aplicação web para monitoramento automatizado de processos judiciais.

## Fase Atual: 3 - Fundação Técnica

Esta branch (`phase-3-foundation`) contém a fundação técnica do projeto, utilizando Next.js, Tailwind CSS, TypeScript, Zod, Vitest e Playwright, preparada para rodar via Docker.

## Requisitos

- Node.js 22 LTS (ver `.node-version`)
- Docker e Docker Compose (para execução local via contêineres)
- Chave da API do DataJud (para a PoC)

## Instalação Local

1. Clone o repositório.
2. Instale as dependências:
   ```bash
   npm ci
   ```
3. Copie o arquivo de variáveis de ambiente:
   ```bash
   cp .env.example .env.local
   ```
   _Nota: Na Fase 3, as variáveis do Supabase são opcionais._

## Execução via Docker

A aplicação está configurada para rodar localmente utilizando Docker, garantindo reprodutibilidade.

1. Construa e inicie o contêiner:
   ```bash
   docker compose up --build -d
   ```
2. Acesse a aplicação em `http://localhost:3000`.
3. Verifique o health check em `http://localhost:3000/api/health`.
4. Para parar a aplicação:
   ```bash
   docker compose down
   ```

## Scripts Disponíveis

- `npm run dev`: Inicia o servidor de desenvolvimento.
- `npm run build`: Constrói a aplicação para produção.
- `npm run start`: Inicia a aplicação em modo de produção.
- `npm run lint`: Executa o ESLint.
- `npm run format`: Formata o código com Prettier.
- `npm run format:check`: Verifica a formatação do código.
- `npm run typecheck`: Verifica os tipos do TypeScript.
- `npm run test`: Executa os testes unitários com Vitest.
- `npm run e2e`: Executa os testes E2E com Playwright.

## Prova de Conceito (PoC)

A Prova de Conceito (PoC) da integração com a API do DataJud encontra-se no diretório `poc/`. Para executá-la:

1. Acesse o diretório: `cd poc`
2. Instale as dependências: `npm ci`
3. Configure o `.env` dentro da pasta `poc/` com sua `DATAJUD_API_KEY`.
4. Execute os testes: `npm test`

## CI/CD

O projeto utiliza GitHub Actions para Integração Contínua. O workflow `.github/workflows/app-ci.yml` garante que o código passe por verificações de lint, tipagem, testes unitários, testes E2E e build, além de verificar se a PoC continua funcional.

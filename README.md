# Juridico

Aplicação web para acompanhamento rastreável da carteira de processos de um escritório.

## Estado atual: carteira conhecida e consulta individual

O produto atual trabalha com clientes e processos cadastrados manualmente. Cada
processo conhecido pode ser consultado individualmente pelo CNJ, normalizado,
comparado com a consulta anterior e incluído em relatório. A fundação de
identidade, autorização, Supabase, RLS e testes continua sendo reutilizada.

## Requisitos

- Node.js 22 LTS (ver `.node-version`)
- Docker e Docker Compose (para execução local via contêineres e Supabase CLI)
- Chave do DataJud não é necessária para os testes locais; o provider público
  permanece explicitamente não configurado até uma homologação autorizada.

## Desenvolvimento local com Supabase

O projeto utiliza a CLI do Supabase para desenvolvimento local, não sendo necessário conectar a um projeto remoto.

### Inicializando o Ambiente

1. Instale as dependências do projeto:

   ```bash
   npm ci
   ```

2. Inicie os serviços locais do Supabase:

   ```bash
   npm run supabase:start
   ```

3. Após a inicialização, a CLI exibirá as credenciais locais. Copie o arquivo `.env.example` para `.env.local` e preencha a URL e a Publishable Key locais:
   ```bash
   cp .env.example .env.local
   ```
   Exemplo de `.env.local` (que não é versionado):
   ```env
   NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sua_chave_anon_local_aqui
   ```

### Comandos Úteis do Banco de Dados

- `npm run db:reset`: Reseta o banco de dados local e reaplica as migrations (destrói dados).
- `npm run db:test`: Executa os testes de banco de dados (pgTAP) cobrindo isolamento e RLS.
- `npm run db:lint`: Verifica o schema local contra melhores práticas.
- `npm run db:types`: Gera os tipos TypeScript baseados no schema local em `src/types/database.types.ts`.
- `npm run supabase:stop`: Para os serviços locais do Supabase sem apagar os dados.

## Execução via Docker (Aplicação)

A aplicação Next.js também está configurada para rodar localmente utilizando Docker, garantindo reprodutibilidade.

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

- `npm run dev`: Inicia o servidor de desenvolvimento local.
- `npm run build`: Constrói a aplicação para produção.
- `npm run start`: Inicia a aplicação em modo de produção.
- `npm run lint`: Executa o ESLint.
- `npm run format`: Formata o código com Prettier.
- `npm run format:check`: Verifica a formatação do código.
- `npm run typecheck`: Verifica os tipos do TypeScript.
- `npm run test`: Executa os testes unitários com Vitest.
- `npm run e2e`: Executa os testes E2E com Playwright.

## Consulta individual e escopo futuro

O Realinhamento 1 prepara a consulta individual de um processo conhecido.
O DataJud foi testado localmente com mocks injetados nos testes, mas não foi
testado live. Descoberta de processos por CPF/CNPJ é evolução futura e depende
de uma fonte externa ainda não definida; não é implementada nesta versão.

## CI/CD

O projeto utiliza GitHub Actions para Integração Contínua. O workflow `.github/workflows/app-ci.yml` garante que o código passe por verificações de lint, tipagem, testes unitários, testes E2E, build e testes de banco de dados local (pgTAP), além de verificar se a PoC continua funcional.

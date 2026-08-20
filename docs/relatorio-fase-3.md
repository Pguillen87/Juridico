# Relatório da Fase 3 - Fundação Técnica

## Status da rodada corretiva

**PARTIAL — aguardando as validações finais desta rodada.** Este relatório documenta a correção da auditoria externa da Fase 3. A Fase 4 não foi iniciada, e não foram iniciadas autenticação, Supabase ou RLS.

A rodada corretiva parte da branch `phase-3-foundation` e do commit auditado `57015a0e777933cca8051109525d88006f73e74f`, tendo como referência aprovada da PoC o commit `d5e8e16c9723809da2788ed504b2b872e4f70cb2`. O objetivo é remover artefatos gerados do índice, restaurar arquivos modificados somente por formatação, recolocar o lint real no CI, adicionar higiene automatizada e repetir as validações locais, Docker e GitHub Actions.

## Correções realizadas

O diretório `poc/node_modules` foi removido somente do índice Git, preservando as dependências locais para execução. A regra de ignorância foi ampliada para `node_modules/` em qualquer nível, mantendo as proteções para `.env*`, `.next/`, `coverage/`, `playwright-report/`, `test-results/` e `poc/evidence/`.

Os documentos históricos e os arquivos da PoC que haviam sido alterados apenas por formatação foram restaurados ao conteúdo do commit aprovado da Fase 2. Foram mantidas somente as alterações documentais intencionais em `docs/07-decisoes-do-mvp.md` e `poc/POC_RESULT.md`, além deste relatório. O arquivo `poc/vitest.config.ts` permanece apenas para permitir a execução isolada da suíte da PoC.

O script `lint` foi corrigido de `next lint` para `eslint .`, e o ESLint foi configurado para ignorar a PoC e artefatos gerados sem desativar as regras da aplicação, das configurações e dos testes E2E. O lint foi reinserido no workflow `app-ci.yml`. Também foi criado `.prettierignore`, limitando o Prettier ao escopo de código e arquivos de aplicação e impedindo novas reformatacões acidentais da documentação histórica e da PoC.

A página mínima passou a usar `lang="pt-BR"`, metadata com título `Juridico` e descrição coerente com monitoramento jurídico. A página não foi redesenhada e nenhum dashboard foi criado.

## Validações finais pendentes de registro

Os valores abaixo serão preenchidos somente após a execução local completa, a validação Docker e a conclusão do novo workflow do GitHub Actions ligado exatamente ao commit final.

| Validação | Resultado desta rodada |
|---|---|
| `npm run format:check` | Pendente de execução final |
| `npm run lint` | Pendente de execução final |
| `npm run typecheck` | Pendente de execução final |
| `npm test` | Pendente de execução final |
| `npm run build` | Pendente de execução final |
| Playwright | Pendente de execução final |
| PoC | Deve permanecer com 29 testes ou mais, sem consulta real ao DataJud |
| Docker | Pendente de execução final |
| CI GitHub Actions | Pendente; não utilizar o run anterior `32421711204` |

O status **APPROVED** somente poderá ser declarado se o commit final tiver um run do workflow `App CI` com `head SHA` idêntico, conclusão `success`, lint e higiene aprovados, PoC verde, Docker validado e nenhum artefato ou segredo versionado.

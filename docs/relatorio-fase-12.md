# Relatório — Fase 12: Relatório Semanal, Revisão e Aprovação

## 1. Identificação e evidência de publicação

| Campo | Estado factual |
|---|---|
| Branch | `phase-12-weekly-reports-review-approval` |
| Baseline Fase 11 | `aa96eca762a47a1497203758fb62513e190139e5` |
| SHA funcional publicado | `47e2ef7f968a9891d2af4c9deab353af3ed6ab4d` |
| App CI | run `33140634841` — `completed/success` |
| Escopo | relatório semanal congelado, edição editorial, revisão, restauração, aprovação e cancelamento |
| `main` | não alterada |
| Migrations anteriores | Fases 9, 10 e 11 preservadas |

A branch permaneceu exclusiva durante a implementação. Os commits finais de correção incluíram o refresh server-rendered dos fluxos E2E (`89a037c`), a desambiguação dos locators (`c856f1d`) e a sincronização do arquivo de tipos com a saída oficial da Supabase CLI (`47e2ef7`). O App CI verde do SHA `47e2ef7` passou também pelos gates posteriores ao Auth E2E.

## 2. IMPLEMENTADO

A migration aditiva `20260827000005_phase_12_weekly_reports.sql` começa literalmente com `SET lock_timeout = '2s';` e cria o domínio `weekly_report`, `report_version`, `report_process`, `report_party` e `report_command_idempotency`. O modelo mantém o relatório por cliente/período, versões imutáveis, projeções congeladas e idempotência de comandos. Triggers e guards impedem alterações indevidas de versões, projeções e registros de idempotência.

A geração `phase12_generate_weekly_report` é backend-only e idempotente por escritório, cliente e período. O período é `[start,end)`, termina na sexta-feira às 17:00 em `America/Sao_Paulo`, é persistido em UTC com o timezone IANA e tem teste histórico de offset. O conteúdo é montado somente a partir de fatos persistidos e distingue `changed`, `unchanged`, `not_comparable` e `failure`; falha não é convertida em `unchanged` e payload bruto não é armazenado no relatório.

A geração falha fechado antes de criar relatório ou versão quando a prova histórica cliente→processo não existe, retornando necessidade de revisão manual. Relações processo→parte ambíguas não confirmam identidade por nome: o processo comprovado permanece pendente de revisão manual. A versão técnica e seu manifesto são congelados e reproduzíveis.

A edição editorial é allowlisted e cria sempre uma nova versão. A restauração produz uma nova versão `restored`, sem sobrescrever o histórico. Submissão e devolução são transições controladas. A aprovação é exclusiva do `lawyer`, recalcula o hash do conteúdo persistido e do manifesto da versão exata e registra a aprovação. O cancelamento é terminal e impede segunda geração ou mutações posteriores para o mesmo cliente/período.

| Capacidade | Implementação factual |
|---|---|
| Leitura | `/app/relatorios` e `/app/relatorios/[id]`, server-side e isoladas por `office_id` |
| Atores | `lawyer` edita/revisa/aprova/cancela; `reviewer` edita/revisa; `operator`/`auditor` bloqueados |
| Mutação | Server Actions validam e chamam RPCs de domínio; não fazem DML direto |
| RPCs | `SECURITY DEFINER`, `search_path` fixo, grants mínimos e D-022 revalidada no banco |
| Auditoria | mutação e `audit_log` na mesma transação; helper interno allowlisted; rollback integral se auditoria falhar |
| Idempotência | chaves de comando e proteção contra replay/duplicação |
| UI | filtros por cliente, período e status; histórico de versões; ações compatíveis com estado e papel; logout visível |
| Limite | aprovação não significa envio; não há PDF, artefato ou delivery |

## 3. Segurança e autorização

A UI não escolhe `office_id`, actor, role ou `is_owner`. O banco deriva e revalida a identidade, o escritório e o papel. Perfis e escritórios inativos são rejeitados. RLS fornece isolamento por `office_id`, enquanto DML direto das tabelas F12 é revogado para `authenticated`, `anon` e `PUBLIC`; escrita de domínio ocorre pelas RPCs específicas.

O helper interno de auditoria aceita somente eventos e metadados allowlisted e não possui uma fronteira pública desnecessária. O `audit_log` permanece append-only. Erros retornados à UI são sanitizados e não expõem SQL, segredo, payload bruto ou detalhes de infraestrutura.

## 4. TESTADO

A suíte pgTAP F12 contém 58 asserts. Ela cobre grants e RLS, negação de DML direto, falha fechada por ausência de histórico, geração e conteúdo congelado, separação dos estados, replay idempotente, isolamento, D-022, edição, submissão, devolução, restauração, restrição de aprovação, allowlist editorial, hash recalculado, falha de integridade, cancelamento terminal, perfis/escritórios inativos e auditoria.

O teste real de concorrência `supabase/tests/concurrency/test_phase12_reports.sh` cobre oito cenários: geração dupla, duas edições na mesma base, edição versus submissão, edição versus aprovação, duas aprovações, aprovação versus cancelamento, dois escritórios no mesmo período e replay idempotente. O App CI verde confirmou o teste juntamente com os testes cumulativos das Fases 9, 10 e 11.

| Validação | Resultado |
|---|---|
| `npm run format:check` | TESTADO — passou localmente e no CI |
| `npm run lint` | TESTADO — passou localmente e no CI |
| `npm run typecheck` | TESTADO — passou localmente e no CI |
| Vitest | TESTADO — 27 arquivos, 136 testes aprovados localmente |
| `npm run build` | TESTADO — build Next.js aprovado localmente |
| Parser da migration | TESTADO — sintaxe validada localmente |
| `node --check`/`bash -n`/`git diff --check` | TESTADO — aprovados |
| Reset Supabase | TESTADO — aprovado no CI |
| Upgrade Fase 11 | TESTADO — aprovado no CI |
| Upgrade Fase 12 | TESTADO — aprovado no CI |
| Auth E2E | TESTADO — aprovado no CI após isolamento de fixture, redirect, logout e locators |
| PoC sintética | TESTADO — aprovado no CI |
| DB lint | TESTADO — aprovado no CI |
| pgTAP | TESTADO — aprovado no CI |
| Concorrência cumulativa | TESTADO — aprovada no CI, incluindo oito cenários F12 |
| Database types | TESTADO — saída gerada pela Supabase CLI comparou sem divergência no CI |
| Secret scan/hygiene/auditoria de dependências | TESTADO — aprovados no CI |

A validação local não executou Docker, `psql`, reset, pgTAP, concorrência PostgreSQL ou Supabase CLI local porque esses recursos não estão disponíveis no sandbox. Esses gates foram considerados TESTADOS somente pela execução remota do App CI `33140634841`.

## 5. PARCIAL

A aprovação está implementada somente como decisão interna e não dispara entrega. A interface informa explicitamente que aprovação não significa envio. Não existe implementação de PDF, artefato, download, storage de entrega, e-mail, webhook, destinatário, retry de delivery ou estado `sent`.

A geração usa fatos e fixtures sintéticas persistidos. Não há integração com DataJud/CNJ real, processo real, credencial real, provider pago, processo sigiloso, produção ou piloto. O comportamento operacional fora do ambiente sintético não foi alegado nem testado.

## 6. DEFERIDO E BLOQUEIOS PRESERVADOS

A skill `impeccable` estava indisponível no ambiente. Ela não foi instalada, substituída nem tratada como dependência da Fase 12; a indisponibilidade foi apenas registrada.

A autorização para `manual_provider_entry` continua pendente conforme a D-022 canônica. Nenhuma role foi inventada para entrada manual operacional. Scheduler, fila, worker novo, IA e demais capacidades posteriores não foram criados ou ampliados nesta fase.

PDF, artefato, envio, e-mail, webhook, delivery, produção, piloto e a fase seguinte permanecem DEFERIDOS. Qualquer avanço nesses itens exige escopo, decisão e validação próprios; não fazem parte deste fechamento.

## 7. Rollback e limites de operação

O rollback seguro consiste em impedir novos comandos da Fase 12 e preservar relatórios, versões, projeções, hashes e auditorias já registrados. Não se apagam evidências, não se reabrem estados terminais e não se desfazem migrations históricas. Qualquer correção de banco deve ser aditiva, revisada e manter o primeiro comando `SET lock_timeout = '2s';`.

Não houve serviço persistente novo, scheduler, fila, worker ou automação de fundo. A execução backend-only da geração ocorre apenas pela fronteira autorizada existente; nenhum mecanismo de produção ou piloto foi introduzido.

> O SHA deste documento de fechamento e o App CI correspondente ao próprio commit documental são evidências posteriores e devem ser verificados no GitHub durante a auditoria final. O relatório referencia o último SHA funcional já validado (`47e2ef7`) para não criar auto-referência circular.

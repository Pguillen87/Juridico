# Relatório — Fase 12: Relatório Semanal, Revisão e Aprovação

## 1. Identificação e evidência de publicação

| Campo | Estado factual |
|---|---|
| Branch | `phase-12-weekly-reports-review-approval` |
| Baseline aprovada da Fase 11 | `aa96eca762a47a1497203758fb62513e190139e5` |
| Último SHA técnico funcional validado | `e671d8599214f8ab77df455e6c2f2d5a6f7e2e01` |
| App CI técnico correspondente | run `33426689009` — `completed/success` |
| Escopo | relatório semanal congelado, edição editorial, revisão, restauração, aprovação e cancelamento |
| `main` | não alterada |
| Migrations anteriores | Fases 9, 10 e 11 preservadas |

A linhagem técnica final foi publicada em commits separados e validados: a correção do teste pgTAP em `0fcaff9010ae23d49d9e08622fc1cf616b07a105` (`test: fix phase 12 hash invariance pgTAP`) e a sincronização dos tipos em `e671d8599214f8ab77df455e6c2f2d5a6f7e2e01` (`chore: sync phase 12 database types`). O App CI técnico verde `33426689009` corresponde exatamente ao SHA `e671d8599214f8ab77df455e6c2f2d5a6f7e2e01`.

As referências à primeira publicação `47e2ef7f968a9891d2af4c9deab353af3ed6ab4d` e ao CI `33140634841` são históricas e superadas; não constituem a evidência final atual. O SHA deste commit documental e o App CI correspondente ainda devem ser verificados externamente no GitHub durante a auditoria de fechamento, sem autorreferência circular neste documento.

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

## 3. Linhagem das migrations e integridade

A Fase 12 passou por correção controlada de integridade de migration. A primeira publicação da migration 00005 possuía defeitos sintáticos comprovados em PostgreSQL real e era originalmente inexequível. Foram autorizadas exceções estreitas somente para tornar essa migration aplicável; não houve reescrita ampla do escopo. O hardening funcional posterior foi mantido em migration aditiva separada.

| Migration | Papel | Blob aprovado |
|---|---|---|
| `supabase/migrations/20260827000005_phase_12_weekly_reports.sql` | migration 00005 canônica atual | `c8f13774c0707d8502c6348283f2adf0e2673149` |
| `supabase/migrations/20260827000006_phase_12_weekly_reports_hardening.sql` | migration aditiva de hardening | `2b61ff7a1e857e5ee395a602dda20d83498e6720` |

O gate de histórico protege essa linhagem. Migrations anteriores permanecem preservadas e não foram alteradas durante as correções finais.

## 4. Hash, segurança e autorização

A migration 00006 introduziu a versão de algoritmo `phase12-hash-v2-epoch-us` e preservou compatibilidade com `phase12-hash-v1` por meio da função legacy `phase12_hash_version_legacy`. A invariância do hash é independente de:

- UTC;
- `America/Sao_Paulo`;
- `Asia/Tokyo`;
- `DateStyle ISO`.

A UI não escolhe `office_id`, actor, role ou `is_owner`. O banco deriva e revalida a identidade, o escritório e o papel. Perfis e escritórios inativos são rejeitados. RLS fornece isolamento por `office_id`, enquanto DML direto das tabelas F12 é revogado para `authenticated`, `anon` e `PUBLIC`; escrita de domínio ocorre pelas RPCs específicas.

O helper interno de auditoria aceita somente eventos e metadados allowlisted e não possui uma fronteira pública desnecessária. O `audit_log` permanece append-only. Erros retornados à UI são sanitizados e não expõem SQL, segredo, payload bruto ou detalhes de infraestrutura.

## 5. TESTADO — pgTAP F12

A suíte pgTAP F12 possui `plan(62)`, executou 62 asserts e terminou com 0 falhas. Ela cobre grants e RLS, negação de DML direto, falha fechada por ausência de histórico, geração e conteúdo congelado, separação dos estados, replay idempotente, isolamento, D-022, edição, submissão, devolução, restauração, restrição de aprovação, allowlist editorial, hash recalculado, invariância multi-timezone, falha de integridade, cancelamento terminal, perfis/escritórios inativos e auditoria.

A correção foi publicada no commit `0fcaff9010ae23d49d9e08622fc1cf616b07a105` e consistiu em:

- remover o uso inválido de `SET LOCAL` fora de transação;
- usar configuração válida de sessão com restauração dos GUCs originais;
- adicionar casts explícitos `::text` nas comparações pgTAP originadas de `\gset`.

Nenhum assert foi removido ou enfraquecido. O teste real de concorrência `supabase/tests/concurrency/test_phase12_reports.sh` cobre oito cenários: geração dupla, duas edições na mesma base, edição versus submissão, edição versus aprovação, duas aprovações, aprovação versus cancelamento, dois escritórios no mesmo período e replay idempotente.

## 6. Validação PostgreSQL local e cumulativa

O ambiente local posterior confirmou Docker operacional, Supabase CLI `2.115.0` e PostgreSQL local acessível. O `db:reset` local passou e aplicou as migrations aprovadas, incluindo 00005 e 00006. O `db:lint` passou com achados preexistentes; o `db:test` passou com suíte PostgreSQL cumulativa de 446 testes aprovados, incluindo F12 com 62/62.

Durante a preparação local foi observado que `supabase/seed.sql` não existe. O reset local passou sem esse arquivo; a Fase 12 utiliza fixtures e dados sintéticos. Nenhum dado remoto ou real foi utilizado.

O arquivo gerado foi sincronizado no commit `e671d8599214f8ab77df455e6c2f2d5a6f7e2e01` (`chore: sync phase 12 database types`) por `npm run db:types`, usando exclusivamente Supabase local (`--local`) após reset local. O diff possui 13 linhas adicionadas em `src/types/database.types.ts`: o campo `hash_algorithm_version` e a RPC `phase12_hash_version_legacy`. O gate `Supabase DB Types Check` passou localmente e no CI.

| Validação | Resultado factual |
|---|---|
| `npm run db:reset` | PASS local e no CI |
| `npm run db:lint` | PASS local e no CI, com achados preexistentes |
| `npm run db:test` | PASS local e no CI; 446 testes PostgreSQL aprovados localmente |
| F12 pgTAP | PASS — plan 62, executed 62, failed 0 |
| `npm run format:check` | PASS no App CI; execução local reportou divergências de formatação preexistentes fora do arquivo documental |
| `npm run lint` | PASS local e no CI |
| `npm run typecheck` | PASS local e no CI |
| Vitest | PASS — 27 arquivos, 136 testes aprovados localmente |
| Migration history | PASS no CI |
| Phase 11 Migration Upgrade | PASS no CI |
| Phase 12 Migration Upgrade | PASS no CI |
| Supabase DB Types Check | PASS local e no CI |
| App CI técnico | run `33426689009`: SUCCESS no SHA `e671d8599214f8ab77df455e6c2f2d5a6f7e2e01` |

## 7. PARCIAL E LIMITES PRESERVADOS

A aprovação está implementada somente como decisão interna e não dispara entrega. A interface informa explicitamente que aprovação não significa envio. Não existe implementação de PDF, artefato definitivo, download, storage de entrega, e-mail real, webhook real, destinatário, delivery, retry de delivery ou estado `sent`.

Permanecem FORA DA FASE 12: PDF; artefato definitivo; envio; e-mail real; webhook real; delivery; `sent`; produção; piloto; DataJud/CNJ/processos reais; credenciais reais; e IA com dados reais. A geração usa fatos e fixtures sintéticas persistidos. Nenhuma evidência usa dados remotos ou reais.

Somente `role=lawyer` aprova. `is_owner` não concede poder jurídico. A aprovação continua sendo decisão interna do relatório e não envio.

A matriz de rastreabilidade registra US-032 a US-037 como `IMPLEMENTADO/TESTADO`. PDF, envio e artefatos permanecem deferidos para a Fase 13; a Fase 13 não foi iniciada neste trabalho.

## 8. DEFERIDO, histórico de tooling e rollback

Durante a implementação original da Fase 12, `impeccable` não estava disponível. Posteriormente a skill foi instalada no ambiente global do agente durante preparação de tooling; isso não é evidência retroativa de validação da implementação original nem requisito funcional da Fase 12.

A autorização para `manual_provider_entry` continua pendente conforme a D-022 canônica. Nenhuma role foi inventada para entrada manual operacional. Scheduler, fila, worker novo, IA e demais capacidades posteriores não foram criados ou ampliados nesta fase.

O rollback seguro consiste em impedir novos comandos da Fase 12 e preservar relatórios, versões, projeções, hashes e auditorias já registrados. Não se apagam evidências, não se reabrem estados terminais e não se desfazem migrations históricas. Qualquer correção de banco deve ser aditiva, revisada e manter o primeiro comando `SET lock_timeout = '2s';`.

O SHA deste relatório documental e o App CI correspondente são evidências posteriores e devem ser verificados externamente no GitHub durante a auditoria final. Este documento não declara a Fase 12 encerrada.

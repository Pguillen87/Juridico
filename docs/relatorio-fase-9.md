# Relatório factual — Fase 9: Scheduler, Fila, Worker e Snapshots

## 1. Escopo e baseline

A Fase 9 é implementada na branch `phase-9-scheduler-queue-snapshots`, derivada do commit publicado `9246583b799a2d5a6e207e3fc7b9944a64a019be` da branch `phase-8-datajud-manual`. A Fase 8 permanece preservada, `main` não é alterada e a Fase 10 não é iniciada.

O objetivo desta fase é disponibilizar, exclusivamente em sandbox sintético, a infraestrutura para ativação autorizada de monitoramento, criação idempotente de jobs por janela, claim concorrente com lease, execução server-only, retry limitado e armazenamento de snapshots imutáveis. O scheduler não chama provider; o worker chama somente o gateway fake existente do DataJud sandbox. Não há CNJ real, processo real, credencial real, endpoint externo, provider pago, produção, piloto, notificação ou relatório semanal.

O provider continua retornando somente `observation` ou `failure`. Os estados `changed` e `unchanged`, comparação, baseline comparativa e `detected_change` permanecem fora da Fase 9 e pertencem à Fase 10.

## 2. Arquitetura implementada

A configuração de monitoramento é formada por `monitoring_configuration` e `monitoring_schedule`. A função `phase9_set_process_monitoring_status` é uma RPC de domínio autenticada por `manage_monitoring`; deriva actor, office e role no banco, bloqueia processo inexistente, inativo, sigiloso ou fora do tenant e registra auditoria na mesma transação. Nenhum processo é ativado por seed ou automaticamente.

O scheduler server-only chama `phase9_scheduler_tick` com um instante controlado. A RPC interpreta a janela no timezone IANA da configuração, converte o horário local para UTC, cria jobs somente para processos ativos e públicos e usa chave idempotente baseada em office, processo, provider, capability e janela UTC. O scheduler não executa provider, não reivindica job e não altera `legal_process` além do estado autorizado de monitoramento.

A fila `query_job` registra o trabalho lógico, a chave idempotente, o número de tentativas, o estado, a disponibilidade e os campos de lease. `phase9_claim_query_job` usa `FOR UPDATE SKIP LOCKED`, incrementa a tentativa exatamente uma vez, cria `query_execution` e retorna um token aleatório de lease. O token, o worker opaco e o vencimento são exigidos na conclusão. `phase9_recover_expired_query_jobs` recupera jobs expirados sem apagar execuções anteriores.

O worker server-only chama o claim, constrói `ProviderRequestV1` com contexto sistêmico explícito, executa o gateway DataJud fake e chama `phase9_complete_query_execution`. A conclusão é transacional: valida a lease, revalida processo e tenant, registra a exchange e o payload privado pelas wrappers internas da Fase 8, cria snapshot apenas para `observation`, finaliza a execução, atualiza o job e grava auditoria sistêmica. Um worker não possui identidade jurídica de usuário.

## 3. Estados e falhas

| Componente | Estados principais | Regra da Fase 9 |
|---|---|---|
| `legal_process.monitoring_status` | `paused`, `active` | Ativação depende de `manage_monitoring`; somente processo público e ativo pode seguir para consulta |
| `query_job` | `queued`, `running`, `retry_scheduled`, `succeeded`, `terminal_failure` | A chave idempotente evita duplicação; jobs terminais não retornam à fila |
| `query_execution` | `running`, `succeeded`, `failed`, `timeout`, `rate_limited`, `not_found`, `not_supported`, `source_unavailable`, `technical_failure` | Cada claim gera uma tentativa preservada; falhas são sanitizadas |
| Provider | `observation`, `failure` | Não contém `changed` nem `unchanged` |
| Retry | até 3 tentativas | Timeout, rate limit, network/DNS e indisponibilidade podem repetir; `not_found`, `not_supported` e schema inválido são terminais |

O retry usa backoff determinístico, respeita `Retry-After` somente dentro do teto configurado e nunca expõe o conteúdo bruto de uma exceção. Mensagens persistidas e respostas do backend permanecem sanitizadas.

## 4. Segurança PostgreSQL e D-022

A migration publicada `20260826000011_phase_9_scheduler_queue_snapshots.sql` foi restaurada byte a byte ao conteúdo original de `2904185d0e43546e6f48433533326878fb200c80`; ela permanece imutável. O hardening de stale lease foi movido exclusivamente para a migration incremental `20260826000012_phase_9_stale_lease_hardening.sql`, cuja primeira instrução é `SET lock_timeout = '2s';` e que reaplica a mesma assinatura pública com `SECURITY DEFINER`, `search_path = pg_catalog, public`, validações DB-side, atomicidade, idempotência e grants mínimos. As tabelas novas possuem RLS habilitada, chaves compostas de tenant e constraints de estado, tenant, attempts e integridade.

O navegador pode solicitar somente a alteração de monitoramento autorizada pela D-022. `authenticated`, `anon` e `PUBLIC` não executam scheduler, claim, recovery, completion, configuração de backend ou escrita sistêmica. O `service_role` não recebe DML direto nas tabelas novas; executa somente as RPCs internas destinadas ao scheduler/worker. O reprocessamento manual permanece sem `EXECUTE` público e sem Server Action até decisão específica para US-012/US-029. Não foi criada a ação `manual_provider_entry`, nem houve fallback automático para `ManualProvider`.

A auditoria sistêmica utiliza `actor_user_id = NULL` e origens allowlisted `system_scheduler` ou `system_worker`. O `worker_id` é um identificador opaco, não uma identidade humana. Metadata arbitrária, actor, office, role e `is_owner` do browser não são aceitos como autoridade. `process_snapshot` é append-only, tem hash SHA-256 sobre payload canônico, provenance, vínculo um-para-um com `query_execution` e trigger que rejeita `UPDATE` e `DELETE`.

## 5. Critérios de aceite e parada

A fase somente pode ser considerada concluída com reset e lint da base, prova byte a byte da imutabilidade de 00011, suíte pgTAP específica e cumulativa, tipos oficiais sincronizados, unitários, typecheck, lint, build, higiene, auditoria de segredos e CI do SHA exato verde. A validação deve provar idempotência de janela, isolamento de tenant, processo sigiloso bloqueado antes do provider, concorrência de lease, rejeição de token stale, recuperação, limite de retries, terminalização de `not_found`, atomicidade de exchange/payload/snapshot/auditoria e imutabilidade.

A implementação deve parar e não publicar se houver execução de provider pelo scheduler, acesso browser às RPCs internas, DML direto de `service_role`, bypass de processo sigiloso, duplicação de job, perda de tentativa, snapshot para falha, comparação antecipada, segredo em código/log/resposta/fixture, fallback automático do ManualProvider, warning de migration não resolvido, falha de regressão ou CI diferente do SHA publicado.

## 6. Validação executada

| Gate | Resultado |
|---|---|
| Typecheck, ESLint e format check no workspace fonte | Passaram |
| Unitários | 106 testes em 19 arquivos, todos passaram |
| Build Next.js | Passou |
| Reset e lint PostgreSQL | Passaram na cópia Docker Windows isolada |
| Suíte pgTAP cumulativa | 12 arquivos, 305 assertions, passou |
| Suíte pgTAP específica da Fase 9 | 36 assertions, passou |
| Concorrência real específica da Fase 9 | Duas conexões PostgreSQL simultâneas; scheduler/claim/conclusão/lease stale, passou |
| Auth E2E após a UI de monitoramento | 25 testes, passou |
| PoC DataJud | 29 testes, passou |
| Concorrência Windows | Rate limit, confirmação Fase 5 e processos/CSV Fase 6 passaram |
| Database types | Saída oficial do Supabase local idêntica ao arquivo versionado após normalização de line endings |
| `npm audit --audit-level=high --omit=dev` | 0 vulnerabilidades |
| Higiene, secret scan e `git diff --check` | Passaram |
| Histórico de migrations | `scripts/check-phase9-migration-history.sh` e o teste concorrente: diff de 00011 contra 2904185 vazio; guard stale exclusivo em 00012 | Passou |
| Revisão PostgreSQL/security | `lock_timeout` inicial, sem DDL destrutivo/grants amplos, `SECURITY DEFINER`, `search_path` fixo, owner PostgreSQL e `service_role` apenas | Passou |

O script bash de concorrência do último proprietário não foi considerado evidência local válida porque a chamada pelo WSL da máquina Windows apresentou line endings CRLF e não encontrou o Docker integrado nessa distribuição. Esse gate permanece para validação no App CI Linux; a falha ambiental não foi mascarada nem usada para relaxar o workflow. O teste específico `supabase/tests/concurrency/test_phase9_concurrency.sh` foi executado com duas conexões PostgreSQL reais pela integração Git Bash/Docker e passou após reset limpo com 00011 original e 00012 incremental, comprovando scheduler idempotente, claim exclusivo, conclusão sem duplicação de exchange/snapshot, rejeição de lease stale e conclusão pela nova lease.

## 7. Status de escopo

A Fase 9 adiciona somente scheduler, fila, worker, retries e snapshots em sandbox. A Fase 10 continua responsável por comparação, `changed`/`unchanged`, movimentos deduplicados e mudanças detectadas. Notificações, failure center de UI, relatórios semanais e armazenamento de artefatos permanecem futuros. A entrada manual operacional continua bloqueada por ausência de `manual_provider_entry` na D-022.

## Referências

[1]: `../docs/01-requisitos-do-produto.md` — Requisitos canônicos do produto.
[2]: `../docs/10-matriz-papeis-e-autorizacao.md` — Matriz normativa D-022.
[3]: `../docs/09-definicao-de-pronto.md` — Definição de pronto.
[4]: `../supabase/migrations/20260826000011_phase_9_scheduler_queue_snapshots.sql` — Migration publicada e imutável, restaurada da versão original.
[5]: `../supabase/migrations/20260826000012_phase_9_stale_lease_hardening.sql` — Hardening incremental de stale lease.
[6]: `../supabase/tests/database/12_phase_9_scheduler_queue_snapshots.test.sql` — Suíte pgTAP da Fase 9.
[7]: `../scripts/check-phase9-migration-history.sh` — Verificador automatizado de integridade do histórico.

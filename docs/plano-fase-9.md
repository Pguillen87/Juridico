# Plano técnico — Fase 9: Scheduler, Fila, Worker e Snapshots

## 1. Baseline e objetivo

A Fase 9 parte da branch `phase-9-scheduler-queue-snapshots`, com baseline publicada em `9246583b799a2d5a6e207e3fc7b9944a64a019be`, o commit final do corretivo da Fase 8. A entrega é incremental, não altera `main` e não inicia a Fase 10. O corretivo posterior usa `3517e6f059a50113d31b0ce9a4f7c3be2ee6d726` como parent e restaura a migration publicada `20260826000011_phase_9_scheduler_queue_snapshots.sql` byte a byte ao conteúdo de `2904185d0e43546e6f48433533326878fb200c80`; o hardening de stale lease vive exclusivamente na nova `20260826000012_phase_9_stale_lease_hardening.sql`.

O objetivo é implementar uma infraestrutura sandbox, sintética e backend-only para ativação autorizada de monitoramento, criação idempotente de jobs, processamento por worker com lease, retries limitados e persistência de snapshots imutáveis. O desenho não habilita operação produtiva nem integração externa.

## 2. Scheduler

O scheduler server-only executa uma RPC controlada que recebe um instante de referência, interpreta a agenda no timezone IANA configurado e cria jobs somente para processos ativos, públicos e com monitoramento ativo. A chave de idempotência combina processo, provider, capability e janela lógica UTC. Execuções concorrentes do scheduler não podem criar dois jobs para a mesma janela. O scheduler não chama provider, não lê payload bruto e não executa comparação.

A ativação ou pausa de monitoramento ocorre por RPC de domínio chamada pela Server Action autorizada por `manage_monitoring`. Actor, office e role são derivados e revalidados no PostgreSQL. Processo sigiloso, processo inativo, usuário inativo e acesso cross-office são bloqueados antes da criação do job.

## 3. Fila e lease

A fila `query_job` registra o trabalho lógico, a chave idempotente, a tentativa atual, a disponibilidade, o estado e os campos de lease. A RPC de claim usa `FOR UPDATE SKIP LOCKED`; duas conexões concorrentes podem reivindicar jobs diferentes, mas apenas uma recebe o mesmo job. Cada claim incrementa `attempt_count` exatamente uma vez, cria uma linha em `query_execution` e retorna token e vencimento da lease.

A renovação exige job, execution, token válido e lease ainda vigente. A conclusão exige a lease atual; token antigo ou execution encerrada são rejeitados. Recovery de lease expirada preserva a tentativa anterior e agenda outra tentativa somente quando o limite ainda não foi atingido.

## 4. Worker

O worker é um módulo `server-only`. Ele reivindica jobs, constrói `ProviderRequestV1` com contexto sistêmico explícito, chama o gateway fake DataJud existente e conclui a execution por RPC transacional. O worker não representa usuário jurídico, não aceita actor/office/role do browser e não expõe scheduler, claim ou completion por rota pública.

O DataJud utilizado nesta fase é exclusivamente fake/sandbox, com fixtures sintéticas e transporte mockado. Não são usados CNJ real, processo real, credencial real, endpoint real, provider pago, produção ou piloto. O provider retorna somente `observation` ou `failure`.

## 5. Retries e falhas

Timeout, rate limit, falha de rede/DNS e indisponibilidade de origem podem ser classificados como retryáveis, com backoff determinístico, teto de `Retry-After` e no máximo três tentativas. `not_found`, `not_supported`, schema inválido e falhas de entrada são terminais conforme o contrato. Mensagens persistidas e logs são sanitizados; conteúdo bruto não é colocado em mensagens de erro.

As transições de job e execution são protegidas por constraints, triggers e RPCs de domínio. Estados terminais não retornam silenciosamente à fila. Reprocessamento manual continua bloqueado sem decisão específica para US-012/US-029 e sem `EXECUTE` público ou de `service_role`.

## 6. Snapshots

Uma conclusão `observation` válida pode criar um único `process_snapshot` vinculado à `query_execution`. O snapshot armazena dados normalizados, campos ausentes, provenance e hash SHA-256 determinístico do JSON canônico. O payload é validado contra chaves sensíveis e contra campos de comparação; a tabela é append-only e rejeita `UPDATE` e `DELETE` físicos.

Não há snapshot para falha. A Fase 9 não calcula diferença entre snapshots e não produz `changed`, `unchanged` ou `detected_change`; comparação e movimentos deduplicados pertencem à Fase 10.

## 7. Segurança, RLS e auditoria

A migration incremental usa `SET lock_timeout = '2s'`, `SECURITY DEFINER` com `search_path` fixo, RLS nas tabelas novas e grants mínimos. `authenticated`, `anon` e `PUBLIC` não executam scheduler, claim, recovery, completion, configuração interna ou auditoria sistêmica. O `service_role` executa somente as RPCs internas necessárias ao backend e não recebe DML direto nas tabelas.

A auditoria sistêmica é gravada na mesma transação da mutação correspondente, com `actor_user_id = NULL`, origem allowlisted `system_scheduler` ou `system_worker`, `worker_id` opaco e metadata allowlisted. Falha de auditoria causa rollback da mutação inteira. D-022 continua determinando as capacidades humanas; `is_owner` não acrescenta autorização operacional.

## 8. Testes e CI

A validação deve incluir unitários da política de retry, snapshots, scheduler e worker; pgTAP de grants, RLS, estados, leases, retry, conclusão, idempotência, atomicidade e imutabilidade; tipos oficiais do Supabase; Auth E2E; PoC sintética; concorrências anteriores; higiene; secret scan; audit; build e lint. Deve também executar `scripts/check-phase9-migration-history.sh`, comprovando com `git diff --exit-code 2904185... -- 00011` que a migration publicada não mudou e que o guard stale existe somente em 00012.

Também é obrigatório um teste de concorrência real com pelo menos duas conexões PostgreSQL simultâneas, cobrindo: dois workers tentando o mesmo claim; apenas um vencedor; duas conclusões para a mesma lease sem duplicar exchange ou snapshot; rejeição de lease antiga após nova lease; e dois schedulers na mesma janela sem job duplicado. O teste usa apenas dados sintéticos e é executado automaticamente no App CI Linux.

## 9. Critérios de aceite e parada

A fase somente é aceita quando as invariantes de concorrência forem demonstradas no PostgreSQL real, a integridade byte a byte de 00011 for comprovada, o teste específico rodar no CI, `docs/plano-fase-9.md` existir, a regressão cumulativa passar, os tipos oficiais estiverem sincronizados e o App CI do SHA exato terminar com `success`.

A execução deve parar se houver duplicação de job, claim duplo, duplicação de exchange/snapshot, aceitação de token stale, bypass de processo sigiloso, DML direto indevido, segredo exposto, fallback automático do ManualProvider, comparação antecipada, falha de migration, falha de regressão ou CI diferente do SHA publicado.

## 10. Fora de escopo

Ficam fora desta fase: DataJud real, CNJ/processo real, credenciais reais, endpoint externo, provider pago, produção, piloto, scheduler externo, fila externa, notificações, relatórios semanais, central visual de falhas, retenção operacional definitiva, snapshots comparativos, `changed`, `unchanged`, `detected_change` e toda implementação da Fase 10. A entrada manual operacional continua bloqueada por D-022; não existe `manual_provider_entry`.

## Referências

[1]: `01-requisitos-do-produto.md` — Requisitos canônicos do produto.
[2]: `10-matriz-papeis-e-autorizacao.md` — Matriz normativa D-022.
[3]: `09-definicao-de-pronto.md` — Definição de pronto.
[4]: `20260826000011_phase_9_scheduler_queue_snapshots.sql` — Migration publicada e imutável da Fase 9, restaurada da baseline original.
[5]: `20260826000012_phase_9_stale_lease_hardening.sql` — Hardening incremental de stale lease.
[6]: `../supabase/tests/concurrency/test_phase9_concurrency.sh` — Concorrência real da Fase 9.
[7]: `../scripts/check-phase9-migration-history.sh` — Verificação automatizada de histórico e exclusividade do hardening.

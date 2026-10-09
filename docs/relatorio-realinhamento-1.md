# Relatório técnico: Realinhamento 1 — Consulta individual de processo conhecido

> Este documento registra o estado técnico local do R1. A validação descrita
> aqui usa fixtures e mocks explícitos; não houve chamada ao DataJud real,
> CNJ real ou chave real.

## 1. Visão Geral

O **Realinhamento 1** implementa localmente o fluxo vertical de atualização sob demanda para um processo conhecido por CNJ e prepara o adapter da API Pública do DataJud:

1. **Migration Aditiva (`20260905000001_realignment1_manual_refresh.sql`)**:
   - Atualizou constraints para permitir `provider_id = 'datajud_public'` e `job_kind = 'manual_refresh'`.
   - Implementou a RPC `realignment1_request_process_refresh` com locking transacional `FOR UPDATE` para impedir disparos concorrentes duplicados.
   - Implementou a RPC `realignment1_claim_query_job` com targeted claim estrito e recuperação isolada de leases expirados.
   - Ajustou guards de monitoramento para que processos com `monitoring_status = 'paused'` possam ser atualizados manualmente por advogados e operadores.

2. **Módulos de Integração e Provider**:
   - `src/lib/providers/datajud-endpoint-resolver.ts`: Mapeamento puro de CNJs para endpoints canônicos de cada tribunal.
   - `src/lib/providers/adapters/datajud-public.ts`: Normalizador do envelope Elasticsearch do DataJud, com identificação determinística de movimentações por SHA-256 e detecção de ambiguidade.
   - `src/lib/providers/adapters/datajud-http-transport.ts`: Transporte HTTP resiliente com suporte a timeout de 15s e sanitização de erros.
   - `src/lib/providers/datajud-config-core.ts`: Suporte seguro ao modo `live` com validação de chaves no servidor.

3. **Motor de Comparação e Read Model**:
   - `src/lib/comparison/comparator.ts`: Introdução do `ComparisonProfile` puro, permitindo comparações sem partes/sistema para `datajud_public` enquanto preserva 100% da integridade do `datajud_sandbox`.
   - `src/lib/monitoring/worker.ts`: Suporte a `targetJobId`, preservação de descriptors nos fallbacks de erro e targeted claim.

4. **Interface e Ações do Usuário**:
   - `src/app/app/processos/actions.ts`: Adição da Server Action `requestProcessRefreshAction`.
   - `src/app/app/processos/page.tsx`: Inclusão do botão "Atualizar agora", exibição da data da última atualização no tribunal (`sourceUpdatedAt`) e status da busca.

5. **Testes Automatizados**:
   - Os testes unitários, de integração, banco e E2E usam dados sintéticos e fixture HTTP local, sem chamadas de rede externas.

6. **Extensão da carteira**:
   - `20260921152859_client_portfolio_batch_refresh.sql` adiciona o lote pai,
     jobs filhos, progresso protegido por RLS e detalhes sob demanda.
   - A action **Atualizar carteira** somente enfileira processos públicos e
     ativos já vinculados ao cliente; não executa descoberta por CPF/CNPJ.
   - O read model expõe metadados documentados, último andamento e estado da
     consulta sem renderizar provider, job, lease, snapshot ou UUID técnico.

## Limites de produto

- A primeira versão operacional é centrada em cliente, carteira, processos
  cadastrados manualmente, consulta individual, novidades e relatório.
- CPF/CNPJ, descoberta automática, `DiscoveryProvider`, consulta em lote
  externa e autoimportação permanecem **DEFERIDOS / EVOLUÇÃO FUTURA**.
- O DataJud Público é mantido somente para consulta/atualização de CNJ
  conhecido. Não há contrato público confirmado neste projeto para descobrir
  todos os processos de uma pessoa por CPF/CNPJ.

## Estado de validação

- O transporte HTTP real exige configuração explícita e não possui fallback
  sintético no registry operacional.
- A validação local usa o fixture em
  `scripts/datajud-e2e-fixture-server.mjs`, limitado a `127.0.0.1`.
- A integração live com o DataJud e o uso de credencial real permanecem não
  testados e fora do escopo desta entrega.

# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

**Decisão provisória, sujeita à aprovação do usuário:** Next.js, TypeScript, PostgreSQL por meio do Supabase, Supabase Auth, Row Level Security, Tailwind CSS, Zod, Vitest e Playwright. A decisão técnica final exige aprovação do usuário antes da inicialização do projeto. Nenhuma dependência deve ser instalada nesta etapa.

## Users

O usuário principal é um advogado que acompanha aproximadamente 60 processos judiciais, revisa alterações, trata falhas de consulta e aprova relatórios destinados a clientes. Usuários básicos de um mesmo escritório poderão executar atividades delegadas conforme papéis e permissões que ainda exigem definição e validação do advogado.

O sistema representará uma cliente principal e suas três filhas, além de familiares, dependentes, representantes, pessoas físicas, pessoas jurídicas e outras partes relacionadas. O cadastro comum de partes será representado conceitualmente por `party`; `client` representará a relação comercial com o escritório e `client_related_party` representará relações entre partes.

## Product Purpose

O produto atual começa pela carteira conhecida: cliente, processos cadastrados
manualmente, consulta individual por CNJ, histórico, normalização, comparação,
novidades e relatório. Scheduler, alertas e automações amplas permanecem
infraestrutura reutilizável ou evolução posterior.

O sucesso do produto depende de tornar claramente visíveis os processos consultados com alteração, sem alteração, com fonte indisponível, não encontrados, não suportados, sujeitos a limite de requisições, timeout, falha técnica ou revisão manual. Uma consulta que falhou nunca poderá ser apresentada como processo sem movimentação.

## Positioning

O produto será uma central de acompanhamento jurídico orientada à rastreabilidade. Cada informação deverá indicar fonte, data da consulta, estado da consulta e histórico. A fonte oficial será sempre o conector determinístico ou o registro manual autorizado; a IA será somente uma camada opcional de apoio para rascunhos revisáveis.

## Operating Context

O advogado cadastra processos conhecidos e pode solicitar uma atualização
individual. A consulta agendada automática não faz parte da primeira versão
operacional.

A primeira fonte automática prevista é a API Pública do DataJud. O sistema também terá um `ManualProvider` para processos que não possam ser consultados automaticamente. Outros conectores, como DJEN, PJe, eproc, ESAJ e Projudi, são futuros e não serão implementados no MVP.

Relatórios existentes continuam disponíveis para revisão, aprovação e geração de
PDF conforme as regras já implementadas. Envio real permanece fora do escopo.

## Capabilities and Constraints

O escopo operacional atual abrange autenticação, escritório, usuários, clientes,
partes, processos manuais/CSV, validação CNJ, consulta individual, histórico,
snapshots, normalização, comparação, detecção de alterações, central de falhas,
relatórios, aprovação, PDF, auditoria e controle de acesso. Scheduler de
produção, descoberta externa, notificações e envio real são futuros.

O modelo de partes deverá ser comum e não limitar a associação a uma categoria restrita de pessoa relacionada. A entidade `party` representará pessoa física, pessoa jurídica, cliente principal, filha, familiar, representante e qualquer outra parte. `client` apontará para a parte principal; `client_related_party` registrará relações; `process_party` fará a associação N:N entre processo e parte.

A consulta de processo público conhecido usa o provider DataJud Público quando
configurado. O provider foi implementado localmente e testado com mock explícito;
não há validação live. Processos sigilosos não são consultados automaticamente.

Consultas, comparações, deduplicação e detecção serão determinísticas. A IA poderá organizar movimentações, sugerir resumos, simplificar linguagem processual e sugerir textos de relatório, sempre em rascunho. A IA não será fonte oficial, não inventará fatos, não alterará datas, não emitirá parecer, não determinará prazos e não enviará conteúdo sem aprovação do advogado.

A importação CSV terá validação de CNJ, linhas inválidas, pré-visualização, confirmação, prevenção de duplicações, resumo e auditoria. Os números CNJ para a prova de conceito deverão ser públicos, reais, fornecidos e aprovados explicitamente antes de qualquer consulta.

O canal inicial de alerta será e-mail. O provedor de e-mail permanecerá abstrato, sem fornecedor definitivo. Desenvolvimento e testes usarão um adaptador falso ou sandbox. WhatsApp, SMS e notificações internas são futuros.

Respostas brutas e snapshots serão imutáveis. A retenção inicial proposta para respostas brutas é de 180 dias, sujeita à validação jurídica. Relatórios enviados, versões enviadas e trilhas de auditoria não serão excluídos automaticamente até definição jurídica. Timestamps serão armazenados em UTC e apresentados em `America/Sao_Paulo`.

## Evidence on Hand

O repositório contém a aplicação e sua infraestrutura operacional. Documentos de
fases anteriores permanecem como histórico quando necessário.

Não existem números CNJ aprovados para consulta. A prova de conceito usará de cinco a dez processos públicos reais somente após fornecimento e aprovação explícita. Não serão usados processos inventados.

## Product Principles

1. Preservar rastreabilidade entre informação, fonte, consulta, snapshot, alteração e relatório.
2. Diferenciar sempre falha de consulta e ausência de movimentação.
3. Manter revisão e aprovação humana como controles obrigatórios.
4. Usar conectores determinísticos como fonte oficial e IA apenas como apoio de rascunho.
5. Nunca confirmar vínculo por semelhança de nome sem ação humana auditada.
6. Manter dados isolados por escritório e segredos fora do código e dos payloads.
7. Projetar para recuperação, reprocessamento idempotente e evolução de provedores.

## Accessibility & Inclusion

A interface deverá comunicar estados, falhas, alterações e pendências por texto e estrutura, sem depender somente de cor. Processos e partes deverão ser distinguíveis por nome, tipo, papel e relação. O produto deverá considerar acessibilidade, controle de acesso, proteção de dados pessoais e LGPD desde o planejamento.

## Open Decisions

| Decisão | Estado | Validação necessária |
|---|---|---|
| Stack técnica | `proposed` | Aprovação do usuário e revisão técnica |
| Fuso `America/Sao_Paulo` | `proposed` | Validação do advogado |
| Horários 08:00, 13:00 e 18:00 | `proposed` | Validação do advogado |
| Fechamento sexta-feira 17:00 | `proposed` | Validação do advogado |
| Canal inicial e-mail | `proposed` | Aprovação do usuário |
| Fornecedor de e-mail | `deferred` | Contratação de fornecedor e credencial externa |
| Adaptador falso/sandbox | `proposed` | Validação técnica |
| Retenção bruta de 180 dias | `proposed` | Validação jurídica |
| Retenção de relatórios e auditoria sem exclusão automática | `proposed` | Validação jurídica |
| Consulta automática de processos sigilosos | `rejected` no MVP | Revisão jurídica se o escopo mudar |
| Números CNJ da PoC | `requires_user_input` | Fornecimento e aprovação explícita do usuário |

# Decisões do MVP

## Estados

Os estados utilizados neste documento são `proposed`, `approved`, `rejected`, `deferred`, `requires_legal_review` e `requires_user_input`.

## Registro de Decisões

| ID | Decisão | Estado | Responsável | Prazo desejado | Impacto | Classificação |
|---|---|---|---|---|---|---|
| D-001 | Usar aplicação web como plataforma | `approved` | Usuário/owner | Já definido | Exclui app nativo do MVP | Não bloqueante |
| D-002 | Começar com um escritório | `approved` | Usuário/owner | Já definido | Simplifica operação, mantém `office_id` | Não bloqueante |
| D-003 | Monitorar carteira inicial de aproximadamente 60 processos | `approved` | Advogado | Antes da importação | Define volume inicial | Não bloqueante |
| D-004 | Usar DataJud como primeiro provider automático | `proposed` | Usuário/owner | Antes da Fase 1 | Define PoC e contrato | Bloqueante para consulta real |
| D-005 | Manter `ManualProvider` como fallback | `proposed` | Usuário/advogado | Antes dos providers | Permite exceções | Não bloqueante |
| D-006 | Usar `party` como cadastro comum | `approved` conceitual | Técnico/advogado | Antes do modelo físico | Corrige modelagem de pessoas | Não bloqueante |
| D-007 | Não confirmar vínculo por semelhança de nome | `approved` | Advogado | Permanente | Reduz risco de homônimo | Não bloqueante |
| D-008 | Usar Next.js e TypeScript | `proposed` | Usuário/owner | Antes da fundação | Define estrutura de código | Bloqueante para implementação |
| D-009 | Usar Supabase/PostgreSQL, Auth e RLS | `proposed` | Usuário/owner | Antes do banco | Define persistência e segurança | Bloqueante para implementação |
| D-010 | Usar Tailwind, Zod, Vitest e Playwright | `proposed` | Usuário/owner | Antes da fundação | Define UI e testes | Bloqueante para implementação |
| D-011 | Usar `America/Sao_Paulo` | `proposed` | Advogado | Antes do scheduler | Define apresentação e janelas | Bloqueante para agenda |
| D-012 | Consultar às 08:00, 13:00 e 18:00 | `proposed` | Advogado | Antes do scheduler | Define carga inicial | Bloqueante para agenda |
| D-013 | Fechar relatório sexta-feira às 17:00 | `proposed` | Advogado | Antes do relatório | Define período | Bloqueante para relatório |
| D-014 | Usar e-mail no MVP | `proposed` | Usuário/advogado | Antes de notificações | Define canal inicial | Bloqueante para envio |
| D-015 | Manter provider de e-mail abstrato | `approved` provisório | Técnico | Antes do código de envio | Evita lock-in | Não bloqueante |
| D-016 | Usar falso/sandbox em desenvolvimento | `proposed` | Técnico | Antes dos testes | Evita envio real | Não bloqueante |
| D-017 | Reter payload bruto por 180 dias | `requires_legal_review` | Jurídico/owner | Antes da retenção | Afeta LGPD e custo | Bloqueante para retenção |
| D-018 | Não excluir relatórios enviados e auditoria automaticamente | `requires_legal_review` | Jurídico/owner | Antes da produção | Afeta privacidade e storage | Bloqueante para política final |
| D-019 | Não consultar processos sigilosos automaticamente no MVP | `approved` provisório | Advogado | Escopo atual | Reduz risco de acesso indevido | Não bloqueante |
| D-020 | Fazer PoC com 5–10 processos públicos reais | `approved` como estratégia | Usuário/advogado | Antes do DataJud integral | Valida risco técnico | Bloqueante para execução |
| D-021 | CNJs devem ser fornecidos e aprovados explicitamente | `requires_user_input` | Usuário | Antes da PoC | Autoriza consulta | Bloqueante |
| D-022 | Definir papéis finais (`owner`, `lawyer`, `operator`, `reviewer`, `auditor`) | `requires_user_input` | Advogado | Antes de RLS | Define autorização | Bloqueante para autorização |
| D-023 | Definir fornecedor de hospedagem | `requires_user_input` | Owner | Antes da implantação | Afeta backup e custo | Bloqueante para produção |
| D-024 | Definir fornecedor de e-mail | `deferred` | Owner | Antes do envio real | Exige contratação e credencial | Bloqueante para envio real |
| D-025 | Definir RPO/RTO e estratégia de backup | `requires_user_input` | Owner/técnico | Antes da produção | Afeta recuperação | Bloqueante para implantação |
| D-026 | Definir limites de retry, backoff e TTL de lock | `proposed` | Técnico | Antes dos workers | Afeta carga e recuperação | Bloqueante para scheduler |
| D-027 | Não instalar dependências nesta auditoria | `approved` | Usuário | Nesta etapa | Mantém escopo documental | Não bloqueante |
| D-028 | Não consultar processos reais nesta auditoria | `approved` | Usuário | Nesta etapa | Mantém segurança | Não bloqueante |
| D-029 | Criar `DESIGN.md` manual seed porque `/impeccable init` real não está disponível | `approved` provisório | Técnico | Nesta etapa | Registra orientação visual sem fingir execução | Não bloqueante |

## Decisões Bloqueantes Atuais

A implementação permanece bloqueada pela aprovação da stack, definição dos papéis, confirmação do fuso e horários, definição do fornecedor de hospedagem e e-mail, política jurídica de retenção, RPO/RTO, parâmetros de workers e fornecimento/aprovação dos CNJs da PoC.

## Decisões Não Bloqueantes

A definição de tokens visuais exatos, componentes finais, novos providers, WhatsApp, SMS e refinamentos de layout podem aguardar a existência de código e a execução posterior de `$impeccable document`. Nenhuma dessas pendências autoriza implementação nesta etapa.

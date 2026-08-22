# Plano de Planejamento — Fase 4C do Juridico

## 1. Objetivo e modo desta execução

Este documento define o plano de trabalho para encerrar a macrofase 4 do projeto **Juridico**, partindo exatamente do commit-base `f17146a0557c5959f1fcc8dc929c467987e487fc` da branch `phase-4b-auth-flows`. A execução atual está em **`/plan`**: nenhum código, migration, workflow, schema, rota, Server Action, dependência ou interface da Fase 4C será implementado nesta etapa.

A implementação futura deverá ocorrer primeiro localmente, em uma branch de planejamento/implementação derivada do commit-base, com validação local e Docker-first. Não serão publicados checkpoints nem trabalho parcialmente testado. O primeiro push somente ocorrerá depois de todos os testes locais completos e da revisão do código, do plano e do relatório. Se o GitHub Actions encontrar um problema específico do ambiente CI, a correção será feita localmente, os testes necessários serão repetidos e será feito somente o push corretivo mínimo; o objetivo é minimizar pushes sem forçar a regra de um push a qualquer custo. Não haverá merge, force-push, release ou alteração de `main`.

| Item | Valor de referência | Regra |
|---|---|---|
| Repositório | `Pguillen87/Juridico` | Fonte de auditoria externa |
| Base exata | `f17146a0557c5959f1fcc8dc929c467987e487fc` | Não partir de `main` |
| Branch de base | `phase-4b-auth-flows` | Deve permanecer intacta |
| Branch do documento | `phase-4c-plan` | Criada localmente somente após `Confirmar`; em `/plan` não criar branch remota nem fazer push |
| `main` | `e48faff7a24a77e469365b9afe2cc5d47b8f4cd1` | Não alterar, não mergear |
| Documento planejado | `docs/plano-fase-4c.md` | Salvo localmente após `Confirmar`, antes do código; não publicar durante `/plan` |
| Impeccable | `unavailable` | Não simular execução |
| Teste manual | Ainda não executado | Deve permanecer explicitamente registrado até que seja feito |

## 2. Estado real analisado

A Fase 4A foi aprovada com o núcleo de identidade, isolamento por escritório, policies RLS, proteção transacional do último owner, testes pgTAP, concorrência, tipos gerados e CI. A Fase 4B foi aprovada com login, logout, recuperação de senha, callback PKCE, cadastro público negado, convite administrativo, Mailpit, convite repetido e suíte E2E de autenticação.

A implementação física atual é deliberadamente menor que o modelo conceitual do MVP. O banco real contém apenas o enum `user_role`, as tabelas `office` e `user_profile` e a função `get_auth_user_profile()`. Não existem ainda tabelas físicas de clientes, partes, processos, monitoramento, providers, jobs, snapshots, notificações, relatórios, artefatos ou auditoria. Portanto, não se deve declarar que as 29 ações de D-022 já estão implementadas apenas porque a matriz documental existe.

No backend atual, `requireAuthenticatedProfile()` valida usuário, perfil ativo e escritório ativo; `requireOwnerProfile()` valida `is_owner`; `inviteUserAction` é a única Server Action administrativa. A action usa `service_role` somente no servidor, extrai `office_id` do perfil autenticado, valida nome/e-mail/papel e executa compensação quando a criação do perfil falha. Não há ações controladas para alterar role, ativar/inativar, conceder/revogar owner, administrar o nome do escritório, consultar auditoria administrativa ou aplicar rate limit da aplicação.

A tela `/app/usuarios` apenas lista nome, role, status e `is_owner` e apresenta o formulário de convite. Não há controles de mutação por usuário, confirmação de ações destrutivas, visualização de auditoria, estado de inconsistência Auth/profile ou tela administrativa do escritório.

O banco possui políticas úteis, mas permissivas demais para a próxima etapa: `authenticated` ainda possui `UPDATE` amplo em `user_profile`, e owners podem atualizar perfis do próprio escritório sem uma API de comando por operação. Os triggers impedem autoelevação de role, owner e office, além de proteger o último owner ativo, mas ainda não constituem, sozinhos, um contrato completo de autorização por ação.

A configuração local do Supabase já possui `enable_signup = false` no bloco global de Auth e mantém `auth.email.enable_signup = true` para preservar login de contas existentes e convites administrativos. O Auth local já possui limites próprios de sign-in/sign-up, verificação de token e envio de e-mail. Esses limites não substituem rate limiting de Server Actions administrativas.

A baseline automatizada atual é: 18 testes unitários, 12 cenários Auth E2E, 34 pgTAP, teste de concorrência do último owner, verificação de tipos, lint, typecheck, format, build implícito no runner standalone, PoC 29/29 e CI `App CI`. O workflow sobe Supabase local, executa `db:reset`, roda Auth E2E, PoC, lint, pgTAP, concorrência e diff de tipos, e encerra o Supabase. Essa baseline deverá continuar verde.

## 3. GAP analysis: documentado versus implementado versus testado versus faltante

| Área | Documentado | Implementado no commit-base | Testado hoje | Faltante para a Fase 4C ou fase posterior |
|---|---|---|---|---|
| Identidade, sessão e tenant | Supabase Auth, `office_id`, perfil ativo, RLS e fail-closed | Sim, em `office`, `user_profile`, `proxy.ts`, guards e callback | 18 unitários, 12 Auth E2E, 34 pgTAP | Endurecer mutações por comando e ampliar combinações role/owner |
| Invite-only | Signup público negado, invite administrativo server-side, mensagens genéricas | Sim, incluindo `inviteUserAction` e configuração local | API pública deny, `/signup` 404, invite/accept e convite repetido | Contagem explícita Auth/profile antes/depois, rate limit, auditoria e concorrência mais forte |
| Usuários e autorização | 29 ações D-022, role funcional único e `is_owner` ortogonal | Somente invite, listagem e invariantes DB parciais | Owner/non-owner, self-elevation e last-owner | Catálogo de permissões, RPCs/actions para role/status/owner, matriz completa e UI |
| Administração do escritório | Nome e estado do office, sem auto-desativação arbitrária | DB permite leitura e update limitado de `name`; não há tela/action | pgTAP para nome e bloqueios de colunas | Action, UI, auditoria, erros e regra explícita para `is_active` |
| Auditoria administrativa | `audit_log` append-only e eventos críticos | Não existe tabela física nem serviço | Não há evidência de audit log | Schema, função de append, RLS de leitura, sanitização, índices e testes |
| Rate limiting | Limites Auth e limites de jobs/admin previstos | Apenas configuração nativa do Auth local | Não há rate limit da aplicação | Limiter persistente para invite/mutações, política e testes atômicos |
| Domínio operacional | Clientes, partes, processos, provider, monitoramento, relatórios e PDF | Não implementado fisicamente | Apenas PoC isolada, não integração do app | Fases posteriores do MVP; não criar tabelas falsas na 4C |
| Fixtures e matriz de combinações | Papéis e `is_owner` ortogonais, cross-office e negativos | Cinco perfis fixos; só lawyer-owner e operator non-owner | Cobertura limitada aos 4B | Fixtures para oito combinações, inativos, dois offices e IDs inexistentes |
| Docker, CI e operação | Local-first, Docker-first, CI reprodutível | Dockerfile do web e Supabase CLI local; CI verde | App CI verde no HEAD-base | Preservar comandos, adicionar suites 4C sem segredos e testar Windows/Docker + Ubuntu |
| Documentação | D-022, arquitetura, modelo conceitual e DoD | Documentação existe, README parcialmente defasado | Relatórios 4A/4B | `docs/plano-fase-4c.md`, depois relatório factual da implementação |

## 4. Decisão de escopo da Fase 4C

A Fase 4C será tratada como o fechamento do **control plane de autorização e administração** da macrofase 4, e não como a implementação integral de todo o MVP. O escopo executável será a parte que pode ser concluída com as tabelas reais de identidade e escritório: contrato canônico de permissões, endurecimento de RLS/grants, mutações administrativas controladas, administração básica do escritório, auditoria administrativa, rate limiting de operações administrativas e a matriz de testes correspondente.

A matriz completa de 29 ações será incorporada ao contrato de autorização. Ações que já possuem entidades físicas (`invite`, perfil, escritório e auditoria a criar) terão enforcement e testes completos nesta fase. Ações que dependem de entidades inexistentes continuarão sem rota ou mutação falsa; terão autorização documentada, critérios de integração e fase de implementação explicitamente indicada. Isso permite encerrar a fundação de segurança sem fingir que clientes, processos, DataJud, scheduler, relatórios ou PDF já existem.

| Dentro da Fase 4C | Fora da Fase 4C e adiado |
|---|---|
| Catálogo das 29 ações e helper único de permissões | Cadastro de clientes, partes e relações |
| Role funcional único + `is_owner` ortogonal | Cadastro/importação de processos e CNJ |
| Listagem, convite, role, status e grant/revoke owner | Providers DataJud/ManualProvider e consultas reais |
| Proteção do último owner em todas as mutações | Scheduler, fila, workers, snapshots e comparação |
| Tratamento fail-closed de Auth/profile órfão | Notificações, e-mail de produção e central de falhas completa |
| Nome/estado do escritório e bloqueio de auto-desativação | Relatório semanal, revisão, PDF e envio |
| `audit_log` administrativo append-only | Backup/RPO/RTO de produção e implantação final |
| Rate limit persistente de invite e mutações | IA, WhatsApp, SMS, múltiplos offices de negócio e portal do cliente |
| Fixtures, unit, integração, pgTAP, concorrência e E2E | Hard delete de `user_profile`/Auth, sem botão/UI; a decisão de preservar histórico está fechada. Fluxo de reconciliação automática permanece posterior |

## 5. Matriz completa de enforcement D-022

A matriz abaixo possui as 29 ações normativas do documento aprovado. `RLS atual` descreve apenas o que existe no commit-base; `DB/RPC 4C` é a solução proposta, não implementação já realizada. A coluna `Evidência` indica a divisão entre testes unitários, integração, pgTAP e E2E.

| # Ação | Role permitido | Efeito de `is_owner` | RLS atual | DB/RPC 4C | Guard server-side | UI 4C ou futura | Unit | pgTAP | E2E | Status atual | Mudança necessária |
|---:|---|---|---|---|---|---|---|---|---|---|---|
| 1 | lawyer/operator/reviewer; auditor DENY | Nenhum | Só existem `office`/perfil; não há dado operacional | Policy por `office_id`, role e estado do recurso | `requirePermission('view_operational_data')` | Futura carteira/dashboard | Permission matrix | Quando tabelas existirem | Futura | Não implementada | Definir contrato agora; implementar com domínio |
| 2 | Somente `is_owner=true` | Concede a ação a qualquer role funcional | Insert público não concedido; invite usa service role | RPC/serviço de invite, unique por Auth/profile e rate limit | `requireOwnerProfile` + permission + schema | Formulário existente com estado controlado | Invite schema/error mapping | Grants e ausência de insert público | V-W/Y + contagem | Parcial, funcional | Auditoria, rate limit, contagem e concorrência |
| 3 | Somente owner | Concede a ação; respeita último owner e self rule | Owner pode update genérico do mesmo office | RPC atômico `deactivate_profile` com lock do office | Owner + alvo do mesmo office | Ação por linha e confirmação | Regras de alvo/status | Invariantes, grants e last-owner | Owner, non-owner, inativo, cross-office, race | Parcial | Remover update genérico e criar comando controlado |
| 4 | Somente owner | Concede a ação a qualquer role | Owner pode update genérico | RPC `change_role`, enum, alvo do mesmo office, sem self-role | Owner + permission | Select por linha e confirmação | Role válido, self, IDs | Policy/RPC/grant | Todas combinações | Não implementada como fluxo | Criar action, RPC, audit e teste direto |
| 5 | Somente owner | Concede grant/revoke, sem alterar role | Trigger protege self; update de terceiros é amplo | RPC `set_owner_status`, lock e proteção last-owner | Owner + regra target | Toggle com confirmação forte | Ortogonalidade role/owner | Trigger/RPC/race | Oito combinações + last-owner | Parcial DB | Completar comando, UI e evidência |
| 6 | lawyer/operator | Não adiciona acesso | Tabela inexistente | Policy por office/role quando `client` existir | Permission específica | Futura tela cliente | Matrix | Futuro | Futuro | Não implementada | Adiar para módulo cliente |
| 7 | lawyer/operator | Não adiciona acesso | Tabela inexistente | Policy por office/role | Permission específica | Futura tela de partes | Matrix | Futuro | Futuro | Não implementada | Adiar para módulo partes |
| 8 | Somente lawyer | Não adiciona acesso | Tabela inexistente | RPC de confirmação, evidência e actor lawyer | Permission + vínculo | Futura tela de vínculos | Confirmação/status | Future RLS/constraint | Futuro | Não implementada | Adiar sem confirmar por nome |
| 9 | lawyer/operator | Não adiciona acesso | Tabela inexistente | Policy tenant + role | Permission | Futura tela de processo | Matrix | Futuro | Futuro | Não implementada | Adiar para processo |
| 10 | lawyer/operator | Não adiciona acesso | Tabela inexistente | RPC import controlado e auditado | Permission + limites | Futura importação | CSV/schema | Futuro | Futuro | Não implementada | Adiar para importação |
| 11 | lawyer/operator | Não adiciona acesso | Tabela inexistente | Policy sobre processo público/provedor | Permission + capability | Futura configuração | Config schema | Futuro | Futuro | Não implementada | Adiar para monitoramento |
| 12 | lawyer/operator | Não adiciona acesso | Tabela inexistente | RPC/job idempotente, lock e rate limit | Permission + processo autorizado | Futura ação manual | Command schema | Futuro | Futuro | Não implementada | Adiar para fila |
| 13 | Somente lawyer | Não adiciona acesso | Tabela inexistente | Policy de payload privado e role | Permission + storage privado | Futura evidência avançada | Matrix/sanitizer | Futuro | Futuro | Não implementada | Adiar para storage/provider |
| 14 | lawyer/operator/reviewer/auditor | Não adiciona acesso | Tabela inexistente | Policy de evidência sanitizada por office | Permission + estado | Futura visão de evidência | Matrix | Futuro | Futuro | Não implementada | Adiar para provider |
| 15 | lawyer/operator/reviewer | Não adiciona acesso | Tabela inexistente | Policy de falha e escopo | Permission | Futura central de falhas | Error mapping | Futuro | Futuro | Não implementada | Adiar para jobs |
| 16 | lawyer/operator | Não adiciona acesso | Tabela inexistente | RPC de tratamento com audit/rate limit | Permission + lock | Futura central de falhas | Command schema | Futuro | Futuro | Não implementada | Adiar para falhas |
| 17 | lawyer/operator/reviewer | Não adiciona acesso | Tabela inexistente | Policy de alterações por office | Permission | Futura histórico | Matrix | Futuro | Futuro | Não implementada | Adiar para comparação |
| 18 | lawyer/reviewer | Não adiciona acesso | Tabela inexistente | Policy de draft e versão imutável | Permission | Futura relatório | Version schema | Futuro | Futuro | Não implementada | Adiar para relatórios |
| 19 | lawyer/reviewer | Não adiciona acesso | Tabela inexistente | RPC de revisão; aprovação continua lawyer | Permission | Futura revisão | State machine | Futuro | Futuro | Não implementada | Adiar para relatório |
| 20 | Somente lawyer | Não adiciona acesso | Tabela inexistente | RPC/policy de approval transition | Permission + version hash | Futura aprovação | State machine | Futuro | Futuro | Não implementada | Adiar para relatório |
| 21 | Somente lawyer | Não adiciona acesso | Tabela inexistente | RPC cancel idempotente e auditado | Permission | Futura ação destrutiva | Confirmation schema | Futuro | Futuro | Não implementada | Adiar para relatório |
| 22 | Somente lawyer | Não adiciona acesso | Tabela inexistente | RPC gera artefato de versão aprovada | Permission + hash | Futura PDF | Hash helper | Futuro | Futuro | Não implementada | Adiar para PDF |
| 23 | Somente lawyer | Não adiciona acesso | Tabela inexistente | RPC de envio só para approved + hash | Permission + approval gate | Futura entrega | Recipient schema | Futuro | Futuro | Não implementada | Adiar para e-mail |
| 24 | lawyer/auditor | Nenhum; owner sozinho não adiciona | Tabela inexistente | Policy `scope=operational`, tenant e role | Permission | Futura auditoria operacional | Matrix | Futuro | Futuro | Não implementada | Separar do admin audit |
| 25 | lawyer/auditor | Nenhum | Tabela inexistente | Export RPC com escopo e filtros seguros | Permission + limit | Futura exportação | Export schema | Futuro | Futuro | Não implementada | Adiar com exportação |
| 26 | auditor ou qualquer role com owner | Owner adiciona acesso administrativo; auditor mantém leitura | Não existe `audit_log` | RLS por `audit_scope=administrative`; append-only | Permission admin audit | Nova leitura administrativa | Matrix/sanitizer | RLS, append-only, no secret | E2E auditor/owner/non-owner | Não implementada | Criar schema, função e tela |
| 27 | auditor ou qualquer role com owner | Owner adiciona exportação administrativa | Não existe `audit_log` | RPC de exportação limitada e auditada | Permission + rate limit | Nova exportação | Export schema | Tenant/limit | E2E direto + UI | Não implementada | Criar endpoint/action sem vazamento |
| 28 | Somente lawyer | Não adiciona acesso | Tabela inexistente | Policy tenant e exportação controlada | Permission + audit | Futura exportação operacional | Export schema | Futuro | Futuro | Não implementada | Adiar para domínio |
| 29 | Somente owner | Concede a qualquer role funcional | `office` permite apenas update de `name`; `is_active` não tem grant | RPC `update_office_settings`, apenas campos aprovados | `requireOwnerProfile` + schema | Nova `/app/configuracoes` provável | Settings schema | Grants/columns/office active | E2E owner/non-owner | Parcial DB | Criar action, UI e audit; bloquear auto-desativação |

A matriz deverá ser mantida como fonte única de verdade. Nenhum novo botão poderá ser criado sem apontar para uma ação da matriz, um guard server-side, um enforcement de banco ou uma justificativa formal de que a ação pertence a uma fase posterior.

## 6. Modelo técnico proposto

### 6.1 Permissões e guards

Criar um catálogo tipado de ações administrativas e operacionais, provavelmente em `src/lib/auth/permissions.ts`, com uma função pura que receba `role`, `is_owner`, estado ativo e ação. A função deverá ser determinística, não consultar banco e não permitir que `is_owner` altere permissões jurídicas ou operacionais que a matriz não lhe concede.

Criar um wrapper server-side, provavelmente em `src/lib/auth/guards.ts`, que combine `requireAuthenticatedProfile()` com a ação solicitada. O wrapper deverá verificar usuário, perfil ativo, escritório ativo, role e `is_owner`, e devolver erro interno controlado ou redirect seguro conforme o contexto. A UI poderá ocultar ações, mas nunca será a autoridade.

Nenhuma Server Action deverá aceitar `office_id`, `actor_user_id`, `is_owner` efetivo ou permissões como verdade fornecida pelo navegador. Esses valores serão derivados da sessão e do perfil do servidor. Os payloads receberão schemas Zod específicos por comando, sem `UPDATE` genérico. `requirePermission()` no Next.js será defesa em profundidade, não a única autoridade: cada RPC administrativa `SECURITY DEFINER` deverá validar no próprio banco `auth.uid()` presente, profile do ator existente, `profile.is_active=true`, office ativo, role/`is_owner` compatíveis com a ação, alvo existente, alvo no mesmo office, invariantes específicas e last-owner quando aplicável. Nunca confiar em `office_id`, `actor_id`, `actor_role` ou `actor_is_owner` enviados pelo cliente.

### 6.2 Mutações de usuário

As operações futuras serão comandos explícitos: convidar, alterar role, ativar/inativar, conceder owner e revogar owner. Cada comando validará o alvo, garantirá mesmo `office_id`, rejeitará role inválido, bloqueará autoelevação, não alterará `id`, `office_id` ou `created_at` por input e aplicará a proteção do último owner na mesma transação do banco.

A proposta é revogar o `UPDATE` genérico de `user_profile` para `authenticated` e conceder somente `SELECT` necessário, usando RPCs `SECURITY DEFINER` com `search_path` fixo, privilégios de execução mínimos e validação de `auth.uid()`. Cada RPC administrativa deverá repetir a autorização no banco: actor autenticado, profile ativo, office ativo, role/owner compatíveis, alvo existente e do mesmo office, invariantes próprias e last-owner quando aplicável. A alternativa de usar `service_role` em todas as mutações deverá ser evitada; ela permanecerá restrita às operações Auth Admin que não possuem equivalente no RLS.

A decisão fechada da Fase 4C é que a operação suportada será **inativação lógica**. Hard delete de `user_profile` ou `Auth` fica fora da Fase 4C: não haverá botão nem UI de hard delete, e o histórico e a auditoria deverão ser preservados. Um Auth user sem profile será tratado como anomalia fail-closed e encaminhado para diagnóstico/repair manual controlado; não haverá associação automática improvisada. Um profile sem Auth não deve existir por causa da FK `ON DELETE CASCADE`, mas será coberto por teste de integridade e relatório de inconsistência.

### 6.3 Auditoria administrativa

Criar uma tabela append-only `audit_log` ou equivalente, com `audit_scope` obrigatório para separar `administrative` de `operational`, `office_id`, ator opcional, ação, tipo de entidade, identificador do recurso, `correlation_id`, metadados sanitizados e timestamp UTC. O desenho deverá impedir `UPDATE` e `DELETE` físicos e deverá ter índices por office/data, ator, ação, entidade e correlação.

A escrita deverá ocorrer por uma função/serviço de append controlado, que derive o ator da sessão e aceite somente um conjunto allowlisted de eventos e metadados. Para cada mutação administrativa, a metadata será sanitizada e limitada ao contrato da ação: `change_role` registra `before.role` e `after.role`; `set_owner` registra `before.is_owner` e `after.is_owner`; `set_active` registra `before.is_active` e `after.is_active`; e `office.rename` registra `before.name` e `after.name`. Metadata arbitrária não será aceita. Nunca serão registrados senha, password hash, token, JWT, cookie, service role, secret key, recovery link, PKCE verifier, FormData bruto ou stack trace com dado sensível. Eventos administrativos mínimos: convite aceito/rejeitado, mudança de role, grant/revoke owner, ativação/inativação, alteração de office, alteração de configuração, bloqueio por last-owner e rejeições sensíveis justificadas.

A leitura administrativa será permitida a `auditor` e a qualquer role funcional quando `is_owner=true`, sempre dentro do mesmo office. `lawyer`, `operator` e `reviewer` com `is_owner=false` receberão DENY. Auditoria administrativa permanece separada de auditoria operacional: ser owner não concede automaticamente acesso à auditoria operacional. A política jurídica definitiva de retenção permanece pendente; na Fase 4C não haverá TTL, purge automático, DELETE periódico nem cron de retenção. Vigora a regra: **“Sem exclusão automática até aprovação formal da política de retenção.”** Essa regra não é uma decisão definitiva de produção.

### 6.4 Rate limiting

O Supabase Auth continuará responsável pelos limites nativos de login, signup, verificação de token e e-mail, que serão apenas documentados e verificados no ambiente local. A aplicação acrescentará limite para invite e mutações administrativas, que hoje não são protegidas por um limiter próprio.

A proposta é um limiter persistente no PostgreSQL, com bucket por operação, office e ator, atualização atômica em RPC transacional e expiração/limpeza controlada. Não armazenar IP ou e-mail bruto. Rate limit por IP somente será usado quando houver uma cadeia de proxy confiável e uma política explícita de normalização; caso contrário, o limite por ator/office é mais confiável para as Server Actions autenticadas.

| Alternativa | Vantagem | Limitação | Decisão proposta |
|---|---|---|---|
| Memória do processo | Simples e barata | Quebra com múltiplas instâncias/restart; não serve para produção fechada | Rejeitar como mecanismo principal |
| Middleware/proxy | Bloqueia cedo | Não possui contador durável e pode confiar em IP incorreto | Usar apenas como defesa complementar se necessário |
| PostgreSQL | Consistente, auditável, funciona no Docker e em múltiplas instâncias | Exige limpeza e cuidado com contenção | Escolher para 4C |
| Redis/serviço externo | Escala e TTL nativo | Nova dependência, custo e operação sem requisito atual | Adiar; não adicionar apenas por precaução |

Os defaults iniciais, calibráveis somente por configuração server-side versionada — nunca por input do navegador — serão os seguintes. O scope padrão é sempre `office + actor + operation`; não será armazenado e-mail bruto; IP somente poderá entrar no futuro se houver proxy confiável formalmente definido. O contador será consumido antes do side effect, com operação atômica, e uma rejeição por limite não deverá criar/alterar o recurso.

| Operação | Operation key | Limite inicial | Janela | Scope | Reset/retry | Ao exceder | Configurabilidade | Justificativa |
|---|---|---:|---|---|---|---|---|---|
| Convite | `admin.invite` | 5 | 15 minutos | office + actor + operation | Próxima janela; resposta com retry-after aproximado | Rejeição genérica, sem chamar Auth Admin | Constante/política server-side allowlisted; calibrável por alteração revisada | Invite envia e-mail e cria identidade; limite reduz spam e duplicação |
| Alterar role | `admin.change_role` | 20 | 15 minutos | office + actor + operation | Próxima janela; retry após reset | Rejeição genérica, sem mutar perfil | Configuração server-side versionada | Mutação sensível, mas com uso operacional moderado |
| Ativar/inativar | `admin.set_active` | 20 | 15 minutos | office + actor + operation | Próxima janela; retry após reset | Rejeição genérica, sem alterar estado | Configuração server-side versionada | Evita abuso de lockout e flapping de acesso |
| Conceder/revogar owner | `admin.set_owner` | 10 | 15 minutos | office + actor + operation | Próxima janela; retry após reset | Rejeição genérica, sem chamar RPC de mudança | Configuração server-side versionada | Permissão de maior impacto, com necessidade de auditoria |
| Alterar nome do office | `admin.update_office_name` | 10 | 15 minutos | office + actor + operation | Próxima janela; retry após reset | Rejeição genérica, sem alterar office | Configuração server-side versionada | Evita abuso de alteração de identificação do tenant |
| Exportar auditoria | `admin.audit_export` | 3 | 1 hora | office + actor + operation | Próxima janela; sem retry imediato | Rejeição genérica e nenhum arquivo gerado | Configuração server-side versionada | Exportação pode carregar muitos eventos e deve ser limitada |

Esses valores são defaults iniciais calibráveis, não uma política definitiva de produção. A implementação deverá retornar `retry-after` ou equivalente quando o contrato permitir, usar mensagem genérica e não confundir bloqueio por abuso com falha de autorização.

## 7. Threat model específico da Fase 4C

| Ameaça | Impacto | Controle proposto | Camada | Teste planejado |
|---|---|---|---|---|
| IDOR | Leitura/mutação de perfil ou audit de outro office | Derivar office do perfil, RLS e checagem de alvo | DB + server | pgTAP, integração e E2E cross-office |
| Spoof de `office_id` | Escrita em tenant incorreto | Ignorar campo do cliente; RPC resolve office pelo actor | Server + DB | FormData adulterado e SQL/RPC |
| Self elevation | Usuário torna-se owner ou muda role | Proibição no helper, action e trigger/RPC | DB + server | Unit, pgTAP e E2E direto |
| Privilege escalation | Role/owner alterado fora da matriz | Catálogo canônico e comandos específicos | Todas | Matriz completa por role/owner |
| Race de last-owner | Escritório fica sem owner ativo | Lock do office e contagem transacional | DB | Concorrência existente + novas mutations |
| Role tampering | Payload cria role inválido ou troca papel indevido | Zod enum, RPC e UI sem input livre | Server + DB | Unit, pgTAP, FormData forjado |
| Exposição de `service_role` | Bypass total de RLS | `server-only`, env runtime e inspeção de bundle | Build + server | Scan de bundle/browser e CI hygiene |
| Client Component importando admin | Chave de serviço no navegador | Separar módulos server-only e actions | Arquitetura | Typecheck/build e teste de import |
| FormData forjado | Chamada direta ignora UI | Revalidar tudo no servidor; ignorar actor/office | Server | Invocação direta de action |
| Invocação direta de Server Action | Bypass de botões/rotas | Guard dentro de cada action e RPC | Server + DB | Testes unitários/integrados sem browser |
| CSRF/origin | Operação administrativa não autorizada | Preservar proteção de Server Actions e validar origem quando houver endpoint | Next/server | Teste de origem inválida quando aplicável |
| Replay | Repetição de mutação sensível | Operações idempotentes, estado esperado e audit/correlation | DB + server | Repetir mesma mutation |
| Duplicate submit | Dois invites ou duas mutations | Botão pending, limiter, constraints e resposta controlada | UI + DB | Double click e concorrência |
| Stale session | Sessão válida com perfil já inativo | `getUser`, profile/office ativo em cada comando | Server + RLS | Inativar e usar token antigo |
| Usuário inativo | Acesso após inativação | Policies/guards fail-closed | DB + server | pgTAP/E2E |
| Office inativo | Acesso de tenant desativado | `get_auth_user_profile` e guard exigem office ativo | DB + server | pgTAP/E2E |
| Auth user órfão | Usuário Auth sem autorização | Não associar automaticamente; diagnóstico fail-closed | Admin/server | Fixture de orphan e ausência de acesso |
| Profile órfão | Perfil sem identidade | FK/cascade e integrity check | DB | pgTAP/repair test |
| Enumeração | Descobrir e-mails existentes | Mensagens genéricas; admin message limitada | UI/server | Login/recovery/invite repeated |
| Abuso/rate limit | Spam de invite/mutações | Bucket PostgreSQL por actor/office e Auth limits | DB + server | limite, janela, bypass, concorrência |
| Log sensível | Vazamento de PII/segredos | Allowlist e sanitização; proibição de campos | Audit/log | Teste de metadata proibida |

## 8. Planejamento por 26 camadas

### Camada 1 — Regras de negócio

| Campo | Plano |
|---|---|
| Objetivo | Transformar D-022 em comandos inequívocos, separando role funcional de capacidade administrativa. |
| Estado atual | Matriz documental aprovada; apenas invite/listagem implementados. |
| Lacunas | Não há state machine para role/status/owner nem regra operacional formal para auto-inativação. |
| Solução técnica | Registrar invariantes: um role funcional, owner ortogonal, office derivado, usuário inativo sem acesso, último owner protegido, sem hard delete na UI. |
| Arquivos existentes | `docs/10-matriz-papeis-e-autorizacao.md`, `src/lib/auth/guards.ts`, `src/lib/auth/validation.ts`. |
| Arquivos novos prováveis | `src/lib/auth/permissions.ts` e seus testes. |
| Dependências | Aprovação das regras A–N já registrada; decisões de escopo sobre hard delete e office estão fechadas; política inicial de rate limit está definida na camada 10. |
| Riscos | Interpretar owner como role ou liberar acesso jurídico por engano. |
| Testes | Matriz unitária das 29 ações e cenários negativos por comando. |
| Pronto | Cada ação tem ALLOW/DENY/NOT_APPLICABLE, fonte e teste previsto. |

### Camada 2 — Modelo de dados

| Campo | Plano |
|---|---|
| Objetivo | Completar somente o modelo físico necessário ao control plane da 4C. |
| Estado atual | `office` e `user_profile`; modelo conceitual amplo ainda não físico. |
| Lacunas | Sem auditoria e rate limiter; sem tabelas de domínio operacional. |
| Solução técnica | Adicionar `audit_log` com scope e `rate_limit_bucket`/equivalente; não criar entidades de clientes/processos nesta fase. |
| Arquivos existentes | Migration core, `src/types/database.types.ts`. |
| Arquivos novos prováveis | Uma ou duas migrations da 4C e tipos gerados. |
| Dependências | Decisão do formato de audit scope e limites. |
| Riscos | Schema prematuro ou incompatível com auditoria operacional futura. |
| Testes | Gerar tipos, constraints, RLS e integração. |
| Pronto | Modelo mínimo, versionado, sem entidade operacional falsa e com backward compatibility. |

### Camada 3 — Migrations

| Campo | Plano |
|---|---|
| Objetivo | Aplicar mudanças incrementais, revisáveis e reversíveis por forward-fix. |
| Estado atual | Uma migration `20260821000616_20260820000000_core_identity_and_rls.sql`. |
| Lacunas | Nenhuma migration de auditoria, comandos administrativos ou limiter. |
| Solução técnica | Migration A para grants/RPCs/audit; Migration B para rate limiter se separação reduzir risco. Preservar enum `user_role`, FKs e dados existentes. |
| Arquivos existentes | `supabase/migrations/20260821000616_20260820000000_core_identity_and_rls.sql`. |
| Arquivos novos prováveis | `supabase/migrations/<timestamp>_phase_4c_authorization_audit.sql`; `..._rate_limit.sql`. |
| Dependências | pgTAP local e `db:reset` antes de aceitar. |
| Riscos | Lock de tabela, grants insuficientes ou migration não idempotente. |
| Testes | `db:reset`, `db:lint`, pgTAP, tipos e teste de rollback em banco descartável. |
| Pronto | Reset reproduz o schema inteiro desde zero e nenhum dado existente perde coluna/semântica. |

### Camada 4 — Constraints, triggers e RPCs

| Campo | Plano |
|---|---|
| Objetivo | Fazer invariantes críticas sobreviverem a chamadas diretas e concorrentes. |
| Estado atual | Triggers de self-elevation e last-owner existem. |
| Lacunas | Update genérico, sem RPC por comando, sem append audit e sem limiter atômico. |
| Solução técnica | RPCs específicas para role/status/owner/settings/audit/rate-limit, `SECURITY DEFINER`, `search_path` fixo, lock de office e grants mínimos. Reusar e testar a trigger de último owner, não duplicá-la na UI. |
| Arquivos existentes | Migration core, `supabase/tests/database/01_core_identity.test.sql`. |
| Arquivos novos prováveis | Migration 4C e `supabase/tests/database/02_phase_4c_authorization.test.sql`. |
| Dependências | Camadas 1–3. |
| Riscos | RPC com bypass, `SECURITY DEFINER` vulnerável ou rollback parcial entre Auth e DB. |
| Testes | Execução como anon/authenticated, input cross-office, self, IDs inexistentes e race. |
| Pronto | SQL direto não consegue contornar invariantes nem gravar audit inválido. |

### Camada 5 — RLS e tenant isolation

| Campo | Plano |
|---|---|
| Objetivo | Isolar office em leitura, mutação e auditoria. |
| Estado atual | `office`/`user_profile` possuem RLS e policies; inactive é filtrado. |
| Lacunas | Policies de perfil permitem update genérico ao owner; audit/limiter inexistentes. |
| Solução técnica | Revogar update amplo de `authenticated`, permitir somente RPCs, adicionar policies de audit por scope/office e limitar leitura de buckets ao serviço. Toda policy deverá exigir perfil e office ativos quando aplicável. |
| Arquivos existentes | Migration core e guards. |
| Arquivos novos prováveis | Migrations 4C e pgTAP 4C. |
| Dependências | RPCs e matriz de autorização. |
| Riscos | Silêncio de RLS em `UPDATE` ser confundido com sucesso; service role mascarar falha. |
| Testes | 34 atuais preservados; novos cross-office, inactive, direct API/SQL e grants. |
| Pronto | Nenhuma leitura/mutação administrativa de outro office é possível com chave pública. |

### Camada 6 — Autorização server-side

| Campo | Plano |
|---|---|
| Objetivo | Tornar server-side a autoridade efetiva de cada ação. |
| Estado atual | `requireAuthenticatedProfile` e `requireOwnerProfile`. |
| Lacunas | Não há `requirePermission(action)` nem autorização por role além de owner. |
| Solução técnica | Criar permission helper puro e wrapper server-side; exigir guard dentro de cada action, nunca somente na página. Mapear erros para mensagens seguras. |
| Arquivos existentes | `src/lib/auth/guards.ts`, actions de usuários. |
| Arquivos novos prováveis | `src/lib/auth/permissions.ts`, testes e talvez `src/lib/auth/errors.ts`. |
| Dependências | Matriz D-022 e schemas Zod. |
| Riscos | UI esconder mas API aceitar; erro de redirect virar 500 genérico. |
| Testes | Unitários de cada combinação; integração de chamada direta; E2E de deny. |
| Pronto | Cada comando tem guard e teste negativo independente da UI. |

### Camada 7 — Administração de usuários

| Campo | Plano |
|---|---|
| Objetivo | Entregar uma fatia vertical utilizável de gestão de usuários sem autoelevação. |
| Estado atual | Listagem e convite. |
| Lacunas | Role, active, owner, confirmação, pending/orphan e auditoria ausentes. |
| Solução técnica | Estender `actions.ts` com comandos explícitos; usar RPCs; manter invite server-only; não expor update genérico. Soft-deactivate como remoção suportada. |
| Arquivos existentes | `src/app/app/usuarios/actions.ts`, `page.tsx`, `invite-form.tsx`, validation e admin client. |
| Arquivos novos prováveis | Componentes de ações por linha e schemas/tests específicos. |
| Dependências | Camadas 1–6, audit e limiter. |
| Riscos | Race Auth/DB no invite, ação destrutiva sem confirmação, orphan Auth. |
| Testes | Unit/action, pgTAP, contagem antes/depois, repeated invite, direct action e E2E. |
| Pronto | Owner gerencia somente membros do próprio office; non-owner, inactive e cross-office falham sem vazamento. |

### Camada 8 — Administração do escritório

| Campo | Plano |
|---|---|
| Objetivo | Expor apenas configurações administrativas aprovadas. |
| Estado atual | DB permite owner alterar `office.name`; não há action/UI. `is_active` não é concedível ao usuário. |
| Lacunas | Nenhuma tela, auditoria ou contrato para nome/estado. |
| Solução técnica | Criar action de alteração de nome com schema e audit; exibir estado ativo como leitura; não criar botão de desativação arbitrária pelo próprio owner. Ativação/desativação operacional fica em fluxo controlado futuro. |
| Arquivos existentes | Migration core, `src/app/app/page.tsx`. |
| Arquivos novos prováveis | `src/app/app/configuracoes/page.tsx`, `actions.ts`, componente de formulário. |
| Dependências | D-022 e auditoria; o escopo do office está fechado nesta fase e não há outras configurações previstas. |
| Riscos | Desativar o próprio tenant e lockout. |
| Testes | pgTAP de colunas/grants, action direta, owner/non-owner e E2E. |
| Pronto | Owner altera somente nome aprovado; status é visível; `is_active` não é alterado pelo browser. |

### Camada 9 — Auditoria administrativa

| Campo | Plano |
|---|---|
| Objetivo | Provar quem fez o quê, onde, quando e sobre qual recurso. |
| Estado atual | Nenhum audit log físico. |
| Lacunas | Sem schema, append-only, sanitização, leitura/exportação ou eventos. |
| Solução técnica | `audit_log` append-only com scope, função de append, allowlist de ações, before/after sanitizados e policies de leitura/exportação. Não implementar TTL, purge automático, DELETE periódico ou cron de retenção; vigora “Sem exclusão automática até aprovação formal da política de retenção.” Registrar sucesso e rejeições sensíveis justificáveis. |
| Arquivos existentes | Actions, migration core, relatório conceitual. |
| Arquivos novos prováveis | Migration, `src/lib/audit.ts`, testes unitários/pgTAP. |
| Dependências | Ações administrativas e correlation id. |
| Riscos | PII/segredo em metadata ou auditoria que possa ser alterada pelo actor. |
| Testes | Insert permitido apenas pelo mecanismo controlado, update/delete negados, filtros tenant e redaction. |
| Pronto | Cada mutation 4C gera audit verificável e nenhum segredo aparece no log. |

### Camada 10 — Rate limiting/abuso

| Campo | Plano |
|---|---|
| Objetivo | Reduzir abuso de invite e mutações sem duplicar o Auth limiter. |
| Estado atual | Supabase Auth possui limites nativos; application actions não possuem bucket. |
| Lacunas | Sem limite por actor/office, reset de janela ou teste de concorrência. |
| Solução técnica | RPC PostgreSQL de bucket atômico; chaves por operação/office/actor; mensagens genéricas; defaults concretos da tabela de rate limit da seção 6.4, configuráveis somente server-side e documentados. IP só quando proxy confiável. |
| Arquivos existentes | `supabase/config.toml`, `inviteUserAction`, env schema. |
| Arquivos novos prováveis | Migration, `src/lib/rate-limit.ts`, tests. |
| Dependências | Camadas DB, actions e política de limites. |
| Riscos | Bloquear operação legítima, contador preso ou bypass por múltiplas instâncias. |
| Testes | limite, reset, actor/office diferentes, bypass, direct action e race. |
| Pronto | Limiter é atômico, observável, não guarda PII bruta e não pode ser pulado pela UI. |

### Camada 11 — Frontend/UI/UX

| Campo | Plano |
|---|---|
| Objetivo | Apresentar controles autorizados sem substituir enforcement. |
| Estado atual | `/app/usuarios` é tabela simples + invite. |
| Lacunas | Sem ações por linha, confirmação, loading individual, empty/error/audit/config screens. |
| Solução técnica | Manter linguagem sóbria do `DESIGN.md`; adicionar controles por capacidade, confirmação explícita para role/owner/status, status textual, foco, teclado, mobile e mensagens sem enumeração. |
| Arquivos existentes | `src/app/app/page.tsx`, `src/app/app/usuarios/page.tsx`, `invite-form.tsx`, CSS. |
| Arquivos novos prováveis | Componentes client de row actions e `/app/configuracoes`. |
| Dependências | Actions e permission catalog. |
| Riscos | Renderizar botão para ação não permitida ou depender de cor. |
| Testes | E2E por estado, acessibilidade estrutural, keyboard focus e mobile viewport. |
| Pronto | UI apenas oferece ações permitidas, nunca mostra segredo/ID sensível e tem estados loading/vazio/erro/sucesso. |

### Camada 12 — Contratos/Server Actions/APIs

| Campo | Plano |
|---|---|
| Objetivo | Fixar contratos de comando e respostas controladas. |
| Estado atual | Uma action de invite recebe FormData e retorna `{success|error}`. |
| Lacunas | Sem contratos de role/status/owner/settings/audit/export/limiter. |
| Solução técnica | Uma action por operação ou dispatcher explicitamente tipado; schemas Zod; resposta serializável e mensagem sanitizada; no browser, nenhum acesso a service role. |
| Arquivos existentes | `src/app/app/usuarios/actions.ts`, `invite-form.tsx`. |
| Arquivos novos prováveis | `actions.ts` de configurações, contratos e helpers. |
| Dependências | Server guards, RPCs, audit e rate limit. |
| Riscos | API genérica, direct invocation ou retorno de erro Supabase. |
| Testes | Chamadas diretas, FormData adulterada, IDs inexistentes e status controlado. |
| Pronto | Cada contrato rejeita payload fora do schema e repete operação sem elevação/duplicação. |

### Camada 13 — Validação/Zod

| Campo | Plano |
|---|---|
| Objetivo | Validar inputs de cada comando, sem usar validação HTML como autoridade. |
| Estado atual | Schemas de login/recovery/reset/invite. |
| Lacunas | Sem schemas de role mutation, status, owner e settings. |
| Solução técnica | Schemas pequenos: `changeRole`, `setActive`, `setOwner`, `updateOfficeName`, `auditFilter`, rate-limit config interna. Normalizar e-mail; rejeitar campos desconhecidos quando aplicável. |
| Arquivos existentes | `src/lib/auth/validation.ts`. |
| Arquivos novos prováveis | Mesmo arquivo estendido e tests. |
| Dependências | Matriz e contratos. |
| Riscos | Aceitar `office_id`, actor ou flags arbitrárias. |
| Testes | Valores válidos, role inválido, vazio, limites de nome, IDs malformados e unknown fields. |
| Pronto | Toda action valida no servidor e retorna erro seguro sem stack/IDs/segredos. |

### Camada 14 — Erros/recuperação/idempotência

| Campo | Plano |
|---|---|
| Objetivo | Ter respostas previsíveis e sem lixo em falhas ou replays. |
| Estado atual | Invite repetido retorna mensagem segura; compensation existe; E2E usa fixtures. |
| Lacunas | Sem contagem Auth/profile, lock por alvo, audit de rejeição e tratamento formal de orphan. Recovery 4B tem tolerância documentada a `Auth session missing`. |
| Solução técnica | Mapear erros internos para códigos/mensagens; usar unique/FK/RPC/limiter; não compensar usuário preexistente; registrar anomalia sem associação automática. Avaliar a dívida de recovery separadamente, sem reabrir 4B sem teste reprodutível. |
| Arquivos existentes | Invite action, bootstrap fixtures, auth E2E, reset page. |
| Arquivos novos prováveis | Error mapper, teste de idempotência/diagnóstico. |
| Dependências | Auth Admin e banco. |
| Riscos | Deletar Auth legítimo durante corrida ou mascarar sucesso parcial. |
| Testes | Duplicate submit, retry, partial failure, orphan e contagens before/after. |
| Pronto | Repetições não criam Auth/profile extra, não elevam papel e deixam erro auditável/controlado. |

### Camada 15 — Segurança

| Campo | Plano |
|---|---|
| Objetivo | Aplicar threat model e fail-closed em todas as fronteiras. |
| Estado atual | RLS, server-only admin e mensagens genéricas já existem parcialmente. |
| Lacunas | Sem audit/rate limit e sem teste da matriz completa. |
| Solução técnica | Corrigir grants, RPCs com `SECURITY DEFINER` seguro, sanitização, origem, serviço server-only, bundle scan, tenant isolation e stale-session checks. |
| Arquivos existentes | `admin.ts`, `server.ts`, `proxy.ts`, guards, workflow. |
| Arquivos novos prováveis | Security tests e helpers. |
| Dependências | Todas as camadas anteriores. |
| Riscos | Bypass por service role, vazamento de metadata ou trust indevido em headers. |
| Testes | Threat model completo e testes negativos obrigatórios. |
| Pronto | Não há caminho de browser/API direta para mutação não autorizada e CI não versiona segredo. |

### Camada 16 — Testes unitários

| Campo | Plano |
|---|---|
| Objetivo | Provar regras puras e mapeamentos sem depender apenas de mocks. |
| Estado atual | 18 testes cobrindo guards, validation, admin/client e ações. |
| Lacunas | Sem permission matrix, audit mapping, limiter e comandos novos. |
| Solução técnica | Adicionar aproximadamente 20–30 testes novos, sem fixar número final antes da implementação: todas as combinações role/owner, schemas, error mapping, audit sanitizer, limiter decision e idempotency. |
| Arquivos existentes | `src/lib/auth/guards.test.ts`, `validation.test.ts`, `src/app/app/usuarios/actions.test.ts`. |
| Arquivos novos prováveis | `permissions.test.ts`, `audit.test.ts`, `rate-limit.test.ts`. |
| Dependências | Contratos definidos. |
| Riscos | Mocks darem falsa segurança. |
| Testes | Unitários serão complemento; cada autorização sensível também terá DB/integration/E2E. |
| Pronto | 18 existentes + novos verdes; nenhum teste removido para facilitar implementação. |

### Camada 17 — Testes de integração

| Campo | Plano |
|---|---|
| Objetivo | Exercitar actions/RPCs com sessão, banco e payload real. |
| Estado atual | Testes unitários mockados e Auth E2E; não há suíte específica de admin mutation. |
| Lacunas | Direct action, cross-office, inactive, duplicate counts e orphan. |
| Solução técnica | Testar cada action fora da UI, com usuários sintéticos e Supabase local; usar service role somente para setup/observação autorizada, nunca para provar deny público. |
| Arquivos existentes | `actions.test.ts`, `bootstrap-auth-fixtures.mjs`. |
| Arquivos novos prováveis | `tests-integration/admin-actions.test.ts` ou scripts equivalentes, com caminho final confirmado antes de criar. |
| Dependências | Docker/Supabase local e migrations. |
| Riscos | Teste observar banco com privilégios e confundir setup com enforcement. |
| Testes | Happy/negative/direct/forged/cross-office/inactive/nonexistent/race. |
| Pronto | Cada comando falha corretamente fora da UI e deixa estado consistente. |

### Camada 18 — Testes de banco/pgTAP

| Campo | Plano |
|---|---|
| Objetivo | Preservar e ampliar a prova independente de RLS, grants, constraints e RPCs. |
| Estado atual | 34/34 em `01_core_identity.test.sql`. |
| Lacunas | Sem audit, rate limit, role combinations completas e RPCs de 4C. |
| Solução técnica | Manter os 34; adicionar suite(s) para audit append-only, grants, policies por scope, RPCs, inactive, owner combinations, cross-office, direct SQL/API e limiter. |
| Arquivos existentes | `supabase/tests/database/01_core_identity.test.sql`. |
| Arquivos novos prováveis | `supabase/tests/database/02_phase_4c_authorization.test.sql` e `03_phase_4c_audit_rate_limit.test.sql`. |
| Dependências | Migrations e database types. |
| Riscos | Tests que passam como postgres mas não como authenticated. |
| Testes | `set_auth_user` e roles reais, pelo menos uma prova por policy e comando. |
| Pronto | 34+ testes verdes, sem reduzir a suíte atual, com bypass direto negado. |

### Camada 19 — Testes de concorrência

| Campo | Plano |
|---|---|
| Objetivo | Provar que invariantes permanecem verdadeiras sob corridas. |
| Estado atual | Script last-owner cobre duas transações e exatamente um owner ativo. |
| Lacunas | Mutations novas e limiter não testados sob corrida. |
| Solução técnica | Preservar `test_concurrency.sh`; adicionar somente corridas com risco real: revoke/deactivate owner, duplicate invite/profile, role/status target e consumo do mesmo bucket. |
| Arquivos existentes | `supabase/tests/concurrency/test_concurrency.sh`. |
| Arquivos novos prováveis | Script 4C específico ou extensão explícita do existente. |
| Dependências | RPCs com lock e unique constraints. |
| Riscos | Flake por timing de shell; resultado não determinístico. |
| Testes | Uma operação deve vencer/rejeitar conforme contrato, nunca deixar zero owners ou dois profiles. |
| Pronto | Last-owner continua verde e novas corridas têm resultado determinístico documentado. |

### Camada 20 — Testes E2E/Playwright

| Campo | Plano |
|---|---|
| Objetivo | Provar que usuários reais veem e executam somente ações autorizadas. |
| Estado atual | 12 cenários Auth em `auth.spec.ts`, serial, localhost, standalone. |
| Lacunas | Só owner-lawyer e operator; sem reviewer/auditor ou mutations administrativas. |
| Solução técnica | Adicionar `tests-e2e/admin.spec.ts` ou extensão claramente separada, mantendo os 12 Auth. Cobrir owner abre admin, non-owner deny, role/status/owner/settings, duplicate, audit, direct request e mobile/keyboard básico. |
| Arquivos existentes | `tests-e2e/auth.spec.ts`, `playwright.config.ts`, `run-auth-e2e.mjs`. |
| Arquivos novos prováveis | `tests-e2e/admin.spec.ts`, helpers de fixture/observação. |
| Dependências | Fixtures completos e migrations. |
| Riscos | Retry alterar banco e contaminar teste serial; flake de cookie PKCE já conhecido. |
| Testes | Reset/cleanup idempotente, e-mail dinâmico somente quando necessário, contagem Auth/profile após duplicate. |
| Pronto | Auth 4B e todos os cenários 4C verdes no CI, sem aceitar sucesso falso por retry. |

### Camada 21 — Fixtures e dados sintéticos

| Campo | Plano |
|---|---|
| Objetivo | Dar cobertura real à ortogonalidade role/owner e aos negativos. |
| Estado atual | Dois offices e cinco perfis; somente lawyer-owner e operator non-owner. |
| Lacunas | Faltam lawyer/operator/reviewer/auditor com e sem owner, inactive por combinação e cross-office abrangente. |
| Solução técnica | Estender `bootstrap-auth-fixtures.mjs` com UUIDs/e-mails sintéticos fixos e reset seguro; criar dois ou mais owners apenas onde a race exige. Não usar processos/CNJs reais. |
| Arquivos existentes | `scripts/bootstrap-auth-fixtures.mjs`, Auth E2E. |
| Arquivos novos prováveis | Helper de snapshot administrativo se necessário. |
| Dependências | Auth local, `db:reset`, Mailpit. |
| Riscos | Retrys deixarem senha/usuário em estado alterado. |
| Testes | Pre/post counts, limpeza de dynamic invite e verificação de role/owner/office. |
| Pronto | Todas as oito combinações mínimas existem e são usadas em testes identificáveis. |

### Camada 22 — CI

| Campo | Plano |
|---|---|
| Objetivo | Validar a implementação futura no mesmo pipeline auditável. |
| Estado atual | `App CI` tem hygiene, format, lint, typecheck, unit, Supabase, Auth E2E, PoC, db lint, pgTAP, concorrência, tipos e teardown. |
| Lacunas | Não há suites 4C; o build é exercitado dentro do runner Auth E2E, não como passo nominal separado. |
| Solução técnica | Preservar todos os passos e adicionar novas suites sem segredo externo. Avaliar tornar `npm run build` explícito somente se não duplicar o build standalone; não retirar a prova atual. Adicionar a branch de implementação ao trigger apenas quando autorizado. |
| Arquivos existentes | `.github/workflows/app-ci.yml`, `playwright.config.ts`, scripts. |
| Arquivos novos prováveis | Nenhum obrigatório; testes entram nos diretórios existentes. |
| Dependências | Docker disponível no `ubuntu-latest` e local Supabase. |
| Riscos | CI gastar tempo com suites serial; dependência de portas/PKCE. |
| Testes | CI final deve ter `head_sha` igual ao HEAD novo, completed/success e todos os jobs verdes. |
| Pronto | Nenhum push final antes de local verde; nenhuma chave real no workflow. |

### Camada 23 — Docker/execução local

| Campo | Plano |
|---|---|
| Objetivo | Não inviabilizar o pacote fechado local futuro. |
| Estado atual | Dockerfile produz Next standalone; compose sobe web em `3000`; Supabase é iniciado pela CLI. |
| Lacunas | Compose não empacota o Supabase local como stack única e o README está defasado quanto à fase. |
| Solução técnica | Manter Node 22, variáveis runtime e web stateless; testar `docker compose up --build -d`, `supabase start`, `db:reset`, fixtures e cleanup. Não introduzir Redis ou serviço permanente para rate limit. |
| Arquivos existentes | `Dockerfile`, `docker-compose.yml`, `scripts/run-auth-e2e.mjs`, README. |
| Arquivos novos prováveis | Ajustes de documentação; nenhum novo container obrigatório. |
| Dependências | Docker Desktop Windows e Docker Ubuntu CI. |
| Riscos | Env ausente, porta ocupada, divergência localhost/127.0.0.1. |
| Testes | Execução local no Windows com Docker Desktop e CI Ubuntu; teardown obrigatório. |
| Pronto | Fase 4C não quebra build/start do pacote e os comandos ficam documentados. |

### Camada 24 — Logs/observabilidade

| Campo | Plano |
|---|---|
| Objetivo | Dar evidência operacional mínima sem registrar dados sensíveis. |
| Estado atual | Logs de CI e erros sanitizados básicos; não há correlation id sistemático. |
| Lacunas | Sem audit, métricas de deny/limiter e duração das ações. |
| Solução técnica | Gerar `correlation_id` por comando/request quando disponível; logar ação, office pseudonimizado, actor pseudonimizado, resultado, duração e código sanitizado. Métricas mínimas: invites aceitos/rejeitados, mutations denied, last-owner bloqueios, limiter blocks, audit failures. |
| Arquivos existentes | Actions, workflow e scripts. |
| Arquivos novos prováveis | Helper de logger/audit, se necessário; evitar framework novo. |
| Dependências | Audit e error mapping. |
| Riscos | PII, e-mail, token ou payload em logs. |
| Testes | Scan textual, testes de sanitização e revisão de logs CI. |
| Pronto | Nenhuma chave, senha, token, cookie, recovery link ou stack sensível aparece. |

### Camada 25 — Rollback

| Campo | Plano |
|---|---|
| Objetivo | Reverter código sem destruir evidência nem deixar schema incompatível. |
| Estado atual | Migration 4A já publicada; branch 4B aprovada. |
| Lacunas | Não há runbook de rollback para audit/limiter/admin actions. |
| Solução técnica | Código reversível por commit; migrations preferencialmente forward-fix, sem `DROP` destrutivo; desabilitar UI/action antes de remover função; preservar audit; soft-deactivate em vez de delete. |
| Arquivos existentes | Migrations, workflow e Docker. |
| Arquivos novos prováveis | Runbook futuro em `docs/` se aprovado. |
| Dependências | Ordem de migrations e generated types. |
| Riscos | Rollback de código antigo contra schema novo; bucket/audit perder referências. |
| Testes | Aplicar migration/reset em cópia, restaurar código anterior, validar leitura e `db:lint`. |
| Pronto | Cada subetapa tem caminho de retorno, risco de dados e decisão sobre forward-fix documentados. |

### Camada 26 — Riscos e dependências

| Campo | Plano |
|---|---|
| Objetivo | Bloquear avanço quando faltar decisão jurídica, técnica ou autorização. |
| Estado atual | D-022 e Docker estão aprovados; o escopo de usuários, office e auditoria administrativa da 4C está fechado; retenção jurídica, RPO/RTO, e-mail, horários e providers ainda têm pendências. |
| Lacunas | Hard delete de usuário e escopo de office já estão decididos para esta fase; permanecem pendentes apenas a política jurídica definitiva de retenção, RPO/RTO, produção e calibração posterior dos defaults de rate limit. |
| Solução técnica | Gate antes de cada fatia; implementar somente controle local/admin que não dependa de decisões externas; manter inativação lógica e histórico preservado; não criar hard delete/UI de remoção; não implementar exclusão automática de audit; registrar dependências e parar diante de credencial, processo real, dado sigiloso ou migration destrutiva. |
| Arquivos existentes | `docs/05-riscos-e-decisoes-pendentes.md`, `docs/07-decisoes-do-mvp.md`, `docs/09-definicao-de-pronto.md`. |
| Arquivos novos prováveis | Se aprovado, atualizar relatório de 4C após implementação; não agora. |
| Dependências | Política jurídica de retenção para decisão futura, LGPD/RPO/RTO, auditoria externa e Docker local. O escopo de usuários e office não é mais uma decisão pendente da 4C. |
| Riscos | Scope creep para o MVP inteiro ou falsa conclusão da macrofase. |
| Testes | Revisão de checklist e auditoria externa do plano/implementação. |
| Pronto | Todos os riscos críticos têm dono, resposta, evidência e condição de parada. |

## 9. UI/UX planejada por tela

A Fase 4C não fará redesign nesta etapa. O `DESIGN.md` seed será seguido: clareza operacional, texto explícito de estado, distinção entre erro e ausência de ação, foco visível, controles acessíveis e confirmação humana para mutações sensíveis. O craft/critique/audit do Impeccable deverá ocorrer somente quando houver UI implementada e a ferramenta estiver disponível; nesta execução, registrar `impeccable: unavailable`.

| Rota | Objetivo | Role/owner | Componentes previstos | Estados obrigatórios | Destrutiva | Acessibilidade/mobile |
|---|---|---|---|---|---|---|
| `/app` | Mostrar contexto, role e capacidade administrativa | Todo perfil ativo; link admin somente owner | Layout atual, cards de contexto, navegação | loading de navegação, sessão expirada, office inativo | Logout não destrutivo; confirmação se novo controle surgir | Heading/landmarks, teclado, cards empilhados |
| `/app/usuarios` | Listar e administrar membros do office | Owner para mutar; auditor/non-owner recebem deny | Tabela, ações por linha, invite form, audit link | loading da tabela, vazio, erro, sucesso, conflito, inactive, pending/orphan | role, owner, inativação exigem confirmação textual | Tabela responsiva ou cards, labels, foco, sem cor única |
| `/app/configuracoes` | Ver office ativo e alterar nome permitido | Owner; demais recebem deny | Form de nome, status read-only, histórico/audit link | loading, nome inválido, conflito, sucesso, office inativo | Não oferecer self-deactivate; eventual ação futura exige confirmação | Form labels, live region, mobile-first |
| `/app/auditoria-administrativa` ou seção controlada | Consultar/exportar eventos administrativos | auditor ou owner conforme D-022 | filtros, tabela, detalhes sanitizados, export | vazio, loading, erro, limite, sem acesso | Export exige confirmação se gerar arquivo | Não expor secrets/IDs desnecessários; tabela adaptável |

O texto de erro deve diferenciar `não autorizado`, `alvo inexistente`, `operação bloqueada pelo último owner`, `limite temporário` e `falha inesperada`, sem revelar se um e-mail público está cadastrado ou detalhes internos do Supabase. A UI não poderá confiar apenas em `is_owner` vindo de props do cliente; a action valida novamente.

## 10. Migrations e compatibilidade

A ordem proposta é primeiro a migration de auditoria e endurecimento de grants/RPCs, depois a migration de rate limit se a separação facilitar revisão. Nenhuma migration será executada nesta execução de planejamento. Na implementação futura, cada migration será criada localmente, lida, aplicada por `db:reset` desde zero e testada em banco descartável antes de qualquer commit.

As mudanças deverão ser aditivas ou de restrição controlada. Não alterar o enum para incluir `owner`; `is_owner` permanece booleano separado. Não remover colunas existentes. A revogação de `UPDATE` amplo deve ocorrer junto com as RPCs e actions que substituem o comportamento, para evitar janela sem funcionalidade. Policies, grants, funções `SECURITY DEFINER`, índices e generated types deverão ser revisados antes do CI.

O rollback de uma migration que criou audit ou rate limit não deverá apagar histórico automaticamente. Se uma função apresentar defeito, desabilitar o caminho de código e aplicar forward-fix. Dados Auth e dados SQL não formam uma única transação; por isso, invite deverá registrar falha/anomalia de compensação sem apagar um usuário preexistente por suposição.

## 11. Matriz de testes planejada

### Unit

A meta aproximada é manter os 18 testes existentes e adicionar cerca de 20–30 testes de regras puras, sem transformar o número estimado em evidência final. Os cenários abrangerão as 29 ações, as oito combinações mínimas role/owner, schemas Zod, permission helpers, guards, error mapping, audit sanitizer, rate-limit decision e idempotência. O número real deverá ser contado no relatório da implementação.

### Integration

Cada Server Action e RPC administrativo será chamado diretamente com sessão/autorização sintética. Serão cobertos happy path, role errado, owner ausente, office diferente, usuário inativo, office inativo, request direto, FormData adulterado, ID inexistente, ID de outro office, repetição e falha parcial. A camada de observação poderá usar credencial administrativa somente para setup e contagem pós-operação; ela nunca será usada para fazer a tentativa pública de signup ou para provar um deny que deveria vir do RLS.

### pgTAP

Os 34 testes atuais são obrigatórios e não podem ser reduzidos. A nova suíte deverá cobrir grants/revokes, RPCs, audit append-only, policies de scope, roles, owner, inactive, tenant, constraints, direct SQL/API bypass e atomicidade do limiter. Cada teste deverá configurar explicitamente o role de banco e o contexto JWT, evitando que o papel `postgres` produza falso positivo.

### Concurrency

Preservar o cenário aprovado de last-owner com um sucesso, uma rejeição e exatamente um owner ativo. Adicionar concorrência somente para: duas mutações sobre o último owner, duas tentativas de mesmo invite/target, duas alterações sobre o mesmo perfil e dois consumos do mesmo bucket de rate limit. Os resultados esperados serão definidos antes do teste; flake de timing não será tratado como aprovação.

### E2E

| Cenário | Evidência |
|---|---|
| Owner abre `/app/usuarios` | Rota e tabela visíveis |
| Lawyer sem owner, operator sem owner, reviewer sem owner e auditor sem owner | Cada um recebe deny e não vê controles de mutação |
| Lawyer+owner, operator+owner, reviewer+owner e auditor+owner | Todos acessam apenas as ações adicionais permitidas pelo `is_owner`; nenhum ganha poderes jurídicos indevidos |
| Owner convida usuário | Mailpit, aceite, reset e login continuam funcionais |
| Convite repetido | Mensagem controlada; contagens Auth/profile não aumentam; office/role/owner não mudam |
| Alterar role | Owner consegue; non-owner, self e cross-office não conseguem |
| Inativar/ativar usuário | Ação auditada; token/sessão do inativo perde acesso |
| Grant/revoke owner | Role funcional permanece; último owner não pode ser removido; race permanece segura |
| Administração do office | Owner altera somente nome; non-owner recebe deny; `is_active` não é mutável pelo usuário |
| Auditoria administrativa | Auditor/owner leem o escopo permitido; lawyer sem owner não lê; export respeita office/limite |
| Request direto | Chamada de action/API sem UI não contorna guard/RLS |
| Signup e Auth 4B | API pública deny, `/signup` 404, login/logout/recovery/invite continuam verdes |

### Regression

Toda implementação deverá repetir a baseline de Fase 4A e 4B: 18 unitários existentes, 12 Auth E2E, 34 pgTAP, concorrência last-owner, `db:lint`, types check, PoC 29/29, lint, typecheck, format e build/start. O teste manual interativo permanece `não executado` até ser efetivamente realizado em Docker Desktop; não será substituído por uma afirmação de execução.

## 12. Fixtures e combinações role/owner

A matriz mínima de identidade será construída com oito perfis funcionais/administrativos: lawyer sem owner, lawyer com owner, operator sem owner, operator com owner, reviewer sem owner, reviewer com owner, auditor sem owner e auditor com owner. Eles deverão ser distribuídos em dois offices para testar tanto o isolamento quanto a ortogonalidade. Perfis inativos e offices inativos serão variantes explícitas, não inferências de um perfil ativo.

O fixture script continuará idempotente e removerá apenas dados sintéticos identificados pela suíte. Nenhum e-mail real, CNJ real ou processo real será introduzido. Para o teste de convite repetido, o executor deverá capturar contagens de Auth e `user_profile` antes e depois, verificar `office_id`, role e `is_owner`, e limpar o usuário dinâmico em teardown quando isso não comprometer a evidência do teste.

## 13. Subetapas verticais futuras

### 4C.0 — Gate, branch e baseline local

| Item | Plano |
|---|---|
| Objetivo | Após `Confirmar`, salvar localmente a versão aprovada em `docs/plano-fase-4c.md`, criar a branch de trabalho a partir de `f17146a...` e registrar a baseline sem alterar 4B/main. Enquanto `/plan` estiver ativo, não criar branch remota, não fazer push e não implementar. |
| Arquivos | Somente documentação de planejamento e registros locais; nenhuma feature. |
| Banco | Nenhuma migration. |
| Backend/UI | Nenhuma alteração. |
| Testes | `git diff --check`, baseline existente e verificação de status limpo. |
| Dependência anterior | Aprovação deste plano e auditoria externa da 4B. |
| Critério de aceite | Base exata confirmada; branch local isolada; plano aprovado salvo antes do código; nenhum push durante o `/plan` ou antes dos testes locais completos. |
| Rollback | Apagar branch local/documento não publicado; não tocar 4B/main. |

### 4C.1 — Contrato de permissões e guards

| Item | Plano |
|---|---|
| Objetivo | Implementar a fonte canônica das 29 ações e guards por comando. |
| Arquivos | `src/lib/auth/guards.ts`, `validation.ts`, novo `permissions.ts` e unit tests. |
| Banco | Nenhuma mudança funcional obrigatória. |
| Backend/UI | Actions passam a chamar `requirePermission`; UI apenas consome decisão. |
| Testes | Oito combinações, todos os ALLOW/DENY, self/inactive. |
| Dependência anterior | 4C.0. |
| Critério de aceite | Não existe helper que conceda poder de lawyer por `is_owner`; 18+ testes verdes. |
| Rollback | Reverter commit local da fatia; nenhuma migration para desfazer. |

### 4C.2 — RLS hardening, RPCs e audit append-only

| Item | Plano |
|---|---|
| Objetivo | Tirar mutações críticas do `UPDATE` genérico e criar evidência imutável. |
| Arquivos | Migrations, generated types, `src/lib/audit.ts`, pgTAP. |
| Banco | Grants, RPCs, audit table/function/policies/indexes/triggers. |
| Backend/UI | Actions usam RPC; sem UI nova ainda além de contratos. |
| Testes | `db:reset`, 34+, direct SQL, RLS, append-only, cross-office. |
| Dependência anterior | 4C.1. |
| Critério de aceite | Mutação direta não atravessa invariantes; audit não pode ser alterado. |
| Rollback | Forward-fix; desativar action antes de alterar função; preservar audit. |

### 4C.3 — Administração de usuários

| Item | Plano |
|---|---|
| Objetivo | Entregar listagem, invite, role, status e owner como fatias controladas. |
| Arquivos | `src/app/app/usuarios/actions.ts`, `page.tsx`, `invite-form.tsx`, novos componentes/schemas/tests. |
| Banco | RPCs de perfil e last-owner existentes/reforçados. |
| Backend/UI | Ações por linha, confirmação, status individual, mensagens seguras. |
| Testes | Unit/integration/pgTAP/concurrency/E2E, oito combos, duplicate counts. |
| Dependência anterior | 4C.2. |
| Critério de aceite | Owner consegue apenas ações permitidas; non-owner/direct request/cross-office falham. |
| Rollback | Desabilitar controles e reverter código; não hard-delete usuários nem audit. |

### 4C.4 — Administração do escritório

| Item | Plano |
|---|---|
| Objetivo | Expor nome e estado do office com regra de não auto-desativação. |
| Arquivos | Nova rota provável `/app/configuracoes`, action e componente; app page link. |
| Banco | Reusar grant/policy de `office`, criar RPC/audit se necessário. |
| Backend/UI | Owner altera nome; status read-only; nenhum botão arbitrário para `is_active`. |
| Testes | pgTAP de colunas/grants, direct action e E2E. |
| Dependência anterior | 4C.3 e audit. |
| Critério de aceite | Nome atualizado somente no próprio office e evento auditado. |
| Rollback | Ocultar rota/link e reverter action; manter nome salvo. |

### 4C.5 — Rate limit de invite e mutações

| Item | Plano |
|---|---|
| Objetivo | Impedir abuso sem introduzir Redis/serviço externo. |
| Arquivos | Migration, `src/lib/rate-limit.ts`, actions e testes. |
| Banco | Bucket e RPC atômico com limpeza/expiração. |
| Backend/UI | Verificar limite antes do side effect; mensagem e retry controlados. |
| Testes | Limite, reset, actor/office, bypass, concorrência e CI local. |
| Dependência anterior | 4C.3 e decisões de parâmetros. |
| Critério de aceite | Excedente é rejeitado; janela reseta; dois actors/offices não compartilham indevidamente bucket. |
| Rollback | Feature flag/configuração para bypass controlado local; forward-fix da tabela. |

### 4C.6 — Auditoria visível, fixtures e matriz E2E

| Item | Plano |
|---|---|
| Objetivo | Dar evidência humana e automatizada da matriz completa do control plane. |
| Arquivos | Página/ação de auditoria, fixtures e `tests-e2e/admin.spec.ts` provável. |
| Banco | Query/export por scope e office, sempre sanitizado. |
| Backend/UI | Auditor/owner acessam somente admin audit; export rate-limited. |
| Testes | E2E owner/non-owner/auditor e request direto, contagens e logs. |
| Dependência anterior | 4C.2–4C.5. |
| Critério de aceite | Eventos aparecem, não vazam segredo e não cruzam office. |
| Rollback | Remover link/export sem apagar audit; leitura pode ser temporariamente bloqueada. |

### 4C.7 — Fechamento local, Docker e CI

| Item | Plano |
|---|---|
| Objetivo | Reexecutar tudo localmente, produzir o relatório factual e publicar a implementação somente após HEAD local completo e revisado. |
| Arquivos | Workflow apenas se necessário para incluir branch/suites; docs/relatório após fatos. |
| Banco | `supabase start`, `db:reset`, `db:lint`, pgTAP, types, concurrency. |
| Backend/UI | Build standalone e execução local via Docker. |
| Testes | `npm ci`, format check, lint, typecheck, unit, build, Auth E2E, 4C E2E, PoC, DB. |
| Dependência anterior | Todas as fatias. |
| Critério de aceite | Local verde, teste manual declarado, primeiro push somente após o pacote completo; se necessário, apenas pushes corretivos mínimos para problemas específicos do CI; novo CI completed/success com `head_sha` exato. |
| Rollback | Reverter o commit final da branch; não mergear/force-push/main. |

## 14. CI e comandos locais de aceite

A sequência local futura será executada no repositório da branch de implementação, sem push entre comandos: `npm ci`; `npm run format:check`; `npm run lint`; `npm run typecheck`; `npm test`; build; `npx supabase start`; `npm run db:reset`; fixtures; `npm run auth:e2e`; suites adicionais; `npm run db:lint`; `npm run db:test`; teste de concorrência; `npm run db:types`; `npm ci --prefix poc`; `npm --prefix poc test`. O Supabase será encerrado ao final, inclusive em falha.

No Docker Desktop Windows, validar `docker compose up --build -d`, acesso local em `localhost:3000`, variáveis públicas sem service role, e teardown. No Ubuntu CI, preservar o uso de `localhost` coerente no runner standalone, Mailpit e Playwright. Não usar Supabase remoto, e-mail real, processo real ou segredo externo.

O App CI futuro deverá conservar Repository Hygiene, Format, Lint, Typecheck, Unit, Build, Supabase Start, DB Reset, Auth E2E, suites 4C, PoC, DB Lint, pgTAP, Concurrency, Database Types Check e Supabase Stop. O novo run será evidência válida somente se `status=completed`, `conclusion=success` e `head_sha` for exatamente o SHA final da implementação; nenhum run anterior poderá ser reutilizado.

## 15. Arquivos existentes e novos prováveis

| Arquivo | Responsabilidade atual | Mudança futura planejada | Dependências/testes |
|---|---|---|---|
| `src/lib/auth/guards.ts` | Auth/profile/owner guards | `requirePermission` e tratamento de erros | Unit, integration, E2E |
| `src/lib/auth/validation.ts` | Schemas Auth/invite | Schemas de mutations/settings/audit | Unit/action |
| `src/app/app/usuarios/actions.ts` | Invite owner-only | Commands de role/status/owner, audit, limiter | Unit/integration/pgTAP/E2E |
| `src/app/app/usuarios/page.tsx` | Lista simples | Ações por linha, states, audit link | E2E/accessibility |
| `src/app/app/usuarios/invite-form.tsx` | Convite | Rate-limit/pending/error consistency | E2E duplicate |
| `src/app/app/page.tsx` | Contexto e link admin | Navegação/configuração/audit conforme permission | E2E |
| `src/lib/supabase/admin.ts` | Auth Admin server-only | Permanecer isolado; talvez helper de diagnóstico | Bundle/security tests |
| `src/types/database.types.ts` | Tipos `office`/profile | Regenerar após migrations | CI diff |
| `supabase/config.toml` | Auth/local ports/limits | Não alterar sem necessidade; documentar Auth limits | Local/CI |
| `scripts/bootstrap-auth-fixtures.mjs` | Cinco fixtures Auth | Oito combos, inactive/cross-office/cleanup | E2E/integration |
| `scripts/run-auth-e2e.mjs` | Build standalone/Auth E2E | Reusar; somente ajustar descoberta/suites se necessário | Local/CI |
| `tests-e2e/auth.spec.ts` | 12 cenários 4B | Preservar; corrigir apenas dívida aprovada | Regression |
| `.github/workflows/app-ci.yml` | Pipeline baseline | Incluir branch/suites 4C somente na implementação autorizada | CI final |
| `Dockerfile`/`docker-compose.yml` | Empacotamento web | Preservar runtime; nenhuma dependência de Redis | Docker smoke |
| `supabase/tests/concurrency/test_concurrency.sh` | Last-owner race | Preservar; adicionar script separado se necessário | CI concurrency |
| `docs/10-matriz-papeis-e-autorizacao.md` | Norma D-022 | Não alterar sem decisão; referenciar como fonte | Audit |

Arquivos novos prováveis, a confirmar somente durante a implementação e sem criá-los agora: `src/lib/auth/permissions.ts`, `src/lib/audit.ts`, `src/lib/rate-limit.ts`, componentes administrativos, `/app/configuracoes`, migration(s) `phase_4c_*`, suítes pgTAP 4C, `tests-e2e/admin.spec.ts` e testes de integração. O caminho final de qualquer arquivo novo deverá ser confirmado contra a estrutura real antes de ser adicionado; não usar `git add .` ou `git add -A`.

## 16. Decisões, riscos e gates abertos

Decisões fechadas da Fase 4C: a operação suportada para usuários é inativação lógica; hard delete de `user_profile`/Auth está fora da fase, não haverá botão/UI de hard delete e histórico/auditoria serão preservados. No office, o owner poderá visualizar o status do próprio office e alterar somente o nome do próprio office; não poderá desativar o próprio office, alterar `id` ou mover arbitrariamente usuários entre offices; não serão inventadas outras configurações. Conforme D-022, auditoria administrativa terá ALLOW para `auditor` e para qualquer role funcional com `is_owner=true`, e DENY para lawyer/operator/reviewer com `is_owner=false`; isso não concede acesso à auditoria operacional.

Permanece pendente somente a política jurídica definitiva de retenção do `audit_log`, além da estratégia de backup/RPO/RTO e eventual política futura de IP/proxy. Na Fase 4C não haverá TTL, purge automático, DELETE periódico nem cron de retenção: **“Sem exclusão automática até aprovação formal da política de retenção.”** Isso não é decisão definitiva de produção. Os defaults de rate limit estão definidos na camada 6.4 e poderão ser calibrados posteriormente por alteração server-side revisada, sem configuração pelo cliente. A Fase 4C não autoriza produção, envio real, retenção definitiva ou consulta de processo real.

A dívida de recovery da 4B — teste que tolera `Auth session missing` e comprova a nova senha por login — deverá ser tratada como item de robustez separado. Não se deve mascarar um erro de senha como sucesso nem reabrir o callback sem reproduzir o defeito com teste determinístico. Esse item não bloqueia a aprovação documentada da 4B, mas pode ser incluído como risco/critério de regressão da 4C.

## 17. Critério objetivo para encerrar a macrofase 4

**MACRO FASE 4 ESTARÁ CONCLUÍDA QUANDO...**

- A base de identidade e RLS da 4A permanecer intacta e todos os seus 34+ testes continuarem verdes.
- A autenticação invite-only da 4B permanecer verde: signup público negado, `/signup` inexistente, callback sem `signup`, recovery/reset, invite/accept, login, logout e sessões.
- As 29 ações de D-022 estiverem catalogadas com ALLOW/DENY/NOT_APPLICABLE, role, `is_owner`, office, RLS, DB guard/RPC, server guard, UI, unit, integração, pgTAP e E2E previstos; nenhuma ação futura poderá ser implicitamente liberada.
- Todas as ações que possuam entidades físicas na 4C — invite, gestão de perfil, owner/status, office settings, audit administrativo e limiter — estiverem implementadas por comandos controlados e testadas fora da UI.
- `UPDATE` genérico do perfil não for um caminho de autorização administrativa; role, status, owner e office forem alterados somente por operações específicas.
- O último owner ativo continuar protegido contra revoke, inativação, exclusão lógica e corridas concorrentes.
- Todas as oito combinações role/owner forem exercitadas, com `is_owner` comprovadamente ortogonal ao papel funcional.
- Convite repetido não criar Auth user/profile adicional, não alterar office, role ou owner, e registrar resposta/auditoria controlada.
- `audit_log` for append-only, sanitizado, isolado por office e separado logicamente entre auditoria administrativa e operacional.
- Rate limit de invite/mutações for atômico, testado em janela, concorrência, actor/office diferentes e sem armazenamento de PII bruta.
- Owner/non-owner, inactive user/office, cross-office, direct request, forged payload, ID inexistente e role errado tiverem testes negativos correspondentes.
- Docker Desktop Windows e CI Ubuntu executarem a aplicação e Supabase local sem dependência remota ou segredo versionado.
- Todos os gates locais estiverem verdes, o relatório de implementação registrar quantidades reais, o teste manual declarar explicitamente seu estado e um novo App CI verde corresponder exatamente ao HEAD final.
- O relatório externo puder classificar cada item como `APPROVED` ou `PARTIAL` sem depender de interpretação da conversa.

As entidades e fluxos que não existirem fisicamente — clientes, partes, processos, DataJud, scheduler, falhas, notificações, relatórios, PDF e envio — permanecerão explicitamente como fases posteriores e não poderão ser usados como evidência de encerramento nesta macrofase.

## 18. Publicação futura do documento e parada obrigatória

Enquanto estivermos em `/plan`, não publicar este plano, não criar branch remota, não fazer push e não implementar. O mecanismo nativo será: `/plan` → editar/refinar → usuário escolher `Editar` ou `Confirmar` → implementação.

Quando o usuário clicar `Confirmar`, antes de alterar qualquer código a execução deverá salvar localmente a versão aprovada em `docs/plano-fase-4c.md`. Esse arquivo será a baseline de execução; não haverá push nesse momento. Depois, toda a Fase 4C será implementada localmente, os testes serão executados localmente, será produzido `docs/relatorio-fase-4c.md`, e plano/código/relatório serão revisados juntos. No GitHub final deverão existir juntos `docs/plano-fase-4c.md`, `docs/relatorio-fase-4c.md`, código, migrations e testes.

Somente quando o pacote inteiro estiver localmente pronto ocorrerá o primeiro push da implementação. Se o CI revelar problema específico do ambiente, corrigir localmente, repetir os testes necessários e fazer apenas o push corretivo mínimo. Após o último CI verde e o relatório factual, parar: não iniciar Fase 5, não alterar `phase-4b-auth-flows` e não alterar `main`. Aguardar auditoria externa pelo GitHub.

## 19. Resumo de aprovação do plano

Este plano está pronto para revisão no mecanismo nativo do Manus. O usuário deverá escolher `Editar` para novo refinamento ou `Confirmar` para iniciar a execução. O plano confirma que: a Fase 4C significa fechamento do control plane de autorização/administração e não implementação do MVP inteiro; as 29 ações de D-022 são a fonte normativa; nenhuma entidade operacional inexistente será fingida como implementada; inativação lógica é a única remoção suportada e hard delete/UI ficam fora; o owner só visualiza status e altera nome do próprio office; auditoria administrativa é distinta da operacional; rate limit usará PostgreSQL sem Redis com defaults concretos; audit será append-only, before/after allowlisted, sem exclusão automática; e toda execução será local-first, Docker-first, sem push durante `/plan` e com o primeiro push apenas após o pacote local completo.

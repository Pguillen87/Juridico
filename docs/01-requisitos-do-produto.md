# Requisitos do Produto

## 1. Visão Geral

O Juridico é uma aplicação web para um advogado monitorar aproximadamente 60 processos judiciais, acompanhar cliente e partes relacionadas, detectar novas movimentações por consultas determinísticas e preparar relatórios semanais revisáveis. O sistema deve tornar fonte, estado, data, falha e evidência visíveis.

## 2. Objetivos de Negócio

O produto deve reduzir a verificação manual, aumentar a previsibilidade do acompanhamento, diminuir o risco de perda de movimentações, produzir comunicação rastreável ao cliente e oferecer recuperação operacional quando um provedor falhar. A primeira validação deve ocorrer com cinco a dez processos públicos reais aprovados antes da consulta.

## 3. Objetivos dos Usuários

O advogado precisa cadastrar clientes, partes e processos, ativar monitoramento, saber o que foi consultado, distinguir alteração de falha, tratar exceções, receber alertas e aprovar um relatório fiel antes do envio. Usuários básicos precisam executar tarefas autorizadas sem acessar dados de outro escritório.

## 4. Não Objetivos

Não fazem parte do MVP portal do cliente, app nativo, cobrança de múltiplos escritórios, WhatsApp, SMS, peticionamento, assinatura digital, login automatizado em tribunais, CAPTCHA, scraping não autorizado, consulta automática de sigilosos, parecer jurídico, cálculo de prazo, identificação automática de partes ou envio sem aprovação.

## 5. Personas

| Persona | Necessidade | Risco a controlar |
|---|---|---|
| Advogado responsável | Acompanhar carteira, revisar alterações e aprovar comunicação | Não confundir falha com ausência de movimentação |
| Usuário básico do escritório | Executar cadastros e tarefas delegadas | Acesso acima da permissão |
| Cliente destinatário | Receber relatório compreensível | Receber versão não aprovada ou dado sem fonte |
| Operador técnico autorizado | Diagnosticar falhas e reprocessar | Exposição de dados pessoais e segredos |

## 6. Papéis e Permissões

`office_owner` administra o escritório e usuários; `lawyer` gerencia processos, partes, monitoramento, revisão e aprovação; `operator` executa cadastros e reprocessamento dentro do escopo autorizado; `reviewer` edita e revisa relatórios, mas não envia sem aprovação; `auditor` consulta registros de auditoria sem alterá-los. O modelo final de permissões exige validação do advogado. Todo acesso deverá observar `office_id` e RLS.

## 7. Requisitos Funcionais Priorizados

| ID | Prioridade | Requisito |
|---|---|---|
| RF-001 | Must | Autenticar e recuperar senha. |
| RF-002 | Must | Isolar dados por escritório e aplicar papéis. |
| RF-003 | Must | Cadastrar cliente, partes e relações. |
| RF-004 | Must | Cadastrar processo, validar CNJ e associar carteira. |
| RF-005 | Must | Importar CSV com pré-visualização, validação e auditoria. |
| RF-006 | Must | Consultar via DataJud e `ManualProvider`. |
| RF-007 | Must | Armazenar payload bruto, normalizar, gerar snapshot e comparar. |
| RF-008 | Must | Deduplicar movimentações, alterações e notificações. |
| RF-009 | Must | Exibir falhas em central separada e permitir reprocessamento. |
| RF-010 | Must | Alertar por e-mail após alteração detectada. |
| RF-011 | Must | Gerar, agrupar, editar, versionar, aprovar e enviar relatório semanal. |
| RF-012 | Must | Gerar PDF e preservar cópia imutável da versão enviada. |
| RF-013 | Must | Auditar ações críticas e entregas. |
| RF-014 | Should | Sugerir resumos com IA apenas em rascunho revisável. |
| RF-015 | Could | Preparar adaptadores para futuros provedores e canais. |

## 8. Requisitos Não Funcionais

O sistema deverá usar UTC para armazenamento e apresentar `America/Sao_Paulo`; aplicar RLS; não expor segredos em código, logs ou payloads; manter payloads, snapshots e versões enviadas imutáveis; operar consultas idempotentes; impedir concorrência por processo; suportar retries com backoff e central de falhas; registrar logs estruturados; emitir métricas e alertas técnicos; possuir backup e restauração testável; manter acessibilidade por teclado, foco, contraste e rótulos; e proteger dados pessoais conforme validação jurídica da LGPD.

## 9. Fluxos Principais

O fluxo de monitoramento é: selecionar processos ativos, escolher provedor compatível, criar job idempotente, consultar, salvar resposta bruta, normalizar, criar snapshot, comparar com último snapshot bem-sucedido, registrar movimentações e alteração, deduplicar, criar notificação e enviar após confirmar o canal.

O fluxo de relatório é: fechar período, consolidar por processo e por parte, gerar rascunho, permitir edição e observação, gerar nova versão, solicitar revisão, aprovar, gerar PDF, confirmar destinatário, enviar somente a versão aprovada e armazenar a cópia imutável.

## 10. Fluxos Alternativos

Se DataJud não suportar a consulta, registrar `process_not_supported` e oferecer `ManualProvider`. Se a fonte estiver indisponível, realizar retries, registrar `source_unavailable` e encaminhar à central de falhas. Se o processo não for encontrado, registrar `not_found` sem classificá-lo como sem alteração. Se houver dúvida de vínculo, manter `pending_confirmation`. Se o e-mail falhar, registrar tentativa, programar retry e impedir alteração silenciosa do relatório aprovado.

## 11. Casos de Borda

O sistema deve tratar CNJ duplicado no mesmo escritório, CSV vazio, colunas ausentes, linha inválida, caracteres inesperados, nomes homônimos, processo sem partes fornecidas, payload incompleto, movimentação fora de ordem, mudança retroativa, timeout, HTTP 429, respostas duplicadas, duas consultas simultâneas, alteração após o fechamento semanal, destinatário inválido, PDF divergente, usuário removido, sessão expirada e tentativa de acesso cruzado entre escritórios.

## 12. Experiência do Usuário

A primeira tela deverá mostrar resumo da carteira por estado e oferecer caminhos para processos, partes, falhas, notificações e relatórios. Cada item deverá exibir fonte, última consulta bem-sucedida, estado atual, última alteração e ação recomendada. Falhas terão linguagem explícita, sem sugerir ausência de movimentação. A interface não dependerá apenas de cor.

## 13. Primeiro Acesso

No primeiro acesso, o advogado deverá autenticar-se, confirmar escritório, configurar fuso e horários provisórios, cadastrar a cliente principal, cadastrar partes relacionadas, revisar permissões e escolher se importará CSV ou cadastrará processo manualmente. Nenhuma consulta real será executada sem confirmação da configuração e dos números CNJ.

## 14. Importação por CSV

O CSV deverá aceitar número CNJ, cliente, tribunal, sistema, parte, relação, papel, público/sigiloso, monitoramento e observações. O sistema validará colunas, CNJ, duplicidade, integridade das relações e campos obrigatórios; mostrará prévia, erros por linha e resumo; exigirá confirmação; gravará somente após confirmação; e registrará auditoria. Linhas inválidas não poderão ser silenciosamente descartadas.

## 15. Monitoramento

O agendamento provisório usa 08:00, 13:00 e 18:00 no fuso `America/Sao_Paulo`, mas deve ser configurável. Cada execução cria `query_job` e `query_execution`, aplica idempotência, lock por processo, limite de concorrência e retries com backoff. Processos sigilosos ficam sem consulta automática no MVP.

## 16. Falhas

Falhas devem conter origem, código, mensagem sanitizada, tentativa, próxima ação, próxima tentativa, responsável e evidência. Estados mínimos são `changed`, `unchanged`, `source_unavailable`, `not_found`, `not_supported`, `rate_limited`, `timeout`, `technical_failure` e `manual_review_required`. O estado `failed` nunca será convertido em `unchanged`.

## 17. Alertas

Uma alteração poderá gerar zero ou várias notificações conforme preferências, destinatários e deduplicação. O alerta de e-mail conterá processo, tribunal, cliente, partes, data da movimentação, descrição, data de detecção, link interno e fonte. O fornecedor permanecerá abstrato; desenvolvimento e teste usarão falso ou sandbox.

## 18. Relatórios

O relatório semanal será fechado na sexta-feira às 17:00 provisoriamente. Terá organização por processo e por parte, indicará alteração, ausência de alteração e falha, conterá observações do advogado, versões imutáveis e estado `draft`, `awaiting_review`, `approved`, `sent` ou `cancelled`. Não poderá ser enviado sem versão aprovada.

## 19. PDF

O PDF deverá ser gerado a partir da versão aprovada, possuir hash, armazenamento privado, referência à versão e metadados de geração. Antes do envio, o sistema deverá verificar que o hash e o conteúdo correspondem à versão aprovada. A entrega registrará destinatário, assunto, data, status e resposta sanitizada do provedor.

## 20. Auditoria

Devem ser auditados login, falha de login, alteração de permissões, criação e alteração de cliente, parte, processo e vínculo, confirmação de vínculo, importação, consulta, reprocessamento, alteração de configuração, geração e edição de relatório, aprovação, geração de PDF, envio e cancelamento. `audit_log` será append-only.

## 21. Privacidade

Dados pessoais, dados de processo e arquivos PDF serão privados. Credenciais não serão persistidas em payload bruto. Segredos estarão em gerenciador de segredos ou variáveis seguras, nunca em código. A retenção inicial proposta para payload bruto é de 180 dias; relatórios enviados e auditoria não terão exclusão automática até validação jurídica. Exclusões necessárias serão lógicas e auditadas.

## 22. Métricas do Usuário

Acompanhar tempo até encontrar uma alteração, quantidade de processos revisados, falhas pendentes, relatórios revisados, tempo de aprovação, alertas lidos, itens corrigidos pelo advogado e taxa de confirmação manual de vínculos.

## 23. Métricas de Negócio

Acompanhar cobertura da carteira, percentual de processos com consulta bem-sucedida, alterações detectadas, redução de verificações manuais, relatórios enviados no prazo, taxa de aprovação sem correção e quantidade de clientes atendidos no período.

## 24. Métricas Técnicas

Acompanhar latência por provedor, taxa de sucesso, taxa de timeout, HTTP 429, retries, jobs duplicados evitados, notificações duplicadas evitadas, falhas de entrega, tempo de fila, integridade de hash, duração de geração de PDF, erros de RLS, sucesso de backup e resultado de restauração.

## 25. Histórias de Usuário e Critérios de Aceitação

As histórias abaixo são sequenciais. Todas as histórias críticas possuem pelo menos um teste associado na matriz de rastreabilidade.

### US-001 — Login

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero autenticar-me para acessar os dados do escritório. |
| Pré-condições | Usuário ativo e credenciais cadastradas. |
| Fluxo principal | Informar e-mail e senha; validar; abrir área autorizada. |
| Fluxo alternativo | Sessão existente válida é reutilizada. |
| Casos de erro | Credenciais inválidas, conta inativa ou sessão expirada. |
| Critérios Given/When/Then | **Given** conta ativa, **When** credenciais válidas são enviadas, **Then** o sistema cria sessão e registra auditoria. |
| Dependências | `user_profile`, autenticação e RLS. |
| Evidências | Teste E2E de login e registro de auditoria. |

### US-002 — Recuperação de senha

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como usuário, quero recuperar senha sem expor a existência de contas. |
| Pré-condições | Serviço de autenticação disponível. |
| Fluxo principal | Solicitar recuperação; receber link; definir nova senha. |
| Fluxo alternativo | Reenviar link ainda válido segundo política. |
| Casos de erro | Token expirado, link usado ou e-mail indisponível. |
| Critérios Given/When/Then | **Given** solicitação válida, **When** link correto é usado, **Then** senha é atualizada e evento é auditado. |
| Dependências | Auth e provedor de e-mail sandbox. |
| Evidências | Teste de token expirado e fluxo completo. |

### US-003 — Autorização por papel

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Office owner |
| Descrição | Como administrador, quero atribuir papéis e limitar ações. |
| Pré-condições | Usuário com permissão administrativa. |
| Fluxo principal | Selecionar usuário; atribuir papel; salvar; aplicar política. |
| Fluxo alternativo | Revogar papel e encerrar sessões conforme política. |
| Casos de erro | Papel inválido ou tentativa sem autorização. |
| Critérios Given/When/Then | **Given** usuário sem permissão de aprovação, **When** tenta aprovar, **Then** ação é recusada e auditada. |
| Dependências | `user_profile`, RLS e matriz de permissões. |
| Evidências | Testes de autorização positiva e negativa. |

### US-004 — Cadastro de cliente

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero cadastrar o cliente principal do escritório. |
| Pré-condições | Usuário autenticado e escritório selecionado. |
| Fluxo principal | Informar dados; validar obrigatórios; salvar `client` apontando para `party`. |
| Fluxo alternativo | Editar dados antes de qualquer processo vinculado. |
| Casos de erro | Duplicidade, campo inválido ou acesso cruzado. |
| Critérios Given/When/Then | **Given** dados válidos, **When** cadastro é confirmado, **Then** cliente e parte principal são registrados com `office_id`. |
| Dependências | `party`, `client`, RLS. |
| Evidências | Teste de criação e isolamento. |

### US-005 — Cadastro de partes relacionadas

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero cadastrar filhas e outras partes relacionadas. |
| Pré-condições | Cliente existente. |
| Fluxo principal | Criar parte; declarar tipo; registrar relação em `client_related_party`. |
| Fluxo alternativo | Associar pessoa jurídica ou representante. |
| Casos de erro | Relação ausente ou parte duplicada não confirmada. |
| Critérios Given/When/Then | **Given** relação informada, **When** cadastro é confirmado, **Then** a parte é salva e a relação fica auditável. |
| Dependências | `party`, `client_related_party`. |
| Evidências | Teste com pessoa física e jurídica. |

### US-006 — Cadastro manual de processo

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero cadastrar um processo manualmente. |
| Pré-condições | Cliente e usuário autorizados. |
| Fluxo principal | Informar CNJ, tribunal, sistema, publicidade e cliente; validar; salvar. |
| Fluxo alternativo | Marcar monitoramento inativo até revisão. |
| Casos de erro | CNJ inválido ou duplicado no escritório. |
| Critérios Given/When/Then | **Given** CNJ válido e único, **When** confirmação ocorre, **Then** `legal_process` é criado com responsável e auditoria. |
| Dependências | Validador CNJ e `legal_process`. |
| Evidências | Testes de CNJ válido, inválido e duplicado. |

### US-007 — Importação CSV

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero importar a carteira inicial por CSV. |
| Pré-condições | Arquivo conforme modelo. |
| Fluxo principal | Enviar; validar; mostrar prévia; listar erros; confirmar; persistir válidos. |
| Fluxo alternativo | Corrigir arquivo e repetir sem duplicar registros. |
| Casos de erro | Coluna ausente, linha inválida, CNJ duplicado ou arquivo vazio. |
| Critérios Given/When/Then | **Given** CSV com erros, **When** prévia é exibida, **Then** nenhuma linha é gravada antes da confirmação e os erros são identificados. |
| Dependências | Parser, validador CNJ, auditoria. |
| Evidências | Fixtures de CSV válido, inválido e duplicado. |

### US-008 — Validação CNJ

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como usuário, quero que o número CNJ seja validado antes do uso. |
| Pré-condições | Campo informado. |
| Fluxo principal | Normalizar máscara; validar formato e dígitos; retornar resultado. |
| Fluxo alternativo | Aceitar apresentação com pontuação sem alterar valor canônico. |
| Casos de erro | Dígito inválido ou tamanho incorreto. |
| Critérios Given/When/Then | **Given** número inválido, **When** formulário é enviado, **Then** gravação é bloqueada com erro compreensível. |
| Dependências | Biblioteca ou regra validada tecnicamente. |
| Evidências | Testes unitários com amostras aprovadas pelo usuário. |

### US-009 — Associação entre parte e processo

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero associar uma parte a um processo com papel. |
| Pré-condições | Processo e parte existentes. |
| Fluxo principal | Selecionar parte; informar papel e fonte; salvar `process_party` pendente ou confirmado. |
| Fluxo alternativo | Manter pendente quando a fonte não fornecer partes. |
| Casos de erro | Processo de outro escritório ou papel ausente. |
| Critérios Given/When/Then | **Given** IDs pertencentes ao escritório, **When** associação é salva, **Then** N:N é criada com `office_id` verificável. |
| Dependências | `party`, `legal_process`, `process_party`. |
| Evidências | Teste de cardinalidade e isolamento. |

### US-010 — Confirmação de vínculo

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero confirmar manualmente um vínculo sugerido. |
| Pré-condições | Vínculo pendente e usuário autorizado. |
| Fluxo principal | Revisar fonte e contexto; confirmar; registrar usuário e data. |
| Fluxo alternativo | Rejeitar ou solicitar revisão manual. |
| Casos de erro | Tentativa de confirmar por nome sem evidência. |
| Critérios Given/When/Then | **Given** evidência revisada, **When** advogado confirma, **Then** status muda e auditoria registra decisão. |
| Dependências | `process_party`, `audit_log`. |
| Evidências | Teste de confirmação e rejeição de homônimo. |

### US-011 — Ativação de monitoramento

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero ativar ou pausar monitoramento por processo. |
| Pré-condições | Processo público e provedor compatível. |
| Fluxo principal | Alterar flag; validar; salvar configuração; auditar. |
| Fluxo alternativo | Manter pausado se processo sigiloso. |
| Casos de erro | Provedor não suporta processo ou usuário sem permissão. |
| Critérios Given/When/Then | **Given** processo público suportado, **When** ativação é confirmada, **Then** jobs futuros podem ser criados. |
| Dependências | `monitoring_configuration`, `provider_capability`. |
| Evidências | Teste de ativação e bloqueio de sigiloso. |

### US-012 — Consulta manual

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero solicitar consulta imediata de um processo. |
| Pré-condições | Processo monitorado e sem lock ativo. |
| Fluxo principal | Solicitar; criar job; executar provedor; mostrar resultado. |
| Fluxo alternativo | Enfileirar se já houver job não iniciado. |
| Casos de erro | Lock, provider indisponível ou limite de requisições. |
| Critérios Given/When/Then | **Given** processo elegível, **When** consulta é solicitada, **Then** job idempotente é criado e status é exibido. |
| Dependências | Scheduler, fila, provider. |
| Evidências | Teste de job duplicado e lock. |

### US-013 — Consulta agendada

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero consultas recorrentes nos horários configurados. |
| Pré-condições | Horários válidos e processos ativos. |
| Fluxo principal | Scheduler identifica janela; cria jobs; fila executa com limite. |
| Fluxo alternativo | Recalcular próxima janela após falha temporária. |
| Casos de erro | Scheduler indisponível ou fuso inválido. |
| Critérios Given/When/Then | **Given** janela 08:00 no fuso configurado, **When** scheduler roda, **Then** cada processo elegível recebe no máximo um job idempotente. |
| Dependências | `monitoring_schedule`, fila e relógio UTC. |
| Evidências | Teste com relógio controlado. |

### US-014 — Integração DataJud

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero consultar DataJud pela interface de provedor. |
| Pré-condições | CNJ aprovado e credencial/configuração autorizada. |
| Fluxo principal | Enviar requisição; validar resposta; guardar metadados; devolver contrato normalizado. |
| Fluxo alternativo | Classificar status HTTP conforme catálogo. |
| Casos de erro | 429, timeout, 5xx, schema inesperado. |
| Critérios Given/When/Then | **Given** resposta válida do DataJud, **When** integração conclui, **Then** payload e resposta sanitizada são registrados sem segredo. |
| Dependências | Contrato do provedor e segredo externo. |
| Evidências | Teste com fixture, sem consultar processo real nesta etapa. |

### US-015 — Provedor manual

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Operador autorizado |
| Descrição | Como operador, quero registrar resultado manual para processo não suportado. |
| Pré-condições | Processo e fonte manual autorizados. |
| Fluxo principal | Informar consulta, fonte, data e movimentações; salvar como entrada manual. |
| Fluxo alternativo | Marcar revisão manual necessária. |
| Casos de erro | Fonte ausente ou usuário não autorizado. |
| Critérios Given/When/Then | **Given** entrada manual completa, **When** confirmada, **Then** ela é diferenciada da resposta automática e auditada. |
| Dependências | `provider`, `query_execution`, auditoria. |
| Evidências | Teste de origem manual. |

### US-016 — Armazenamento da resposta

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero guardar resposta bruta imutável. |
| Pré-condições | Consulta concluída. |
| Fluxo principal | Sanitizar; guardar payload privado, hash, headers permitidos e data. |
| Fluxo alternativo | Guardar falha sem payload quando resposta inexistente. |
| Casos de erro | Payload contém credencial ou storage indisponível. |
| Critérios Given/When/Then | **Given** resposta recebida, **When** persistida, **Then** `raw_provider_payload` é imutável e não contém segredo. |
| Dependências | Storage privado e política de retenção. |
| Evidências | Teste de imutabilidade e sanitização. |

### US-017 — Normalização

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero converter respostas em contrato interno. |
| Pré-condições | Payload válido ou erro classificável. |
| Fluxo principal | Mapear campos, normalizar datas, movimentos e capacidades. |
| Fluxo alternativo | Omitir capacidade não fornecida sem inventar valor. |
| Casos de erro | Schema inesperado ou campo obrigatório ausente. |
| Critérios Given/When/Then | **Given** payload sem partes, **When** normalizado, **Then** processo é aceito e capacidade de partes fica ausente, não falsa. |
| Dependências | Contrato versionado e provider. |
| Evidências | Testes de payload completo e incompleto. |

### US-018 — Snapshot

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero criar snapshot imutável do estado normalizado. |
| Pré-condições | Consulta bem-sucedida e normalizada. |
| Fluxo principal | Canonicalizar; calcular hash; armazenar snapshot com UTC. |
| Fluxo alternativo | Não criar snapshot em falha. |
| Casos de erro | Canonicalização inconsistente ou hash ausente. |
| Critérios Given/When/Then | **Given** estado normalizado, **When** salvo, **Then** snapshot possui hash estável e não pode ser editado. |
| Dependências | `process_snapshot`, hash criptográfico. |
| Evidências | Teste de hash estável. |

### US-019 — Comparação

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero comparar estado atual com último snapshot bem-sucedido. |
| Pré-condições | Snapshot anterior e atual disponíveis. |
| Fluxo principal | Comparar campos relevantes; identificar mudança material; registrar resultado. |
| Fluxo alternativo | Primeiro snapshot cria baseline sem alerta. |
| Casos de erro | Snapshot ausente ou incompatível. |
| Critérios Given/When/Then | **Given** primeiro snapshot, **When** comparação ocorre, **Then** baseline é registrado sem alteração falsa. |
| Dependências | Snapshot e contrato normalizado. |
| Evidências | Teste baseline e alteração. |

### US-020 — Deduplicação

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero impedir duplicidade de movimentos e eventos. |
| Pré-condições | Hash estável disponível. |
| Fluxo principal | Calcular chave; verificar unicidade; ignorar repetição ou relacionar original. |
| Fluxo alternativo | Atualização retroativa gera evento distinto auditável. |
| Casos de erro | Hash instável ou colisão detectada. |
| Critérios Given/When/Then | **Given** mesmo movimento recebido duas vezes, **When** persistido, **Then** uma única movimentação material permanece. |
| Dependências | Índices únicos e comparador. |
| Evidências | Teste de reexecução idempotente. |

### US-021 — Detecção de alteração

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero registrar alteração com evidência. |
| Pré-condições | Comparação material concluída. |
| Fluxo principal | Criar `detected_change` com snapshots, chave e descrição de fonte. |
| Fluxo alternativo | Mudança irrelevante é registrada como sem alteração. |
| Casos de erro | Evidência ausente ou comparação não confiável. |
| Critérios Given/When/Then | **Given** novo movimento material, **When** comparador termina, **Then** uma alteração é criada com chave idempotente. |
| Dependências | Snapshots, movimentos e auditoria. |
| Evidências | Teste de mudança material. |

### US-022 — Consulta sem alteração

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como advogado, quero saber quando consulta bem-sucedida não alterou o estado. |
| Pré-condições | Consulta concluída sem diferença. |
| Fluxo principal | Registrar `unchanged` e última consulta válida. |
| Fluxo alternativo | Não enviar alerta de alteração. |
| Casos de erro | Não confundir falha com `unchanged`. |
| Critérios Given/When/Then | **Given** consulta bem-sucedida sem mudança, **When** status é salvo, **Then** aparece como sem alteração e não como falha. |
| Dependências | `query_execution`, snapshot. |
| Evidências | Teste de ausência real de alteração. |

### US-023 — Fonte indisponível

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como advogado, quero visualizar fonte indisponível separadamente. |
| Pré-condições | Provedor sem resposta após política de retry. |
| Fluxo principal | Registrar `source_unavailable`, tentativas e próxima ação. |
| Fluxo alternativo | Reprocessar manualmente depois. |
| Casos de erro | Mensagem de erro conter segredo. |
| Critérios Given/When/Then | **Given** provedor indisponível, **When** retry termina, **Then** processo não é marcado como sem alteração. |
| Dependências | Fila e central de falhas. |
| Evidências | Teste de indisponibilidade simulada. |

### US-024 — Timeout

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero classificar timeout sem bloquear a fila. |
| Pré-condições | Tempo limite configurado. |
| Fluxo principal | Cancelar chamada; registrar timeout; aplicar retry; liberar lock. |
| Fluxo alternativo | Encaminhar para dead-letter após tentativas. |
| Casos de erro | Lock permanecer após timeout. |
| Critérios Given/When/Then | **Given** chamada excede timeout, **When** job é encerrado, **Then** estado é `timeout` e processo pode ser reprocessado. |
| Dependências | Worker e lock com expiração. |
| Evidências | Teste com servidor lento simulado. |

### US-025 — Rate limit

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero respeitar limite de requisições do provedor. |
| Pré-condições | Resposta HTTP 429 ou limite declarado. |
| Fluxo principal | Registrar `rate_limited`; aplicar backoff; agendar próxima tentativa. |
| Fluxo alternativo | Reduzir concorrência da janela. |
| Casos de erro | Loop de retries sem limite. |
| Critérios Given/When/Then | **Given** HTTP 429, **When** resposta é processada, **Then** job não dispara alerta de alteração e próxima tentativa é registrada. |
| Dependências | Scheduler e política de retry. |
| Evidências | Teste de 429 com backoff. |

### US-026 — Processo não encontrado

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como advogado, quero distinguir processo não encontrado de consulta sem alteração. |
| Pré-condições | Fonte responde ausência. |
| Fluxo principal | Registrar `not_found`, evidência e revisão necessária. |
| Fluxo alternativo | Confirmar CNJ e reprocessar. |
| Casos de erro | Não apagar processo automaticamente. |
| Critérios Given/When/Then | **Given** fonte informa não encontrado, **When** resultado é salvo, **Then** relatório exibe não encontrado explicitamente. |
| Dependências | Provider e central de falhas. |
| Evidências | Fixture de resposta not found. |

### US-027 — Processo não suportado

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero saber quando o provider não suporta o processo. |
| Pré-condições | Capacidade declarada ausente. |
| Fluxo principal | Registrar `not_supported` e sugerir provedor manual. |
| Fluxo alternativo | Pausar monitoramento automático. |
| Casos de erro | Tentar consulta proibida. |
| Critérios Given/When/Then | **Given** provider não declara capacidade, **When** job é avaliado, **Then** não consulta e marca não suportado. |
| Dependências | `provider_capability`. |
| Evidências | Teste de capability ausente. |

### US-028 — Central de falhas

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero uma lista acionável de falhas. |
| Pré-condições | Falha registrada. |
| Fluxo principal | Filtrar por tipo, processo, data, tentativa e prioridade. |
| Fluxo alternativo | Atribuir responsável e observação. |
| Casos de erro | Falha aparecer como sem alteração. |
| Critérios Given/When/Then | **Given** consulta falha, **When** central é aberta, **Then** estado e ação recomendada ficam claros. |
| Dependências | `query_execution`, `audit_log`. |
| Evidências | Teste de filtros e status. |

### US-029 — Reprocessamento

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Operador autorizado |
| Descrição | Como operador, quero reprocessar uma falha sem duplicar eventos. |
| Pré-condições | Falha pendente e permissão. |
| Fluxo principal | Solicitar reprocessamento; criar novo job com chave; executar; atualizar falha. |
| Fluxo alternativo | Cancelar se a fonte exigir revisão manual. |
| Casos de erro | Job concorrente ou permissão ausente. |
| Critérios Given/When/Then | **Given** falha reprocessável, **When** retry é confirmado, **Then** nova execução é auditada e eventos duplicados são evitados. |
| Dependências | Idempotência, fila, lock. |
| Evidências | Teste de reprocessamento. |

### US-030 — Alerta por e-mail

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero receber alerta quando alteração for detectada. |
| Pré-condições | Alteração, preferência ativa e sandbox configurado. |
| Fluxo principal | Criar notificação; renderizar dados; enviar; registrar resposta. |
| Fluxo alternativo | Reprogramar retry se provedor falhar. |
| Casos de erro | Destinatário inválido ou conteúdo sem fonte. |
| Critérios Given/When/Then | **Given** alteração aprovada para notificação, **When** envio conclui, **Then** e-mail contém processo, movimento, fonte e data. |
| Dependências | `notification`, `email_delivery`, provider abstrato. |
| Evidências | Teste em sandbox. |

### US-031 — Bloqueio de alerta duplicado

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero evitar o mesmo alerta para o mesmo evento e destinatário. |
| Pré-condições | Chave idempotente calculada. |
| Fluxo principal | Consultar chave; criar apenas se não existir. |
| Fluxo alternativo | Registrar tentativa como duplicada ignorada. |
| Casos de erro | Chave baseada em texto instável. |
| Critérios Given/When/Then | **Given** mesma alteração e destinatário, **When** job repete, **Then** nova notificação não é criada. |
| Dependências | Índice único e `detected_change`. |
| Evidências | Teste de execução repetida. |

### US-032 — Geração semanal

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Sistema |
| Descrição | Como sistema, quero gerar rascunho semanal no horário configurado. |
| Pré-condições | Período e clientes definidos. |
| Fluxo principal | Fechar período; selecionar evidências; criar `weekly_report` draft. |
| Fluxo alternativo | Registrar relatório vazio com explicação. |
| Casos de erro | Período sobreposto ou execução duplicada. |
| Critérios Given/When/Then | **Given** sexta-feira às 17:00, **When** scheduler executa, **Then** um draft idempotente cobre o período correto. |
| Dependências | Scheduler e estados de relatório. |
| Evidências | Teste com relógio controlado. |

### US-033 — Agrupamento por processo

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero revisar relatório organizado por processo. |
| Pré-condições | Draft gerado. |
| Fluxo principal | Abrir visão; exibir CNJ, tribunal, partes, papéis, movimentos, consulta e fonte. |
| Fluxo alternativo | Filtrar processos com alteração ou falha. |
| Casos de erro | Ocultar evidência ou misturar estados. |
| Critérios Given/When/Then | **Given** processo com falha, **When** relatório é exibido, **Then** falha permanece separada de sem alteração. |
| Dependências | `report_process`. |
| Evidências | Teste de agrupamento e estados. |

### US-034 — Agrupamento por parte

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero revisar relatório organizado por parte. |
| Pré-condições | Partes e relações confirmadas. |
| Fluxo principal | Exibir parte, relação, quantidade, processos, alterações e falhas. |
| Fluxo alternativo | Exibir vínculo pendente como revisão manual. |
| Casos de erro | Associar parte a escritório incorreto. |
| Critérios Given/When/Then | **Given** parte em vários processos, **When** visão é aberta, **Then** todos os processos pertencentes ao escritório são agrupados. |
| Dependências | `report_party`, `process_party`. |
| Evidências | Teste N:N. |

### US-035 — Edição

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Reviewer |
| Descrição | Como revisor, quero editar rascunho e inserir observações. |
| Pré-condições | Relatório em `draft` ou `awaiting_review`. |
| Fluxo principal | Editar; validar; salvar nova versão. |
| Fluxo alternativo | Cancelar edição sem alterar versão. |
| Casos de erro | Tentar editar aprovado. |
| Critérios Given/When/Then | **Given** draft aberto, **When** observação é salva, **Then** nova versão registra autor e timestamp. |
| Dependências | `report_version`, auditoria. |
| Evidências | Teste de edição e bloqueio pós-aprovação. |

### US-036 — Versionamento

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero consultar versões e saber qual será enviada. |
| Pré-condições | Mais de uma edição. |
| Fluxo principal | Listar versões; comparar metadados; selecionar versão revisável. |
| Fluxo alternativo | Restaurar conteúdo criando nova versão, nunca sobrescrevendo. |
| Casos de erro | Editar versão imutável enviada. |
| Critérios Given/When/Then | **Given** duas versões, **When** relatório é aprovado, **Then** uma `report_version` exata é marcada como enviada. |
| Dependências | `report_version`, hash. |
| Evidências | Teste de imutabilidade. |

### US-037 — Aprovação

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero aprovar a versão revisada antes do envio. |
| Pré-condições | Usuário com permissão e relatório completo. |
| Fluxo principal | Revisar; confirmar aprovação; registrar usuário, data e versão. |
| Fluxo alternativo | Devolver para edição ou cancelar. |
| Casos de erro | Usuário sem papel de aprovação. |
| Critérios Given/When/Then | **Given** versão revisada, **When** advogado aprova, **Then** estado muda para `approved` e envio ainda depende do fluxo autorizado. |
| Dependências | Permissões, `report_version`, auditoria. |
| Evidências | Teste de aprovação positiva e negativa. |

### US-038 — Geração de PDF

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero gerar PDF da versão aprovada. |
| Pré-condições | Relatório aprovado. |
| Fluxo principal | Renderizar conteúdo; calcular hash; armazenar em local privado. |
| Fluxo alternativo | Regenerar apenas criando artefato e hash rastreáveis. |
| Casos de erro | Conteúdo mudou após aprovação. |
| Critérios Given/When/Then | **Given** versão aprovada, **When** PDF é criado, **Then** hash e versão são registrados e conteúdo corresponde. |
| Dependências | `report_artifact`, storage privado. |
| Evidências | Teste de hash e comparação. |

### US-039 — Envio

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Advogado |
| Descrição | Como advogado, quero enviar somente a versão aprovada ao destinatário confirmado. |
| Pré-condições | Aprovação, destinatário e PDF válidos. |
| Fluxo principal | Confirmar; enviar; registrar entrega. |
| Fluxo alternativo | Reprogramar retry sem mudar versão. |
| Casos de erro | Versão não aprovada, destinatário inválido ou e-mail falho. |
| Critérios Given/When/Then | **Given** PDF da versão aprovada, **When** envio é confirmado, **Then** fornecedor recebe exatamente aquele artefato. |
| Dependências | `email_delivery`, provider de e-mail. |
| Evidências | Teste sandbox de envio bloqueado e permitido. |

### US-040 — Cópia imutável

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Auditor |
| Descrição | Como auditor, quero recuperar a cópia exata enviada. |
| Pré-condições | Entrega registrada. |
| Fluxo principal | Consultar report, versão, destinatário, assunto, hash, local privado, data e status. |
| Fluxo alternativo | Exibir entrega falha sem marcar enviada. |
| Casos de erro | Artefato ausente ou hash divergente. |
| Critérios Given/When/Then | **Given** envio bem-sucedido, **When** cópia é consultada, **Then** conteúdo e hash correspondem à versão aprovada. |
| Dependências | `email_delivery`, `report_artifact`. |
| Evidências | Teste de recuperação e hash. |

### US-041 — Auditoria

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Auditor |
| Descrição | Como auditor, quero uma trilha append-only de ações críticas. |
| Pré-condições | Evento de negócio. |
| Fluxo principal | Registrar ator, ação, entidade, data UTC, correlação e resultado. |
| Fluxo alternativo | Registrar ação de sistema sem usuário. |
| Casos de erro | Tentativa de editar log. |
| Critérios Given/When/Then | **Given** aprovação de relatório, **When** operação conclui, **Then** evento append-only contém ator, versão e timestamp. |
| Dependências | `audit_log`. |
| Evidências | Teste de auditoria e bloqueio de alteração. |

### US-042 — Isolamento por escritório

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Usuário básico |
| Descrição | Como usuário, quero visualizar apenas dados do meu escritório. |
| Pré-condições | Dois escritórios de teste. |
| Fluxo principal | Consultar listas e detalhes; aplicar RLS. |
| Fluxo alternativo | Usuário multi-escritório conforme política futura. |
| Casos de erro | ID forjado ou acesso direto à API. |
| Critérios Given/When/Then | **Given** usuário do escritório A, **When** requisita processo de B, **Then** resposta não revela existência nem conteúdo. |
| Dependências | `office_id`, RLS e testes de segurança. |
| Evidências | Testes negativos de RLS. |

### US-043 — Retenção

| Campo | Conteúdo |
|---|---|
| Prioridade | Must |
| Persona | Office owner |
| Descrição | Como administrador, quero política de retenção auditável. |
| Pré-condições | Política provisória aprovada para teste. |
| Fluxo principal | Aplicar 180 dias a payloads brutos; preservar relatório e auditoria até decisão jurídica. |
| Fluxo alternativo | Suspender exclusão por revisão jurídica. |
| Casos de erro | Excluir relatório enviado automaticamente. |
| Critérios Given/When/Then | **Given** item elegível, **When** rotina de retenção roda, **Then** regra e exceção são auditadas e dados protegidos não são apagados indevidamente. |
| Dependências | Storage, política jurídica e auditoria. |
| Evidências | Teste com relógio simulado. |

### US-044 — IA para rascunho

| Campo | Conteúdo |
|---|---|
| Prioridade | Should |
| Persona | Advogado |
| Descrição | Como advogado, quero sugestão de resumo sem alterar a fonte oficial. |
| Pré-condições | Dados oficiais disponíveis e serviço de IA opcional. |
| Fluxo principal | Enviar contexto permitido; gerar rascunho; mostrar origem; exigir revisão. |
| Fluxo alternativo | Desativar IA e manter texto manual. |
| Casos de erro | Sugestão altera data, inventa fato ou parece aprovada. |
| Critérios Given/When/Then | **Given** IA gera texto, **When** rascunho aparece, **Then** é marcado como não oficial e não pode ser enviado sem revisão/aprovação. |
| Dependências | Provedor de IA opcional, `report_version`, auditoria. |
| Evidências | Teste de marcação e bloqueio de envio. |

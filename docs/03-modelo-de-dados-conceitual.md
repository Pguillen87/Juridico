# Modelo de Dados Conceitual Revisado

## Convenções Gerais

Todos os timestamps serão armazenados em UTC e apresentados em `America/Sao_Paulo`. Toda entidade operacional terá `office_id` diretamente ou por relacionamento obrigatório verificável. Chaves primárias serão UUIDs. Registros auditáveis terão `created_at`, `updated_at` quando mutáveis e `created_by` quando houver ator humano.

Dados de processos, partes, payloads, relatórios e PDFs serão privados. RLS deverá impedir acesso cruzado entre escritórios. Payloads brutos, snapshots, versões enviadas, artefatos enviados e `audit_log` serão imutáveis ou append-only conforme indicado. Exclusão, quando necessária, será lógica, auditada e sujeita à política jurídica.

## Entidades de Identidade e Partes

### `office`

| Aspecto                          | Definição                                                                            |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| Finalidade                       | Isolar um escritório e seus dados.                                                   |
| Campos principais e obrigatórios | `id` PK, `name` obrigatório, `active` obrigatório, `created_at` obrigatório.         |
| Chaves e unicidade               | `id`; nome não precisa ser globalmente único.                                        |
| Relacionamentos/cardinalidade    | 1:N com `user_profile`, `client`, `legal_process`, `provider`, configurações e logs. |
| Índices                          | `active`, `created_at`.                                                              |
| Auditoria                        | Criação, ativação, desativação e alteração de dados.                                 |
| Dados pessoais                   | Nome do escritório pode ser dado pessoal profissional.                               |
| Retenção/exclusão                | Retenção conforme contrato; desativação lógica.                                      |
| Falha                            | Não permitir operação se escritório inativo.                                         |

### `user_profile`

| Aspecto                          | Definição                                                                |
| -------------------------------- | ------------------------------------------------------------------------ |
| Finalidade                       | Perfil de autorização ligado à identidade de autenticação.               |
| Campos principais e obrigatórios | `id` PK/Auth FK, `office_id` FK, `name`, `role`, `status`, `created_at`. |
| Chaves e unicidade               | E-mail administrado pelo Auth; usuário ativo deve possuir escritório.    |
| Relacionamentos/cardinalidade    | N:1 com `office`; 1:N com auditoria, aprovações e confirmações.          |
| Índices                          | `office_id`, `role`, `status`.                                           |
| Auditoria                        | Criação, alteração de papel, bloqueio e exclusão lógica.                 |
| Dados pessoais                   | Nome e e-mail.                                                           |
| Retenção/exclusão                | Desativação; preservação de autoria histórica.                           |
| Falha                            | Usuário inativo não autentica nem executa comandos.                      |

### `party`

| Aspecto                          | Definição                                                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Cadastro comum de pessoa física, pessoa jurídica, cliente, filha, familiar, representante ou outra parte.         |
| Campos principais e obrigatórios | `id` PK, `party_type`, `display_name`, `document_reference` opcional e protegido, `created_at`.                   |
| Chaves e unicidade               | Não confirmar unicidade apenas por nome; documento, quando disponível, terá regra jurídica.                       |
| Relacionamentos/cardinalidade    | N:N com `legal_process` por `process_party`; 1:N como parte principal em `client`; N:N em `client_related_party`. |
| Índices                          | `party_type`, nome normalizado para busca assistida, nunca para confirmação automática.                           |
| Auditoria                        | Criação, alteração, merge rejeitado, confirmação e desativação.                                                   |
| Dados pessoais                   | Nome, documento e contatos.                                                                                       |
| Retenção/exclusão                | Exclusão lógica quando houver histórico.                                                                          |
| Falha                            | Registro incompleto permanece pendente e não é usado como fato confirmado.                                        |

### `client`

| Aspecto                          | Definição                                                                                     |
| -------------------------------- | --------------------------------------------------------------------------------------------- |
| Finalidade                       | Relação comercial do escritório com a parte principal.                                        |
| Campos principais e obrigatórios | `id` PK, `office_id` FK, `party_id` FK obrigatório, `status`, `created_at`.                   |
| Chaves e unicidade               | Um vínculo ativo de parte principal por cliente conforme regra de negócio.                    |
| Relacionamentos/cardinalidade    | N:1 com `office` e `party`; 1:N com `client_related_party`, `legal_process`, `weekly_report`. |
| Índices                          | `office_id + party_id`, `status`.                                                             |
| Auditoria                        | Criação, alteração de status e encerramento.                                                  |
| Dados pessoais                   | Dados da parte principal e contatos comerciais.                                               |
| Retenção/exclusão                | Desativação lógica e retenção contratual.                                                     |
| Falha                            | Não criar processo sem cliente ou carteira responsável.                                       |

### `client_related_party`

| Aspecto                          | Definição                                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Registrar relação da parte principal com filhas, familiares, dependentes e representantes.                                      |
| Campos principais e obrigatórios | `id` PK, `office_id` FK, `client_id` FK, `party_id` FK, `relation_type`, `confirmation_status`, `confirmed_by`, `confirmed_at`. |
| Chaves e unicidade               | Evitar duplicar a mesma relação ativa; não usar nome como chave.                                                                |
| Relacionamentos/cardinalidade    | N:1 com `client` e `party`; um cliente possui 0:N partes relacionadas.                                                          |
| Índices                          | `office_id + client_id`, `party_id`, `confirmation_status`.                                                                     |
| Auditoria                        | Toda confirmação, rejeição ou alteração.                                                                                        |
| Dados pessoais                   | Relação familiar e dados das partes.                                                                                            |
| Retenção/exclusão                | Desativação lógica se houver histórico.                                                                                         |
| Falha                            | Relação não confirmada não pode alimentar relatório como fato confirmado.                                                       |

## Entidades Processuais

### `legal_process`

| Aspecto                          | Definição                                                                                                                                                  |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Representar processo judicial pertencente a uma carteira de cliente.                                                                                       |
| Campos principais e obrigatórios | `id` PK, `office_id` FK, `client_id` FK obrigatório, `cnj_number` canônico, `tribunal`, `system` opcional, `is_public`, `monitoring_status`, `created_at`. |
| Chaves e unicidade               | `office_id + cnj_number` único; CNJ validado.                                                                                                              |
| Relacionamentos/cardinalidade    | N:1 com `office` e `client`; N:N com `party` por `process_party`; 1:N com jobs, execuções, snapshots, movimentos e alterações.                             |
| Índices                          | `office_id + cnj_number`, `client_id`, `monitoring_status`, `is_public`.                                                                                   |
| Auditoria                        | Cadastro, CNJ, cliente, publicidade, monitoramento e exclusão lógica.                                                                                      |
| Dados pessoais                   | CNJ e dados processuais vinculados a pessoas.                                                                                                              |
| Retenção/exclusão                | Encerramento lógico; manter histórico necessário.                                                                                                          |
| Falha                            | Processo sem provider compatível permanece com revisão manual.                                                                                             |

### `process_party`

| Aspecto                          | Definição                                                                                                                                                                |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Finalidade                       | Associar N:N um processo a uma parte e registrar papel e evidência.                                                                                                      |
| Campos principais e obrigatórios | `id` PK, `office_id`, `process_id`, `party_id`, `role_in_process`, `source`, `confirmation_status`, `confirmed_by`, `confirmed_at`, `notes`, `created_at`, `updated_at`. |
| Chaves e unicidade               | Evitar duplicidade ativa por `process_id + party_id + role_in_process`; não confirmar por nome.                                                                          |
| Relacionamentos/cardinalidade    | N:1 com `legal_process` e `party`; processo possui 0:N partes; parte participa de 0:N processos.                                                                         |
| Índices                          | `office_id + process_id`, `party_id`, `confirmation_status`, `role_in_process`.                                                                                          |
| Auditoria                        | Criação, sugestão, confirmação, rejeição e alteração.                                                                                                                    |
| Dados pessoais                   | Papel e vínculo entre pessoas e processo.                                                                                                                                |
| Retenção/exclusão                | Desativação lógica para preservar histórico.                                                                                                                             |
| Falha                            | Sem fonte de partes, status permanece desconhecido ou pendente.                                                                                                          |

## Provedores e Monitoramento

### `provider`

| Aspecto                          | Definição                                                           |
| -------------------------------- | ------------------------------------------------------------------- |
| Finalidade                       | Cadastrar adaptador de fonte automática ou manual.                  |
| Campos principais e obrigatórios | `id`, `office_id`, `name`, `provider_type`, `active`, `created_at`. |
| Chaves e unicidade               | Nome técnico único por escritório.                                  |
| Relacionamentos/cardinalidade    | 1:N com `provider_capability`, `query_job`, `query_execution`.      |
| Índices                          | `office_id + active`, `provider_type`.                              |
| Auditoria                        | Ativação, desativação e configuração.                               |
| Dados pessoais                   | Não armazenar credencial na tabela.                                 |
| Retenção/exclusão                | Desativação lógica.                                                 |
| Falha                            | Provider indisponível classifica jobs, não os converte em sucesso.  |

### `provider_capability`

| Aspecto                          | Definição                                                                         |
| -------------------------------- | --------------------------------------------------------------------------------- |
| Finalidade                       | Declarar capacidades opcionais do provider.                                       |
| Campos principais e obrigatórios | `id`, `office_id`, `provider_id`, `capability_code`, `supported`, `effective_at`. |
| Chaves e unicidade               | `provider_id + capability_code + effective_at` conforme versionamento.            |
| Relacionamentos/cardinalidade    | N:1 com `provider`.                                                               |
| Índices                          | `provider_id + capability_code`, `supported`.                                     |
| Auditoria                        | Mudança de contrato/capacidade.                                                   |
| Dados pessoais                   | Não deve conter dados pessoais.                                                   |
| Retenção/exclusão                | Preservar versões usadas em consultas históricas.                                 |
| Falha                            | Ausência de capability resulta em `not_supported`.                                |

### `monitoring_configuration`

| Aspecto                          | Definição                                                            |
| -------------------------------- | -------------------------------------------------------------------- |
| Finalidade                       | Configurar monitoramento por escritório e regras globais.            |
| Campos principais e obrigatórios | `id`, `office_id`, `timezone`, `active`, `created_at`, `updated_at`. |
| Chaves e unicidade               | Uma configuração ativa por escopo.                                   |
| Relacionamentos/cardinalidade    | N:1 com `office`; 1:N com `monitoring_schedule`.                     |
| Índices                          | `office_id + active`.                                                |
| Auditoria                        | Toda alteração e ativação.                                           |
| Dados pessoais                   | Não deve conter dados pessoais além do ator.                         |
| Retenção/exclusão                | Versionar mudanças; não apagar configuração usada historicamente.    |
| Falha                            | Timezone inválido bloqueia ativação.                                 |

### `monitoring_schedule`

| Aspecto                          | Definição                                                                                             |
| -------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Finalidade                       | Representar janelas de consulta como 08:00, 13:00 e 18:00 provisórios.                                |
| Campos principais e obrigatórios | `id`, `office_id`, `monitoring_configuration_id`, `local_time`, `timezone`, `days_of_week`, `active`. |
| Chaves e unicidade               | Evitar duas janelas iguais no mesmo escopo.                                                           |
| Relacionamentos/cardinalidade    | N:1 com configuração e escritório.                                                                    |
| Índices                          | `office_id + active`, próxima janela calculada.                                                       |
| Auditoria                        | Criação, edição e pausa.                                                                              |
| Dados pessoais                   | Nenhum.                                                                                               |
| Retenção/exclusão                | Preservar versões usadas em jobs.                                                                     |
| Falha                            | Janela ambígua não gera consulta.                                                                     |

### `query_job`

| Aspecto                          | Definição                                                                                                                                |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Unidade enfileirada de consulta.                                                                                                         |
| Campos principais e obrigatórios | `id`, `office_id`, `process_id`, `provider_id`, `scheduled_window_utc`, `idempotency_key`, `status`, `attempt_count`, `next_attempt_at`. |
| Chaves e unicidade               | Chave de consulta: `office_id + process_id + scheduled_window_utc + provider_id`.                                                        |
| Relacionamentos/cardinalidade    | N:1 com processo e provider; 1:N com execuções.                                                                                          |
| Índices                          | Idempotência, `status + next_attempt_at`, `process_id`.                                                                                  |
| Auditoria                        | Criação, cancelamento, retry e conclusão.                                                                                                |
| Dados pessoais                   | Referência indireta a processo.                                                                                                          |
| Retenção/exclusão                | Manter histórico operacional conforme política.                                                                                          |
| Falha                            | Vai para retry ou dead-letter com causa.                                                                                                 |

### `query_execution`

| Aspecto                          | Definição                                                                                                                                                                |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Finalidade                       | Registrar cada tentativa efetiva de consulta.                                                                                                                            |
| Campos principais e obrigatórios | `id`, `office_id`, `query_job_id`, `process_id`, `provider_id`, `started_at`, `finished_at`, `status`, `http_status` opcional, `error_code` e `error_message_sanitized`. |
| Chaves e unicidade               | ID próprio; não duplicar execução equivalente sem tentativa distinta.                                                                                                    |
| Relacionamentos/cardinalidade    | N:1 com job, processo e provider; 1:0/1 com payload bruto e snapshot conforme resultado.                                                                                 |
| Índices                          | `process_id + started_at`, `status`, `query_job_id`.                                                                                                                     |
| Auditoria                        | Criação e classificação de resultado.                                                                                                                                    |
| Dados pessoais                   | Pode referenciar processo; não guardar segredo.                                                                                                                          |
| Retenção/exclusão                | Conforme política operacional.                                                                                                                                           |
| Falha                            | Estados específicos nunca viram `unchanged`.                                                                                                                             |

### `raw_provider_payload`

| Aspecto                          | Definição                                                                                                                            |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Finalidade                       | Preservar resposta original sanitizada.                                                                                              |
| Campos principais e obrigatórios | `id`, `office_id`, `query_execution_id`, `provider_id`, `payload_uri_private`, `payload_hash`, `received_at`, `sanitization_status`. |
| Chaves e unicidade               | `query_execution_id` no máximo um payload bruto principal.                                                                           |
| Relacionamentos/cardinalidade    | 1:1 ou 1:N para fragmentos controlados por execução.                                                                                 |
| Índices                          | Hash, execução, data de retenção.                                                                                                    |
| Auditoria                        | Criação e tentativa de acesso. Conteúdo não é editável.                                                                              |
| Dados pessoais                   | Pode conter dados processuais; storage privado.                                                                                      |
| Retenção/exclusão                | 180 dias inicialmente, sujeito a validação jurídica.                                                                                 |
| Falha                            | Se sanitização falhar, não disponibilizar payload e encaminhar à falha.                                                              |

### `process_snapshot`

| Aspecto                          | Definição                                                                                                       |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Guardar estado normalizado e imutável para comparação.                                                          |
| Campos principais e obrigatórios | `id`, `office_id`, `process_id`, `query_execution_id`, `canonical_data_private`, `snapshot_hash`, `created_at`. |
| Chaves e unicidade               | `process_id + snapshot_hash` único.                                                                             |
| Relacionamentos/cardinalidade    | N:1 com processo e execução; serve de origem para alterações.                                                   |
| Índices                          | `process_id + created_at`, hash.                                                                                |
| Auditoria                        | Criação e leitura autorizada; nunca editar.                                                                     |
| Dados pessoais                   | Pode conter partes; acesso privado.                                                                             |
| Retenção/exclusão                | Conforme política; preservar snapshots usados por relatório.                                                    |
| Falha                            | Não criar em consulta falha.                                                                                    |

### `process_movement`

| Aspecto                          | Definição                                                                                                  |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Representar movimentação normalizada.                                                                      |
| Campos principais e obrigatórios | `id`, `office_id`, `process_id`, `source`, `movement_date`, `description`, `stable_hash`, `first_seen_at`. |
| Chaves e unicidade               | `process_id + stable_hash` único; hash não depender de texto volátil.                                      |
| Relacionamentos/cardinalidade    | N:1 com processo; pode ser referenciada por alteração.                                                     |
| Índices                          | Processo/data, hash, `movement_date`.                                                                      |
| Auditoria                        | Origem e primeira detecção; correções criam registro auditável.                                            |
| Dados pessoais                   | Descrição pode conter dados pessoais; acesso privado.                                                      |
| Retenção/exclusão                | Preservar histórico necessário ao relatório.                                                               |
| Falha                            | Movimento sem evidência fica pendente, não oficial.                                                        |

### `detected_change`

| Aspecto                          | Definição                                                                                                                                      |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Registrar diferença material entre snapshots.                                                                                                  |
| Campos principais e obrigatórios | `id`, `office_id`, `process_id`, `previous_snapshot_id`, `new_snapshot_id`, `change_fingerprint`, `change_type`, `description`, `detected_at`. |
| Chaves e unicidade               | `process_id + previous_snapshot_id + new_snapshot_id + change_fingerprint` único.                                                              |
| Relacionamentos/cardinalidade    | N:1 com processo e snapshots; **1:N com `notification`**. Uma alteração pode gerar zero ou várias notificações.                                |
| Índices                          | Processo/data, fingerprint, status de processamento.                                                                                           |
| Auditoria                        | Criação, revisão e silenciamento.                                                                                                              |
| Dados pessoais                   | Descrição pode conter dados processuais.                                                                                                       |
| Retenção/exclusão                | Preservar enquanto referenciada por alertas e relatórios.                                                                                      |
| Falha                            | Alteração sem evidência não gera notificação.                                                                                                  |

## Notificações

### `notification_preference`

| Aspecto                          | Definição                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------- |
| Finalidade                       | Definir canal, destinatários e tipos de alerta.                                       |
| Campos principais e obrigatórios | `id`, `office_id`, `user_profile_id`, `channel`, `recipient`, `active`, `created_at`. |
| Chaves e unicidade               | Um destinatário/canal ativo por escopo e evento conforme política.                    |
| Relacionamentos/cardinalidade    | N:1 com usuário e escritório; pode originar N notificações.                           |
| Índices                          | Escritório, usuário, canal, ativo.                                                    |
| Auditoria                        | Criação, alteração e pausa.                                                           |
| Dados pessoais                   | E-mail do destinatário.                                                               |
| Retenção/exclusão                | Desativação lógica.                                                                   |
| Falha                            | Destinatário inválido fica pendente e não envia.                                      |

### `notification`

| Aspecto                          | Definição                                                                                                                                            |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Fila de alerta ligado a uma alteração.                                                                                                               |
| Campos principais e obrigatórios | `id`, `office_id`, `detected_change_id`, `recipient`, `channel`, `content_private`, `idempotency_key`, `status`, `attempt_count`, `next_attempt_at`. |
| Chaves e unicidade               | `detected_change_id + recipient + channel + template_version` único.                                                                                 |
| Relacionamentos/cardinalidade    | **N:1 com `detected_change`; 1:N com `notification_attempt`**.                                                                                       |
| Índices                          | Status/próxima tentativa, chave, alteração.                                                                                                          |
| Auditoria                        | Criação, processamento, cancelamento e envio.                                                                                                        |
| Dados pessoais                   | Destinatário e conteúdo processual; privado.                                                                                                         |
| Retenção/exclusão                | Preservar histórico de entrega e falha.                                                                                                              |
| Falha                            | Retry ou `failed`/`dead_letter`, nunca sucesso falso.                                                                                                |

### `notification_attempt`

| Aspecto                          | Definição                                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Finalidade                       | Histórico de cada tentativa de envio.                                                                        |
| Campos principais e obrigatórios | `id`, `office_id`, `notification_id`, `attempted_at`, `status`, `provider_response_sanitized`, `error_code`. |
| Chaves e unicidade               | ID de tentativa; não sobrescrever tentativa anterior.                                                        |
| Relacionamentos/cardinalidade    | **N:1 com `notification`**; uma notificação possui várias tentativas.                                        |
| Índices                          | Notificação/data, status.                                                                                    |
| Auditoria                        | Cada tentativa é evidência.                                                                                  |
| Dados pessoais                   | Resposta sanitizada e destinatário indireto.                                                                 |
| Retenção/exclusão                | Preservar conforme entrega e auditoria.                                                                      |
| Falha                            | Resposta bruta do fornecedor não deve conter segredo.                                                        |

## Relatórios e Entregas

### `weekly_report`

| Aspecto                          | Definição                                                                                                          |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Finalidade                       | Representar o relatório semanal de um cliente.                                                                     |
| Campos principais e obrigatórios | `id`, `office_id`, `client_id`, `period_start_utc`, `period_end_utc`, `timezone`, `status`, `created_at`.          |
| Chaves e unicidade               | Uma chave por cliente e período.                                                                                   |
| Relacionamentos/cardinalidade    | N:1 com cliente; 1:N com `report_process`, `report_party`, `report_version`, `report_artifact` e `email_delivery`. |
| Índices                          | Cliente/período, status.                                                                                           |
| Auditoria                        | Geração, edição, aprovação, cancelamento e envio.                                                                  |
| Dados pessoais                   | Conteúdo consolidado de cliente, partes e processos.                                                               |
| Retenção/exclusão                | Relatórios enviados não excluídos automaticamente até validação jurídica.                                          |
| Falha                            | Não avançar para envio sem versão aprovada e artefato íntegro.                                                     |

### `report_process`

| Aspecto                          | Definição                                                                                              |
| -------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Finalidade                       | Compor visão do relatório por processo.                                                                |
| Campos principais e obrigatórios | `id`, `office_id`, `report_id`, `process_id`, `status_in_period`, `summary_draft`, `source_reference`. |
| Chaves e unicidade               | `report_id + process_id` único.                                                                        |
| Relacionamentos/cardinalidade    | N:1 com relatório e processo.                                                                          |
| Índices                          | Relatório, processo, estado.                                                                           |
| Auditoria                        | Inclusão, remoção e edição.                                                                            |
| Dados pessoais                   | Resumo processual.                                                                                     |
| Retenção/exclusão                | Segue relatório; exclusão lógica.                                                                      |
| Falha                            | Falha de consulta deve ser estado explícito.                                                           |

### `report_party`

| Aspecto                          | Definição                                                                     |
| -------------------------------- | ----------------------------------------------------------------------------- |
| Finalidade                       | Compor visão do relatório por parte.                                          |
| Campos principais e obrigatórios | `id`, `office_id`, `report_id`, `party_id`, `summary_draft`, `process_count`. |
| Chaves e unicidade               | `report_id + party_id` único.                                                 |
| Relacionamentos/cardinalidade    | N:1 com relatório e parte.                                                    |
| Índices                          | Relatório, parte.                                                             |
| Auditoria                        | Inclusão e edição.                                                            |
| Dados pessoais                   | Nome e resumo da parte.                                                       |
| Retenção/exclusão                | Segue relatório; exclusão lógica.                                             |
| Falha                            | Relação pendente deve aparecer como revisão manual.                           |

### `report_version`

| Aspecto                          | Definição                                                                                                                           |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Preservar cada versão editável ou aprovada.                                                                                         |
| Campos principais e obrigatórios | `id`, `office_id`, `report_id`, `version_number`, `content_snapshot_private`, `content_hash`, `created_by`, `created_at`, `status`. |
| Chaves e unicidade               | `report_id + version_number` único.                                                                                                 |
| Relacionamentos/cardinalidade    | **N:1 com `weekly_report`**; um relatório possui várias versões; `email_delivery` aponta para a versão exata.                       |
| Índices                          | Relatório/número, hash, status.                                                                                                     |
| Auditoria                        | Criação, aprovação e uso no envio.                                                                                                  |
| Dados pessoais                   | Conteúdo do relatório.                                                                                                              |
| Retenção/exclusão                | Versão enviada imutável e preservada.                                                                                               |
| Falha                            | Não editar versão aprovada; criar nova versão.                                                                                      |

### `report_artifact`

| Aspecto                          | Definição                                                                                                               |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Registrar PDF ou outro artefato derivado de versão.                                                                     |
| Campos principais e obrigatórios | `id`, `office_id`, `report_id`, `report_version_id`, `artifact_type`, `private_storage_uri`, `file_hash`, `created_at`. |
| Chaves e unicidade               | Hash identifica conteúdo; versão pode ter artefatos de teste e final.                                                   |
| Relacionamentos/cardinalidade    | N:1 com relatório e versão; pode ser referenciado por entregas.                                                         |
| Índices                          | Relatório, versão, hash.                                                                                                |
| Auditoria                        | Criação, acesso e invalidação.                                                                                          |
| Dados pessoais                   | PDF contém dados processuais; storage privado.                                                                          |
| Retenção/exclusão                | Artefato enviado preservado.                                                                                            |
| Falha                            | Hash divergente bloqueia envio.                                                                                         |

### `email_delivery`

| Aspecto                          | Definição                                                                                                                                                                           |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Registrar cada tentativa ou entrega de e-mail de relatório.                                                                                                                         |
| Campos principais e obrigatórios | `id`, `office_id`, `report_id`, `report_version_id`, `artifact_id`, `recipient`, `subject`, `artifact_hash`, `private_pdf_uri`, `sent_at`, `status`, `provider_response_sanitized`. |
| Chaves e unicidade               | Idempotência por versão, destinatário e hash; múltiplas entregas são permitidas.                                                                                                    |
| Relacionamentos/cardinalidade    | **N:1 com `weekly_report` e `report_version`**; um relatório possui 1:N entregas/tentativas.                                                                                        |
| Índices                          | Relatório/data, versão/status, destinatário.                                                                                                                                        |
| Auditoria                        | Cada tentativa, sucesso, falha e retry.                                                                                                                                             |
| Dados pessoais                   | Destinatário e PDF.                                                                                                                                                                 |
| Retenção/exclusão                | Cópia enviada não excluída automaticamente.                                                                                                                                         |
| Falha                            | Não marcar `sent` sem confirmação adequada do provider.                                                                                                                             |

## Auditoria

### `audit_log`

| Aspecto                          | Definição                                                                                                                                |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Finalidade                       | Trilha append-only de ações críticas e eventos de segurança.                                                                             |
| Campos principais e obrigatórios | `id`, `office_id`, `actor_user_id` opcional, `action`, `entity_type`, `entity_id`, `correlation_id`, `metadata_sanitized`, `created_at`. |
| Chaves e unicidade               | ID próprio; não atualizar nem apagar fisicamente.                                                                                        |
| Relacionamentos/cardinalidade    | N:1 opcional com usuário; referência polimórfica controlada.                                                                             |
| Índices                          | Escritório/data, entidade, ator, correlação.                                                                                             |
| Auditoria                        | O próprio log deve ter proteção append-only.                                                                                             |
| Dados pessoais                   | IP e metadados minimizados e protegidos.                                                                                                 |
| Retenção/exclusão                | Sem exclusão automática até validação jurídica.                                                                                          |
| Falha                            | Falha de auditoria bloqueia operações críticas ou gera incidente técnico.                                                                |

## Regras Globais de Integridade

1. CNJ é único por escritório.
2. Hash estável de movimentação é único por processo.
3. Snapshots são imutáveis.
4. Payloads brutos são imutáveis e não contêm credenciais.
5. Versão enviada do relatório é imutável.
6. Auditoria é append-only.
7. Referências de arquivos são sempre privadas.
8. Toda entidade operacional possui `office_id` direto ou verificável.
9. `detected_change` relaciona-se a 0:N notificações; `notification` a 1:N tentativas; `weekly_report` a 1:N versões e entregas.
10. Nenhuma consulta falha pode gerar estado de ausência de alteração.
11. Nenhuma associação sugerida por nome é confirmada automaticamente.
12. Todas as alterações de configuração, confirmação e envio são auditadas.

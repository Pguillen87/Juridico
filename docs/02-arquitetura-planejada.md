# Arquitetura Planejada

## 1. Visão e Limites

A solução será uma aplicação web hospedada. O computador do advogado será usado para desenvolvimento e manutenção, mas não será requisito para a execução diária. O MVP ficará limitado a um escritório, porém todas as entidades operacionais terão `office_id` diretamente ou por relacionamento obrigatório verificável.

### Diagrama textual

```text
[Usuário / Navegador]
        |
        v
[Frontend administrativo]
        | HTTPS + sessão
        v
[API / Casos de uso]
   |       |        |        |
   |       |        |        +--> [Serviço de relatórios / PDF]
   |       |        +-----------> [Scheduler / fila]
   |       +--------------------> [Auth / autorização / RLS]
   v
[PostgreSQL + storage privado]
   |              |
   |              +--> [Payloads brutos, snapshots e artefatos]
   v
[Workers]
   |
   +--> [Provider DataJud]
   +--> [ManualProvider]
   +--> [Futuros providers por capabilities]
   |
   +--> [Normalizador -> comparador -> detected_change]
   +--> [Fila de notificações -> EmailProvider abstrato]

[Logs estruturados / métricas / alertas técnicos / auditoria]
```

O frontend não acessará diretamente provedores processuais, storage privado ou tabelas sem passar por API e políticas de autorização. A API aplicará casos de uso, validação e `office_id`; workers executarão consultas e notificações; o banco manterá estado auditável; provedores serão adaptadores isolados.

## 2. Fronteiras entre Camadas

| Camada | Responsabilidade | Não deve fazer |
|---|---|---|
| Frontend | Apresentar dados, estados, ações e erros; coletar confirmação | Consultar tribunal diretamente ou decidir autorização |
| API | Autenticar, autorizar, validar comandos e orquestrar casos de uso | Esconder falha como ausência de movimentação |
| Banco | Persistir estado, constraints, RLS, hashes e auditoria | Conter segredo em payload ou depender de texto livre para integridade |
| Scheduler | Calcular janelas no fuso operacional e criar jobs idempotentes | Executar consultas diretamente no processo do usuário |
| Fila/worker | Executar jobs com lock, retries e classificação | Criar duplicações ou manter lock indefinido |
| Provider | Converter contrato interno em chamada de fonte autorizada | Fazer scraping, bypass ou inventar capacidades |
| Normalizador/comparador | Canonicalizar, criar snapshots e detectar diferenças | Consultar fonte ou emitir parecer jurídico |
| IA opcional | Sugerir rascunhos | Ser fonte oficial, aprovar, alterar datas ou enviar |
| E-mail | Entregar mensagens aprovadas e registrar resposta | Escolher versão não aprovada |

## 3. Fluxo de Consulta

1. O scheduler identifica processos ativos e a janela no fuso `America/Sao_Paulo`.
2. Para cada processo, verifica capacidade do provider, publicidade, lock e existência de job equivalente.
3. Cria `query_job` com chave de idempotência.
4. O worker adquire lock com expiração e cria `query_execution`.
5. O provider consulta somente fonte autorizada e devolve contrato bruto e metadados.
6. O sistema sanitiza e grava `raw_provider_payload` imutável, sem credenciais.
7. O normalizador gera estrutura interna e o snapshot canônico.
8. O comparador usa o último snapshot bem-sucedido, registra movimentos por hash estável e cria `detected_change` se houver mudança material.
9. O sistema registra `changed`, `unchanged` ou estado de falha específico. Falha nunca vira `unchanged`.
10. Para alteração, cria zero ou mais notificações conforme preferências e chave idempotente.
11. O worker libera lock, registra métricas e disponibiliza evidência para o relatório.

## 4. Interface dos Provedores

Cada provider implementará uma interface conceitual:

```text
Provider
  id(): string
  capabilities(): ProviderCapability[]
  canQuery(process): boolean
  query(process, context): ProviderResponse
  classifyError(error): QueryFailureState
```

Capacidades opcionais: `basic_data`, `movements`, `parties`, `publications`, `documents` e `sealed_process`. Ausência de `parties` significa que partes não foram fornecidas; não autoriza inferência por nome. `DataJudProvider` será o primeiro adaptador automático. `ManualProvider` registrará fonte, operador, data e evidência sem fingir consulta automática.

Não serão fixados fornecedor de hospedagem ou fornecedor definitivo de e-mail nesta etapa. A integração de e-mail usará `EmailProvider` abstrato e adaptador falso/sandbox para desenvolvimento e testes.

## 5. Agendamento e Fila

Os horários iniciais são 08:00, 13:00 e 18:00 em `America/Sao_Paulo`, configuráveis e sujeitos à validação do advogado. O scheduler armazena timestamps em UTC, calcula a próxima janela com timezone explícito e não depende do navegador.

`query_job` e `notification` serão processados por workers. A fila terá tentativa, prioridade, status, próxima tentativa, início, conclusão, erro sanitizado e correlação. Estados de job incluem `pending`, `processing`, `succeeded`, `retry_scheduled`, `failed`, `dead_letter` e `cancelled`.

## 6. Idempotência e Concorrência

Chaves conceituais:

| Operação | Chave idempotente |
|---|---|
| Consulta | `office_id + process_id + scheduled_window_utc + provider_id` |
| Alteração | `process_id + previous_snapshot_hash + new_snapshot_hash + change_fingerprint` |
| Notificação | `detected_change_id + recipient + channel + template_version` |
| Relatório | `office_id + client_id + period_start_utc + period_end_utc` |
| Entrega | `report_version_id + recipient + artifact_hash` |

O banco terá constraints únicas para essas chaves quando aplicável. Antes de consultar, o worker adquirirá lock por `office_id + process_id`, com TTL e renovação controlada. Lock expirado poderá ser recuperado por worker de manutenção. Uma consulta concorrente do mesmo processo deverá ser rejeitada ou agregada, nunca executada duas vezes em paralelo.

## 7. Retries e Central de Falhas

Retries serão aplicados somente a falhas transitórias, como timeout, indisponibilidade e limites de requisição, com backoff exponencial, jitter e máximo configurável. Respostas não encontradas ou não suportadas não serão repetidas indefinidamente. Após o limite, o job irá para dead-letter ou central de falhas, com ação recomendada e reprocessamento manual auditado.

## 8. Armazenamento

Payloads brutos serão armazenados em local privado, com hash, referência ao provider, query execution, data UTC, status de sanitização e política de retenção. Snapshots serão imutáveis e conterão hash canônico. PDFs serão armazenados em bucket privado, nunca em URL pública; referências expostas à aplicação deverão ser temporárias e autorizadas.

A retenção inicial proposta para payload bruto é de 180 dias, sujeita à validação jurídica. Relatórios enviados, versões enviadas, artefatos e trilhas de auditoria não serão excluídos automaticamente até decisão jurídica. Exclusões necessárias serão lógicas, auditadas e não apagarão evidências essenciais.

## 9. Autenticação, Autorização e RLS

A autenticação usará Supabase Auth ou mecanismo equivalente aprovado. O usuário terá perfil em `user_profile` vinculado a `office`. A API validará sessão, papel e `office_id` antes de cada comando. O PostgreSQL aplicará RLS por escritório, sem confiar apenas em filtros do frontend.

A tentativa de acessar um processo, parte, relatório, payload ou artefato de outro escritório não poderá revelar existência ou conteúdo. Operações administrativas, aprovação, envio, reprocessamento e alteração de permissões exigirão papéis específicos e auditoria.

## 10. Segredos e Dados Sensíveis

Credenciais externas serão mantidas em gerenciador de segredos ou variáveis de ambiente seguras. Não serão gravadas em código, commits, logs, payloads brutos, mensagens de erro ou PDFs. Logs deverão aplicar sanitização e mascaramento. Processos sigilosos não terão consulta automática no MVP.

## 11. Logs, Métricas e Alertas Técnicos

Logs estruturados deverão conter correlação, `office_id` não sensível, processo pseudonimizado, provider, job, duração, status e erro sanitizado. Métricas incluirão sucesso, falha, latência, timeout, HTTP 429, retries, jobs duplicados, fila, notificações, PDF, RLS e armazenamento.

Alertas técnicos deverão ser emitidos para falha prolongada do scheduler, aumento de timeout, DLQ, erro de backup, divergência de hash, falha de entrega e indisponibilidade de provider. Nenhum alerta técnico deverá incluir segredo ou conteúdo desnecessário de processo.

## 12. Backups e Restauração

O banco deverá possuir backup automático conforme capacidade do fornecedor escolhido, retenção documentada e restauração testada em ambiente isolado. Payloads e PDFs privados deverão possuir estratégia de backup ou reconstrução definida. Cada teste de restauração terá data, ambiente, resultado, tempo de recuperação e pendências.

## 13. Ambientes e Implantação

Haverá ambientes local, homologação e produção. Local usará dados fictícios controlados, adaptador falso e nenhum processo real. Homologação usará sandbox de e-mail e fixtures; qualquer PoC real exigirá números CNJ fornecidos e aprovados. Produção usará credenciais próprias, RLS, storage privado, observabilidade, backup e aprovação de implantação.

A estratégia de implantação será definida após aprovação da stack e do fornecedor de hospedagem. Migrações deverão ser revisáveis e executadas somente em etapa autorizada; esta auditoria não inicializa Next.js, Supabase, banco ou migrações.

## 14. Decisões Pendentes

Permanecem pendentes a aprovação da stack, fornecedor de hospedagem, fornecedor de e-mail, mecanismo de fila, storage, valores finais de retry, TTL de lock, retenção, papéis definitivos, contrato de DataJud, política jurídica de dados sigilosos, RPO/RTO de backup e critérios de prontidão para produção.

# Plano de Implementação

Este plano descreve a sequência autorizável do MVP. A prova de conceito técnica ocorre antes da implementação integral do DataJud. Cada fase possui objetivo, pré-requisitos, alterações autorizadas, arquivos prováveis, entregas, testes, validações manuais, riscos, dependências, critério de conclusão, definição de pronto e itens que exigem autorização. Esta auditoria não executa nenhuma fase de implementação.

## Fase 1 — Validação e PoC Técnica

| Item | Plano |
|---|---|
| Objetivo | Validar contrato do provider, modelo de resposta, armazenamento privado, normalização, snapshot e sandbox sem usar números não aprovados. |
| Pré-requisitos | Stack aprovada, números CNJ públicos reais fornecidos e aprovados, autorização explícita para consulta, credenciais externas válidas. |
| Alterações autorizadas | Somente ambiente de teste, fixtures, adaptadores falsos e documentação da PoC. |
| Arquivos prováveis | `docs/06-plano-da-prova-de-conceito.md`, testes de contrato, configuração de sandbox. |
| Entregas | Resultado por processo, contrato de provider e lista de lacunas. |
| Testes | Unitários de canonicalização, fixtures de sucesso/falha e teste de hash. |
| Validações manuais | Confirmar processos públicos, fonte, campos e autorização. |
| Riscos | Contrato desconhecido, dados incompletos, limite de requisições. |
| Dependências | Decisão do usuário e validação jurídica. |
| Critério de conclusão | PoC aprovada ou riscos bloqueantes registrados. |
| Definição de pronto | Evidências armazenadas sem segredo e nenhuma alteração não explicada. |
| Autorização | Números CNJ, consulta real e uso de credencial externa. |

## Fase 2 — Fundação do Repositório

| Item | Plano |
|---|---|
| Objetivo | Inicializar repositório e convenções técnicas após aprovação da stack. |
| Pré-requisitos | Stack aprovada e autorização de inicialização. |
| Alterações autorizadas | Criar scaffold, lint, formatação, testes, ambientes e documentação de operação. |
| Arquivos prováveis | `package.json`, `src/`, `tests/`, `.env.example`, CI e `README.md`. |
| Entregas | Projeto executável localmente com comandos documentados. |
| Testes | Build, lint, teste mínimo e verificação sem segredos. |
| Validações manuais | Conferir scripts, README, exclusão de `.env` e reprodutibilidade. |
| Riscos | Dependência precoce ou stack incompatível. |
| Dependências | Fase 1 e decisão da stack. |
| Critério de conclusão | Scaffold reproduzível e limpo. |
| Definição de pronto | Nenhuma credencial real; CI básico verde. |
| Autorização | Instalação de dependências e criação do código. |

## Fase 3 — Autenticação e Autorização

| Item | Plano |
|---|---|
| Objetivo | Implementar login, recuperação de senha, perfis e papéis. |
| Pré-requisitos | Fundação e fornecedor Auth aprovado. |
| Alterações autorizadas | Telas, casos de uso, `user_profile`, policies e auditoria de autenticação. |
| Arquivos prováveis | `src/auth/`, `src/users/`, migrations, testes E2E. |
| Entregas | Sessão segura, papéis e bloqueios. |
| Testes | Login, recuperação, sessão expirada, autorização positiva/negativa. |
| Validações manuais | Conferir permissões por papel e mensagens sem enumeração de contas. |
| Riscos | Acesso indevido e recuperação insegura. |
| Dependências | Fase 2, Auth e RLS posterior. |
| Critério de conclusão | Fluxos críticos cobertos e auditados. |
| Definição de pronto | Usuário sem permissão não executa ação nem vê dados. |
| Autorização | Configurar serviço externo de autenticação. |

## Fase 4 — Modelo de Dados e RLS

| Item | Plano |
|---|---|
| Objetivo | Criar entidades, constraints, índices e isolamento por escritório. |
| Pré-requisitos | Modelo conceitual aprovado e banco de homologação. |
| Alterações autorizadas | Migrations, RLS, seeds não reais e testes de isolamento. |
| Arquivos prováveis | `db/migrations/`, schemas, policies e testes. |
| Entregas | Esquema consistente, `party`, `process_party`, cardinalidades e auditoria. |
| Testes | Constraints, unicidade CNJ/hash, imutabilidade, RLS e rollback em teste. |
| Validações manuais | Tentar acesso cruzado e confirmar ausência de vazamento. |
| Riscos | Modelo incorreto, migração destrutiva, RLS incompleta. |
| Dependências | Fase 3 e aprovação jurídica de retenção. |
| Critério de conclusão | Entidades e políticas cobertas por testes. |
| Definição de pronto | Nenhum registro operacional sem `office_id` verificável. |
| Autorização | Criar banco real e executar migrações. |

## Fase 5 — Clientes, Partes e Vínculos

| Item | Plano |
|---|---|
| Objetivo | Entregar cadastro de cliente, partes e relações confirmáveis. |
| Pré-requisitos | Modelo e RLS. |
| Alterações autorizadas | UI/API de `client`, `party`, `client_related_party`, `process_party`. |
| Arquivos prováveis | Módulos de cadastro, validação e auditoria. |
| Entregas | Cliente principal, filhas e partes jurídicas com papéis e confirmação. |
| Testes | N:N, homônimos, confirmação, rejeição e isolamento. |
| Validações manuais | Conferir origem, evidência e status de cada vínculo. |
| Riscos | Associação equivocada e exposição de PII. |
| Dependências | Fase 4. |
| Critério de conclusão | Vínculo por nome não é confirmado automaticamente. |
| Definição de pronto | Todas as decisões humanas ficam auditadas. |
| Autorização | Cadastrar dados reais de cliente e partes. |

## Fase 6 — Processos e Importação CSV

| Item | Plano |
|---|---|
| Objetivo | Cadastrar processos e importar carteira com validação. |
| Pré-requisitos | Clientes, partes e validador CNJ. |
| Alterações autorizadas | UI/API, parser, prévia, confirmação e auditoria. |
| Arquivos prováveis | Módulo de processos, parser CSV, fixtures e testes. |
| Entregas | Cadastro manual e importação sem duplicação. |
| Testes | CSV válido, vazio, coluna ausente, CNJ inválido e duplicado. |
| Validações manuais | Conferir linhas inválidas antes de confirmar. |
| Riscos | Importação silenciosa, CNJ errado, dados sigilosos. |
| Dependências | Fase 5. |
| Critério de conclusão | Nenhum CSV grava sem prévia e confirmação. |
| Definição de pronto | Resumo e auditoria coincidem com registros persistidos. |
| Autorização | Importar a carteira real de aproximadamente 60 processos. |

## Fase 7 — Abstração de Provedores

| Item | Plano |
|---|---|
| Objetivo | Criar contrato comum, capabilities e classificação de falhas. |
| Pré-requisitos | PoC e modelo de processos. |
| Alterações autorizadas | Interfaces, adapters, catálogo de capabilities e testes de contrato. |
| Arquivos prováveis | `providers/`, contratos, schemas e fixtures. |
| Entregas | `Provider`, `ManualProvider`, `ProviderCapability` e estados padronizados. |
| Testes | Provider sem partes, não suportado, erro e capability. |
| Validações manuais | Confirmar que provider nunca usa scraping ou bypass. |
| Riscos | Contrato rígido ou capability inventada. |
| Dependências | Fases 1, 4 e 6. |
| Critério de conclusão | Todos os adapters obedecem contrato e falhas são explícitas. |
| Definição de pronto | Fonte ausente não é convertida em sem alteração. |
| Autorização | Contrato de acesso do fornecedor. |

## Fase 8 — DataJud e Provedor Manual

| Item | Plano |
|---|---|
| Objetivo | Implementar o conector DataJud somente após PoC aprovada e manter fallback manual. |
| Pré-requisitos | Fases 1, 4 e 7; contrato e credenciais aprovados. |
| Alterações autorizadas | Adapter, sanitização, payload, normalização e configuração segura. |
| Arquivos prováveis | `providers/datajud/`, `providers/manual/`, testes de contrato. |
| Entregas | Consulta autorizada, resposta bruta, capabilities e estados. |
| Testes | Sucesso, schema incompleto, timeout, 429, 5xx e not found simulados. |
| Validações manuais | Conferir logs sem segredo e evidência por processo. |
| Riscos | Mudança de contrato, indisponibilidade, dados incompletos. |
| Dependências | Fornecedor e credencial externa. |
| Critério de conclusão | DataJud e manual classificados corretamente em homologação. |
| Definição de pronto | Nenhum processo sigiloso é consultado automaticamente. |
| Autorização | Consulta real, credencial e uso de dados reais. |

## Fase 9 — Scheduler, Fila e Snapshots

| Item | Plano |
|---|---|
| Objetivo | Automatizar janelas, jobs, locks, retries e snapshots. |
| Pré-requisitos | Provider funcional e configuração de horários. |
| Alterações autorizadas | Scheduler, worker, queue, lock, `query_job`, `query_execution`, payload e snapshot. |
| Arquivos prováveis | `jobs/`, `workers/`, `queue/`, migrations e testes. |
| Entregas | Execução programada idempotente e estado observável. |
| Testes | Concorrência, relógio, lock expirado, retry, dead-letter e snapshot. |
| Validações manuais | Confirmar UTC/apresentação local e fila. |
| Riscos | Job duplicado, scheduler parado, perda de payload. |
| Dependências | Fases 4 e 8. |
| Critério de conclusão | Jobs não se duplicam e falhas não viram sucesso. |
| Definição de pronto | Reprocessamento seguro e evidência disponível. |
| Autorização | Ativar scheduler em homologação/produção. |

## Fase 10 — Comparação e Detecção

| Item | Plano |
|---|---|
| Objetivo | Normalizar, comparar, deduplicar movimentos e criar alterações. |
| Pré-requisitos | Snapshots e contrato normalizado. |
| Alterações autorizadas | Comparador, hash, `process_movement`, `detected_change`. |
| Arquivos prováveis | `comparison/`, `normalization/`, testes unitários. |
| Entregas | Baseline, alteração material e ausência de alteração corretas. |
| Testes | Ordem de movimentos, correção retroativa, repetição e falso positivo/negativo. |
| Validações manuais | Revisar evidência e classificação por processo. |
| Riscos | Falso positivo, falso negativo, hash instável. |
| Dependências | Fase 9. |
| Critério de conclusão | Comparador reproduz resultados esperados em fixtures. |
| Definição de pronto | Falha não produz `unchanged`; alteração possui fingerprint. |
| Autorização | Usar dados reais na PoC aprovada. |

## Fase 11 — Notificações e Central de Falhas

| Item | Plano |
|---|---|
| Objetivo | Entregar fila de alertas, e-mail abstrato e tratamento operacional de falhas. |
| Pré-requisitos | Detecção e preferências. |
| Alterações autorizadas | `notification`, tentativas, provider e central. |
| Arquivos prováveis | `notifications/`, `failures/`, templates e testes sandbox. |
| Entregas | Alerta sem duplicidade, retries e ação manual. |
| Testes | E-mail falso, falha, retry, destinatário inválido e idempotência. |
| Validações manuais | Confirmar conteúdo, fonte e bloqueio de envio indevido. |
| Riscos | E-mail não entregue, segredo no conteúdo, duplicação. |
| Dependências | Fases 8-10 e fornecedor futuro. |
| Critério de conclusão | Cada falha tem status e próximo passo. |
| Definição de pronto | Envio só ocorre para evento elegível e destinatário ativo. |
| Autorização | Contratar fornecedor e enviar para destinatário real. |

## Fase 12 — Relatório Semanal, Revisão e Versionamento

| Item | Plano |
|---|---|
| Objetivo | Gerar, editar, versionar e aprovar relatório por processo e parte. |
| Pré-requisitos | Movimentos, alterações, falhas e permissões. |
| Alterações autorizadas | `weekly_report`, `report_process`, `report_party`, `report_version` e UI. |
| Arquivos prováveis | `reports/`, templates e testes. |
| Entregas | Draft, revisão, estados e versão aprovada. |
| Testes | Período, agrupamentos, edição, versão, cancelamento e bloqueio. |
| Validações manuais | Conferir que falha permanece falha e revisão é explícita. |
| Riscos | Janela errada, versão incorreta, conteúdo IA apresentado como oficial. |
| Dependências | Fases 10-11. |
| Critério de conclusão | Relatório exibe evidência e transita com autorização. |
| Definição de pronto | Não existe caminho de envio sem aprovação. |
| Autorização | Aprovar modelo de comunicação ao cliente. |

## Fase 13 — PDF e Envio por E-mail

| Item | Plano |
|---|---|
| Objetivo | Gerar PDF da versão aprovada e registrar entrega imutável. |
| Pré-requisitos | Relatório aprovado, storage privado e provider sandbox. |
| Alterações autorizadas | `report_artifact`, `email_delivery`, renderer e validação de hash. |
| Arquivos prováveis | `pdf/`, `delivery/`, storage policies e testes. |
| Entregas | PDF privado, hash, versão exata e cópia de envio. |
| Testes | PDF divergente, retry, falha, destinatário e hash. |
| Validações manuais | Comparar PDF com versão aprovada e destinatário. |
| Riscos | PDF diferente, e-mail errado, artefato público. |
| Dependências | Fase 12 e fornecedor de e-mail. |
| Critério de conclusão | Entrega usa exatamente versão e artefato aprovados. |
| Definição de pronto | Cópia imutável recuperável e privada. |
| Autorização | Envio real e armazenamento definitivo. |

## Fase 14 — Segurança, Testes, Implantação e Piloto

| Item | Plano |
|---|---|
| Objetivo | Consolidar segurança, testes críticos, backups, implantação e piloto controlado. |
| Pré-requisitos | Fases anteriores concluídas e decisões jurídicas. |
| Alterações autorizadas | Hardening, CI/CD, monitoramento, backup e documentação operacional. |
| Arquivos prováveis | Policies, pipelines, runbooks, testes, dashboards e matriz de incidentes. |
| Entregas | MVP candidato, plano de recuperação e piloto. |
| Testes | Unitários, E2E, RLS, carga limitada, backup/restauração e segurança. |
| Validações manuais | Aprovação do advogado, processo real aprovado, relatório de ponta a ponta. |
| Riscos | Restauração não testada, custos, dependência de fornecedor. |
| Dependências | Todas as fases e aprovações. |
| Critério de conclusão | Critérios de pronto do MVP e piloto atendidos. |
| Definição de pronto | Operação e recuperação documentadas, sem envio não aprovado. |
| Autorização | Implantação, piloto e consulta dos números CNJ aprovados. |

## Regra de Paralisação

Qualquer fase deve parar se exigir credencial não fornecida, consulta de processo não aprovada, acesso a sigiloso, mudança destrutiva, fornecedor não contratado, decisão jurídica pendente ou interpretação que possa apresentar falha como ausência de movimentação.

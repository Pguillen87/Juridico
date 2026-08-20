# Riscos e Decisões Pendentes

## Matriz de Riscos

| ID | Risco | Probabilidade | Impacto | Prevenção | Detecção | Resposta | Responsável | Evidência de mitigação |
|---|---|---|---|---|---|---|---|---|
| R-001 | Mudança de contrato da API | Média | Alto | Adapter versionado e contrato de teste | Falha de schema e métrica de erro | Pausar provider, adaptar contrato e usar manual | Técnico/provider | Teste de contrato versionado |
| R-002 | Indisponibilidade prolongada | Média | Alto | Retries limitados e provider manual | SLO e alerta técnico | Central de falhas e revisão manual | Operador | Incidente e reprocessamento |
| R-003 | Retorno atrasado da fonte | Média | Médio | Timeout e janela de retry | Latência por provider | Reclassificar e informar data | Técnico | Métrica de latência |
| R-004 | Mudança retroativa em movimentação | Média | Alto | Hash e comparação versionada | Diferença em snapshot anterior | Criar alteração auditável, não apagar histórico | Advogado/técnico | Caso de teste retroativo |
| R-005 | Dados incompletos | Alta | Alto | Capabilities e campos opcionais | Validação de schema | Marcar desconhecido/manual, nunca inventar | Técnico | Fixture incompleta |
| R-006 | Exposição de dados pessoais | Baixa | Crítico | RLS, storage privado, minimização | DLP/logs e revisão de acesso | Revogar acesso, investigar e notificar conforme plano | Segurança | Teste de acesso e incidente |
| R-007 | Acesso cruzado entre escritórios | Baixa | Crítico | `office_id` obrigatório e RLS | Testes negativos de API/RLS | Bloquear e corrigir policy | Técnico | Teste automatizado RLS |
| R-008 | Perda de payloads | Baixa | Alto | Storage privado, hash e backup | Verificação de URI/hash | Restaurar backup e registrar lacuna | Operações | Teste de restauração |
| R-009 | Falha de scheduler | Média | Alto | Healthcheck e execução idempotente | Métrica de janela perdida | Recriar jobs da janela e abrir incidente | Operações | Alerta de janela |
| R-010 | Execução duplicada | Média | Alto | Chave e lock por processo | Métrica de deduplicação | Cancelar duplicada e preservar evidência | Técnico | Teste de concorrência |
| R-011 | Notificação duplicada | Média | Médio | Chave por alteração/destinatário/canal | Índice único e métrica | Ignorar duplicada e auditar | Técnico | Teste de retry |
| R-012 | E-mail não entregue | Média | Alto | Sandbox, retries e provider abstrato | Status de entrega | Retry, central e contato manual | Operador | Evidência do provider |
| R-013 | Relatório enviado com versão incorreta | Baixa | Crítico | `report_version_id` obrigatório | Comparação de hash | Bloquear envio e investigar | Advogado/técnico | Teste de versão |
| R-014 | PDF diferente da versão aprovada | Baixa | Crítico | Hash do artefato e verificação pré-envio | Hash divergente | Bloquear e regenerar | Técnico | Teste de hash |
| R-015 | Vazamento de segredo | Baixa | Crítico | Secret manager e sanitização | Scan de logs/repositório | Revogar/rotacionar e investigar | Segurança | Scan sem segredo |
| R-016 | Custos externos inesperados | Média | Médio | Limites, orçamento e sandbox | Métrica de consumo | Pausar integração e revisar | Owner | Relatório de custo |
| R-017 | Dependência de fornecedor | Média | Alto | Interfaces e ManualProvider | Mudança de SLA/preço | Plano de contingência e adapter | Owner/técnico | Teste de fallback |
| R-018 | Ausência de backup | Baixa | Crítico | Política e rotina automatizada | Alerta de backup ausente | Suspender produção e configurar | Operações | Relatório de backup |
| R-019 | Restauração não testada | Média | Alto | Exercício periódico | Registro de RTO/RPO | Corrigir runbook e repetir | Operações | Ata de restauração |
| R-020 | Crescimento de armazenamento | Alta | Médio | Retenção de payload e orçamento | Métrica de volume | Arquivar conforme decisão jurídica | Owner/técnico | Relatório de capacidade |
| R-021 | Falso positivo | Média | Alto | Comparador e regras de materialidade | Amostragem e revisão | Corrigir regra e gerar nota | Técnico/advogado | Suite de regressão |
| R-022 | Falso negativo | Média | Crítico | Baseline, cobertura de campos e revisão | Amostragem de fonte | Reprocessar período e comunicar | Técnico/advogado | Teste de detecção |
| R-023 | Uso indevido da IA | Média | Alto | Marcação de rascunho e bloqueio de envio | Auditoria e revisão | Remover texto, corrigir e registrar | Advogado | Teste de bloqueio |
| R-024 | IA interpretada como prazo oficial | Média | Crítico | Aviso explícito e ausência de cálculo | Revisão de conteúdo | Retirar rascunho e comunicar | Advogado | Checklist de revisão |
| R-025 | Homônimo associado incorretamente | Média | Alto | Confirmação humana obrigatória | Auditoria de vínculos | Reverter vínculo e revisar processos | Advogado | Teste de confirmação |
| R-026 | Processo sigiloso consultado | Baixa | Crítico | Bloqueio automático no MVP | Auditoria de provider | Interromper, investigar e revisar autorização | Advogado/técnico | Teste de bloqueio |
| R-027 | CNJ inválido ou duplicado | Média | Médio | Validador e constraint por escritório | Erro de importação | Corrigir fonte e reimportar | Operador | Fixture de CSV |
| R-028 | Falha de lock | Média | Alto | TTL, renovação e cleanup | Jobs presos | Liberar lock expirado com auditoria | Técnico | Teste de timeout |
| R-029 | Janela em fuso errado | Média | Alto | IANA timezone e UTC interno | Comparação de janela | Corrigir configuração e reprogramar | Owner/técnico | Teste de relógio |
| R-030 | Relatório mistura falha e ausência | Baixa | Crítico | Estados obrigatórios e testes | Revisão de conteúdo | Bloquear aprovação e corrigir | Advogado/técnico | Teste de relatório |

## Decisões Pendentes

| ID | Decisão | Estado | Responsável | Prazo desejado | Impacto | Validação exigida |
|---|---|---|---|---|---|---|
| D-001 | Aprovar stack técnica | `proposed` | Usuário/owner | Antes da fundação | Bloqueia código e dependências | Aprovação do usuário |
| D-002 | Confirmar fuso `America/Sao_Paulo` | `proposed` | Advogado | Antes do scheduler | Afeta consultas e relatório | Validação do advogado |
| D-003 | Confirmar 08:00, 13:00 e 18:00 | `proposed` | Advogado | Antes do scheduler | Afeta carga e alertas | Validação do advogado |
| D-004 | Confirmar sexta 17:00 | `proposed` | Advogado | Antes do relatório | Afeta período semanal | Validação do advogado |
| D-005 | Escolher fornecedor de hospedagem | `requires_user_input` | Owner | Antes da implantação | Afeta custos, backup e RLS | Aprovação do usuário/contratação |
| D-006 | Escolher fornecedor de e-mail | `deferred` | Owner | Antes do envio real | Exige contratação e credencial | Contratação e credencial externa |
| D-007 | Usar falso/sandbox em desenvolvimento | `proposed` | Técnico | Antes da implementação | Permite testes seguros | Validação técnica |
| D-008 | Reter payload bruto 180 dias | `proposed` | Advogado/jurídico | Antes da retenção | Afeta LGPD e custo | Validação jurídica |
| D-009 | Não excluir relatórios e auditoria automaticamente | `proposed` | Jurídico/owner | Antes da produção | Afeta privacidade e storage | Validação jurídica |
| D-010 | Não consultar sigilosos no MVP | `approved` provisório | Advogado | Escopo atual | Limita cobertura, reduz risco | Revisão jurídica se mudar |
| D-011 | Fornecer 5–10 CNJs públicos reais | `requires_user_input` | Usuário/advogado | Antes da PoC | Bloqueia teste real | Aprovação explícita |
| D-012 | Definir papéis definitivos | `requires_user_input` | Advogado | Antes de RLS | Afeta autorização | Validação do advogado |
| D-013 | Definir RPO/RTO | `requires_user_input` | Owner/técnico | Antes da produção | Afeta backup e custo | Aprovação do usuário |
| D-014 | Definir limites de retry e lock | `proposed` | Técnico | Antes dos workers | Afeta carga e recuperação | Validação técnica |

Não há implementação autorizada enquanto decisões marcadas como bloqueantes não forem resolvidas. Credenciais externas, consultas reais, retenção jurídica e envio real exigem autorizações separadas.

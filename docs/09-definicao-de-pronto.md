# Definição de Pronto

## Pronto para uma História

Uma história estará pronta quando:

1. O fluxo principal, alternativo e casos de erro estiverem implementados conforme a história.
2. Critérios Given/When/Then estiverem cobertos por teste automatizado ou evidência manual aprovada.
3. Autorização, `office_id`, validação e auditoria estiverem aplicados.
4. Estados de falha estiverem explícitos e nunca forem tratados como ausência de movimentação.
5. Dados pessoais e segredos estiverem protegidos.
6. A documentação e a matriz de rastreabilidade estiverem atualizadas.
7. O advogado ou responsável indicado tiver revisado o comportamento quando houver decisão de negócio.

## Pronto para uma Fase

Uma fase estará pronta quando todos os entregáveis da fase estiverem concluídos, os pré-requisitos e autorizações estiverem registrados, os testes planejados estiverem aprovados ou com exceção formal, os riscos críticos tiverem resposta, nenhuma migração destrutiva estiver pendente e a definição de pronto específica da fase estiver satisfeita.

A fase não será considerada concluída se depender de credencial externa não fornecida, decisão jurídica pendente, consulta não autorizada, teste crítico ausente ou comportamento que classifique falha como sem alteração.

## Pronto para a Prova de Conceito

A PoC estará pronta quando:

- Houver de cinco a dez processos públicos reais fornecidos e aprovados explicitamente.
- Existir autorização para consulta, ambiente de homologação e sandbox de e-mail.
- Cada processo possuir ficha com CNJ mascarado quando necessário, tribunal, confirmação pública, data, resposta HTTP, campos, movimentos, snapshot, hash, alteração, falha, resultado e observações.
- Os grupos DataJud real, dados simulados, indisponibilidade, deduplicação, relatório e e-mail sandbox estiverem separados.
- Não houver processo inventado, sigiloso não autorizado, segredo exposto ou envio real indevido.
- Falhas forem separadas de ausência de movimentação.
- O comparador, a deduplicação, o relatório, o PDF e a aprovação forem validados.

## Pronto para o MVP

O MVP somente poderá ser considerado pronto quando:

- O advogado conseguir autenticar-se e recuperar a senha.
- O escritório conseguir cadastrar clientes, partes relacionadas e seus papéis.
- O sistema conseguir cadastrar e importar processos por CSV com validação CNJ, prévia, confirmação, erros e auditoria.
- O sistema conseguir vincular partes e processos por `process_party`, sem confirmação automática por nome.
- O advogado conseguir ativar ou pausar monitoramento.
- O sistema conseguir consultar DataJud e `ManualProvider` conforme capabilities e autorização.
- Respostas brutas forem armazenadas de forma privada e imutável, sem credenciais.
- Dados forem normalizados, snapshots forem criados e comparações forem reprodutíveis.
- O sistema detectar alteração e impedir duplicação de movimentos, alterações e notificações.
- Consulta sem alteração for distinguida de fonte indisponível, não encontrado, não suportado, limite, timeout, falha técnica e revisão manual.
- A central de falhas permitir reprocessamento manual auditado.
- O sistema enviar alerta de teste em sandbox.
- O sistema gerar relatório semanal por processo e por parte.
- O advogado conseguir revisar, editar, versionar e aprovar.
- O sistema gerar PDF da versão aprovada.
- O sistema enviar somente a versão aprovada e preservar cópia imutável com hash, destinatário, assunto, artefato, data, status e resposta sanitizada.
- Auditoria, RLS, backups, restauração, testes críticos, documentação de operação e recuperação estiverem concluídos.

## Pronto para Implantação

A implantação estará pronta quando:

1. Stack e fornecedores estiverem aprovados e contratados.
2. Ambientes local, homologação e produção estiverem separados.
3. Segredos estiverem em mecanismo seguro e ausentes de código, logs e payloads.
4. Migrações forem revisadas, reproduzíveis e executadas somente no ambiente autorizado.
5. RLS e testes de acesso cruzado estiverem aprovados.
6. Backup, restauração, RPO e RTO estiverem documentados e testados.
7. Scheduler, fila, retries, locks, dead-letter, métricas e alertas técnicos estiverem observáveis.
8. Política de retenção tiver validação jurídica.
9. Plano de rollback e resposta a incidentes estiverem disponíveis.
10. Não existir caminho de envio sem aprovação humana.

## Pronto para o Piloto

O piloto estará pronto quando houver um escritório e usuários autorizados, processos públicos aprovados, configuração de e-mail confirmada, limites de consulta conhecidos, relatório e alerta revisados pelo advogado, suporte para falhas, runbook de operação, canal de incidentes, métricas de sucesso e critérios de interrupção.

Durante o piloto, qualquer processo sigiloso, consulta sem autorização, divergência de PDF, falha de isolamento, segredo exposto, classificação de falha como ausência de movimentação ou envio sem aprovação interromperá a operação e exigirá análise antes de retomar.

## Critérios de Bloqueio

Nenhum nível de prontidão substitui validação jurídica, aprovação do usuário ou fornecimento dos números CNJ. O status de pronto deve permanecer bloqueado quando uma dependência crítica estiver em `requires_user_input`, `requires_legal_review` ou sem evidência.

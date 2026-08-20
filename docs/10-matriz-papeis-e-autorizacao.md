# Status: PROPOSTA — AGUARDANDO APROVAÇÃO DO USUÁRIO

## 1. Documentos analisados

A elaboração desta proposta baseou-se na análise rigorosa da documentação do projeto Juridico. Foram consultados os requisitos do produto, o modelo de dados conceitual, o plano de implementação, as decisões do MVP, a matriz de rastreabilidade e a definição de pronto. A fundação técnica existente na branch `phase-3-foundation` (commit `689c84cbf5abce3163baa01edc4bc0c12d3fcd81`) também foi considerada para garantir o alinhamento com a arquitetura estabelecida.

## 2. Papéis candidatos e capacidade administrativa

A documentação original lista cinco papéis: `owner`, `lawyer`, `operator`, `reviewer` e `auditor`. No entanto, para evitar contradições entre poderes administrativos e responsabilidades jurídicas, a recomendação principal para o MVP é separar o papel funcional da capacidade administrativa.

O usuário possuirá exatamente **um papel funcional** (`role`) entre:
- `lawyer`
- `operator`
- `reviewer`
- `auditor`

Adicionalmente, o usuário poderá possuir uma **capacidade administrativa** definida por um atributo booleano separado:
- `is_owner`

O atributo `is_owner` concede poderes para administrar o escritório (convidar usuários, alterar configurações, inativar contas), mas **não** concede automaticamente poderes jurídicos (como aprovar relatórios). Os poderes jurídicos continuam derivados estritamente do `role`. Por exemplo, um advogado proprietário terá `role = lawyer` e `is_owner = true`, somando as permissões jurídicas do advogado às permissões administrativas do proprietário.

## 3. Matriz atômica de permissões

A tabela abaixo detalha as permissões atômicas de acesso e operação para cada um dos papéis funcionais, bem como as permissões adicionadas pela capacidade `is_owner`. Todas as ações avaliadas utilizam exclusivamente os valores `ALLOW`, `DENY` ou `NOT_APPLICABLE`.

| Ação | `lawyer` | `operator` | `reviewer` | `auditor` | `is_owner` adiciona |
|---|---|---|---|---|---|
| 1. Visualizar dados operacionais do escritório | ALLOW | ALLOW | ALLOW (se necessário à revisão) | DENY | ALLOW |
| 2. Convidar usuário | DENY | DENY | DENY | DENY | ALLOW |
| 3. Inativar usuário | DENY | DENY | DENY | DENY | ALLOW |
| 4. Alterar papel funcional | DENY | DENY | DENY | DENY | ALLOW |
| 5. Conceder/remover owner | DENY | DENY | DENY | DENY | ALLOW |
| 6. Criar/editar clientes | ALLOW | ALLOW | DENY | DENY | DENY |
| 7. Criar/editar partes | ALLOW | ALLOW | DENY | DENY | DENY |
| 8. Confirmar vínculos de partes | ALLOW | DENY | DENY | DENY | DENY |
| 9. Cadastrar processo | ALLOW | ALLOW | DENY | DENY | DENY |
| 10. Importar CSV | ALLOW | ALLOW | DENY | DENY | DENY |
| 11. Ativar/desativar monitoramento | ALLOW | ALLOW | DENY | DENY | DENY |
| 12. Executar reprocessamento manual | ALLOW | ALLOW | DENY | DENY | DENY |
| 13. Visualizar payload bruto | ALLOW | DENY | DENY | DENY | DENY |
| 14. Visualizar evidência sanitizada | ALLOW | ALLOW | ALLOW | ALLOW | DENY |
| 15. Visualizar falhas | ALLOW | ALLOW | ALLOW | DENY | DENY |
| 16. Tratar falhas | ALLOW | ALLOW | DENY | DENY | DENY |
| 17. Visualizar alterações | ALLOW | ALLOW | ALLOW | DENY | DENY |
| 18. Editar rascunho de relatório | ALLOW | DENY | ALLOW | DENY | DENY |
| 19. Marcar/revisar relatório | ALLOW | DENY | ALLOW | DENY | DENY |
| 20. Aprovar relatório final | ALLOW | DENY | DENY | DENY | DENY |
| 21. Cancelar relatório | ALLOW | DENY | DENY | DENY | DENY |
| 22. Gerar PDF final | ALLOW | DENY | DENY | DENY | DENY |
| 23. Autorizar envio | ALLOW | DENY | DENY | DENY | DENY |
| 24. Visualizar audit_log | ALLOW | DENY | DENY | ALLOW | ALLOW |
| 25. Exportar auditoria | ALLOW | DENY | DENY | ALLOW | ALLOW |
| 26. Exportar dados operacionais | ALLOW | DENY | DENY | DENY | ALLOW |
| 27. Alterar configurações administrativas | DENY | DENY | DENY | DENY | ALLOW |

## 4. Decisões A–N (Pontos que exigem decisão do usuário)

A implementação da autorização requer decisões explícitas sobre comportamentos específicos do sistema. As recomendações técnicas a seguir visam equilibrar segurança e usabilidade com o novo modelo `role` + `is_owner`.

| Item | Pergunta | Recomendação | Justificativa e Riscos |
|---|---|---|---|
| A | OWNER pode aprovar relatório jurídico? | **DENY (isoladamente)** | A aprovação exige conhecimento jurídico. O `is_owner` sozinho não permite aprovar; o usuário deve ter `role=lawyer` + `is_owner=true`. Liberar apenas pelo `is_owner` arrisca aprovação por administrador técnico. |
| B | REVIEWER pode editar relatório? | **ALLOW** | A revisão pressupõe a capacidade de corrigir erros antes da aprovação. Restringir a apenas leitura reduziria a utilidade do papel. |
| C | REVIEWER pode aprovar relatório final? | **DENY** | A aprovação para envio ao cliente deve ser responsabilidade exclusiva do advogado (`lawyer`). Liberar essa ação arrisca o envio de informações sem crivo jurídico final. |
| D | OPERATOR pode executar reprocessamento manual? | **ALLOW (com limites)** | É rotina técnica para resolver falhas (ex: timeouts), sem alterar mérito jurídico. Deve haver limites, auditoria e restrição a processos autorizados para evitar consumo excessivo da API. |
| E | OPERATOR pode visualizar payload bruto? | **DENY** | O payload pode conter dados sensíveis ou técnicos não destinados à operação básica. O operador deve se guiar pela interface normalizada. |
| F | AUDITOR pode visualizar payload bruto? | **DENY** | O auditor deve focar nas trilhas de ações e estados, não na depuração de rede. Liberar isso expõe dados potencialmente sigilosos contidos nos payloads brutos. |
| G | LAWYER pode convidar usuários? | **DENY (pelo role)** | A gestão de acessos deve ser centralizada. Apenas se o advogado possuir `is_owner=true` a ação será permitida (ALLOW). |
| H | Somente OWNER pode alterar papéis? | **ALLOW apenas para is_owner=true** | A alteração de papéis é uma escalada de privilégios e deve ser restrita ao administrador, garantindo o Princípio do Menor Privilégio. |
| I | Um usuário pode ter mais de um papel? | **DENY no MVP** | O usuário terá um único papel funcional (`role`) e a capacidade administrativa separada (`is_owner`), simplificando a lógica de RLS sem perder flexibilidade. |
| J | Papel é único por usuário no MVP? | **ALLOW (papel funcional único)** | Armazenar o papel em uma única coluna enum na tabela de perfil é a abordagem mais segura e rápida para o MVP. |
| K | Usuário inativo perde acesso imediatamente? | **ALLOW (revogação imediata)** | Requisito de segurança. As policies e guards devem verificar `user_profile.is_active = true`, não dependendo apenas da revogação da sessão. |
| L | OWNER pode desativar a própria conta? | **DENY (salvo se houver outro ativo)** | O `owner` só pode desativar a si mesmo se existir outro `owner` ativo capaz de administrar o escritório, prevenindo lockout irreversível. |
| M | Último OWNER pode ser removido? | **DENY** | O sistema deve garantir a existência de pelo menos um `owner` ativo por escritório para evitar instâncias órfãs. |
| N | Quem visualiza documentos protegidos? | **lawyer (por padrão)** | Documentos jurídicos protegidos são acessíveis ao `lawyer`. O `is_owner` sozinho não concede acesso. O `reviewer` poderá acessar apenas se estritamente necessário à revisão. |

## 5. Cadastro público no MVP?

Um novo ponto de decisão emerge sobre a forma de entrada de novos usuários.
- **Recomendação:** DENY. O MVP com escritório único deve permitir a entrada de usuários **somente por convite administrativo** de um usuário com `is_owner=true`.
- **Justificativa:** O convite deverá ser realizado em backend seguro, garantindo que a chave de serviço (`service_role`) nunca seja exposta ao navegador e mantendo o controle absoluto sobre as licenças e acessos do escritório.

## 6. Modelo recomendado de autorização

Para o MVP, a arquitetura de autorização recomendada baseia-se na atribuição de um único papel funcional (`role`) e uma capacidade administrativa (`is_owner`). Estes atributos serão armazenados na tabela `user_profile`, que estará obrigatoriamente vinculada a um identificador de escritório (`office_id`) e possuirá um status de atividade (`is_active`).

A nomenclatura recomendada para código e documentação futura é utilizar `is_owner` para a capacidade administrativa e `role` para os papéis funcionais (`lawyer`, `operator`, `reviewer`, `auditor`).

A segurança será garantida através de uma abordagem em camadas. A interface de usuário ocultará rotas e ações não autorizadas. O middleware do Next.js protegerá as rotas da API, verificando a validade da sessão e os atributos do usuário. O banco de dados utilizará políticas de segurança em nível de linha (Row Level Security) para assegurar o isolamento e as restrições, independentemente de falhas nas camadas superiores.

## 7. Princípios futuros de RLS (Row Level Security)

As políticas RLS a serem implementadas na Fase 4 seguirão princípios estritos de isolamento e segurança:
- **Identidade e Isolamento de Tenant:** A identidade será baseada em `auth.uid()`, resolvendo o perfil ativo e obtendo o `office_id` e atributos confiáveis. O sistema não aceitará um `office_id` arbitrário fornecido pelo cliente e não dependerá de claims customizadas mutáveis/obsoletas como única fonte de isolamento.
- **Bloqueio de Usuários Inativos:** Toda policy e guard sensível deverá verificar obrigatoriamente `user_profile.is_active = true`. Uma sessão ou token ainda existente não poderá fornecer acesso aos dados após a inativação.
- **Restrição de Mutação por Papel:** A mutação de dados será restrita conforme o `role` e o `is_owner`.
- **Prevenção de Escalada:** Nenhum usuário poderá alterar seu próprio `role` ou conceder `is_owner` a si próprio.
- **Segurança da Service Role:** A chave de serviço (`service_role`), que ignora o RLS, será mantida estritamente no backend e nunca exposta ao ambiente do navegador.
- **Proteção do Último Owner:** A garantia de que o último `owner` ativo nunca seja removido ou inativado deverá existir de forma transacional no banco ou em função SQL controlada para impedir condições de corrida.

## 8. Escopo futuro de Supabase Auth

A integração com o Supabase Auth na Fase 4 abrangerá a configuração segura do cliente no Next.js, suportando fluxos completos de login, logout e recuperação de senha. O sistema tratará adequadamente sessões expiradas e protegerá rotas autenticadas via Middleware.

O fluxo de registro exigirá a criação do perfil do usuário (`user_profile`) e seu vínculo a um escritório (`office_id`). Para mitigar riscos de segurança, as mensagens de erro de autenticação serão genéricas, prevenindo a enumeração de contas registradas na plataforma.

## 9. Matriz futura de testes

A validação da autorização exigirá testes automatizados rigorosos para garantir a integridade do sistema. A matriz futura de testes deverá cobrir os seguintes cenários positivos e negativos:
- `lawyer` sem `is_owner` não gerencia usuários.
- `lawyer` com `is_owner` gerencia usuários.
- `is_owner` com `role` não-lawyer não aprova relatório.
- `reviewer` não aprova relatórios.
- `reviewer` não gera PDF final.
- `auditor` não acessa dados operacionais gerais.
- `auditor` exporta somente auditoria.
- `operator` não acessa payload bruto.
- Usuário não altera próprio `role`.
- Usuário não concede `is_owner` a si próprio.
- Último `owner` não pode ser removido.
- `owner` pode sair somente se existir outro `owner` ativo.
- Usuário inativo com token ainda válido não lê/escreve dados.
- Escritório A não acessa dados do escritório B.
- `office_id` enviado pelo cliente não permite falsificação.
- Acesso direto à API não contorna restrições da UI.
- `service_role` nunca é exposta ao browser.

## 10. Pontos pendentes de decisão do usuário

A decisão D-022 permanece pendente de aprovação explícita do usuário. As seguintes definições precisam ser confirmadas antes de iniciar a implementação da Fase 4:
- Adoção do modelo separando `role` funcional e capacidade administrativa `is_owner`.
- Aprovação da matriz atômica de permissões.
- Aprovação das recomendações para os itens de decisão A–N e do item sobre cadastro público.
- Implementação transacional da regra de proteção do último `owner` ativo.

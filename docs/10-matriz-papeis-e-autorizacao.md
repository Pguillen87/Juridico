# Status: PROPOSTA — AGUARDANDO APROVAÇÃO DO USUÁRIO

## 1. Documentos analisados

A elaboração desta proposta baseou-se na análise rigorosa da documentação do projeto Juridico. Foram consultados os requisitos do produto, o modelo de dados conceitual, o plano de implementação, as decisões do MVP, a matriz de rastreabilidade e a definição de pronto. A fundação técnica existente na branch `phase-3-foundation` (commit `689c84cbf5abce3163baa01edc4bc0c12d3fcd81`) também foi considerada para garantir o alinhamento com a arquitetura estabelecida.

## 2. Papéis candidatos

A documentação atual define cinco papéis distintos para o sistema: `owner`, `lawyer`, `operator`, `reviewer` e `auditor`.

## 3. Matriz completa de permissões

A tabela abaixo detalha as permissões de acesso e operação para cada um dos papéis candidatos, aplicando o Princípio do Menor Privilégio. Todas as ações avaliadas utilizam exclusivamente os valores `ALLOW`, `DENY` ou `NOT_APPLICABLE`.

| Ação | `owner` | `lawyer` | `operator` | `reviewer` | `auditor` |
|---|---|---|---|---|---|
| Visualizar dados do escritório | ALLOW | ALLOW | ALLOW | ALLOW | ALLOW |
| Gerenciar usuários | ALLOW | DENY | DENY | DENY | DENY |
| Alterar papéis | ALLOW | DENY | DENY | DENY | DENY |
| Criar/editar clientes e partes | ALLOW | ALLOW | ALLOW | DENY | DENY |
| Confirmar vínculos de partes | ALLOW | ALLOW | DENY | DENY | DENY |
| Cadastrar processos e importar CSV | ALLOW | ALLOW | ALLOW | DENY | DENY |
| Ativar/desativar monitoramento | ALLOW | ALLOW | DENY | DENY | DENY |
| Executar reprocessamento manual | ALLOW | ALLOW | ALLOW | DENY | DENY |
| Visualizar payload bruto e evidência privada | ALLOW | ALLOW | DENY | DENY | DENY |
| Visualizar falhas e alterações | ALLOW | ALLOW | ALLOW | ALLOW | DENY |
| Tratar falhas | ALLOW | ALLOW | ALLOW | DENY | DENY |
| Editar rascunho e revisar relatório | ALLOW | ALLOW | DENY | ALLOW | DENY |
| Aprovar relatório e autorizar envio | ALLOW | ALLOW | DENY | DENY | DENY |
| Cancelar relatório | ALLOW | ALLOW | DENY | DENY | DENY |
| Gerar PDF | ALLOW | ALLOW | DENY | ALLOW | DENY |
| Visualizar auditoria e exportar informações | ALLOW | DENY | DENY | DENY | ALLOW |
| Alterar configurações do escritório | ALLOW | DENY | DENY | DENY | DENY |

## 4. Decisões A–N (Pontos que exigem decisão do usuário)

A implementação da autorização requer decisões explícitas sobre comportamentos específicos do sistema. As recomendações técnicas a seguir visam equilibrar segurança e usabilidade.

| Item | Pergunta | Recomendação | Justificativa e Riscos |
|---|---|---|---|
| A | OWNER pode aprovar relatório jurídico? | **ALLOW** | O administrador principal deve ter controle total sobre a operação. Negar isso bloquearia o sócio do escritório de operar o sistema se ele não possuir também o papel de advogado. |
| B | REVIEWER pode editar relatório? | **ALLOW** | A revisão pressupõe a capacidade de corrigir erros antes da aprovação. Restringir a apenas leitura reduziria a utilidade do papel, sobrecarregando o advogado. |
| C | REVIEWER pode aprovar relatório final? | **DENY** | A aprovação para envio ao cliente deve ser responsabilidade exclusiva do advogado. Liberar essa ação arrisca o envio de informações sem crivo jurídico. |
| D | OPERATOR pode executar reprocessamento manual? | **ALLOW** | O reprocessamento é uma rotina técnica para resolver falhas, sem alterar o mérito jurídico. Negar isso sobrecarregaria o advogado com tarefas puramente técnicas. |
| E | OPERATOR pode visualizar payload bruto? | **DENY** | O payload pode conter dados sensíveis ou técnicos não destinados à operação básica. O operador deve se guiar pela interface normalizada. |
| F | AUDITOR pode visualizar payload bruto? | **DENY** | O auditor deve focar nas trilhas de ações e estados, não na depuração de rede. Liberar isso expõe dados potencialmente sigilosos contidos nos payloads. |
| G | LAWYER pode convidar usuários? | **DENY** | A gestão de acessos deve ser centralizada no administrador para controle de custos e segurança, evitando o crescimento descontrolado de licenças. |
| H | Somente OWNER pode alterar papéis? | **ALLOW apenas para owner** | A alteração de papéis é uma escalada de privilégios e deve ser restrita ao administrador, garantindo o Princípio do Menor Privilégio. |
| I | Um usuário pode ter mais de um papel? | **DENY no MVP** | Um papel único simplifica drasticamente a lógica de autorização e RLS no MVP. A multiplicidade traria complexidade exponencial ao banco de dados. |
| J | Papel é único por usuário no MVP? | **ALLOW (papel único)** | Armazenar o papel em uma única coluna enum na tabela de perfil é a abordagem mais segura e rápida para garantir a entrega da Fase 4. |
| K | Usuário inativo perde acesso imediatamente? | **ALLOW (revogação imediata)** | Requisito fundamental de segurança. A inativação deve invalidar a sessão atual e bloquear novos logins para proteger os dados do escritório. |
| L | OWNER pode desativar a própria conta? | **DENY** | Previne que o escritório fique sem nenhum administrador ativo, o que causaria um bloqueio irrecuperável do sistema para aquele tenant. |
| M | Último OWNER pode ser removido? | **DENY** | Pela mesma razão do item anterior, o sistema deve garantir a existência de pelo menos um administrador ativo por escritório. |
| N | Quem visualiza documentos protegidos? | **owner, lawyer** | Documentos possuem alta sensibilidade (LGPD) e não devem ser acessíveis a operadores de rotina, mitigando o risco de vazamento de dados. |

## 5. Modelo recomendado de autorização

Para o MVP, a arquitetura de autorização recomendada baseia-se na atribuição de um papel único por usuário. Este papel será armazenado em uma coluna enum na tabela de perfil. Esse perfil estará obrigatoriamente vinculado a um identificador de escritório (`office_id`) e possuirá um status de atividade (`is_active`).

A segurança será garantida através de uma abordagem em camadas. A interface de usuário ocultará rotas e ações não autorizadas. O middleware do Next.js protegerá as rotas da API, verificando a validade da sessão e o papel do usuário. O banco de dados utilizará políticas de segurança em nível de linha (Row Level Security) para assegurar que nenhuma operação SQL possa contornar as restrições de tenant ou de papel, independentemente de falhas nas camadas superiores.

A proteção contra autoelevação será garantida pelo bloqueio de qualquer atualização na coluna de papel pelo próprio usuário, permitindo essa alteração apenas a administradores autorizados. A proteção do último administrador ativo será imposta por meio de regras de negócio na API ou gatilhos no banco de dados.

## 6. Princípios futuros de RLS (Row Level Security)

As políticas RLS a serem implementadas na Fase 4 seguirão princípios estritos de isolamento. O isolamento de tenant garantirá que nenhuma operação afete ou retorne registros cujo identificador de escritório divirja do perfil autenticado. O sistema prevenirá a falsificação de identidade forçando o uso do identificador derivado do token JWT seguro, rejeitando qualquer identificador fornecido arbitrariamente pelo cliente em operações de escrita.

A mutação de dados será restrita conforme o papel. Auditores terão acesso exclusivo de leitura, enquanto operadores e revisores terão permissões de atualização limitadas a tabelas operacionais, sendo bloqueados de alterar perfis de usuário. O sistema também bloqueará usuários inativos no nível do banco de dados e impedirá a escalada de privilégios, garantindo que nenhum usuário possa alterar seu próprio papel. A chave de serviço (`service_role`), que ignora o RLS, será mantida estritamente no backend e nunca exposta ao ambiente do navegador.

## 7. Escopo futuro de Supabase Auth

A integração com o Supabase Auth na Fase 4 abrangerá a configuração segura do cliente no Next.js, suportando fluxos completos de login, logout e recuperação de senha. O sistema tratará adequadamente sessões expiradas e protegerá rotas autenticadas via Middleware.

O fluxo de registro exigirá a criação atômica do perfil do usuário e seu vínculo imediato a um escritório, possivelmente utilizando gatilhos no banco de dados. Para mitigar riscos de segurança, as mensagens de erro de autenticação serão genéricas, prevenindo a enumeração de contas registradas na plataforma.

## 8. Matriz futura de testes

A validação da autorização exigirá testes automatizados rigorosos para garantir a integridade do sistema. A matriz futura de testes deverá cobrir cenários de isolamento, garantindo que usuários de escritórios distintos não acessem dados cruzados. Testes de autorização positiva e negativa confirmarão que cada papel consegue executar apenas as ações permitidas, como a aprovação de relatórios restrita a advogados.

Cenários de segurança incluirão a verificação de que usuários comuns não conseguem escalar seus próprios privilégios e que contas inativas ou com sessões expiradas têm suas requisições sumariamente rejeitadas. Regras de negócio críticas, como o impedimento da remoção do último administrador ativo de um escritório, também serão validadas.

## 9. Pontos pendentes de decisão do usuário

A decisão D-022 permanece pendente de aprovação explícita do usuário. As definições sobre a manutenção dos cinco papéis candidatos, a aprovação das permissões sugeridas e as recomendações para os itens de decisão A–N precisam ser confirmadas. O modelo de papel único por usuário no MVP e a implementação da regra de proteção do último administrador ativo também aguardam validação antes de iniciar a implementação da Fase 4.

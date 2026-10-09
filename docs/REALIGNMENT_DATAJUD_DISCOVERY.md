# Consulta DataJud e descoberta de processos — Realinhamento 1

> Documento de contrato local. A implementação foi testada somente com
> fixtures/mocks explícitos; não houve consumo de dados reais ou validação live.

## 1. Status das Capacidades da API Pública do CNJ

| Recurso / Capacidade | Status no Realinhamento 1 | Implementação Técnica |
| :--- | :--- | :--- |
| **Metadados do Processo** (`numeroProcesso`, `siglaTribunal`, `dataAjuizamento`, `classe`, `assuntos`, `grau`, `nivelSigilo`, `formato`, `sistema`, `orgaoJulgador`) | **TESTADO COM MOCK/ FIXTURE LOCAL** | Implementado no `DataJudPublicAdapter` e no read model da carteira |
| **Movimentações Processuais** (`codigo`, `nome`, `dataHora`, `orgaoJulgador`, `complementosTabelados`) | **TESTADO COM MOCK** | Implementado com `movementRef = sha256(codigo + dataHora + orgao)` e detecção de ambiguidade |
| **Data de Última Atualização** (`dataHoraUltimaAtualizacao`) | **TESTADO COM MOCK** | Capturado em `sourceMetadata.sourceUpdatedAt` fora do payload comparável |
| **Partes do Processo** (polo ativo/passivo) | **NÃO GARANTIDO PELO CONTRATO ATUAL** | A carteira usa vínculos manuais existentes; o provider não inventa parties |
| **CPF/CNPJ → descoberta de processos** | **NÃO IMPLEMENTADO / FONTE NÃO DEFINIDA** | Não há `DiscoveryProvider`, consulta por CPF/CNPJ ou autoimportação |
| **Integração Live com Chave Real do CNJ** | **NÃO TESTADO LIVE** | Gateway e transporte HTTP preparados; testes locais rodam com fixture determinística em `127.0.0.1:54325` |

---

## 2. Padrão de Identidade de Movimentações e Ambiguidades

- Identidade primária da movimentação: `sha256(codigo + dataHora + orgao)`.
- **Deduplicação Determinística**: Entradas estritamente duplicadas no payload retornado pelo CNJ são deduplicadas silenciosamente.
- **Detecção de Colisão Ambígua**: Se o tribunal retornar dois registros com mesma data/código/órgão porém descrições ou complementos divergentes, o sistema rejeita a inferência arbitrária e marca `result_status = 'manual_review_required'` com `error_code = 'datajud_movement_ambiguity_detected'`.

---

## 3. Estrutura Canônica de Endpoint

- Host: `https://api-publica.datajud.cnj.jus.br`
- Resolução via `DataJudEndpointResolver` utilizando o dígito de justiça `J` e tribunal `TR` do padrão CNJ (20 dígitos).
- Exemplo: `NNNNNNN-DD.YYYY.8.26.OOOO` $\rightarrow$ `https://api-publica.datajud.cnj.jus.br/api_publica_tjsp/_search`.
- Consulta: Elasticsearch DSL com `{ query: { match: { numeroProcesso: "NNNNNNNDDYYYY826OOOO" } } }`.

## Fronteira de produto

O R1 cobre somente a carteira já conhecida: o advogado cadastra o processo,
o sistema consulta o CNJ informado e compara observações sucessivas. A
capacidade distinta `CPF/CNPJ → descoberta → revisão humana → incorporação à
carteira` continua deferida até a definição de uma fonte legítima, contratável
e adequada à LGPD. Este documento não presume que o DataJud Público ofereça
essa busca.

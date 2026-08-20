# Prova de Conceito - Juridico (Fase 2)

## Objetivo
Validar tecnicamente a integração com a API Pública do DataJud, comprovando o núcleo do projeto: extração, normalização, hash determinístico de movimentações e deduplicação de eventos.

## Requisitos
- Node.js (v20 ou superior recomendado)
- NPM ou Yarn

## Instalação e Configuração
1. Instale as dependências de desenvolvimento na pasta da PoC:
   ```bash
   cd poc
   npm install
   ```

2. Configure a variável de ambiente. Crie um arquivo `.env` baseado no `.env.example` e adicione sua chave pública:
   ```bash
   DATAJUD_API_KEY=sua_chave_publica_aqui
   ```

## Como executar

### Validação de CNJs
Para testar o script que valida o formato, tamanho e tribunal dos CNJs (focado no TJPR para esta PoC):
```bash
node validate_cnj.js
```

### Testes Automatizados
Para executar a suíte conceitual que valida o algoritmo de comparação e deduplicação sem fazer requisições reais:
```bash
npx vitest comparison.test.ts
# ou, se estiver usando jest: npx jest comparison.test.ts
```

### Execução da PoC (Consultas Reais)
Para executar o orquestrador que consulta o DataJud e gera as evidências:
```bash
node runner.js
```

## Evidências
As consultas reais salvam os payloads brutos (`raw.json`), os dados normalizados (`normalized.json`) e os hashes (`hashes.json`) no diretório `poc/evidence/`. 

**Atenção:** A pasta `poc/evidence/` não é versionada no repositório por conter dados de processos. As evidências permanecem exclusivamente no ambiente local de quem executar a PoC.

## Restrições de Segurança
- Consultas reais devem usar somente processos públicos previamente autorizados.
- Não versionar a chave da API.
- Não expor dados pessoais desnecessários.

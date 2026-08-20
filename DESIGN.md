<!-- SEED: estabelecido como orientação provisória antes da implementação; executar $impeccable document depois que houver código para extrair tokens e componentes reais. -->

---

name: juridico
description: Documento visual provisório para a aplicação administrativa Juridico, uma central de monitoramento jurídico orientada à rastreabilidade, revisão humana e clareza de estados.
---

# Design Seed

## Overview

A interface do Juridico deverá transmitir **clareza operacional, confiança e rastreabilidade**, sem transformar a aplicação em um painel visualmente chamativo ou em uma fonte de aconselhamento jurídico. O design deverá privilegiar a leitura rápida de status, a identificação da fonte e o próximo passo necessário para o advogado.

A tese visual provisória é: **cada processo é uma unidade auditável, cada estado precisa ser compreensível e cada ação irreversível precisa exigir confirmação humana**. A primeira expressão deverá favorecer uma área de trabalho administrativa com hierarquia de informação, filtros, estados explícitos e contexto suficiente para revisão.

A linguagem de movimento deverá ser discreta e funcional, reservada a transições de estado, carregamento e confirmação de ações. Não usar movimento como decoração ou para esconder falhas. A assinatura reutilizável deverá ser a apresentação consistente de fonte, data da consulta, status, evidência e ação recomendada.

## Colors

A estratégia de cores deverá priorizar legibilidade, contraste e distinção semântica de estados. Os valores exatos permanecem `[a serem definidos durante a implementação]`.

Os estados de consulta não poderão depender apenas de cor: alteração, ausência de alteração, fonte indisponível, processo não encontrado, processo não suportado, limite de requisições, timeout, falha técnica e revisão manual necessária deverão possuir rótulo textual, ícone ou estrutura auxiliar. Tons de alerta deverão ser usados com parcimônia para não transformar a central de falhas em uma superfície permanentemente alarmista.

## Typography

A tipografia deverá favorecer leitura prolongada de descrições, datas, nomes de partes, identificadores processuais e observações. A combinação de fontes, pesos, tamanhos e escala permanece `[a ser definida durante a implementação]`.

Números CNJ, datas, status e identificadores deverão manter diferenciação suficiente para comparação visual, sem utilizar fonte excessivamente estilizada. A hierarquia deverá separar claramente título da página, processo, movimentação, fonte, estado e ação.

## Layout

A gramática espacial deverá ser administrativa, previsível e responsiva. O layout deverá permitir que o advogado alterne entre visão por processo e visão por parte, acesse a central de falhas e revise relatórios sem perder contexto.

A interface deverá reservar áreas consistentes para filtros, resumo do estado da carteira, lista de processos, detalhe do item selecionado e histórico. Medidas exatas, breakpoints e grade permanecem `[a serem definidos durante a implementação]`. Em telas menores, a prioridade será preservar o conteúdo essencial, os estados e as ações de revisão.

## Elevation & Depth

A profundidade deverá ser contida e funcional. Superfícies, divisões e estados de foco devem orientar a leitura, não simular um painel de métricas decorativo. Sombras, bordas e camadas permanecem `[a serem definidos durante a implementação]`.

A cópia imutável de um relatório enviado e a evidência de uma consulta deverão ser apresentadas como registros auditáveis, com distinção clara entre dado da fonte, rascunho de IA e anotação do advogado.

## Shapes

A linguagem de formas deverá ser sóbria, consistente e adequada a uma ferramenta profissional. O raio de cantos, espessuras de borda e dimensões de controles permanecem `[a serem definidos durante a implementação]`. Evitar agrupar todo conteúdo em cartões aninhados e evitar formas decorativas que dificultem a leitura de tabelas e históricos.

## Do's and Don'ts

### Do

- Apresentar estado, fonte, data, confiança operacional e ação seguinte de forma explícita.
- Manter falhas de consulta visualmente e semanticamente separadas de ausência de movimentação.
- Exigir confirmação humana para vínculos, aprovação de relatório e envio.
- Expor contexto suficiente para distinguir cliente, parte, papel e processo.
- Usar foco, contraste, rótulos e mensagens de erro acessíveis.
- Preservar a diferença entre informação oficial, entrada manual e rascunho sugerido por IA.

### Don't

- Não representar falha como “sem movimentação”.
- Não confirmar associação por nome automaticamente.
- Não sugerir que IA é fonte oficial, parecerista ou calculadora de prazo.
- Não enviar relatório sem aprovação explícita.
- Não depender somente de cor para comunicar estados.
- Não inventar dados, testemunhos, métricas, movimentações ou referências visuais.
- Não usar cores, gradientes, animações ou ornamentos que reduzam a legibilidade de uma ferramenta jurídica.

> Este documento é um **seed manual**, criado porque o executável real `impeccable` não está disponível no computador local. Quando houver código, executar `$impeccable document` para registrar o sistema visual real e gerar tokens e componentes baseados na implementação.

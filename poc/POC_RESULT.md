# Resultado da Prova de Conceito (Fase 2)

## Status Final: APPROVED

A Prova de Conceito técnica demonstrou que é possível consultar processos públicos reais via API Pública do DataJud, normalizar os dados, extrair um hash determinístico das movimentações e distinguir corretamente uma alteração material (`success_with_changes`) de uma consulta idêntica (`success_without_changes`), sem confundir falhas técnicas com ausência de movimentação.

**Limitação:** esta rodada da PoC valida o provider DataJud para TJPR, mas não valida ainda o roteamento entre tribunais distintos.

Os payloads brutos e evidências completas permanecem exclusivamente no ambiente local e não foram publicados no repositório.

## Critérios Avaliados

1. **Consulta real ao DataJud:** PASS (Endpoint `api_publica_tjpr` consultado com chave pública)
2. **Validação do CNJ:** PASS (10 CNJs validados como pertencentes ao TJPR)
3. **Identificação do tribunal:** PASS (Segmento 8, Tribunal 16 mapeado para TJPR)
4. **Dados básicos:** PASS (Extraídos `classe`, `assuntos`, datas)
5. **Movimentações:** PASS (Lista de eventos extraída)
6. **Payload bruto:** PASS (Salvo localmente em `raw.json` para auditoria)
7. **Normalização:** PASS (Campos convertidos para formato interno estável)
8. **Snapshot:** PASS (Snapshot determinístico criado para comparação)
9. **Hash:** PASS (Hashes SHA-256 gerados ignorando milissegundos voláteis)
10. **Comparação:** PASS (Testado baseline vs nova consulta)
11. **Deduplicação:** PASS (Rodada 2 gerou `success_without_changes` para 8 processos)
12. **Consulta sem alteração:** PASS (Diferenciada de erro e de alteração)
13. **Detecção de alteração:** PASS (Validada via `TEST_FIXTURE_ONLY` gerando `success_with_changes`)
14. **Indisponibilidade / Timeout:** PASS (Tratado e simulado nos testes unitários)
15. **Rate limit:** PASS (Tratamento para HTTP 429 implementado no provider)

## Testes automatizados antes da publicação

Comando executado: `npm test -- --reporter=verbose`.

| Métrica | Resultado |
|---|---:|
| Testes executados | 16 |
| Aprovados | 16 |
| Falhos | 0 |
| Ignorados | 0 |

A suíte cobre comparação unificada, deduplicação, normalização real, hash determinístico unificado, validação completa de CNJ, `process_not_found`, HTTP 429, HTTP 500/503, JSON inválido, regressão de baseline (sucesso após falha) e timeout simulado.

## Execução Real (Segunda Rodada de PoC)

- **Total de CNJs fornecidos:** 10
- **CNJs válidos:** 10
- **Consultas realizadas:** 20 (2 rodadas por processo)
- **Falhas de rede/Timeout reais observadas:** 0 (todas as requisições concluídas com sucesso nesta execução).

### Resumo por Processo

| CNJ | Rodada 1 | Rodada 2 | Movimentações |
|---|---|---|---|
| 0004453-12.2026.8.16.0000 | `success_with_changes` | `success_without_changes` | 36 |
| 0008569-61.2026.8.16.0000 | `success_with_changes` | `success_without_changes` | 34 |
| 0002557-31.2026.8.16.0000 | `success_with_changes` | `success_without_changes` | 42 |
| 0008902-13.2026.8.16.0000 | `success_with_changes` | `success_without_changes` | 32 |
| 0003907-54.2026.8.16.0000 | `success_with_changes` | `success_without_changes` | 42 |
| 0123860-46.2025.8.16.0000 | `success_with_changes` | `success_without_changes` | 39 |
| 0152098-75.2025.8.16.0000 | `success_with_changes` | `success_without_changes` | 30 |
| 0099021-54.2025.8.16.0000 | `success_with_changes` | `success_without_changes` | 55 |
| 0143282-07.2025.8.16.0000 | `success_with_changes` | `success_without_changes` | 48 |
| 0129656-18.2025.8.16.0000 | `success_with_changes` | `success_without_changes` | 38 |

*(Nota: a Rodada 1 retorna `success_with_changes` por ser a consulta baseline - o snapshot anterior era nulo).*

### Teste de Fixture Controlada
Uma movimentação artificial (`TEST_FIXTURE_ONLY`) foi injetada no snapshot do CNJ `0008569`. A comparação do hash antigo com o hash do novo snapshot detectou corretamente a divergência e retornou `success_with_changes`.

## Conclusão
O núcleo de extração, normalização e comparação determinística funciona conforme planejado. O mecanismo é resiliente a variações de rede (timeouts foram classificados corretamente e não geraram falso positivo de ausência de movimentação). O projeto está tecnicamente apto a avançar para a Fase 3 (Fundação Técnica) assim que autorizado.

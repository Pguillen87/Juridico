const { generateMovementHash, generateSnapshotHash } = require('./comparison');

class DataJudProvider {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.baseUrl = 'https://api-publica.datajud.cnj.jus.br';
  }

  id() {
    return 'datajud_public_api';
  }

  capabilities() {
    return ['basic_data', 'movements']; // Partes não estão presentes nos payloads atuais
  }

  canQuery(cnjNumber, tribunalAlias) {
    return !!cnjNumber && tribunalAlias === 'api_publica_tjpr';
  }

  async query(cnjNumber, tribunalAlias) {
    if (!this.canQuery(cnjNumber, tribunalAlias)) {
      return { state: 'unsupported', errorMessage: `Endpoint não suportado: ${tribunalAlias}`, rawPayload: null, durationMs: 0 };
    }

    const cleanCnj = cnjNumber.replace(/\D/g, '');
    const url = `${this.baseUrl}/${tribunalAlias}/_search`;
    
    const payload = {
      query: {
        match: {
          numeroProcesso: cleanCnj
        }
      }
    };

    const startTime = Date.now();
    let response;
    
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `APIKey ${this.apiKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000) // 15s timeout
      });
    } catch (error) {
      if (error.name === 'TimeoutError' || error.name === 'AbortError') {
        return { state: 'timeout', errorMessage: 'Timeout na consulta ao DataJud', rawPayload: null, durationMs: Date.now() - startTime };
      }
      return { state: 'source_unavailable', errorMessage: error.message, rawPayload: null, durationMs: Date.now() - startTime };
    }

    const durationMs = Date.now() - startTime;
    
    if (response.status === 429) {
      return { state: 'rate_limited', errorCode: '429', rawPayload: null, durationMs };
    }
    
    if (!response.ok) {
      return { state: 'source_unavailable', errorCode: response.status.toString(), errorMessage: response.statusText, rawPayload: null, durationMs };
    }

    let rawText;
    let data;
    try {
      rawText = await response.text();
      data = JSON.parse(rawText);
    } catch (e) {
      return { state: 'failed', errorMessage: 'Falha ao ler/parsear JSON da resposta', rawPayload: rawText || null, durationMs };
    }

    if (!data.hits || !data.hits.hits || data.hits.hits.length === 0) {
      return { state: 'process_not_found', rawPayload: data, durationMs };
    }

    const _source = data.hits.hits[0]._source;
    
    // Normalização básica
    const normalizedData = {
      cnjNumber: _source.numeroProcesso,
      tribunal: tribunalAlias,
      classe: _source.classe?.nome,
      assuntos: _source.assuntos?.map(a => a.nome),
      dataAjuizamento: _source.dataAjuizamento,
      lastUpdateDate: _source.dataAtualizacao,
      source: this.id(),
      movements: (_source.movimentos || []).map(m => {
        const stableHash = generateMovementHash(cleanCnj, m);
        return {
          code: m.codigo,
          description: m.nome,
          date: m.dataHora,
          stableHash
        };
      })
    };

    const snapshotHash = generateSnapshotHash(normalizedData.cnjNumber, normalizedData.movements);

    return {
      state: 'success_without_changes', // Será reavaliado pelo comparador na pipeline
      rawPayload: data, // Resposta bruta completa
      httpStatus: response.status,
      normalizedData,
      snapshotHash,
      capabilitiesProvided: this.capabilities(),
      durationMs
    };
  }
}

module.exports = { DataJudProvider };

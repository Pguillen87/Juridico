const crypto = require('crypto');

class DataJudProvider {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.baseUrl = 'https://api-publica.datajud.cnj.jus.br';
  }

  id() {
    return 'datajud_public_api';
  }

  capabilities() {
    return ['basic_data', 'movements', 'parties']; // Pode variar por tribunal
  }

  canQuery(cnjNumber, tribunalAlias) {
    return !!(cnjNumber && tribunalAlias);
  }

  async query(cnjNumber, tribunalAlias) {
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

    let data;
    try {
      data = await response.json();
    } catch (e) {
      return { state: 'failed', errorMessage: 'Falha ao parsear JSON da resposta', rawPayload: null, durationMs };
    }

    if (!data.hits || !data.hits.hits || data.hits.hits.length === 0) {
      return { state: 'process_not_found', rawPayload: data, durationMs };
    }

    const rawPayload = data.hits.hits[0]._source;
    
    // Normalização básica
    const normalizedData = {
      cnjNumber: rawPayload.numeroProcesso,
      tribunal: tribunalAlias,
      classe: rawPayload.classe?.nome,
      assuntos: rawPayload.assuntos?.map(a => a.nome),
      dataAjuizamento: rawPayload.dataAjuizamento,
      lastUpdateDate: rawPayload.dataAtualizacao,
      source: this.id(),
      movements: (rawPayload.movimentos || []).map(m => {
        // Gera stableHash ignorando variações milissegundos
        const dateStr = m.dataHora ? m.dataHora.split('.')[0] : '';
        const hashInput = `${cleanCnj}_${m.codigo || ''}_${m.nome}_${dateStr}`;
        const stableHash = crypto.createHash('sha256').update(hashInput).digest('hex');
        
        return {
          code: m.codigo,
          description: m.nome,
          date: m.dataHora,
          stableHash
        };
      })
    };

    // O hash do snapshot determinístico para comparação
    const snapshotHashInput = JSON.stringify({
      cnj: normalizedData.cnjNumber,
      movs: normalizedData.movements.map(m => m.stableHash).sort()
    });
    const snapshotHash = crypto.createHash('sha256').update(snapshotHashInput).digest('hex');

    return {
      state: 'success_without_changes', // Será reavaliado pelo comparador na pipeline
      rawPayload,
      normalizedData,
      snapshotHash,
      capabilitiesProvided: this.capabilities(),
      durationMs
    };
  }
}

module.exports = { DataJudProvider };

import { createServer } from 'node:http';

const HOST = '127.0.0.1';
// 54322 is reserved by the local Supabase PostgreSQL container on Windows.
const PORT = 54325;
const EXPECTED_AUTHORIZATION = 'APIKey TestOnly-Local-123!';
const requestsByProcess = new Map();

function json(response, status, body, headers = {}) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    ...headers,
  });
  response.end(JSON.stringify(body));
}

function scenarioFor(processNumber) {
  const code = processNumber.slice(-4);
  return (
    {
      '0001': 'not_found',
      '0002': 'mismatch',
      '0003': 'multiple',
      '0004': 'unauthorized',
      '0005': 'endpoint',
      '0006': 'rate_limited',
      '0007': 'source_unavailable',
      '0008': 'timeout',
      '0009': 'changed',
      '0010': 'forbidden',
    }[code] ?? 'exact'
  );
}

function movement(processNumber, suffix) {
  return {
    codigo: suffix === 'new' ? 85 : 60,
    nome:
      suffix === 'new'
        ? 'Movimentação sintética posterior'
        : 'Movimentação sintética inicial',
    dataHora:
      suffix === 'new'
        ? '2026-09-20T12:00:00.000Z'
        : '2026-09-20T10:00:00.000Z',
    orgaoJulgador: {
      codigoOrgao: 100,
      nomeOrgao: 'Vara Sintética Local',
    },
    processo: processNumber,
  };
}

function exactEnvelope(processNumber, includeNewMovement) {
  const movements = [movement(processNumber, 'initial')];
  if (includeNewMovement) movements.push(movement(processNumber, 'new'));
  return {
    hits: {
      total: { value: 1 },
      hits: [
        {
          _source: {
            numeroProcesso: processNumber,
            siglaTribunal: 'TJSP',
            dataAjuizamento: '2026-01-15T00:00:00.000Z',
            grau: 'G1',
            nivelSigilo: 0,
            formato: { codigo: '1', nome: 'Eletrônico' },
            sistema: { codigo: '2', nome: 'PJe' },
            classe: { codigo: '1106', nome: 'Procedimento Comum Cível' },
            assuntos: [{ codigo: '1234', nome: 'Direito sintético' }],
            orgaoJulgador: {
              codigo: '100',
              nome: '1ª Vara Cível Sintética',
            },
            dataHoraUltimaAtualizacao: includeNewMovement
              ? '2026-09-20T12:00:00.000Z'
              : '2026-09-20T10:00:00.000Z',
            movimentos: movements,
          },
        },
      ],
    },
  };
}

async function requestBody(request) {
  let body = '';
  for await (const chunk of request) body += chunk;
  try {
    return JSON.parse(body || '{}');
  } catch {
    return {};
  }
}

const server = createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/health') {
    json(response, 200, { status: 'ok' });
    return;
  }

  if (request.method !== 'POST' || !request.url?.startsWith('/api_publica_')) {
    json(response, 404, { error: 'fixture route not found' });
    return;
  }

  if (request.headers.authorization !== EXPECTED_AUTHORIZATION) {
    json(response, 401, { error: 'fixture authorization required' });
    return;
  }

  const body = await requestBody(request);
  const processNumber = String(
    body?.query?.match?.numeroProcesso ?? '00000000000000000000'
  ).replace(/\D/g, '');
  const scenario = scenarioFor(processNumber);
  const requestCount = (requestsByProcess.get(processNumber) ?? 0) + 1;
  requestsByProcess.set(processNumber, requestCount);

  if (scenario === 'timeout') {
    return;
  }
  if (scenario === 'not_found') {
    json(response, 200, { hits: { total: { value: 0 }, hits: [] } });
    return;
  }
  if (scenario === 'mismatch') {
    json(response, 200, exactEnvelope('00000017320238260100', false));
    return;
  }
  if (scenario === 'multiple') {
    const envelope = exactEnvelope(processNumber, false);
    envelope.hits.total.value = 2;
    envelope.hits.hits.push(envelope.hits.hits[0]);
    json(response, 200, envelope);
    return;
  }
  if (scenario === 'unauthorized') {
    json(response, 401, { error: 'fixture unauthorized' });
    return;
  }
  if (scenario === 'forbidden') {
    json(response, 403, { error: 'fixture forbidden' });
    return;
  }
  if (scenario === 'endpoint') {
    json(response, 404, { error: 'fixture endpoint not found' });
    return;
  }
  if (scenario === 'rate_limited') {
    json(
      response,
      429,
      { error: 'fixture rate limit' },
      { 'retry-after': '60' }
    );
    return;
  }
  if (scenario === 'source_unavailable') {
    json(response, 503, { error: 'fixture source unavailable' });
    return;
  }

  json(
    response,
    200,
    exactEnvelope(processNumber, scenario === 'changed' && requestCount > 1)
  );
});

server.listen(PORT, HOST, () => {
  process.stdout.write(
    `DataJud E2E fixture listening on http://${HOST}:${PORT}\n`
  );
});

function shutdown() {
  server.close(() => process.exit(0));
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

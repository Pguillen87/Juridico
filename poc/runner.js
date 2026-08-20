const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { DataJudProvider } = require('./datajud_provider');
const { validateCnj } = require('./validate_cnj');

const API_KEY = process.env.DATAJUD_API_KEY;
if (!API_KEY) {
  console.error("ERRO: DATAJUD_API_KEY ausente no ambiente. Pare a execução.");
  process.exit(1);
}

const cnjs = [
  '0004453-12.2026.8.16.0000', '0008569-61.2026.8.16.0000',
  '0002557-31.2026.8.16.0000', '0008902-13.2026.8.16.0000',
  '0003907-54.2026.8.16.0000', '0123860-46.2025.8.16.0000',
  '0152098-75.2025.8.16.0000', '0099021-54.2025.8.16.0000',
  '0143282-07.2025.8.16.0000', '0129656-18.2025.8.16.0000'
];

function compareSnapshots(oldHash, newHash) {
  if (!oldHash) return 'success_with_changes'; // Primeira vez = baseline = nova "alteração" detectada para o sistema
  return oldHash === newHash ? 'success_without_changes' : 'success_with_changes';
}

async function run() {
  const provider = new DataJudProvider(API_KEY);
  const evidenceDir = path.join(__dirname, 'evidence');
  if (!fs.existsSync(evidenceDir)) fs.mkdirSync(evidenceDir);

  const results = [];

  for (const cnj of cnjs) {
    const val = validateCnj(cnj);
    if (!val.isValid) {
      results.push({ cnj, state: 'invalid_cnj', reason: val.reason });
      continue;
    }

    const processDir = path.join(evidenceDir, val.clean);
    if (!fs.existsSync(processDir)) fs.mkdirSync(processDir);

    // Rodada 1
    console.log(`Consultando ${cnj} (Rodada 1)...`);
    const res1 = await provider.query(val.clean, val.endpointAlias);
    
    let state1 = res1.state;
    if (res1.state === 'success_without_changes') {
      state1 = compareSnapshots(null, res1.snapshotHash); // Baseline
    }

    const run1Dir = path.join(processDir, 'run-001');
    fs.mkdirSync(run1Dir, { recursive: true });
    
    if (res1.rawPayload) {
      const rawStr = JSON.stringify(res1.rawPayload, null, 2);
      fs.writeFileSync(path.join(run1Dir, 'raw.json'), rawStr);
      const rawHash = crypto.createHash('sha256').update(rawStr).digest('hex');
      fs.writeFileSync(path.join(run1Dir, 'hashes.json'), JSON.stringify({ rawHash, snapshotHash: res1.snapshotHash }, null, 2));
      fs.writeFileSync(path.join(run1Dir, 'normalized.json'), JSON.stringify(res1.normalizedData, null, 2));
    }
    fs.writeFileSync(path.join(run1Dir, 'metadata.json'), JSON.stringify({ state: state1, durationMs: res1.durationMs, error: res1.errorMessage }, null, 2));

    // Rodada 2 (imediatamente após, para testar deduplicação sem alteração real)
    console.log(`Consultando ${cnj} (Rodada 2)...`);
    const res2 = await provider.query(val.clean, val.endpointAlias);
    
    let state2 = res2.state;
    if (res2.state === 'success_without_changes' && res1.snapshotHash) {
      state2 = compareSnapshots(res1.snapshotHash, res2.snapshotHash);
    }

    const run2Dir = path.join(processDir, 'run-002');
    fs.mkdirSync(run2Dir, { recursive: true });
    if (res2.rawPayload) {
      fs.writeFileSync(path.join(run2Dir, 'raw.json'), JSON.stringify(res2.rawPayload, null, 2));
      fs.writeFileSync(path.join(run2Dir, 'normalized.json'), JSON.stringify(res2.normalizedData, null, 2));
    }
    fs.writeFileSync(path.join(run2Dir, 'metadata.json'), JSON.stringify({ state: state2, durationMs: res2.durationMs }, null, 2));

    results.push({
      cnj,
      isValid: true,
      run1_state: state1,
      run2_state: state2,
      movementsCount: res1.normalizedData ? res1.normalizedData.movements.length : 0
    });
    
    // Evitar rate limit severo
    await new Promise(r => setTimeout(r, 1000));
  }

  console.log("\n--- SIMULAÇÃO DE FIXTURE (ALTERAÇÃO CONTROLADA) ---");
  const validRes = results.find(r => r.run1_state === 'success_with_changes' && r.movementsCount > 0);
  if (validRes) {
    const cleanCnj = validRes.cnj.replace(/\D/g, '');
    const normData = JSON.parse(fs.readFileSync(path.join(evidenceDir, cleanCnj, 'run-001', 'normalized.json')));
    const oldHash = JSON.parse(fs.readFileSync(path.join(evidenceDir, cleanCnj, 'run-001', 'hashes.json'))).snapshotHash;
    
    // Adiciona movimento artificial
    normData.movements.push({
      code: 9999,
      description: "TEST_FIXTURE_ONLY - Movimentacao artificial para teste",
      date: new Date().toISOString(),
      stableHash: "artificial_hash_123"
    });
    
    const newSnapshotHashInput = JSON.stringify({
      cnj: normData.cnjNumber,
      movs: normData.movements.map(m => m.stableHash).sort()
    });
    const newSnapshotHash = crypto.createHash('sha256').update(newSnapshotHashInput).digest('hex');
    
    const simState = compareSnapshots(oldHash, newSnapshotHash);
    console.log(`Teste Fixture: Snapshot A -> Snapshot B (com movimento artificial) = ${simState}`);
  }

  console.log("\n--- RESULTADOS GERAIS ---");
  console.log(JSON.stringify(results, null, 2));
}

run().catch(console.error);

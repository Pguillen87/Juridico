const crypto = require('crypto');

/**
 * Extrai a lógica de hash determinístico e comparação
 * para garantir que o provider e os testes usem o mesmo algoritmo.
 */

function generateMovementHash(cnjNumber, movement) {
  // Ignora milissegundos voláteis
  const dateStr = movement.dataHora ? movement.dataHora.split('.')[0] : '';
  const hashInput = `${cnjNumber}_${movement.codigo || ''}_${movement.nome || movement.descricao || ''}_${dateStr}`;
  return crypto.createHash('sha256').update(hashInput).digest('hex');
}

function generateSnapshotHash(cnjNumber, movements) {
  // Deduplica movimentos idênticos no mesmo payload antes de gerar o snapshot
  const uniqueMovHashes = [...new Set(movements.map(m => m.stableHash))].sort();
  const snapshotHashInput = JSON.stringify({ cnj: cnjNumber, movs: uniqueMovHashes });
  return crypto.createHash('sha256').update(snapshotHashInput).digest('hex');
}

function compareSnapshots(oldHash, newHash) {
  // Se não há hash anterior válido, a primeira consulta bem sucedida
  // é sempre uma nova "alteração" (baseline), mesmo que tenha havido
  // timeout ou falha em rodadas anteriores.
  if (!oldHash) return 'success_with_changes';
  return oldHash === newHash ? 'success_without_changes' : 'success_with_changes';
}

module.exports = {
  generateMovementHash,
  generateSnapshotHash,
  compareSnapshots
};

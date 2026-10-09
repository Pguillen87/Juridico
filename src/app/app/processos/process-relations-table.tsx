import { formatCnj } from '@/lib/processes/cnj';
import {
  confirmProcessPartyAction,
  createProcessPartyAction,
  deactivateProcessPartyAction,
  rejectProcessPartyAction,
} from './actions';

const processRoles = [
  'client',
  'plaintiff',
  'defendant',
  'representative',
  'interested_party',
  'other',
] as const;

type ProcessSummary = {
  readonly id: string;
  readonly cnj_number: string;
  readonly status: string;
};

type PartySummary = {
  readonly id: string;
  readonly display_name: string;
};

type ProcessRelationSummary = {
  readonly id: string;
  readonly process_id: string;
  readonly party_id: string;
  readonly role_in_process: string;
  readonly confirmation_status: string;
  readonly confirmed_at: string | null;
  readonly status: string;
};

function statusLabel(status: string) {
  return status === 'active' ? 'Ativo' : 'Inativo';
}

function confirmationLabel(status: string) {
  if (status === 'confirmed') return 'Confirmado';
  if (status === 'rejected') return 'Rejeitado';
  return 'Aguardando aprovação';
}

function formatDate(value: string | null) {
  return value
    ? new Date(value).toLocaleString('pt-BR')
    : 'Ainda não disponível';
}

async function addProcessRelation(formData: FormData) {
  'use server';
  await createProcessPartyAction(formData);
}

async function confirmProcessRelation(formData: FormData) {
  'use server';
  await confirmProcessPartyAction(formData);
}

async function rejectProcessRelation(formData: FormData) {
  'use server';
  await rejectProcessPartyAction(formData);
}

async function deactivateProcessRelation(formData: FormData) {
  'use server';
  await deactivateProcessPartyAction(formData);
}

export function ProcessRelationsTable({
  processes,
  relations,
  parties,
  partyById,
  canMutate,
  canConfirm,
}: {
  readonly processes: readonly ProcessSummary[];
  readonly relations: readonly ProcessRelationSummary[];
  readonly parties: readonly PartySummary[];
  readonly partyById: ReadonlyMap<string, PartySummary>;
  readonly canMutate: boolean;
  readonly canConfirm: boolean;
}) {
  const processById = new Map(
    processes.map((process) => [process.id, process])
  );

  return (
    <section
      data-testid="process-relations-manager"
      className="overflow-hidden rounded-xl border border-slate-300 bg-white shadow-sm"
    >
      <div className="border-b border-slate-300 p-5 sm:p-6">
        <h2 className="text-lg font-semibold text-slate-950">
          Administração de partes
        </h2>
        <p className="mt-1 text-sm text-slate-600">
          Associações e aprovações ficam fora da grade de comparação para não
          misturar gestão de partes com a consulta processual.
        </p>
      </div>

      {canMutate ? (
        <form
          action={addProcessRelation}
          className="grid gap-4 border-b border-slate-300 bg-slate-50 p-5 lg:grid-cols-[minmax(220px,1.3fr)_minmax(220px,1.3fr)_160px_minmax(220px,1fr)_auto] lg:items-end"
        >
          <label className="text-sm font-medium text-slate-700">
            Processo
            <select
              name="processId"
              required
              className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
            >
              <option value="">Selecione o processo</option>
              {processes.map((process) => (
                <option key={process.id} value={process.id}>
                  {formatCnj(process.cnj_number)}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm font-medium text-slate-700">
            Parte
            <select
              name="partyId"
              required
              className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
            >
              <option value="">Selecione a parte</option>
              {parties.map((party) => (
                <option key={party.id} value={party.id}>
                  {party.display_name}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm font-medium text-slate-700">
            Papel
            <select
              name="role"
              defaultValue="plaintiff"
              className="mt-1 w-full rounded border border-slate-300 bg-white px-3 py-2"
            >
              {processRoles.map((role) => (
                <option key={role} value={role}>
                  {role}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm font-medium text-slate-700">
            Observação
            <input
              name="notes"
              maxLength={1000}
              className="mt-1 w-full rounded border border-slate-300 px-3 py-2"
            />
          </label>
          <button
            className="rounded border border-sky-300 bg-white px-3 py-2 font-semibold text-sky-800 hover:bg-sky-50"
            type="submit"
          >
            Adicionar parte para revisão
          </button>
        </form>
      ) : null}

      <div className="overflow-x-auto">
        <table className="min-w-[980px] w-full text-left text-xs text-slate-700">
          <caption className="sr-only">
            Associações de partes aos processos
          </caption>
          <thead className="bg-slate-100 text-slate-700">
            <tr>
              <th className="border-b border-r border-slate-300 px-3 py-3 font-bold uppercase tracking-wide">
                Processo
              </th>
              <th className="border-b border-r border-slate-300 px-3 py-3 font-bold uppercase tracking-wide">
                Parte
              </th>
              <th className="border-b border-r border-slate-300 px-3 py-3 font-bold uppercase tracking-wide">
                Papel
              </th>
              <th className="border-b border-r border-slate-300 px-3 py-3 font-bold uppercase tracking-wide">
                Situação
              </th>
              <th className="border-b border-r border-slate-300 px-3 py-3 font-bold uppercase tracking-wide">
                Decisão
              </th>
              <th className="border-b border-r border-slate-300 px-3 py-3 font-bold uppercase tracking-wide">
                Ações
              </th>
            </tr>
          </thead>
          <tbody>
            {relations.length === 0 ? (
              <tr>
                <td
                  colSpan={6}
                  className="px-3 py-6 text-center text-slate-500"
                >
                  Nenhuma associação de parte cadastrada.
                </td>
              </tr>
            ) : null}
            {relations.map((relation) => {
              const process = processById.get(relation.process_id);
              const party = partyById.get(relation.party_id);
              const canDeactivate = canMutate && relation.status === 'active';
              const canDecide =
                canConfirm &&
                relation.status === 'active' &&
                relation.confirmation_status === 'pending';

              return (
                <tr
                  key={relation.id}
                  data-relation-id={relation.id}
                  data-relation-process-id={relation.process_id}
                  className="align-top odd:bg-white even:bg-slate-50/70"
                >
                  <td className="border-b border-r border-slate-200 px-3 py-3 font-mono font-semibold tabular-nums text-slate-900">
                    {process
                      ? formatCnj(process.cnj_number)
                      : 'Processo não encontrado'}
                  </td>
                  <td className="border-b border-r border-slate-200 px-3 py-3 font-medium text-slate-900">
                    {party?.display_name ?? 'Parte não encontrada'}
                  </td>
                  <td className="border-b border-r border-slate-200 px-3 py-3">
                    {relation.role_in_process}
                  </td>
                  <td className="border-b border-r border-slate-200 px-3 py-3">
                    {statusLabel(relation.status)}
                  </td>
                  <td className="border-b border-r border-slate-200 px-3 py-3 whitespace-nowrap">
                    <p>{confirmationLabel(relation.confirmation_status)}</p>
                    <p className="mt-1 text-slate-500">
                      {relation.confirmed_at
                        ? formatDate(relation.confirmed_at)
                        : 'Ainda não decidida'}
                    </p>
                  </td>
                  <td className="border-b border-slate-200 px-3 py-3">
                    <div className="flex flex-wrap gap-2">
                      {canDecide ? (
                        <>
                          <form action={confirmProcessRelation}>
                            <input
                              type="hidden"
                              name="relationId"
                              value={relation.id}
                            />
                            <button
                              className="rounded bg-emerald-700 px-3 py-1.5 font-semibold text-white hover:bg-emerald-800"
                              type="submit"
                            >
                              Confirmar
                            </button>
                          </form>
                          <form action={rejectProcessRelation}>
                            <input
                              type="hidden"
                              name="relationId"
                              value={relation.id}
                            />
                            <button
                              className="rounded bg-rose-700 px-3 py-1.5 font-semibold text-white hover:bg-rose-800"
                              type="submit"
                            >
                              Rejeitar
                            </button>
                          </form>
                        </>
                      ) : null}
                      {canDeactivate ? (
                        <form action={deactivateProcessRelation}>
                          <input
                            type="hidden"
                            name="relationId"
                            value={relation.id}
                          />
                          <button
                            className="rounded border border-slate-300 px-3 py-1.5 text-slate-700 hover:bg-slate-50"
                            type="submit"
                          >
                            Desativar
                          </button>
                        </form>
                      ) : null}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}

import Link from 'next/link';
import { randomUUID } from 'node:crypto';
import { notFound } from 'next/navigation';
import { LogoutButton } from '@/components/auth/logout-button';
import {
  displayReportResult,
  displayReportStatus,
  type ReportVersionRecord,
} from '@/lib/reports/contract';
import { getReportDetail, requireReportAccess } from '@/lib/reports/server';
import {
  approveReportAction,
  cancelReportAction,
  createEditorialVersionAction,
  restoreReportVersionAction,
  returnReportToDraftAction,
  submitReportAction,
} from '../actions';
import { generateFinalPdfReportAction } from '../f13-actions';
import { ReportActionForm } from '../report-action-form';
import { F13DeliveryPanel } from '../f13-delivery-panel';

function shortId(value: string | null): string {
  return value ? value.slice(0, 8) : '—';
}

function dateTime(value: string | null): string {
  return value ? new Date(value).toLocaleString('pt-BR') : '—';
}

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function arrayValue(value: unknown): readonly Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter(objectValue) : [];
}

function textValue(value: unknown): string {
  return typeof value === 'string' ? value : '—';
}

const resultMessages: Readonly<Record<string, string>> = {
  'editorial-created':
    'Nova versão editorial criada. Os fatos técnicos permanecem congelados.',
  'editorial-restored': 'Conteúdo editorial restaurado em uma nova versão.',
  submitted: 'Relatório enviado para revisão.',
  returned: 'Relatório devolvido para edição.',
  approved:
    'Versão aprovada com hash recalculado. Aprovação não significa envio.',
  cancelled: 'Relatório cancelado. O estado é terminal nesta fase.',
};

function VersionHistory({
  versions,
  reportId,
  currentVersionId,
  canEdit,
  cancelled,
}: {
  versions: readonly ReportVersionRecord[];
  reportId: string;
  currentVersionId: string | null;
  canEdit: boolean;
  cancelled: boolean;
}) {
  return (
    <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
      <h2 className="text-lg font-semibold text-slate-950">
        Histórico de versões
      </h2>
      <p className="mt-1 text-sm text-slate-600">
        Versões anteriores são imutáveis. Restaurar copia somente conteúdo
        editorial e sempre cria uma nova versão.
      </p>
      <ol className="mt-5 space-y-4">
        {versions.map((version) => {
          const current = version.id === currentVersionId;
          const canRestore = canEdit && !cancelled && !current;
          return (
            <li
              key={version.id}
              className="rounded-lg border border-slate-200 p-4"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="font-semibold text-slate-950">
                    Versão {version.version_number}{' '}
                    {current ? (
                      <span className="text-sky-700">(atual)</span>
                    ) : null}
                  </p>
                  <p className="mt-1 text-xs text-slate-500">
                    {version.creation_kind} · {dateTime(version.created_at)} ·
                    hash {version.content_hash.slice(0, 16)}
                  </p>
                </div>
                {canRestore ? (
                  <ReportActionForm action={restoreReportVersionAction}>
                    <input type="hidden" name="reportId" value={reportId} />
                    <input
                      type="hidden"
                      name="baseVersionId"
                      value={currentVersionId ?? ''}
                    />
                    <input
                      type="hidden"
                      name="sourceVersionId"
                      value={version.id}
                    />
                    <input
                      type="hidden"
                      name="idempotencyKey"
                      value={`restore-${randomUUID()}`}
                    />
                    <button
                      type="submit"
                      className="rounded-md border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
                    >
                      Restaurar conteúdo editorial
                    </button>
                  </ReportActionForm>
                ) : null}
              </div>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

export default async function ReportDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ result?: string | string[] }>;
}) {
  const { profile } = await requireReportAccess();
  const { id } = await params;
  const query = await searchParams;
  const resultKey = Array.isArray(query.result)
    ? query.result[0]
    : query.result;
  const resultMessage = resultKey ? resultMessages[resultKey] : undefined;
  const detail = await getReportDetail(id);
  if (!detail) notFound();
  const { report, versions, processes, parties } = detail;
  const currentVersion =
    versions.find((version) => version.id === report.current_version_id) ??
    versions[0];
  const currentContent = objectValue(currentVersion?.structured_content);
  const processContent = arrayValue(currentContent.processes);
  const partyContent = arrayValue(currentContent.parties);
  const canEdit = profile.role === 'lawyer' || profile.role === 'reviewer';
  const canApprove = profile.role === 'lawyer';
  const canCancel = profile.role === 'lawyer';
  const editable =
    canEdit &&
    (report.status === 'draft' || report.status === 'awaiting_review');
  const terminal = report.status === 'cancelled';

  return (
    <main className="min-h-screen bg-slate-100">
      <nav className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex min-h-16 max-w-7xl items-center justify-between gap-4 px-4">
          <Link href="/app/relatorios" className="font-semibold text-slate-950">
            ← Relatórios semanais
          </Link>
          <div className="flex items-center gap-4">
            <Link
              href="/app"
              className="text-sm text-slate-600 hover:underline"
            >
              Área protegida
            </Link>
            <LogoutButton />
          </div>
        </div>
      </nav>

      <div className="mx-auto max-w-7xl space-y-8 px-4 py-10 sm:px-6 lg:px-8">
        {resultMessage ? (
          <p
            className="rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900"
            role="status"
          >
            {resultMessage}
          </p>
        ) : null}
        <header className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-sm font-semibold uppercase tracking-wide text-sky-700">
                Relatório semanal · cliente {shortId(report.client_id)}
              </p>
              <h1 className="mt-2 text-3xl font-bold text-slate-950">
                Período de{' '}
                {new Date(report.period_start_utc).toLocaleDateString('pt-BR')}{' '}
                a {new Date(report.period_end_utc).toLocaleDateString('pt-BR')}
              </h1>
              <p className="mt-2 text-sm text-slate-600">
                Cutoff UTC: {dateTime(report.period_end_utc)} · timezone
                persistida: {report.timezone}
              </p>
            </div>
            <span className="rounded-full bg-slate-100 px-3 py-2 text-sm font-semibold text-slate-800">
              {displayReportStatus(report.status)}
            </span>
          </div>
          {terminal ? (
            <p className="mt-5 rounded-md border border-amber-200 bg-amber-50 p-4 text-sm text-amber-950">
              Este relatório está cancelado e é terminal nesta fase. Não aceita
              edição, restauração, nova versão, nova aprovação ou segunda
              geração.
            </p>
          ) : null}
          {report.status === 'approved' ? (
            <p className="mt-5 rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-950">
              Aprovação registrada para a versão{' '}
              {shortId(report.approved_version_id)}e hash{' '}
              {report.approved_hash?.slice(0, 16)}. Aprovação não significa
              envio.
            </p>
          ) : null}
        </header>

        {report.status === 'approved' &&
        canApprove &&
        report.approved_version_id &&
        report.approved_hash ? (
          <section
            className="rounded-xl border border-emerald-200 bg-white p-6 shadow-sm"
            aria-labelledby="f13-artifact-heading"
          >
            <h2
              id="f13-artifact-heading"
              className="text-lg font-semibold text-slate-950"
            >
              Artefato PDF aprovado
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              A geração usa exclusivamente a versão aprovada persistida. O hash
              de conteúdo identifica a versão jurídica; o hash do arquivo será
              calculado após a renderização.
            </p>
            <p className="mt-3 font-mono text-xs text-slate-700">
              Versão {shortId(report.approved_version_id)} · approved hash{' '}
              {report.approved_hash.slice(0, 16)}…
            </p>
            <ReportActionForm action={generateFinalPdfReportAction}>
              <input type="hidden" name="reportId" value={report.id} />
              <input
                type="hidden"
                name="reportVersionId"
                value={report.approved_version_id}
              />
              <input
                type="hidden"
                name="approvedHash"
                value={report.approved_hash}
              />
              <button
                type="submit"
                className="mt-4 rounded-md bg-emerald-700 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-800"
              >
                Gerar PDF local
              </button>
            </ReportActionForm>
          </section>
        ) : null}

        {report.status === 'approved' &&
        canApprove &&
        report.approved_version_id &&
        report.approved_hash ? (
          <F13DeliveryPanel
            reportId={report.id}
            clientId={report.client_id}
            reportVersionId={report.approved_version_id}
          />
        ) : null}

        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <p className="text-sm text-slate-500">Versão atual</p>
            <p className="mt-1 text-xl font-semibold text-slate-950">
              {currentVersion ? `V${currentVersion.version_number}` : '—'}
            </p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <p className="text-sm text-slate-500">Processos</p>
            <p className="mt-1 text-xl font-semibold text-slate-950">
              {processContent.length}
            </p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <p className="text-sm text-slate-500">Partes</p>
            <p className="mt-1 text-xl font-semibold text-slate-950">
              {partyContent.length}
            </p>
          </div>
          <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
            <p className="text-sm text-slate-500">Evidência vazia</p>
            <p className="mt-1 text-xl font-semibold text-slate-950">
              {currentContent.empty_explanation ? 'Sim' : 'Não'}
            </p>
          </div>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">
            Ações do fluxo
          </h2>
          <p className="mt-1 text-sm text-slate-600">
            Cada ação é revalidada no banco. A aprovação recalcula o hash da
            versão persistida e sempre aponta para uma versão exata.
          </p>
          <div className="mt-5 flex flex-wrap gap-3">
            {editable && currentVersion ? (
              <ReportActionForm action={submitReportAction}>
                <input type="hidden" name="reportId" value={report.id} />
                <input
                  type="hidden"
                  name="versionId"
                  value={currentVersion.id}
                />
                <input
                  type="hidden"
                  name="idempotencyKey"
                  value={`submit-${randomUUID()}`}
                />
                <button
                  type="submit"
                  className="rounded-md bg-sky-700 px-4 py-2 font-semibold text-white hover:bg-sky-800"
                >
                  Submeter para revisão
                </button>
              </ReportActionForm>
            ) : null}
            {report.status === 'awaiting_review' &&
            canEdit &&
            currentVersion ? (
              <ReportActionForm action={returnReportToDraftAction}>
                <input type="hidden" name="reportId" value={report.id} />
                <input
                  type="hidden"
                  name="versionId"
                  value={currentVersion.id}
                />
                <input
                  type="hidden"
                  name="idempotencyKey"
                  value={`return-${randomUUID()}`}
                />
                <button
                  type="submit"
                  className="rounded-md border border-slate-300 px-4 py-2 font-semibold text-slate-700 hover:bg-slate-50"
                >
                  Devolver para edição
                </button>
              </ReportActionForm>
            ) : null}
            {report.status === 'awaiting_review' &&
            canApprove &&
            currentVersion ? (
              <ReportActionForm action={approveReportAction}>
                <input type="hidden" name="reportId" value={report.id} />
                <input
                  type="hidden"
                  name="versionId"
                  value={currentVersion.id}
                />
                <input
                  type="hidden"
                  name="idempotencyKey"
                  value={`approve-${randomUUID()}`}
                />
                <button
                  type="submit"
                  className="rounded-md bg-emerald-700 px-4 py-2 font-semibold text-white hover:bg-emerald-800"
                >
                  Aprovar esta versão
                </button>
              </ReportActionForm>
            ) : null}
            {canCancel && !terminal ? (
              <ReportActionForm
                action={cancelReportAction}
                className="flex flex-wrap items-center gap-2"
              >
                <input type="hidden" name="reportId" value={report.id} />
                <input
                  type="hidden"
                  name="versionId"
                  value={currentVersion?.id ?? ''}
                />
                <input
                  type="hidden"
                  name="idempotencyKey"
                  value={`cancel-${randomUUID()}`}
                />
                <label className="sr-only" htmlFor="cancel-reason">
                  Motivo do cancelamento
                </label>
                <select
                  id="cancel-reason"
                  name="reasonCode"
                  defaultValue="incorrect_content"
                  className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
                >
                  <option value="incorrect_content">Conteúdo incorreto</option>
                  <option value="duplicate">Duplicado</option>
                  <option value="no_longer_required">
                    Não é mais necessário
                  </option>
                  <option value="other">Outro</option>
                </select>
                <button
                  type="submit"
                  className="rounded-md border border-rose-300 px-4 py-2 font-semibold text-rose-800 hover:bg-rose-50"
                >
                  Cancelar relatório
                </button>
              </ReportActionForm>
            ) : null}
          </div>
          {profile.role === 'reviewer' ? (
            <p className="mt-4 text-sm text-slate-600">
              Seu papel permite editar e revisar, mas não aprovar nem cancelar.
            </p>
          ) : null}
        </section>

        {editable && currentVersion ? (
          <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            <h2 className="text-lg font-semibold text-slate-950">
              Editar conteúdo editorial
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              Somente campos editoriais são aceitos. Fatos, fontes, timestamps,
              resultados e evidências não podem ser alterados.
            </p>
            <ReportActionForm
              action={createEditorialVersionAction}
              className="mt-5 grid gap-4"
            >
              <input type="hidden" name="reportId" value={report.id} />
              <input
                type="hidden"
                name="baseVersionId"
                value={currentVersion.id}
              />
              <input
                type="hidden"
                name="idempotencyKey"
                value={`edit-${randomUUID()}`}
              />
              <label className="text-sm font-medium text-slate-700">
                Título editorial
                <input
                  name="title"
                  maxLength={240}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="text-sm font-medium text-slate-700">
                Observação geral
                <textarea
                  name="summaryNote"
                  maxLength={2000}
                  rows={4}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="text-sm font-medium text-slate-700">
                Encerramento editorial
                <textarea
                  name="closingNote"
                  maxLength={2000}
                  rows={3}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
              <div>
                <button
                  type="submit"
                  className="rounded-md bg-slate-900 px-4 py-2 font-semibold text-white hover:bg-slate-800"
                >
                  Criar nova versão editorial
                </button>
              </div>
            </ReportActionForm>
          </section>
        ) : null}

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">Por processo</h2>
          <p className="mt-1 text-sm text-slate-600">
            Os estados abaixo são derivados da comparação e das falhas
            persistidas; uma falha nunca é exibida como ausência de alteração.
          </p>
          <div className="mt-5 space-y-5">
            {processContent.length === 0 ? (
              <p className="rounded-md bg-slate-50 p-4 text-sm text-slate-600">
                {textValue(currentContent.empty_explanation)}
              </p>
            ) : null}
            {processContent.map((process) => {
              const changed = arrayValue(process.changed);
              const unchanged = arrayValue(process.unchanged);
              const incomparable = arrayValue(process.not_comparable);
              const failures = arrayValue(process.failures);
              return (
                <article
                  key={textValue(process.process_id)}
                  className="rounded-lg border border-slate-200 p-5"
                >
                  <h3 className="font-semibold text-slate-950">
                    Processo {shortId(textValue(process.process_id))} ·{' '}
                    {textValue(process.tribunal)}
                  </h3>
                  <p className="mt-1 text-sm text-slate-600">
                    Última consulta válida até o cutoff:{' '}
                    {dateTime(
                      typeof process.last_valid_query_at === 'string'
                        ? process.last_valid_query_at
                        : null
                    )}
                  </p>
                  <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    {[
                      ['changed', changed.length],
                      ['unchanged', unchanged.length],
                      ['not_comparable', incomparable.length],
                      ['failure', failures.length],
                    ].map(([kind, count]) => (
                      <div key={kind} className="rounded-md bg-slate-50 p-3">
                        <p className="text-xs uppercase tracking-wide text-slate-500">
                          {displayReportResult(String(kind))}
                        </p>
                        <p className="mt-1 text-xl font-semibold text-slate-950">
                          {count}
                        </p>
                      </div>
                    ))}
                  </div>
                  {failures.length > 0 ? (
                    <p className="mt-4 rounded-md border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">
                      Há falhas persistidas neste período; elas não foram
                      convertidas em “sem alteração”.
                    </p>
                  ) : null}
                  {Boolean(process.manual_review_required) ? (
                    <p className="mt-4 rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-950">
                      Relação histórica de parte exige revisão manual; nenhuma
                      identidade foi confirmada por semelhança de nome.
                    </p>
                  ) : null}
                </article>
              );
            })}
          </div>
        </section>

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">Por parte</h2>
          <div className="mt-5 grid gap-4 md:grid-cols-2">
            {partyContent.length === 0 ? (
              <p className="text-sm text-slate-600">
                Nenhuma parte elegível foi congelada nesta versão.
              </p>
            ) : null}
            {partyContent.map((party) => (
              <article
                key={textValue(party.party_id)}
                className="rounded-lg border border-slate-200 p-4"
              >
                <h3 className="font-semibold text-slate-950">
                  {textValue(party.display_name)}
                </h3>
                <p className="mt-1 text-sm text-slate-600">
                  Tipo: {textValue(party.party_type)} · estado:{' '}
                  {textValue(party.relationship_state)}
                </p>
                {Boolean(party.manual_review_required) ? (
                  <p className="mt-3 text-sm font-medium text-amber-900">
                    Revisão manual necessária.
                  </p>
                ) : null}
              </article>
            ))}
          </div>
        </section>

        <VersionHistory
          versions={versions}
          reportId={report.id}
          currentVersionId={report.current_version_id}
          canEdit={canEdit}
          cancelled={terminal}
        />

        <section className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-semibold text-slate-950">
            Limites desta fase
          </h2>
          <p className="mt-2 text-sm text-slate-600">
            Esta tela não gera PDF, não cria arquivo final, não envia relatório,
            não possui destinatário externo e não alcança o estado{' '}
            <code>sent</code>. A Fase 13 cobre apenas operações locais e
            simuladas; nenhum envio real é executado.
          </p>
          <p className="mt-2 text-xs text-slate-500">
            Fonte da versão: {shortId(currentVersion?.id ?? null)} · projeções
            carregadas: {processes.length + parties.length}
          </p>
        </section>
      </div>
    </main>
  );
}

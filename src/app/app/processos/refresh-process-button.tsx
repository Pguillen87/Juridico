'use client';

import { useActionState } from 'react';
import { requestProcessRefreshAction } from './actions';

type RefreshActionState = Awaited<
  ReturnType<typeof requestProcessRefreshAction>
> | null;

export function RefreshProcessButton({
  processId,
  compact = false,
}: {
  readonly processId: string;
  readonly compact?: boolean;
}) {
  const [state, submit, pending] = useActionState(
    async (_previous: RefreshActionState, formData: FormData) =>
      requestProcessRefreshAction(formData),
    null
  );

  return (
    <form action={submit} className="space-y-1">
      <input type="hidden" name="processId" value={processId} />
      <button
        type="submit"
        disabled={pending}
        className={
          compact
            ? 'rounded-md border border-sky-300 px-3 py-1.5 text-xs font-semibold text-sky-800 hover:bg-sky-50 disabled:cursor-not-allowed disabled:opacity-60'
            : 'rounded-md bg-sky-700 px-3 py-2 text-sm font-semibold text-white hover:bg-sky-800 disabled:cursor-not-allowed disabled:opacity-60'
        }
      >
        {pending ? 'Atualizando…' : 'Atualizar agora'}
      </button>
      {pending ? (
        <p className="text-xs text-slate-500" aria-live="polite">
          Atualizando processo…
        </p>
      ) : null}
      {state && 'error' in state && state.error ? (
        <p className="text-xs text-rose-800" role="alert">
          {state.error}
        </p>
      ) : null}
      {state && 'success' in state && state.success ? (
        <p className="text-xs text-emerald-800" role="status">
          Atualização concluída.
        </p>
      ) : null}
    </form>
  );
}

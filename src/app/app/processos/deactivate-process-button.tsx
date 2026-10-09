'use client';

import { useActionState, type FormEvent } from 'react';
import { deactivateProcessAction } from './actions';

type DeactivateActionState = Awaited<
  ReturnType<typeof deactivateProcessAction>
> | null;

export function DeactivateProcessButton({
  processId,
  compact = false,
}: {
  readonly processId: string;
  readonly compact?: boolean;
}) {
  const [state, submit, pending] = useActionState(
    async (_previous: DeactivateActionState, formData: FormData) =>
      deactivateProcessAction(formData),
    null
  );

  function confirmDeactivation(event: FormEvent<HTMLFormElement>) {
    if (
      !window.confirm(
        'Excluir este processo da carteira? O histórico de auditoria será preservado.'
      )
    ) {
      event.preventDefault();
    }
  }

  return (
    <form action={submit} onSubmit={confirmDeactivation} className="space-y-1">
      <input type="hidden" name="processId" value={processId} />
      <button
        type="submit"
        disabled={pending}
        className={
          compact
            ? 'rounded-md border border-rose-300 px-3 py-1.5 text-xs font-semibold text-rose-800 hover:bg-rose-50 disabled:cursor-not-allowed disabled:opacity-60'
            : 'rounded-md bg-rose-700 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-800 disabled:cursor-not-allowed disabled:opacity-60'
        }
      >
        {pending ? 'Excluindo…' : 'Excluir processo'}
      </button>
      {state && 'error' in state && state.error ? (
        <p className="text-xs text-rose-800" role="alert">
          {state.error}
        </p>
      ) : null}
      {state && 'success' in state && state.success ? (
        <p className="text-xs text-emerald-800" role="status">
          Processo excluído da carteira.
        </p>
      ) : null}
    </form>
  );
}

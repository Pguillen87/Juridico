'use client';

import { useActionState, type ReactNode } from 'react';
import type { ReportActionState } from './actions';

type ReportAction = (
  previousState: ReportActionState | null,
  formData: FormData
) => Promise<ReportActionState>;

export function ReportActionForm({
  action,
  children,
  className,
}: {
  readonly action: ReportAction;
  readonly children: ReactNode;
  readonly className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, null);

  return (
    <form action={formAction} className={className}>
      {children}
      {pending ? (
        <p className="mt-2 text-xs text-slate-500" aria-live="polite">
          Processando…
        </p>
      ) : null}
      {state?.error ? (
        <p className="mt-2 text-sm text-rose-800" role="alert">
          {state.error}
        </p>
      ) : null}
      {state?.success && state.message ? (
        <p className="mt-2 text-sm text-emerald-800" role="status">
          {state.message}
        </p>
      ) : null}
    </form>
  );
}

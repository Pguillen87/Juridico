'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  requestClientPortfolioRefreshAction,
  getClientPortfolioRefreshProgressAction,
  runClientPortfolioRefreshBatchAction,
  type PortfolioBatchRunActionResult,
  type PortfolioRefreshActionResult,
  type PortfolioProgressActionResult,
} from '../processos/actions';
import type { ClientPortfolioRefreshProgress } from '@/lib/clients/portfolio';

type RefreshState =
  | PortfolioRefreshActionResult
  | PortfolioProgressActionResult
  | PortfolioBatchRunActionResult
  | null;

function progressMessage(progress: ClientPortfolioRefreshProgress) {
  if (progress.state === 'completed_with_issues') {
    return `Atualização concluída com ${progress.failureCount + progress.reviewCount} processo(s) que precisam de atenção.`;
  }
  if (progress.state === 'completed') {
    return `Carteira atualizada: ${progress.noveltyCount} com novidade e ${progress.unchangedCount} sem novidade.`;
  }
  return `Atualização em andamento: ${progress.completedCount} de ${progress.eligibleCount} processo(s).`;
}

export function RefreshClientPortfolioButton({
  clientId,
  buttonLabel = 'Atualizar carteira',
}: {
  readonly clientId: string;
  readonly buttonLabel?: string;
}) {
  const router = useRouter();
  const [state, setState] = useState<RefreshState>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    if (!pending) return;
    let active = true;
    const poll = async () => {
      const result = await getClientPortfolioRefreshProgressAction(clientId);
      if (active && result.success && result.progress) setState(result);
    };
    void poll();
    const timer = window.setInterval(() => void poll(), 1000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [clientId, pending]);

  async function handleRefresh() {
    setPending(true);
    setState(null);
    try {
      const request = new FormData();
      request.set('clientId', clientId);
      const queued = await requestClientPortfolioRefreshAction(request);
      setState(queued);
      if (!queued.success) return;

      const result = await runClientPortfolioRefreshBatchAction(clientId);
      setState(result);
      router.refresh();
    } finally {
      setPending(false);
    }
  }

  const progress =
    state && 'progress' in state && state.success ? state.progress : null;
  const error = state && !state.success ? state.message : null;

  return (
    <div className="space-y-2">
      <button
        type="button"
        onClick={handleRefresh}
        disabled={pending}
        className="rounded-md bg-sky-700 px-3 py-2 text-sm font-semibold text-white hover:bg-sky-800 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {pending ? 'Atualizando carteira…' : buttonLabel}
      </button>
      {state &&
      'eligibleCount' in state &&
      state.success &&
      state.skippedCount > 0 ? (
        <p className="text-xs text-slate-600" role="status">
          {state.skippedCount} processo(s) não entram na atualização automática.
        </p>
      ) : null}
      {progress ? (
        <p className="text-xs text-slate-700" role="status" aria-live="polite">
          {progressMessage(progress)}
        </p>
      ) : null}
      {error ? (
        <p className="text-xs text-rose-800" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}

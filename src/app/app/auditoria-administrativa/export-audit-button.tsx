'use client';

import { useState, useTransition } from 'react';
import { exportAdministrativeAuditAction } from './actions';

export function ExportAuditButton() {
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState('');
  const [isError, setIsError] = useState(false);

  function exportAudit() {
    if (!window.confirm('Confirma a exportação da auditoria administrativa?'))
      return;

    setMessage('Preparando arquivo…');
    setIsError(false);
    startTransition(async () => {
      const result = await exportAdministrativeAuditAction();
      if (!result.success || !result.csv) {
        setIsError(true);
        setMessage(result.error ?? 'Não foi possível exportar.');
        return;
      }

      const blob = new Blob([result.csv], { type: 'text/csv;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'auditoria-administrativa.csv';
      link.click();
      URL.revokeObjectURL(url);
      setMessage('Arquivo exportado.');
    });
  }

  return (
    <div>
      <button
        className="rounded-md bg-slate-900 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:bg-slate-400"
        disabled={pending}
        onClick={exportAudit}
        type="button"
      >
        {pending ? 'Exportando…' : 'Exportar CSV'}
      </button>
      <p
        aria-live="polite"
        className={`mt-2 text-sm ${isError ? 'text-red-700' : 'text-slate-600'}`}
        role={isError ? 'alert' : 'status'}
      >
        {message}
      </p>
    </div>
  );
}

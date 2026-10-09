'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { requestSelectedProcessesRefreshAction } from './actions';
import {
  buildProcessExportCsv,
  PROCESS_EXPORT_COLUMN_KEYS,
  type ProcessExportRow,
} from './processes-export-model';
import {
  PORTFOLIO_COLUMNS_CHANGED_EVENT,
  PortfolioColumnVisibility,
} from './portfolio-column-visibility-control';
import {
  PORTFOLIO_SPREADSHEET_COLUMNS,
  type PortfolioSpreadsheetColumn,
} from './processes-spreadsheet-model';

const PROCESS_SELECTION_SELECTOR = 'input[data-process-selection]';

function selectedProcessKeys() {
  return Array.from(
    document.querySelectorAll<HTMLInputElement>(
      `${PROCESS_SELECTION_SELECTOR}:checked`
    )
  ).flatMap((input) => {
    const key = input.dataset.processSelection;
    return key ? [key] : [];
  });
}

function selectedProcessIds() {
  return Array.from(
    document.querySelectorAll<HTMLInputElement>(
      `${PROCESS_SELECTION_SELECTOR}:checked`
    )
  ).flatMap((input) => {
    const id = input.dataset.processId;
    return id ? [id] : [];
  });
}

function allProcessSelectionInputs() {
  return Array.from(
    document.querySelectorAll<HTMLInputElement>(PROCESS_SELECTION_SELECTOR)
  );
}

function selectedColumnKeys() {
  const selected = Array.from(
    document.querySelectorAll<HTMLInputElement>(
      '[data-portfolio-column-toggle]:checked'
    )
  ).flatMap((input) => {
    const key = input.dataset.portfolioColumnToggle;
    return key ? [key] : [];
  });
  const visible = new Set(selected);
  const exportable = new Set<string>(PROCESS_EXPORT_COLUMN_KEYS);
  return PORTFOLIO_SPREADSHEET_COLUMNS.filter(
    (column) => visible.has(column.key) && exportable.has(column.key)
  ).map((column) => column.key);
}

function downloadSpreadsheet(
  rows: readonly ProcessExportRow[],
  visibleColumnKeys: readonly string[]
) {
  const blob = new Blob([buildProcessExportCsv(rows, visibleColumnKeys)], {
    type: 'text/csv;charset=utf-8',
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `carteira-processos-${new Date().toISOString().slice(0, 10)}.csv`;
  anchor.click();
  URL.revokeObjectURL(url);
}

export function ProcessExportControls({
  rows,
  columns,
}: {
  readonly rows: readonly ProcessExportRow[];
  readonly columns: readonly PortfolioSpreadsheetColumn[];
}) {
  const router = useRouter();
  const [selectedCount, setSelectedCount] = useState(0);
  const [message, setMessage] = useState<string | null>(null);
  const [refreshingSelected, setRefreshingSelected] = useState(false);
  const [visibleColumnKeys, setVisibleColumnKeys] = useState<string[]>([
    ...PROCESS_EXPORT_COLUMN_KEYS,
  ]);

  useEffect(() => {
    const updateCount = () => setSelectedCount(selectedProcessKeys().length);
    document.addEventListener('change', updateCount);
    updateCount();
    const updateColumns = () => setVisibleColumnKeys(selectedColumnKeys());
    window.addEventListener(PORTFOLIO_COLUMNS_CHANGED_EVENT, updateColumns);
    updateColumns();
    return () => {
      document.removeEventListener('change', updateCount);
      window.removeEventListener(
        PORTFOLIO_COLUMNS_CHANGED_EVENT,
        updateColumns
      );
    };
  }, []);

  function setAllSelected(checked: boolean) {
    allProcessSelectionInputs().forEach((input) => {
      input.checked = checked;
    });
    setSelectedCount(checked ? allProcessSelectionInputs().length : 0);
    setMessage(null);
  }

  function exportSelected() {
    const selected = new Set(selectedProcessKeys());
    const selectedRows = rows.filter((row) => selected.has(row.selectionKey));
    if (selectedRows.length === 0) {
      setMessage('Selecione pelo menos um processo para exportar.');
      return;
    }
    downloadSpreadsheet(selectedRows, visibleColumnKeys);
    setMessage(
      `${selectedRows.length} processo(s) exportado(s) para Excel (CSV).`
    );
  }

  async function refreshSelected() {
    const processIds = selectedProcessIds();
    if (processIds.length === 0) {
      setMessage('Selecione pelo menos um processo para atualizar.');
      return;
    }

    setRefreshingSelected(true);
    setMessage(null);
    try {
      const request = new FormData();
      processIds.forEach((processId) => request.append('processId', processId));
      const result = await requestSelectedProcessesRefreshAction(request);
      if (!result.success) {
        setMessage(result.message);
        return;
      }
      const issueMessage =
        result.failedCount > 0
          ? ` ${result.failedCount} processo(s) não puderam ser atualizado(s).`
          : '';
      setMessage(
        `${result.completedCount} processo(s) atualizado(s).${issueMessage}`
      );
      router.refresh();
    } finally {
      setRefreshingSelected(false);
    }
  }

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-300 bg-slate-50 px-4 py-3">
      <div>
        <p className="text-sm font-semibold text-slate-800">
          Seleção da carteira
        </p>
        <p className="text-xs text-slate-600" aria-live="polite">
          {selectedCount} processo(s) selecionado(s)
        </p>
        <p className="text-xs text-slate-500">
          O arquivo CSV abre diretamente no Excel.
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <PortfolioColumnVisibility columns={columns} />
        <button
          type="button"
          onClick={() => setAllSelected(true)}
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-100"
        >
          Selecionar todos
        </button>
        <button
          type="button"
          onClick={() => setAllSelected(false)}
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-100"
        >
          Limpar seleção
        </button>
        <button
          type="button"
          onClick={refreshSelected}
          disabled={selectedCount === 0 || refreshingSelected}
          className="rounded-md bg-sky-700 px-3 py-2 text-xs font-semibold text-white hover:bg-sky-800 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {refreshingSelected
            ? 'Atualizando selecionados…'
            : 'Atualizar selecionados'}
        </button>
        <button
          type="button"
          onClick={exportSelected}
          disabled={selectedCount === 0}
          className="rounded-md bg-emerald-700 px-3 py-2 text-xs font-semibold text-white hover:bg-emerald-800 disabled:cursor-not-allowed disabled:opacity-50"
        >
          Exportar para Excel
        </button>
      </div>
      {message ? (
        <p className="basis-full text-xs text-slate-600" role="status">
          {message}
        </p>
      ) : null}
    </div>
  );
}

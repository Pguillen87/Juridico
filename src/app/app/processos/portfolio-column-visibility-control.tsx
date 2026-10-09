'use client';

import { useEffect, useMemo, useSyncExternalStore } from 'react';
import {
  parseStoredPortfolioColumnKeys,
  PORTFOLIO_COLUMN_VISIBILITY_STORAGE_KEY,
  serializePortfolioColumnKeys,
} from './portfolio-column-visibility';
import {
  PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS,
  type PortfolioSpreadsheetColumn,
} from './processes-spreadsheet-model';

export const PORTFOLIO_COLUMNS_CHANGED_EVENT = 'portfolio-columns-change';

function subscribeToColumnVisibility(callback: () => void) {
  const handleChange = () => callback();
  window.addEventListener(PORTFOLIO_COLUMNS_CHANGED_EVENT, handleChange);
  window.addEventListener('storage', handleChange);
  return () => {
    window.removeEventListener(PORTFOLIO_COLUMNS_CHANGED_EVENT, handleChange);
    window.removeEventListener('storage', handleChange);
  };
}

function getStoredColumnVisibility() {
  return window.localStorage.getItem(PORTFOLIO_COLUMN_VISIBILITY_STORAGE_KEY);
}

function getServerColumnVisibility() {
  return null;
}

function applyColumnVisibility(keys: readonly string[]) {
  const visible = new Set(keys);
  document
    .querySelectorAll<HTMLElement>('[data-portfolio-column]')
    .forEach((element) => {
      const key = element.dataset.portfolioColumn;
      if (key) element.hidden = !visible.has(key);
    });
  window.dispatchEvent(
    new CustomEvent(PORTFOLIO_COLUMNS_CHANGED_EVENT, {
      detail: { keys: [...keys] },
    })
  );
}

export function PortfolioColumnVisibility({
  columns,
}: {
  readonly columns: readonly PortfolioSpreadsheetColumn[];
}) {
  const allowedKeys = useMemo(
    () => columns.map((column) => column.key),
    [columns]
  );
  const optionalColumns = columns.filter(
    (column) => column.key !== 'select' && column.key !== 'actions'
  );
  const storedVisibility = useSyncExternalStore(
    subscribeToColumnVisibility,
    getStoredColumnVisibility,
    getServerColumnVisibility
  );
  const visibleKeys = useMemo(
    () =>
      parseStoredPortfolioColumnKeys(
        storedVisibility,
        allowedKeys,
        PORTFOLIO_DEFAULT_VISIBLE_COLUMN_KEYS
      ),
    [allowedKeys, storedVisibility]
  );

  useEffect(() => {
    applyColumnVisibility(visibleKeys);
  }, [visibleKeys]);

  function toggleColumn(key: string, checked: boolean) {
    const nextKeys = checked
      ? [...visibleKeys, key]
      : visibleKeys.filter((visibleKey) => visibleKey !== key);
    const orderedKeys = allowedKeys.filter((allowedKey) =>
      nextKeys.includes(allowedKey)
    );
    window.localStorage.setItem(
      PORTFOLIO_COLUMN_VISIBILITY_STORAGE_KEY,
      serializePortfolioColumnKeys(orderedKeys)
    );
    applyColumnVisibility(orderedKeys);
  }

  return (
    <details className="relative">
      <summary className="cursor-pointer list-none rounded-md border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-700 hover:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-500">
        Colunas
      </summary>
      <div className="absolute right-0 z-30 mt-2 w-64 rounded-lg border border-slate-200 bg-white p-3 shadow-lg">
        <p className="text-xs font-semibold text-slate-800">
          Mostrar ou ocultar colunas
        </p>
        <div className="mt-2 space-y-2">
          {optionalColumns.map((column) => (
            <label
              key={column.key}
              className="flex items-center gap-2 text-xs text-slate-700"
            >
              <input
                type="checkbox"
                data-portfolio-column-toggle={column.key}
                checked={visibleKeys.includes(column.key)}
                onChange={(event) =>
                  toggleColumn(column.key, event.currentTarget.checked)
                }
                className="h-4 w-4 rounded border-slate-300 text-sky-700 focus:ring-sky-600"
              />
              {column.label}
            </label>
          ))}
        </div>
      </div>
    </details>
  );
}

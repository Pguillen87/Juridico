'use client';

import { useEffect, useRef, useState, type ReactNode } from 'react';

export function ProcessesSpreadsheetScroll({
  children,
}: {
  readonly children: ReactNode;
}) {
  const topScrollRef = useRef<HTMLDivElement>(null);
  const tableScrollRef = useRef<HTMLDivElement>(null);
  const syncingRef = useRef(false);
  const [contentWidth, setContentWidth] = useState(0);

  useEffect(() => {
    const viewport = tableScrollRef.current;
    if (!viewport) return;

    const updateWidth = () => setContentWidth(viewport.scrollWidth);
    updateWidth();
    const observer = new ResizeObserver(updateWidth);
    observer.observe(viewport);
    return () => observer.disconnect();
  }, []);

  function syncScroll(source: HTMLDivElement, target: HTMLDivElement | null) {
    if (!target || syncingRef.current) return;
    syncingRef.current = true;
    target.scrollLeft = source.scrollLeft;
    window.requestAnimationFrame(() => {
      syncingRef.current = false;
    });
  }

  return (
    <div className="space-y-1">
      <div
        ref={topScrollRef}
        data-testid="processes-spreadsheet-top-scroll"
        className="overflow-x-scroll overflow-y-hidden rounded border border-slate-300 bg-slate-100 focus:outline-none focus:ring-2 focus:ring-sky-500"
        role="region"
        aria-label="Rolagem horizontal da carteira"
        tabIndex={0}
        onScroll={(event) =>
          syncScroll(event.currentTarget, tableScrollRef.current)
        }
        style={{ scrollbarGutter: 'stable' }}
      >
        <div
          aria-hidden="true"
          className="h-3"
          style={{ width: contentWidth || '100%' }}
        />
      </div>
      <div
        ref={tableScrollRef}
        data-testid="processes-spreadsheet-viewport"
        className="max-h-[min(68vh,760px)] overflow-x-scroll overflow-y-scroll rounded border border-slate-300 bg-white focus-within:ring-2 focus-within:ring-sky-500"
        role="region"
        aria-label="Tabela da carteira de processos"
        onScroll={(event) =>
          syncScroll(event.currentTarget, topScrollRef.current)
        }
        style={{
          scrollbarColor: 'rgb(71 85 105) rgb(226 232 240)',
          scrollbarGutter: 'stable both-edges',
        }}
      >
        {children}
      </div>
    </div>
  );
}

export default function ReportsLoading() {
  return (
    <main
      className="min-h-screen bg-slate-100 p-6"
      aria-busy="true"
      aria-live="polite"
    >
      <div className="mx-auto max-w-7xl rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
        <p className="text-sm text-slate-600">
          Carregando relatórios semanais…
        </p>
      </div>
    </main>
  );
}

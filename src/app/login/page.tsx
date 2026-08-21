import { Suspense } from 'react';
import { LoginForm } from '@/components/auth/login-form';

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <section className="w-full max-w-md rounded-xl border border-slate-200 bg-white p-8 shadow-sm">
        <div className="mb-8">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-700">
            Juridico
          </p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight text-slate-950">
            Acesso seguro ao escritório
          </h1>
          <p className="mt-2 text-sm leading-6 text-slate-600">
            Entre com suas credenciais para acompanhar a operação jurídica.
          </p>
        </div>
        <Suspense
          fallback={<p className="text-sm text-slate-500">Carregando…</p>}
        >
          <LoginForm />
        </Suspense>
      </section>
    </main>
  );
}

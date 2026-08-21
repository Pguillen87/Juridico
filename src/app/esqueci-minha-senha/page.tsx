'use client';

import { useState, type FormEvent } from 'react';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import { recoverySchema } from '@/lib/auth/validation';

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    const parsed = recoverySchema.safeParse({ email });
    if (!parsed.success) {
      setError(
        parsed.error.issues[0]?.message ?? 'Confira o e-mail informado.'
      );
      return;
    }

    setLoading(true);
    const redirectTo = `${window.location.origin}/auth/callback?next=/redefinir-senha`;
    const { error: recoveryError } =
      await createClient().auth.resetPasswordForEmail(parsed.data.email, {
        redirectTo,
      });

    if (recoveryError) {
      setError(
        'Não foi possível iniciar a recuperação agora. Tente novamente.'
      );
      setLoading(false);
      return;
    }

    setSent(true);
    setLoading(false);
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <section className="w-full max-w-md rounded-xl border border-slate-200 bg-white p-8 shadow-sm">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-700">
          Juridico
        </p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-slate-950">
          Recuperar senha
        </h1>
        <p className="mt-2 text-sm leading-6 text-slate-600">
          Informe seu e-mail e enviaremos as instruções, caso exista uma conta
          correspondente.
        </p>

        {sent ? (
          <div
            className="mt-8 rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm leading-6 text-emerald-800"
            role="status"
          >
            Se existir uma conta para este e-mail, enviaremos as instruções de
            recuperação.
          </div>
        ) : (
          <form className="mt-8 space-y-5" onSubmit={handleSubmit} noValidate>
            {error ? (
              <p
                className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700"
                role="alert"
              >
                {error}
              </p>
            ) : null}
            <div>
              <label
                className="block text-sm font-medium text-slate-700"
                htmlFor="email"
              >
                E-mail
              </label>
              <input
                autoComplete="email"
                className="mt-2 block w-full rounded-md border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100"
                id="email"
                name="email"
                onChange={(event) => setEmail(event.target.value)}
                required
                type="email"
                value={email}
              />
            </div>
            <button
              className="flex w-full items-center justify-center rounded-md bg-sky-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-800 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:bg-slate-400"
              disabled={loading}
              type="submit"
            >
              {loading ? 'Enviando…' : 'Enviar instruções'}
            </button>
          </form>
        )}

        <Link
          className="mt-6 inline-flex text-sm font-medium text-sky-700 hover:text-sky-900"
          href="/login"
        >
          Voltar para o login
        </Link>
      </section>
    </main>
  );
}

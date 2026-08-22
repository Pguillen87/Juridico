'use client';

import { useEffect, useState, type FormEvent } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { resetPasswordSchema } from '@/lib/auth/validation';

export default function ResetPasswordPage() {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    let mounted = true;

    void supabase.auth.getUser().then(({ data, error: userError }) => {
      if (!mounted) return;
      if (userError || !data.user) {
        setError(
          'Este link de recuperação é inválido ou expirou. Solicite um novo link.'
        );
      }
      setReady(true);
    });

    return () => {
      mounted = false;
    };
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    const parsed = resetPasswordSchema.safeParse({ password, confirmation });
    if (!parsed.success) {
      setError(
        parsed.error.issues[0]?.message ?? 'Confira os dados informados.'
      );
      return;
    }

    setLoading(true);
    const { error: updateError } = await createClient().auth.updateUser({
      password: parsed.data.password,
    });

    if (updateError) {
      setError(`Erro no Supabase ao atualizar senha: ${updateError.message}`);
      setLoading(false);
      return;
    }

    await createClient().auth.signOut();
    setSuccess(true);
    setLoading(false);
    window.setTimeout(
      () => router.replace('/login?success=password-reset'),
      900
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-12">
      <section className="w-full max-w-md rounded-xl border border-slate-200 bg-white p-8 shadow-sm">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-sky-700">
          Juridico
        </p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-slate-950">
          Definir nova senha
        </h1>
        <p className="mt-2 text-sm leading-6 text-slate-600">
          Escolha uma senha nova para voltar a acessar sua conta.
        </p>

        {success ? (
          <div
            className="mt-8 rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800"
            role="status"
          >
            Senha atualizada. Redirecionando para o login…
          </div>
        ) : !ready ? (
          <p className="mt-8 text-sm text-slate-500">Validando o link…</p>
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
                htmlFor="password"
              >
                Nova senha
              </label>
              <input
                autoComplete="new-password"
                className="mt-2 block w-full rounded-md border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100"
                id="password"
                minLength={10}
                onChange={(event) => setPassword(event.target.value)}
                required
                type="password"
                value={password}
              />
            </div>
            <div>
              <label
                className="block text-sm font-medium text-slate-700"
                htmlFor="confirmation"
              >
                Confirmar nova senha
              </label>
              <input
                autoComplete="new-password"
                className="mt-2 block w-full rounded-md border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100"
                id="confirmation"
                minLength={10}
                onChange={(event) => setConfirmation(event.target.value)}
                required
                type="password"
                value={confirmation}
              />
            </div>
            <button
              className="flex w-full items-center justify-center rounded-md bg-sky-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-800 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:bg-slate-400"
              disabled={loading}
              type="submit"
            >
              {loading ? 'Atualizando…' : 'Atualizar senha'}
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

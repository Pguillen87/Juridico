'use client';

import { useState, type FormEvent } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { loginSchema } from '@/lib/auth/validation';

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const routeError = searchParams.get('error');
  const message =
    routeError === 'inactive'
      ? 'Sua conta ou escritório está inativo. Entre em contato com o administrador.'
      : routeError === 'forbidden'
        ? 'Você não tem permissão para acessar essa área.'
        : error;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    const formData = new FormData(event.currentTarget);
    const parsed = loginSchema.safeParse({
      email: formData.get('email'),
      password: formData.get('password'),
    });

    if (!parsed.success) {
      setError(
        parsed.error.issues[0]?.message ?? 'Confira os dados informados.'
      );
      return;
    }

    setLoading(true);
    const supabase = createClient();
    console.log('Enviando requisição de login para o Supabase Auth...');
    const { error: authError, data } = await supabase.auth.signInWithPassword(
      parsed.data
    );
    console.log('Resposta do Supabase Auth:', {
      error: authError?.message,
      user: data?.user?.id,
    });

    if (authError) {
      setError('E-mail ou senha incorretos.');
      setLoading(false);
      return;
    }

    // No ambiente standalone (CI), o router.refresh() imediato pode preceder
    // a persistência efetiva do cookie no browser. Um micro-delay resolve.
    console.log('Login bem sucedido. Agendando redirecionamento para /app...');
    window.setTimeout(() => {
      console.log('Executando redirecionamento para /app agora...');
      router.replace('/app');
      router.refresh();
    }, 100);
  }

  return (
    <form className="space-y-5" onSubmit={handleSubmit} noValidate>
      {message ? (
        <div
          className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700"
          role="alert"
        >
          {message}
        </div>
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
          placeholder="seu@email.com"
          required
          type="email"
        />
      </div>

      <div>
        <div className="flex items-center justify-between gap-4">
          <label
            className="block text-sm font-medium text-slate-700"
            htmlFor="password"
          >
            Senha
          </label>
          <Link
            className="text-sm font-medium text-sky-700 hover:text-sky-900"
            href="/esqueci-minha-senha"
          >
            Esqueci minha senha
          </Link>
        </div>
        <input
          autoComplete="current-password"
          className="mt-2 block w-full rounded-md border border-slate-300 bg-white px-3 py-2.5 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100"
          id="password"
          name="password"
          required
          type="password"
        />
      </div>

      <button
        className="flex w-full items-center justify-center rounded-md bg-sky-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-800 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:bg-slate-400"
        disabled={loading}
        type="submit"
      >
        {loading ? 'Entrando…' : 'Entrar'}
      </button>
    </form>
  );
}

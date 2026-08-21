'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

export function LogoutButton() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleLogout() {
    setLoading(true);
    setError(null);

    const { error: signOutError } = await createClient().auth.signOut();
    if (signOutError) {
      setError('Não foi possível sair agora. Tente novamente.');
      setLoading(false);
      return;
    }

    router.replace('/login');
    router.refresh();
  }

  return (
    <div className="flex items-center gap-3">
      {error ? (
        <span className="text-xs text-red-700" role="alert">
          {error}
        </span>
      ) : null}
      <button
        className="text-sm font-semibold text-slate-600 transition hover:text-slate-950 disabled:cursor-not-allowed disabled:opacity-50"
        disabled={loading}
        onClick={handleLogout}
        type="button"
      >
        {loading ? 'Saindo…' : 'Sair'}
      </button>
    </div>
  );
}

'use client';

import { useState, useRef } from 'react';
import { useFormStatus } from 'react-dom';
import { inviteUserAction } from './actions';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      className="flex w-full items-center justify-center rounded-md bg-sky-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-sky-800 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:bg-slate-400"
      disabled={pending}
      type="submit"
    >
      {pending ? 'Enviando convite…' : 'Enviar convite'}
    </button>
  );
}

export function InviteForm() {
  const [state, setState] = useState<{ error?: string; success?: boolean }>({});
  const formRef = useRef<HTMLFormElement>(null);

  async function action(formData: FormData) {
    setState({});
    const result = await inviteUserAction(formData);
    setState(result);
    if (result.success) {
      formRef.current?.reset();
    }
  }

  return (
    <form action={action} className="space-y-4" ref={formRef}>
      {state.success ? (
        <div
          className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800"
          role="status"
        >
          Convite enviado com sucesso!
        </div>
      ) : null}

      {state.error ? (
        <div
          className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700"
          role="alert"
        >
          {state.error}
        </div>
      ) : null}

      <div>
        <label
          className="block text-sm font-medium text-slate-700"
          htmlFor="name"
        >
          Nome
        </label>
        <input
          className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100 sm:text-sm"
          id="name"
          name="name"
          required
          type="text"
        />
      </div>

      <div>
        <label
          className="block text-sm font-medium text-slate-700"
          htmlFor="email"
        >
          E-mail
        </label>
        <input
          className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100 sm:text-sm"
          id="email"
          name="email"
          required
          type="email"
        />
      </div>

      <div>
        <label
          className="block text-sm font-medium text-slate-700"
          htmlFor="role"
        >
          Papel
        </label>
        <select
          className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100 sm:text-sm"
          id="role"
          name="role"
          required
        >
          <option value="lawyer">Advogado</option>
          <option value="operator">Operador</option>
          <option value="reviewer">Revisor</option>
          <option value="auditor">Auditor</option>
        </select>
      </div>

      <div className="pt-2">
        <SubmitButton />
      </div>
    </form>
  );
}

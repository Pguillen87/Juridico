'use client';

import { useRef, useState, useTransition } from 'react';
import { updateOfficeNameAction } from './actions';

export function OfficeNameForm({ currentName }: { currentName: string }) {
  const [name, setName] = useState(currentName);
  const [message, setMessage] = useState('');
  const [isError, setIsError] = useState(false);
  const [pending, startTransition] = useTransition();
  const formRef = useRef<HTMLFormElement>(null);

  function submit() {
    const formData = new FormData(formRef.current ?? undefined);
    setMessage('Salvando…');
    setIsError(false);
    startTransition(async () => {
      const result = await updateOfficeNameAction(formData);
      if (result.success) {
        setMessage('Nome do escritório atualizado.');
        return;
      }
      setIsError(true);
      setMessage(result.error ?? 'Não foi possível salvar.');
    });
  }

  return (
    <form
      className="space-y-4"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
      ref={formRef}
    >
      <div>
        <label
          className="block text-sm font-medium text-slate-700"
          htmlFor="office-name"
        >
          Nome do escritório
        </label>
        <input
          aria-describedby="office-name-help"
          className="mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-slate-900 outline-none transition focus:border-sky-600 focus:ring-2 focus:ring-sky-100"
          id="office-name"
          maxLength={160}
          minLength={2}
          name="name"
          onChange={(event) => setName(event.target.value)}
          required
          type="text"
          value={name}
        />
        <p className="mt-1 text-xs text-slate-500" id="office-name-help">
          Use entre 2 e 160 caracteres. Esta é a única configuração editável
          nesta fase.
        </p>
      </div>
      <button
        className="rounded-md bg-sky-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-sky-800 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:bg-slate-400"
        disabled={pending}
        type="submit"
      >
        {pending ? 'Salvando…' : 'Salvar nome'}
      </button>
      <p
        aria-live="polite"
        className={isError ? 'text-sm text-red-700' : 'text-sm text-slate-600'}
        role={isError ? 'alert' : 'status'}
      >
        {message}
      </p>
    </form>
  );
}

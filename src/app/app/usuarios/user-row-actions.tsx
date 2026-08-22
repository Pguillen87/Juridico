'use client';

import { useState, useTransition } from 'react';
import type { Tables } from '@/types/database.types';
import {
  changeRoleAction,
  setActiveAction,
  setOwnerAction,
  type AdminActionResult,
} from './actions';

const roleOptions: Array<{
  value: Tables<'user_profile'>['role'];
  label: string;
}> = [
  { value: 'lawyer', label: 'Advogado' },
  { value: 'operator', label: 'Operador' },
  { value: 'reviewer', label: 'Revisor' },
  { value: 'auditor', label: 'Auditor' },
];

type UserRow = Pick<
  Tables<'user_profile'>,
  'id' | 'role' | 'is_active' | 'is_owner'
>;

type UserRowActionsProps = {
  user: UserRow;
  currentProfileId: string;
};

function getResultMessage(result: AdminActionResult): string {
  return result.success
    ? 'Alteração salva.'
    : (result.error ?? 'Não foi possível salvar.');
}

export function UserRowActions({
  user,
  currentProfileId,
}: UserRowActionsProps) {
  const [pending, startTransition] = useTransition();
  const [role, setRole] = useState(user.role);
  const [isActive, setIsActive] = useState(user.is_active);
  const [isOwner, setIsOwner] = useState(user.is_owner);
  const [message, setMessage] = useState('');
  const isSelf = user.id === currentProfileId;

  function runAction(
    label: string,
    action: (formData: FormData) => Promise<AdminActionResult>,
    fields: Record<string, string>,
    onSuccess: () => void
  ) {
    if (!window.confirm(`Confirma: ${label}?`)) return;

    const formData = new FormData();
    Object.entries(fields).forEach(([key, value]) => formData.set(key, value));
    setMessage('Salvando…');
    startTransition(async () => {
      const result = await action(formData);
      setMessage(getResultMessage(result));
      if (result.success) onSuccess();
    });
  }

  return (
    <div className="min-w-56 space-y-2">
      <label className="sr-only" htmlFor={`role-${user.id}`}>
        Papel de {user.id}
      </label>
      <select
        aria-label="Alterar papel funcional"
        className="w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-xs text-slate-800 focus:border-sky-600 focus:outline-none focus:ring-2 focus:ring-sky-100"
        disabled={pending || isSelf}
        id={`role-${user.id}`}
        onChange={(event) => {
          const nextRole = event.target.value as UserRow['role'];
          if (nextRole === role) return;
          event.currentTarget.value = role;
          runAction(
            'alterar o papel funcional',
            changeRoleAction,
            { userId: user.id, role: nextRole },
            () => setRole(nextRole)
          );
        }}
        value={role}
      >
        {roleOptions.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>

      <div className="flex flex-wrap gap-2">
        <button
          className="rounded-md border border-slate-300 px-2 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
          disabled={pending}
          onClick={() =>
            runAction(
              isActive ? 'inativar este usuário' : 'ativar este usuário',
              setActiveAction,
              { userId: user.id, isActive: String(!isActive) },
              () => setIsActive(!isActive)
            )
          }
          type="button"
        >
          {isActive ? 'Inativar' : 'Ativar'}
        </button>
        <button
          className="rounded-md border border-slate-300 px-2 py-1.5 text-xs font-medium text-slate-700 transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-300 disabled:cursor-not-allowed disabled:opacity-50"
          disabled={pending || isSelf}
          onClick={() =>
            runAction(
              isOwner
                ? 'revogar a capacidade de owner'
                : 'conceder a capacidade de owner',
              setOwnerAction,
              { userId: user.id, isOwner: String(!isOwner) },
              () => setIsOwner(!isOwner)
            )
          }
          type="button"
        >
          {isOwner ? 'Revogar owner' : 'Conceder owner'}
        </button>
      </div>

      <p aria-live="polite" className="text-xs text-slate-500">
        {message ||
          (isSelf
            ? 'Seu papel e sua capacidade não podem ser alterados aqui.'
            : '')}
      </p>
    </div>
  );
}

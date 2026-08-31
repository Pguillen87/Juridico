'use client';

import {
  useActionState,
  useEffect,
  useState,
  type FormEvent,
  type ReactNode,
} from 'react';
import {
  authorizeSendAction,
  confirmClientContactAction,
  createClientContactAction,
  deactivateClientContactAction,
  executeFakeDeliveryAction,
  reconcileUnknownDeliveryAction,
  resendDeliveryAction,
  retryDeliveryAction,
} from './f13-actions';

type ActionState = {
  success?: boolean;
  error?: string;
  message?: string;
} | null;
type Action = (data: FormData) => Promise<{
  success?: boolean;
  error?: string;
  message?: string;
}>;

function ActionForm({
  action,
  children,
  confirm,
  onSuccess,
}: {
  action: Action;
  children: ReactNode;
  confirm?: string;
  onSuccess?: () => void;
}) {
  const [state, submit, pending] = useActionState(
    async (_previous: ActionState, data: FormData) => action(data),
    null
  );
  useEffect(() => {
    if (state?.success) onSuccess?.();
  }, [onSuccess, state?.success]);
  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    if (confirm && !window.confirm(confirm)) event.preventDefault();
  };
  return (
    <form action={submit} onSubmit={onSubmit} className="space-y-3">
      {children}
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-md bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {pending ? 'Processando…' : 'Confirmar operação'}
      </button>
      {pending ? (
        <p className="text-xs text-slate-500" aria-live="polite">
          Processando operação…
        </p>
      ) : null}
      {state?.error ? (
        <p role="alert" className="text-sm text-rose-800">
          {state.error}
        </p>
      ) : null}
      {state?.success ? (
        <p
          role="status"
          aria-live="polite"
          className="text-sm text-emerald-800"
        >
          Operação concluída. Recarregue para atualizar os estados.
        </p>
      ) : null}
    </form>
  );
}

function Field({
  label,
  name,
  type = 'text',
  required = true,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
}) {
  return (
    <label className="block text-sm font-medium text-slate-700">
      {label}
      <input
        name={name}
        type={type}
        required={required}
        className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
      />
    </label>
  );
}

export function F13DeliveryPanel({
  reportId,
  clientId,
  reportVersionId,
}: {
  reportId: string;
  clientId: string;
  reportVersionId: string;
}) {
  const [status, setStatus] = useState('pending');
  const common = 'rounded-lg border border-slate-200 p-4';
  return (
    <section
      className="rounded-xl border border-sky-200 bg-white p-6 shadow-sm"
      aria-labelledby="f13-delivery-heading"
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2
            id="f13-delivery-heading"
            className="text-lg font-semibold text-slate-950"
          >
            Entrega PDF (F13)
          </h2>
          <p className="mt-1 text-sm text-slate-600">
            Operações locais simuladas, com autorização jurídica e trilha de
            auditoria.
          </p>
        </div>
        <span
          className="rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-900"
          aria-label={`Status: ${status}`}
        >
          {status}
        </span>
      </div>
      <div className="mt-4" aria-live="polite">
        <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
          Estados possíveis da entrega
        </p>
        <ul className="mt-2 flex flex-wrap gap-2 text-xs text-slate-600">
          {[
            'pending',
            'processing',
            'delivered',
            'retry_available',
            'failed',
            'unknown_outcome',
          ].map((item) => (
            <li key={item} className="rounded bg-slate-100 px-2 py-1">
              {item}
            </li>
          ))}
        </ul>
      </div>

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        <div className={common}>
          <h3 className="font-semibold text-slate-950">Contato do cliente</h3>
          <p className="mt-1 text-xs text-slate-600">
            Crie, confirme ou inative um destinatário.
          </p>
          <div className="mt-3 space-y-4">
            <ActionForm action={createClientContactAction}>
              <Field label="Nome exibido" name="displayName" />
              <Field label="E-mail" name="email" type="email" />
              <input type="hidden" name="clientId" value={clientId} />
            </ActionForm>
            <ActionForm
              action={confirmClientContactAction}
              confirm="Confirmar este contato para receber relatórios?"
            >
              <Field label="ID do contato a confirmar" name="contactId" />
            </ActionForm>
            <ActionForm
              action={deactivateClientContactAction}
              confirm="Inativar este contato? Esta ação não pode ser desfeita aqui."
            >
              <Field label="ID do contato a inativar" name="contactId" />
            </ActionForm>
          </div>
        </div>

        <div className={common}>
          <h3 className="font-semibold text-slate-950">Autorizar e executar</h3>
          <p className="mt-1 text-xs text-slate-600">
            A autorização não envia. A execução usa o provedor de e-mail falso.
          </p>
          <div className="mt-3 space-y-4">
            <ActionForm
              action={authorizeSendAction}
              confirm="Autorizar a entrega deste PDF aprovado?"
              onSuccess={() => setStatus('pending')}
            >
              <input type="hidden" name="reportId" value={reportId} />
              <input
                type="hidden"
                name="reportVersionId"
                value={reportVersionId}
              />
              <Field label="ID do artefato" name="artifactId" />
              <Field label="ID do contato confirmado" name="clientContactId" />
              <Field label="Assunto" name="subject" />
              <Field label="Chave de idempotência" name="idempotencyKey" />
            </ActionForm>
            <ActionForm
              action={executeFakeDeliveryAction}
              confirm="Executar a entrega simulada agora?"
              onSuccess={() => setStatus('delivered')}
            >
              <Field label="ID da entrega" name="deliveryId" />
            </ActionForm>
          </div>
        </div>

        <div className={common}>
          <h3 className="font-semibold text-slate-950">
            Recuperação e reconciliação
          </h3>
          <div className="mt-3 space-y-4">
            <ActionForm
              action={retryDeliveryAction}
              confirm="Solicitar uma nova tentativa manual?"
              onSuccess={() => setStatus('pending')}
            >
              <Field label="ID da entrega" name="deliveryId" />
              <Field label="Chave de idempotência" name="idempotencyKey" />
            </ActionForm>
            <ActionForm
              action={reconcileUnknownDeliveryAction}
              confirm="Registrar a reconciliação deste resultado desconhecido?"
            >
              <Field label="ID da entrega" name="deliveryId" />
              <label className="block text-sm font-medium text-slate-700">
                Resultado confirmado
                <select
                  name="delivered"
                  required
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                >
                  <option value="true">Entregue</option>
                  <option value="false">Não entregue</option>
                </select>
              </label>
              <label className="block text-sm font-medium text-slate-700">
                Motivo
                <textarea
                  name="reason"
                  required
                  minLength={1}
                  maxLength={500}
                  rows={3}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
            </ActionForm>
            <ActionForm
              action={resendDeliveryAction}
              confirm="Reenviar intencionalmente? O motivo será registrado na auditoria."
              onSuccess={() => setStatus('pending')}
            >
              <Field label="ID da entrega original" name="deliveryId" />
              <Field label="Chave de idempotência" name="idempotencyKey" />
              <label className="block text-sm font-medium text-slate-700">
                Motivo obrigatório
                <textarea
                  name="reason"
                  required
                  minLength={1}
                  maxLength={500}
                  rows={3}
                  className="mt-1 w-full rounded-md border border-slate-300 px-3 py-2"
                />
              </label>
            </ActionForm>
          </div>
        </div>
      </div>
    </section>
  );
}

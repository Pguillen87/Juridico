import type { Tables } from '@/types/database.types';

export type FunctionalRole = Tables<'user_profile'>['role'];

export const d022Actions = [
  {
    id: 1,
    action: 'view_operational_data',
    label: 'Visualizar dados operacionais do escritório',
  },
  { id: 2, action: 'invite_user', label: 'Convidar usuário' },
  { id: 3, action: 'set_active', label: 'Inativar usuário' },
  { id: 4, action: 'change_role', label: 'Alterar papel funcional' },
  { id: 5, action: 'set_owner', label: 'Conceder/remover owner' },
  { id: 6, action: 'manage_clients', label: 'Criar/editar clientes' },
  { id: 7, action: 'manage_parties', label: 'Criar/editar partes' },
  {
    id: 8,
    action: 'confirm_party_links',
    label: 'Confirmar vínculos de partes',
  },
  { id: 9, action: 'create_process', label: 'Cadastrar processo' },
  { id: 10, action: 'import_csv', label: 'Importar CSV' },
  {
    id: 11,
    action: 'manage_monitoring',
    label: 'Ativar/desativar monitoramento',
  },
  {
    id: 12,
    action: 'manual_reprocess',
    label: 'Executar reprocessamento manual',
  },
  { id: 13, action: 'view_raw_payload', label: 'Visualizar payload bruto' },
  {
    id: 14,
    action: 'view_sanitized_evidence',
    label: 'Visualizar evidência sanitizada',
  },
  { id: 15, action: 'view_failures', label: 'Visualizar falhas' },
  { id: 16, action: 'handle_failures', label: 'Tratar falhas' },
  { id: 17, action: 'view_changes', label: 'Visualizar alterações' },
  {
    id: 18,
    action: 'edit_report_draft',
    label: 'Editar rascunho de relatório',
  },
  { id: 19, action: 'review_report', label: 'Marcar/revisar relatório' },
  { id: 20, action: 'approve_final_report', label: 'Aprovar relatório final' },
  { id: 21, action: 'cancel_report', label: 'Cancelar relatório' },
  { id: 22, action: 'generate_final_pdf', label: 'Gerar PDF final' },
  { id: 23, action: 'authorize_send', label: 'Autorizar envio' },
  {
    id: 24,
    action: 'view_operational_audit',
    label: 'Visualizar auditoria operacional',
  },
  {
    id: 25,
    action: 'export_operational_audit',
    label: 'Exportar auditoria operacional',
  },
  {
    id: 26,
    action: 'view_administrative_audit',
    label: 'Visualizar auditoria administrativa',
  },
  {
    id: 27,
    action: 'export_administrative_audit',
    label: 'Exportar auditoria administrativa',
  },
  {
    id: 28,
    action: 'export_operational_data',
    label: 'Exportar dados operacionais',
  },
  {
    id: 29,
    action: 'update_office_settings',
    label: 'Alterar configurações administrativas',
  },
] as const;

export type PermissionAction = (typeof d022Actions)[number]['action'];

export type PermissionContext = {
  role: FunctionalRole;
  isOwner: boolean;
  isActive: boolean;
  officeIsActive: boolean;
};

const ownerActions: readonly PermissionAction[] = [
  'invite_user',
  'set_active',
  'change_role',
  'set_owner',
  'update_office_settings',
];

const administrativeAuditActions: readonly PermissionAction[] = [
  'view_administrative_audit',
  'export_administrative_audit',
];

const roleActions: Record<FunctionalRole, readonly PermissionAction[]> = {
  lawyer: [
    'view_operational_data',
    'manage_clients',
    'manage_parties',
    'confirm_party_links',
    'create_process',
    'import_csv',
    'manage_monitoring',
    'manual_reprocess',
    'view_raw_payload',
    'view_sanitized_evidence',
    'view_failures',
    'handle_failures',
    'view_changes',
    'edit_report_draft',
    'review_report',
    'approve_final_report',
    'cancel_report',
    'generate_final_pdf',
    'authorize_send',
    'view_operational_audit',
    'export_operational_audit',
    'export_operational_data',
  ],
  operator: [
    'view_operational_data',
    'manage_clients',
    'manage_parties',
    'create_process',
    'import_csv',
    'manage_monitoring',
    'manual_reprocess',
    'view_sanitized_evidence',
    'view_failures',
    'handle_failures',
    'view_changes',
  ],
  reviewer: [
    'view_operational_data',
    'view_sanitized_evidence',
    'view_failures',
    'view_changes',
    'edit_report_draft',
    'review_report',
  ],
  auditor: [
    'view_sanitized_evidence',
    'view_operational_audit',
    'export_operational_audit',
  ],
};

const ownerActionSet = new Set<PermissionAction>(ownerActions);
const administrativeAuditActionSet = new Set<PermissionAction>(
  administrativeAuditActions
);

export function canPerformAction(
  context: PermissionContext,
  action: PermissionAction
): boolean {
  if (!context.isActive || !context.officeIsActive) return false;
  if (ownerActionSet.has(action)) return context.isOwner;
  if (administrativeAuditActionSet.has(action)) {
    return context.isOwner || context.role === 'auditor';
  }
  return roleActions[context.role].includes(action);
}

export function getAllowedActions(
  context: PermissionContext
): readonly PermissionAction[] {
  if (!context.isActive || !context.officeIsActive) return [];

  const roleAllowed = roleActions[context.role];
  const ownerAllowed = context.isOwner ? ownerActions : [];
  const auditAllowed =
    context.isOwner || context.role === 'auditor'
      ? administrativeAuditActions
      : [];
  return [...new Set([...roleAllowed, ...ownerAllowed, ...auditAllowed])];
}

export function getD022Action(id: number) {
  return d022Actions.find((entry) => entry.id === id);
}

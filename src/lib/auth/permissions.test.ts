import { describe, expect, it } from 'vitest';
import {
  canPerformAction,
  d022Actions,
  getAllowedActions,
  type PermissionAction,
  type PermissionContext,
} from './permissions';

const active = (
  role: PermissionContext['role'],
  isOwner = false
): PermissionContext => ({
  role,
  isOwner,
  isActive: true,
  officeIsActive: true,
});

const expectedByRole: Record<
  PermissionContext['role'],
  readonly PermissionAction[]
> = {
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

const ownerOnlyActions: readonly PermissionAction[] = [
  'invite_user',
  'set_active',
  'change_role',
  'set_owner',
  'update_office_settings',
];

describe('catálogo canônico D-022', () => {
  it('contém exatamente as 29 ações normativas sem duplicação', () => {
    expect(d022Actions).toHaveLength(29);
    expect(new Set(d022Actions.map(({ id }) => id)).size).toBe(29);
    expect(new Set(d022Actions.map(({ action }) => action)).size).toBe(29);
  });

  it.each(Object.entries(expectedByRole))(
    'mantém a matriz funcional para %s sem owner',
    (role, expected) => {
      expect(
        getAllowedActions(active(role as PermissionContext['role']))
      ).toEqual(expect.arrayContaining([...expected]));
      expect(
        getAllowedActions(active(role as PermissionContext['role']))
      ).toHaveLength(expected.length + (role === 'auditor' ? 2 : 0));
      for (const action of ownerOnlyActions) {
        expect(
          canPerformAction(active(role as PermissionContext['role']), action)
        ).toBe(false);
      }
    }
  );

  it.each(Object.keys(expectedByRole) as PermissionContext['role'][])(
    '%s + owner ganha somente capacidades administrativas adicionais',
    (role) => {
      const context = active(role, true);
      const allowed = getAllowedActions(context);
      for (const action of expectedByRole[role]) {
        expect(allowed).toContain(action);
      }
      for (const action of ownerOnlyActions) {
        expect(allowed).toContain(action);
      }
      expect(allowed).toContain('view_administrative_audit');
      expect(allowed).toContain('export_administrative_audit');
      expect(canPerformAction(context, 'approve_final_report')).toBe(
        role === 'lawyer'
      );
      expect(canPerformAction(context, 'view_raw_payload')).toBe(
        role === 'lawyer'
      );
    }
  );

  it('nega qualquer ação a perfil ou office inativo', () => {
    for (const role of Object.keys(
      expectedByRole
    ) as PermissionContext['role'][]) {
      expect(
        getAllowedActions({ ...active(role, true), isActive: false })
      ).toEqual([]);
      expect(
        canPerformAction(
          { ...active(role, true), officeIsActive: false },
          'invite_user'
        )
      ).toBe(false);
    }
  });

  it('auditor sem owner acessa somente auditoria administrativa adicional', () => {
    const context = active('auditor');
    expect(canPerformAction(context, 'view_administrative_audit')).toBe(true);
    expect(canPerformAction(context, 'export_administrative_audit')).toBe(true);
    expect(canPerformAction(context, 'view_operational_data')).toBe(false);
    expect(canPerformAction(context, 'invite_user')).toBe(false);
  });

  it('não transforma owner em papel funcional', () => {
    expect(
      canPerformAction(active('operator', true), 'approve_final_report')
    ).toBe(false);
    expect(
      canPerformAction(active('reviewer', true), 'generate_final_pdf')
    ).toBe(false);
    expect(canPerformAction(active('auditor', true), 'view_raw_payload')).toBe(
      false
    );
    expect(
      canPerformAction(active('auditor', true), 'view_operational_data')
    ).toBe(false);
  });
});

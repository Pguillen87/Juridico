import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  requirePermission: vi.fn(),
  createClient: vi.fn(),
  renderer: vi.fn(),
  getReportDetail: vi.fn(),
}));
vi.mock('@/lib/auth/guards', () => ({
  requirePermission: mocks.requirePermission,
}));
vi.mock('@/lib/supabase/server', () => ({ createClient: mocks.createClient }));
vi.mock('@/lib/supabase/admin', () => ({
  createAdminClient: mocks.createClient,
}));
vi.mock('@/lib/reports/pdf-renderer', () => ({
  createPlaywrightPdfRenderer: mocks.renderer,
}));
vi.mock('@/lib/reports/server', () => ({
  getReportDetail: mocks.getReportDetail,
}));
const providerSend = vi.hoisted(() => vi.fn());
const providerReconcile = vi.hoisted(() => vi.fn());
vi.mock('@/lib/delivery/email-provider', () => ({
  FakeEmailProvider: class {
    send = providerSend;
    reconcile = providerReconcile;
  },
}));

import {
  authorizeSendAction,
  createClientContactAction,
  generateFinalPdfAction,
  executeFakeDeliveryAction,
  reconcileUnknownDeliveryAction,
} from './f13-actions';

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
function form(values: Record<string, string>) {
  const data = new FormData();
  Object.entries(values).forEach(([key, value]) => data.set(key, value));
  return data;
}

describe('F13 report actions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.requirePermission.mockResolvedValue({ profile: { role: 'lawyer' } });
    providerSend.mockResolvedValue({
      status: 'delivered',
      retryable: false,
      providerResponse: 'synthetic delivered',
      idempotencyKey: 'k',
    });
    providerReconcile.mockResolvedValue({ status: 'still_unknown' });
    mocks.createClient.mockResolvedValue({
      rpc: vi.fn().mockResolvedValue({ data: id(9), error: null }),
    });
  });

  it('validates contact input before RPC', async () => {
    await expect(
      createClientContactAction(
        form({ clientId: 'bad', email: 'bad', displayName: '' })
      )
    ).resolves.toEqual({ error: 'Os dados do contato são inválidos.' });
    expect(mocks.createClient.mock.results).toHaveLength(0);
  });

  it('requires lawyer permission for final PDF generation', async () => {
    mocks.requirePermission.mockRejectedValue(new Error('Permission denied'));
    await expect(
      generateFinalPdfAction(
        form({
          reportId: id(1),
          reportVersionId: id(2),
          approvedHash: 'a'.repeat(64),
        })
      )
    ).resolves.toEqual({
      error: 'Você não tem autorização para esta operação.',
    });
    expect(mocks.renderer).not.toHaveBeenCalled();
  });

  it('uses generate_final_pdf permission without granting send authority', async () => {
    mocks.getReportDetail.mockResolvedValue({
      report: {
        status: 'approved',
        approved_version_id: id(2),
        approved_hash: 'a'.repeat(64),
      },
      versions: [
        {
          id: id(2),
          content_hash: 'a'.repeat(64),
          structured_content: {},
          source_manifest: {},
        },
      ],
    });
    mocks.renderer.mockResolvedValue({
      render: vi.fn().mockResolvedValue({
        bytes: Buffer.from('%PDF-1.7\\nfixture'),
        artifactSha256: 'b'.repeat(64),
      }),
    });
    await generateFinalPdfAction(
      form({
        reportId: id(1),
        reportVersionId: id(2),
        approvedHash: 'a'.repeat(64),
      })
    );
    expect(mocks.requirePermission).toHaveBeenCalledWith(
      'generate_final_pdf',
      expect.anything()
    );
    expect(mocks.requirePermission).not.toHaveBeenCalledWith(
      'authorize_send',
      expect.anything()
    );
  });

  it('uses authorize_send RPC without reading F13 tables', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: id(9), error: null });
    mocks.createClient.mockResolvedValue({ rpc });
    await expect(
      authorizeSendAction(
        form({
          reportId: id(1),
          reportVersionId: id(2),
          artifactId: id(3),
          clientContactId: id(4),
          subject: ' Relatório ',
          idempotencyKey: 'key-1',
        })
      )
    ).resolves.toEqual({ success: true, deliveryId: id(9) });
    expect(rpc).toHaveBeenCalledWith(
      'phase13_authorize_send',
      expect.objectContaining({ p_subject: 'Relatório' })
    );
    expect(mocks.requirePermission).toHaveBeenCalledWith(
      'authorize_send',
      expect.anything()
    );
    expect(mocks.requirePermission).not.toHaveBeenCalledWith(
      'generate_final_pdf',
      expect.anything()
    );
  });

  it('does not finalize a delivery when the atomic claim is lost', async () => {
    const rpc = vi.fn(async (name: string) => {
      if (name === 'phase13_get_delivery_for_send')
        return {
          data: [
            {
              delivery_id: id(10),
              attempt_number: 1,
              recipient: 'client@example.test',
              subject: 'Report',
              artifact_hash: 'a'.repeat(64),
              storage_bucket: 'private-reports',
              storage_object_key: 'object.pdf',
            },
          ],
          error: null,
        };
      if (name === 'phase13_claim_delivery_attempt')
        return { data: null, error: { message: 'delivery is not claimable' } };
      return { data: id(99), error: null };
    });
    mocks.createClient.mockResolvedValue({ rpc });

    await expect(
      executeFakeDeliveryAction(form({ deliveryId: id(10) }))
    ).resolves.toEqual({ error: 'Não foi possível concluir a operação.' });

    expect(providerSend).not.toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalledWith(
      'phase13_record_delivery_attempt',
      expect.anything()
    );
  });

  it('validates reconciliation without accepting a browser delivered boolean', async () => {
    await expect(
      reconcileUnknownDeliveryAction(
        form({ deliveryId: id(1), delivered: 'true', reason: 'human says so' })
      )
    ).resolves.toEqual({ error: 'Os dados da reconciliação são inválidos.' });
  });
});

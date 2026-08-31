import { NextResponse } from 'next/server';
import { artifactSha256 } from '@/lib/reports/pdf-renderer';
import { requirePermission } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';
import { createAdminClient } from '@/lib/supabase/admin';

type ArtifactRow = {
  artifact_id: string;
  report_id: string;
  storage_bucket: string;
  storage_object_key: string;
  file_hash: string;
  byte_size: number;
};

type RpcClient = {
  rpc(
    name: string,
    args: Record<string, unknown>
  ): Promise<{ data: unknown; error: { message: string } | null }>;
};

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string; artifactId: string }> }
) {
  try {
    await requirePermission('generate_final_pdf', { redirectOnDenied: false });
    const { id: reportId, artifactId } = await params;
    const db = (await createClient()) as unknown as RpcClient;
    const result = await db.rpc('phase13_get_artifact', {
      p_artifact_id: artifactId,
    });
    if (result.error) {
      return NextResponse.json(
        { error: 'Artefato não disponível.' },
        { status: 404 }
      );
    }
    const row = Array.isArray(result.data)
      ? (result.data[0] as ArtifactRow | undefined)
      : undefined;
    if (
      !row ||
      row.report_id !== reportId ||
      row.storage_bucket !== 'private-reports'
    )
      return NextResponse.json(
        { error: 'Artefato não disponível.' },
        { status: 404 }
      );

    const admin = createAdminClient();
    const downloaded = await admin.storage
      .from(row.storage_bucket)
      .download(row.storage_object_key);
    if (downloaded.error || !downloaded.data)
      return NextResponse.json(
        { error: 'Artefato não disponível.' },
        { status: 404 }
      );
    const bytes = new Uint8Array(await downloaded.data.arrayBuffer());
    if (
      artifactSha256(bytes) !== row.file_hash ||
      bytes.byteLength !== row.byte_size
    )
      return NextResponse.json(
        { error: 'Integridade do artefato não confirmada.' },
        { status: 409 }
      );
    return new NextResponse(bytes, {
      status: 200,
      headers: {
        'Content-Type': 'application/pdf',
        'Content-Disposition': `attachment; filename="report-${artifactId}.pdf"`,
        'Cache-Control': 'private, no-store',
      },
    });
  } catch {
    return NextResponse.json(
      { error: 'Artefato não disponível.' },
      { status: 404 }
    );
  }
}

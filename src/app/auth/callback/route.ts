import type { EmailOtpType } from '@supabase/supabase-js';
import { NextResponse, type NextRequest } from 'next/server';
import { safeInternalRedirect } from '@/lib/auth/guards';
import { env } from '@/lib/env';
import { createClient } from '@/lib/supabase/server';

const allowedOtpTypes = new Set<EmailOtpType>([
  'email',
  'invite',
  'recovery',
  'signup',
]);

export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const tokenHash = url.searchParams.get('token_hash');
  const rawType = url.searchParams.get('type');
  const next = safeInternalRedirect(url.searchParams.get('next'));
  const redirectUrl = new URL(next, env.NEXT_PUBLIC_SITE_URL);

  if (
    !code &&
    !(tokenHash && rawType && allowedOtpTypes.has(rawType as EmailOtpType))
  ) {
    redirectUrl.pathname = '/login';
    redirectUrl.searchParams.set('error', 'auth-code');
    return NextResponse.redirect(redirectUrl);
  }

  const supabase = await createClient();
  const result = code
    ? await supabase.auth.exchangeCodeForSession(code)
    : await supabase.auth.verifyOtp({
        token_hash: tokenHash as string,
        type: rawType as EmailOtpType,
      });

  if (result.error) {
    redirectUrl.pathname = '/login';
    redirectUrl.search = '';
    redirectUrl.searchParams.set('error', 'auth-code');
    return NextResponse.redirect(redirectUrl);
  }

  redirectUrl.search = '';
  return NextResponse.redirect(redirectUrl);
}

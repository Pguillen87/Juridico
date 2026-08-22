import type { EmailOtpType } from '@supabase/supabase-js';
import { NextResponse, type NextRequest } from 'next/server';
import { safeInternalRedirect } from '@/lib/auth/guards';
import { createClient } from '@/lib/supabase/server';

const allowedOtpTypes = new Set<EmailOtpType>(['email', 'invite', 'recovery']);

export async function GET(request: NextRequest) {
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const tokenHash = url.searchParams.get('token_hash');
  const rawType = url.searchParams.get('type');
  const next = safeInternalRedirect(url.searchParams.get('next'));
  const redirectUrl = new URL(next, request.nextUrl.origin);

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
  const response = NextResponse.redirect(redirectUrl);

  // Garantir que os cookies recém-setados no cookieStore sejam passados para o redirect
  // Isso previne o bug "Auth session missing" no CI onde o Next.js pode perder cookies em redirecionamentos.
  const { cookies } = await import('next/headers');
  const cookieStore = await cookies();
  cookieStore.getAll().forEach((cookie) => {
    response.cookies.set(cookie.name, cookie.value, {
      ...cookie,
      secure:
        process.env.NODE_ENV === 'production' &&
        process.env.HOSTNAME !== '127.0.0.1',
      sameSite: 'lax',
    });
  });

  return response;
}

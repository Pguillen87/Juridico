import { createBrowserClient } from '@supabase/ssr';
import { env } from '../env';

export function createClient() {
  if (
    !env.NEXT_PUBLIC_SUPABASE_URL ||
    !env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  ) {
    throw new Error('Missing Supabase environment variables');
  }
  return createBrowserClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookieOptions: {
        secure: process.env.NEXT_PUBLIC_SITE_URL?.startsWith('https') ?? false,
        sameSite: 'lax',
      },
    }
  );
}

import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function proxy(request: NextRequest) {
  let supabaseResponse = NextResponse.next({
    request,
  });

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    // Se não há configuração, apenas repassa a requisição
    return supabaseResponse;
  }

  const supabase = createServerClient(supabaseUrl, supabaseKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) =>
          request.cookies.set(name, value)
        );
        supabaseResponse = NextResponse.next({
          request,
        });
        cookiesToSet.forEach(({ name, value, options }) =>
          supabaseResponse.cookies.set(name, value, options)
        );
      },
    },
  });

  // IMPORTANTE: NÃO usar supabase.auth.getSession() para proteger rotas.
  // Use supabase.auth.getUser() para validar a identidade de forma segura no servidor.
  // O Proxy apenas garante que a sessão seja atualizada.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const url = request.nextUrl.clone();
  const path = url.pathname;

  const publicRoutes = [
    '/login',
    '/esqueci-minha-senha',
    '/auth/callback',
    '/redefinir-senha',
  ];
  const isPublicRoute = publicRoutes.some((route) => path.startsWith(route));

  // Se o usuário está autenticado e tenta acessar /login ou /, redireciona para /app
  // (Note que a verificação de is_active do perfil será feita no servidor nas rotas protegidas)
  if (user && (path === '/login' || path === '/')) {
    url.pathname = '/app';
    return NextResponse.redirect(url);
  }

  // Se não está autenticado e tenta acessar uma rota protegida (não pública), redireciona para /login
  if (!user && !isPublicRoute && path !== '/') {
    url.pathname = '/login';
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * Feel free to modify this pattern to include more paths.
     */
    '/((?!_next/static|_next/image|favicon.ico|api/health|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
};

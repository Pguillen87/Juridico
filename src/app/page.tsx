import { redirect } from 'next/navigation';

export default function Home() {
  // O proxy.ts já redireciona '/' para '/login' (ou '/app' se autenticado).
  // Este é um fallback seguro.
  redirect('/login');
}

export default function Home() {
  return (
    <main className="min-h-screen flex flex-col items-center justify-center p-8 bg-gray-50 text-gray-900">
      <div className="max-w-2xl text-center space-y-6">
        <h1 className="text-4xl font-bold tracking-tight">Juridico</h1>
        <p className="text-xl text-gray-600">Fundação técnica operacional.</p>
        <div className="bg-white p-6 rounded-lg shadow-sm border border-gray-200">
          <p className="text-sm text-gray-500">
            A infraestrutura local com Next.js, App Router, Tailwind e Docker
            está configurada.
          </p>
        </div>
      </div>
    </main>
  );
}

import { LoginForm } from "./LoginForm";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const params = await searchParams;

  return (
    <main className="flex min-h-screen items-center justify-center bg-[linear-gradient(180deg,hsl(210_28%_98%),hsl(178_28%_94%))] p-4">
      <LoginForm next={params.next ?? "/dashboard"} />
    </main>
  );
}

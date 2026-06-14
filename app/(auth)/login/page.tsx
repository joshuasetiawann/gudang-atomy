import { LoginForm } from "./LoginForm";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const params = await searchParams;

  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[linear-gradient(180deg,hsl(210_28%_98%),hsl(178_28%_94%))] p-4">
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -left-32 -top-40 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
        <div className="absolute -right-40 top-1/4 h-[28rem] w-[28rem] rounded-full bg-accent/10 blur-3xl" />
        <div className="absolute -bottom-48 left-1/3 h-[30rem] w-[30rem] rounded-full bg-primary/[0.07] blur-3xl" />
      </div>
      <div className="relative z-10 w-full max-w-md">
        <LoginForm next={params.next ?? "/dashboard"} />
        <p className="mt-6 text-center text-xs font-medium text-muted-foreground">Gudang Atomy · Manajemen gudang berbasis QR</p>
      </div>
    </main>
  );
}

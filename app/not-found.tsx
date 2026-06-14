import Link from "next/link";
import { Compass, Home, PackageSearch } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export default function NotFound() {
  return (
    <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[linear-gradient(180deg,hsl(210_28%_98%),hsl(178_28%_94%))] p-4">
      <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden">
        <div className="absolute -left-32 -top-40 h-96 w-96 rounded-full bg-primary/10 blur-3xl" />
        <div className="absolute -right-40 bottom-0 h-[28rem] w-[28rem] rounded-full bg-accent/10 blur-3xl" />
      </div>
      <Card className="animate-rise relative z-10 w-full max-w-md rounded-xl border-border/70 shadow-lift">
        <CardContent className="flex flex-col items-center p-8 text-center sm:p-10">
          <div className="flex h-16 w-16 items-center justify-center rounded-xl bg-primary/10 text-primary ring-1 ring-primary/15">
            <PackageSearch className="h-8 w-8" />
          </div>
          <p className="mt-6 font-mono text-sm font-semibold uppercase tracking-wider text-primary tabular-nums">Error 404</p>
          <h1 className="mt-2 text-2xl font-semibold tracking-normal">Halaman tidak ditemukan</h1>
          <p className="mt-2 max-w-sm text-sm leading-relaxed text-muted-foreground">
            Halaman yang kamu cari mungkin sudah dipindahkan, dihapus, atau alamatnya keliru. Periksa kembali tautan atau kembali ke dashboard.
          </p>
          <div className="mt-7 flex w-full flex-col gap-2.5 sm:flex-row sm:justify-center">
            <Button asChild size="lg" className="w-full sm:w-auto">
              <Link href="/dashboard">
                <Home className="h-4 w-4" />
                Kembali ke dashboard
              </Link>
            </Button>
            <Button asChild variant="outline" size="lg" className="w-full sm:w-auto">
              <Link href="/dashboard">
                <Compass className="h-4 w-4" />
                Jelajahi gudang
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </main>
  );
}

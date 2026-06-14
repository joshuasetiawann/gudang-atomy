import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { ToastProvider, ToastViewport } from "@/components/ui/toast";

const geistSans = Geist({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap"
});

const geistMono = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap"
});

export const metadata: Metadata = {
  title: {
    default: "Gudang Atomy",
    template: "%s · Gudang Atomy"
  },
  description:
    "Pencatatan barang masuk dan keluar Gudang Atomy berbasis QR/barcode — manajemen gudang yang cepat, rapi, dan akurat.",
  applicationName: "Gudang Atomy",
  openGraph: {
    title: "Gudang Atomy",
    description:
      "Pencatatan barang masuk dan keluar Gudang Atomy berbasis QR/barcode — manajemen gudang yang cepat, rapi, dan akurat.",
    siteName: "Gudang Atomy",
    type: "website",
    locale: "id_ID"
  }
};

export const viewport: Viewport = {
  themeColor: "#1d6f6a",
  colorScheme: "light"
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="id" className={`${geistSans.variable} ${geistMono.variable}`}>
      <body>
        <ToastProvider>
          {children}
          <ToastViewport />
        </ToastProvider>
      </body>
    </html>
  );
}
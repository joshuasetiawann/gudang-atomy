"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { BrowserMultiFormatReader, type IScannerControls } from "@zxing/browser";
import { AlertTriangle, Camera, Keyboard, ScanLine, Square } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";

type VideoDevice = {
  deviceId: string;
  label: string;
};

type ScanResult = {
  getText: () => string;
};

const backCameraPattern = /(back|rear|environment|belakang)/i;

export function BarcodeScanner({ onDetected }: { onDetected: (value: string) => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const startRef = useRef<() => Promise<void>>(async () => {});
  const autoStartedRef = useRef(false);
  const detectedRef = useRef(false);
  const [devices, setDevices] = useState<VideoDevice[]>([]);
  const [deviceId, setDeviceId] = useState<string>("");
  const [manualValue, setManualValue] = useState("");
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const stop = useCallback(() => {
    controlsRef.current?.stop();
    controlsRef.current = null;
    setRunning(false);
  }, []);

  const start = useCallback(async () => {
    if (!videoRef.current) return;
    setError(null);
    detectedRef.current = false;
    try {
      const reader = new BrowserMultiFormatReader();
      controlsRef.current?.stop();
      const onResult = (result: ScanResult | undefined | null) => {
        if (!result || detectedRef.current) return;
        detectedRef.current = true;
        onDetected(result.getText());
        controlsRef.current?.stop();
        controlsRef.current = null;
        setRunning(false);
      };

      if (deviceId) {
        controlsRef.current = await reader.decodeFromVideoDevice(deviceId, videoRef.current, onResult);
      } else {
        try {
          controlsRef.current = await reader.decodeFromConstraints(
            {
              audio: false,
              video: {
                facingMode: { ideal: "environment" },
                width: { ideal: 1280 },
                height: { ideal: 720 }
              }
            },
            videoRef.current,
            onResult
          );
        } catch {
          controlsRef.current = await reader.decodeFromVideoDevice(undefined, videoRef.current, onResult);
        }
      }
      setRunning(true);
    } catch (scanError) {
      setRunning(false);
      controlsRef.current = null;
      setError(scanError instanceof Error ? scanError.message : "Scanner gagal berjalan.");
    }
  }, [deviceId, onDetected]);

  useEffect(() => {
    startRef.current = start;
  }, [start]);

  useEffect(() => {
    BrowserMultiFormatReader.listVideoInputDevices()
      .then((list) => {
        const mapped = list.map((device, index) => ({
          deviceId: device.deviceId,
          label: device.label || `Kamera ${index + 1}`
        }));
        const preferredDevice = mapped.find((device) => backCameraPattern.test(device.label));
        setDevices(mapped);
        setDeviceId(preferredDevice?.deviceId ?? "");
      })
      .catch(() => setError("Kamera belum bisa diakses."));

    return () => stop();
  }, [stop]);

  useEffect(() => {
    if (autoStartedRef.current) return;
    autoStartedRef.current = true;
    const timer = window.setTimeout(() => {
      void startRef.current();
    }, 350);
    return () => window.clearTimeout(timer);
  }, []);

  return (
    <div className="min-w-0 space-y-4 rounded-lg border bg-card p-3 shadow-card sm:p-4">
      <div>
        <div className="flex items-center gap-2 text-sm font-semibold">
          <span className="flex h-7 w-7 items-center justify-center rounded-md bg-primary/10 text-primary ring-1 ring-primary/15">
            <ScanLine className="h-4 w-4" />
          </span>
          Scan barcode box
        </div>
        <p className="mt-1 text-xs text-muted-foreground">Gunakan kamera atau masukkan kode barcode manual.</p>
      </div>
      <div className="group relative overflow-hidden rounded-lg border bg-slate-950 shadow-inner">
        <video ref={videoRef} className="aspect-square w-full object-cover sm:aspect-[4/3]" muted playsInline />
        {/* Bingkai pemindai sebagai panduan visual */}
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center p-6">
          <div
            className={cn(
              "relative h-3/5 w-4/5 rounded-lg transition-colors duration-200",
              running ? "ring-2 ring-primary/70" : "ring-1 ring-white/20"
            )}
          >
            <span className="absolute -left-px -top-px h-6 w-6 rounded-tl-lg border-l-2 border-t-2 border-primary" />
            <span className="absolute -right-px -top-px h-6 w-6 rounded-tr-lg border-r-2 border-t-2 border-primary" />
            <span className="absolute -bottom-px -left-px h-6 w-6 rounded-bl-lg border-b-2 border-l-2 border-primary" />
            <span className="absolute -bottom-px -right-px h-6 w-6 rounded-br-lg border-b-2 border-r-2 border-primary" />
            {running ? (
              <span className="absolute inset-x-2 top-1/2 h-px -translate-y-1/2 bg-gradient-to-r from-transparent via-primary to-transparent shadow-[0_0_8px_0] shadow-primary/60" />
            ) : null}
          </div>
        </div>
        <div className="pointer-events-none absolute left-3 top-3">
          <span
            className={cn(
              "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-medium backdrop-blur-sm transition-colors duration-200",
              running
                ? "bg-success/20 text-success ring-1 ring-success/30"
                : "bg-white/10 text-white/80 ring-1 ring-white/20"
            )}
          >
            <span className={cn("h-1.5 w-1.5 rounded-full", running ? "animate-pulse bg-success" : "bg-white/60")} />
            {running ? "Memindai" : "Siaga"}
          </span>
        </div>
      </div>
      {devices.length > 1 ? (
        <div className="space-y-2">
          <Label htmlFor="camera">Kamera</Label>
          <select
            id="camera"
            value={deviceId}
            onChange={(event) => {
              setDeviceId(event.target.value);
              stop();
            }}
            className="h-10 w-full rounded-md border bg-card px-3 text-sm shadow-soft outline-none transition-all duration-200 focus:border-primary/50 focus:ring-2 focus:ring-ring"
          >
            <option value="">Kamera belakang otomatis</option>
            {devices.map((device) => (
              <option key={device.deviceId} value={device.deviceId}>
                {device.label}
              </option>
            ))}
          </select>
        </div>
      ) : null}
      <div className="grid grid-cols-2 gap-2 sm:flex sm:flex-wrap">
        <Button className="w-full sm:w-auto" type="button" onClick={start} disabled={running}>
          <Camera className="h-4 w-4" />
          Mulai
        </Button>
        <Button className="w-full sm:w-auto" type="button" onClick={stop} variant="outline" disabled={!running}>
          <Square className="h-4 w-4" />
          Berhenti
        </Button>
      </div>
      <form
        className="grid min-w-0 gap-2 sm:grid-cols-[minmax(0,1fr)_auto]"
        onSubmit={(event) => {
          event.preventDefault();
          if (manualValue.trim()) onDetected(manualValue.trim());
        }}
      >
        <Input
          value={manualValue}
          onChange={(event) => setManualValue(event.target.value)}
          placeholder="ATMY_BOX:BOX-YYYYMMDD-000001:XXXX"
          className="min-w-0 font-mono text-xs sm:text-sm"
        />
        <Button className="w-full sm:w-auto" type="submit" variant="secondary">
          <Keyboard className="h-4 w-4" />
          Input
        </Button>
      </form>
      {error ? (
        <p
          role="alert"
          className="flex items-start gap-2 rounded-md border border-destructive/20 bg-destructive/10 p-3 text-sm text-destructive"
        >
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          <span>{error}</span>
        </p>
      ) : null}
    </div>
  );
}

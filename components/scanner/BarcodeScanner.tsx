"use client";

import { useEffect, useRef, useState } from "react";
import { BrowserMultiFormatReader, type IScannerControls } from "@zxing/browser";
import { Camera, Keyboard, ScanLine, Square } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type VideoDevice = {
  deviceId: string;
  label: string;
};

export function BarcodeScanner({ onDetected }: { onDetected: (value: string) => void }) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const [devices, setDevices] = useState<VideoDevice[]>([]);
  const [deviceId, setDeviceId] = useState<string>("");
  const [manualValue, setManualValue] = useState("");
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    BrowserMultiFormatReader.listVideoInputDevices()
      .then((list) => {
        const mapped = list.map((device, index) => ({
          deviceId: device.deviceId,
          label: device.label || `Kamera ${index + 1}`
        }));
        setDevices(mapped);
        setDeviceId(mapped[0]?.deviceId ?? "");
      })
      .catch(() => setError("Kamera belum bisa diakses."));

    return () => controlsRef.current?.stop();
  }, []);

  async function start() {
    if (!videoRef.current) return;
    setError(null);
    try {
      const reader = new BrowserMultiFormatReader();
      controlsRef.current = await reader.decodeFromVideoDevice(deviceId || undefined, videoRef.current, (result) => {
        if (result) {
          onDetected(result.getText());
          controlsRef.current?.stop();
          setRunning(false);
        }
      });
      setRunning(true);
    } catch (scanError) {
      setError(scanError instanceof Error ? scanError.message : "Scanner gagal berjalan.");
    }
  }

  function stop() {
    controlsRef.current?.stop();
    setRunning(false);
  }

  return (
    <div className="space-y-4 rounded-lg border bg-card p-4 shadow-card">
      <div>
        <div className="flex items-center gap-2 text-sm font-semibold">
          <ScanLine className="h-4 w-4 text-primary" />
          Scan Barcode Box
        </div>
        <p className="mt-1 text-xs text-muted-foreground">Gunakan kamera atau masukkan kode barcode manual.</p>
      </div>
      <div className="overflow-hidden rounded-lg border bg-slate-950 shadow-inner">
        <video ref={videoRef} className="aspect-[4/3] w-full object-cover" muted playsInline />
      </div>
      {devices.length > 1 ? (
        <div className="space-y-2">
          <Label htmlFor="camera">Kamera</Label>
          <select
            id="camera"
            value={deviceId}
            onChange={(event) => setDeviceId(event.target.value)}
            className="h-10 w-full rounded-md border bg-card px-3 text-sm outline-none focus:ring-2 focus:ring-ring"
          >
            {devices.map((device) => (
              <option key={device.deviceId} value={device.deviceId}>
                {device.label}
              </option>
            ))}
          </select>
        </div>
      ) : null}
      <div className="flex flex-wrap gap-2">
        <Button type="button" onClick={start} disabled={running}>
          <Camera className="h-4 w-4" />
          Start
        </Button>
        <Button type="button" onClick={stop} variant="outline" disabled={!running}>
          <Square className="h-4 w-4" />
          Stop
        </Button>
      </div>
      <form
        className="grid gap-2 sm:grid-cols-[1fr_auto]"
        onSubmit={(event) => {
          event.preventDefault();
          if (manualValue.trim()) onDetected(manualValue.trim());
        }}
      >
        <Input value={manualValue} onChange={(event) => setManualValue(event.target.value)} placeholder="ATMY_BOX:BOX-YYYYMMDD-000001:XXXX" />
        <Button type="submit" variant="secondary">
          <Keyboard className="h-4 w-4" />
          Input
        </Button>
      </form>
      {error ? <p className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">{error}</p> : null}
    </div>
  );
}

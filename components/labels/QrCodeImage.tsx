"use client";

import { useEffect, useState } from "react";
import QRCode from "qrcode";
import { cn } from "@/lib/utils";

export function QrCodeImage({
  value,
  className,
  imageClassName,
  size = 280
}: {
  value: string;
  className?: string;
  imageClassName?: string;
  size?: number;
}) {
  const [qrUrl, setQrUrl] = useState("");

  useEffect(() => {
    let mounted = true;
    QRCode.toDataURL(value, { errorCorrectionLevel: "M", margin: 1, width: size }).then((url) => {
      if (mounted) setQrUrl(url);
    });
    return () => {
      mounted = false;
    };
  }, [size, value]);

  return (
    <div className={cn("flex items-center justify-center", className)}>
      {qrUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={qrUrl} alt={value} className={cn("h-full w-full rounded-sm object-contain", imageClassName)} />
      ) : (
        <div className={cn("skeleton-shimmer h-full w-full rounded-md bg-muted", imageClassName)} />
      )}
    </div>
  );
}

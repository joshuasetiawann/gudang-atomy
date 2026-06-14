export function checksum(input: string) {
  let hash = 0;
  for (let index = 0; index < input.length; index += 1) {
    hash = (hash * 31 + input.charCodeAt(index)) >>> 0;
  }
  return hash.toString(36).toUpperCase().slice(-4).padStart(4, "0");
}

export function legacyChecksum(input: string) {
  let hash = 0;
  for (let index = 0; index < input.length; index += 1) {
    hash = (hash * 31 + input.charCodeAt(index)) % 1679616;
  }
  return hash.toString(36).toUpperCase().slice(-4).padStart(4, "0");
}

export function buildBarcodeValue(idBox: string) {
  return `ATMY_BOX:${idBox}:${checksum(idBox)}`;
}

export function isValidBarcodeValue(value: string) {
  const match = /^ATMY_BOX:(BOX-\d{8}-\d{6}):([A-Z0-9]{4})$/.exec(value.trim());
  if (!match) return false;
  return checksum(match[1]) === match[2] || legacyChecksum(match[1]) === match[2];
}

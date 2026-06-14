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

// id_box may be a generated code (BOX-YYYYMMDD-NNNNNN) or an imported code
// (e.g. GK-KARDUS-000001). Accept any uppercase alphanumeric/hyphen id and rely
// on the checksum to guarantee integrity, instead of hardcoding one id shape.
export function isValidBarcodeValue(value: string) {
  const match = /^ATMY_BOX:([A-Z0-9][A-Z0-9-]{1,48}):([A-Z0-9]{4})$/.exec(value.trim());
  if (!match) return false;
  return checksum(match[1]) === match[2] || legacyChecksum(match[1]) === match[2];
}

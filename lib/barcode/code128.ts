// Self-contained Code 128 encoder (auto Code B / Code C switching).
//
// IMPORTANT: this only changes how a value is *drawn* (QR -> 1D bars). The
// encoded string is byte-for-byte identical to `barcode_value`, so the
// database, the zod validation (`isValidBarcodeValue`), and the camera scanner
// (@zxing reads Code 128 out of the box) all keep working unchanged.
//
// No external dependency on purpose: keeps the build safe and avoids pulling a
// new package just to render bars.

// Canonical Code 128 module patterns (index 0..106). Each entry is a string of
// "1" (bar module) / "0" (space module). Entries 0..102 are data/function
// symbols, 103 = Start A, 104 = Start B, 105 = Start C, 106 = Stop.
const PATTERNS = [
  "11011001100", "11001101100", "11001100110", "10010011000", "10010001100",
  "10001001100", "10011001000", "10011000100", "10001100100", "11001001000",
  "11001000100", "11000100100", "10110011100", "10011011100", "10011001110",
  "10111001100", "10011101100", "10011100110", "11001110010", "11001011100",
  "11001001110", "11011100100", "11001110100", "11101101110", "11101001100",
  "11100101100", "11100100110", "11101100100", "11100110100", "11100110010",
  "11011011000", "11011000110", "11000110110", "10100011000", "10001011000",
  "10001000110", "10110001000", "10001101000", "10001100010", "11010001000",
  "11000101000", "11000100010", "10110111000", "10110001110", "10001101110",
  "10111011000", "10111000110", "10001110110", "11101110110", "11010001110",
  "11000101110", "11011101000", "11011100010", "11011101110", "11101011000",
  "11101000110", "11100010110", "11101101000", "11101100010", "11100011010",
  "11101111010", "11001000010", "11110001010", "10100110000", "10100001100",
  "10010110000", "10010000110", "10000101100", "10000100110", "10110010000",
  "10110000100", "10011010000", "10011000010", "10000110100", "10000110010",
  "11000010010", "11001010000", "11110111010", "11000010100", "10001111010",
  "10100111100", "10010111100", "10010011110", "10111100100", "10011110100",
  "10011110010", "11110100100", "11110010100", "11110010010", "11011011110",
  "11011110110", "11110110110", "10101111000", "10100011110", "10001011110",
  "10111101000", "10111100010", "11110101000", "11110100010", "10111011110",
  "10111101110", "11101011110", "11110101110", "11010000100", "11010010000",
  "11010011100", "1100011101011"
];

const START_B = 104;
const START_C = 105;
const STOP = 106;
const SWITCH_TO_C = 99; // value used from Code B to switch into Code C
const SWITCH_TO_B = 100; // value used from Code C to switch into Code B

function isDigit(ch: string) {
  return ch >= "0" && ch <= "9";
}

function digitRunLength(data: string, start: number) {
  let n = 0;
  while (start + n < data.length && isDigit(data[start + n])) n += 1;
  return n;
}

// Translate the input into Code 128 symbol values, switching between Code B
// (full ASCII) and Code C (digit pairs) to keep the symbol compact.
function toSymbols(data: string): number[] {
  const symbols: number[] = [];
  let index = 0;

  const leadingDigits = digitRunLength(data, 0);
  let modeC = leadingDigits >= 2 && (leadingDigits === data.length || leadingDigits >= 4);
  symbols.push(modeC ? START_C : START_B);

  while (index < data.length) {
    if (modeC) {
      if (index + 1 < data.length && isDigit(data[index]) && isDigit(data[index + 1])) {
        symbols.push(Number(data.slice(index, index + 2)));
        index += 2;
      } else {
        symbols.push(SWITCH_TO_B);
        modeC = false;
      }
    } else {
      const run = digitRunLength(data, index);
      const reachesEnd = index + run === data.length;
      if (run >= 4 || (reachesEnd && run >= 2)) {
        // Code C consumes digit pairs; keep alignment even by encoding a single
        // leading digit in Code B when the run length is odd.
        if (run % 2 === 1) {
          symbols.push(data.charCodeAt(index) - 32);
          index += 1;
        }
        symbols.push(SWITCH_TO_C);
        modeC = true;
      } else {
        symbols.push(data.charCodeAt(index) - 32);
        index += 1;
      }
    }
  }

  return symbols;
}

function checksum(symbols: number[]) {
  let sum = symbols[0];
  for (let position = 1; position < symbols.length; position += 1) {
    sum += symbols[position] * position;
  }
  return sum % 103;
}

// Returns the full barcode as a string of "1"/"0" modules (bars/spaces),
// including start, checksum and stop symbols.
export function code128Modules(data: string): string {
  if (!data) return "";
  const symbols = toSymbols(data);
  symbols.push(checksum(symbols));
  symbols.push(STOP);
  return symbols.map((symbol) => PATTERNS[symbol]).join("");
}

// Collapse the module string into bar rectangles { x, width } expressed in
// module units, ready to render as SVG <rect> elements.
export function code128Bars(modules: string): Array<{ x: number; width: number }> {
  const bars: Array<{ x: number; width: number }> = [];
  let runStart = -1;
  for (let i = 0; i < modules.length; i += 1) {
    if (modules[i] === "1") {
      if (runStart === -1) runStart = i;
    } else if (runStart !== -1) {
      bars.push({ x: runStart, width: i - runStart });
      runStart = -1;
    }
  }
  if (runStart !== -1) bars.push({ x: runStart, width: modules.length - runStart });
  return bars;
}

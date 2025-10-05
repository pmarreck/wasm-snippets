const modulePath = Deno.args[0];
if (!modulePath) {
  console.error("Usage: deno run deno_wasi.ts <module> [args...]");
  Deno.exit(64);
}

async function readAllStdin(): Promise<Uint8Array> {
  const chunks: Uint8Array[] = [];
  const buffer = new Uint8Array(8192);
  while (true) {
    const n = await Deno.stdin.read(buffer);
    if (n === null || n === 0) break;
    chunks.push(buffer.slice(0, n));
  }
  const total = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

const moduleArgs = ["quicksort-wasm", ...Deno.args.slice(1)];
const locale = Deno.env.get("LC_ALL") ?? "C";
const envStrings = [
  `LC_ALL=${locale}`,
  `LC_COLLATE=${locale}`,
];
const encoder = new TextEncoder();
const envBytes = envStrings.map((s) => encoder.encode(`${s}\0`));
const envBufSize = envBytes.reduce((acc, bytes) => acc + bytes.length, 0);

const stdinData = await readAllStdin();
let stdinOffset = 0;

let memory: WebAssembly.Memory;
const getMemU8 = () => new Uint8Array(memory.buffer);
const getView = () => new DataView(memory.buffer);

class WasiExit extends Error {
  constructor(public code: number) {
    super(`WASI exit ${code}`);
  }
}

const wasiImports = {
  wasi_snapshot_preview1: {
    fd_write(fd: number, iovs: number, iovsLen: number, nwritten: number) {
      const view = getView();
      let written = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = view.getUint32(iovs + i * 8, true);
        const len = view.getUint32(iovs + i * 8 + 4, true);
        const chunk = getMemU8().subarray(ptr, ptr + len);
        if (fd === 1) {
          Deno.stdout.writeSync(chunk);
        } else if (fd === 2) {
          Deno.stderr.writeSync(chunk);
        }
        written += len;
      }
      view.setUint32(nwritten, written, true);
      return 0;
    },
    fd_read(fd: number, iovs: number, iovsLen: number, nread: number) {
      if (fd !== 0) {
        return 8; // __WASI_ERRNO_BADF
      }
      const view = getView();
      let read = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = view.getUint32(iovs + i * 8, true);
        const len = view.getUint32(iovs + i * 8 + 4, true);
        const remaining = stdinData.length - stdinOffset;
        if (remaining <= 0) break;
        const toCopy = Math.min(len, remaining);
        getMemU8().set(stdinData.subarray(stdinOffset, stdinOffset + toCopy), ptr);
        stdinOffset += toCopy;
        read += toCopy;
        if (toCopy < len) break;
      }
      view.setUint32(nread, read, true);
      return 0;
    },
    environ_sizes_get(countPtr: number, bufSizePtr: number) {
      const view = getView();
      view.setUint32(countPtr, envBytes.length, true);
      view.setUint32(bufSizePtr, envBufSize, true);
      return 0;
    },
    environ_get(environPtr: number, environBufPtr: number) {
      const view = getView();
      let bufPtr = environBufPtr;
      envBytes.forEach((bytes, idx) => {
        view.setUint32(environPtr + idx * 4, bufPtr, true);
        getMemU8().set(bytes, bufPtr);
        bufPtr += bytes.length;
      });
      return 0;
    },
    clock_time_get(clockId: number, _precision: bigint, timePtr: number) {
      let ns = 0n;
      if (clockId === 0) {
        ns = BigInt(Math.trunc(Date.now() * 1e6));
      } else {
        ns = BigInt(Math.trunc(performance.now() * 1e6));
      }
      const view = getView();
      view.setBigUint64(timePtr, ns, true);
      return 0;
    },
    proc_exit(code: number) {
      throw new WasiExit(code);
    },
    fd_close() {
      return 0;
    },
    fd_fdstat_get() {
      return 0;
    },
  },
};

const binary = await Deno.readFile(modulePath);
const module = await WebAssembly.compile(binary);
const instance = await WebAssembly.instantiate(
  module,
  wasiImports as Record<string, WebAssembly.Imports>,
);

memory = instance.exports.memory as WebAssembly.Memory;
const start = instance.exports._start as CallableFunction;

try {
  start();
  Deno.exit(0);
} catch (err) {
  if (err instanceof WasiExit) {
    Deno.exit(err.code);
  }
  throw err;
}

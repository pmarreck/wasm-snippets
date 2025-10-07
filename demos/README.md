# demos

## `ns`

A WAT module that demonstrates WASI clock access and the `wasmrun`/`wasmbuild`
workflow. It is executable directly thanks to the shebang:

```
#!/usr/bin/env wasmrun
```

When invoked, `wasmrun` checks whether a cached `.wasm` artefact matching the
source exists; if not, it calls `wasmbuild` (which in turn uses `wasm-tools`) to
compile the text module and timestamp the result so later runs skip the build.
This mirrors the “moonrun/moonbuild” workflow you mentioned and keeps startup
fast when nothing changed.

### Behaviour

- Default: query WASI’s realtime clock (`clock_time_get`) and emit the timestamp
  as `<seconds>.<nanoseconds>\n` on stdout.
- CLI flags:
  - `-a`, `--about` – short description of the demo and its WASM/WASI focus.
  - `-h`, `--help` – usage summary.
- Testing hook: before touching the clock, the module attempts to read eight
  bytes from stdin. If stdin is *not* a TTY and at least eight bytes are
  available, those bytes (interpreted as a little-endian `u64`) replace the
  syscall value. This makes it trivial to pipe in deterministic timestamps for
  tests or demos:

  ```bash
  printf '\x15\xcd\x85\x3d\xfe\x9c\x97\x17' | ./demos/ns
  # -> 1700000000.123456789

  perl -e 'print pack("Q<", 1700000000123456789)' | ./demos/ns
  # -> 1700000000.123456789
  ```

  Alternatively, pair it with `printable_binary` or LuaJIT:

  ```bash
 luajit -e 'ffi=require("ffi"); ffi.cdef[[unsigned long long strtoull(const char*, char**, int);]]; ns=ffi.C.strtoull("1700000000123456789", nil, 10); buf=ffi.new("uint64_t[1]", ns); io.write(ffi.string(buf, 8))' | ./demos/ns
  ```

Because stdin overrides expect raw bytes, you can generate fixtures without
depending on the host clock or adding new dependencies to the project.

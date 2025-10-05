#!/usr/bin/env wasmrun
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  (data (i32.const 64) "realtime_ns: ")
  (data (i32.const 80) "\0a")

  (func $format_u64 (param $value i64) (param $out i32)
    (local $buf_end i32)
    (local $write_ptr i32)
    (local $len i32)
    (local $digit i32)
    (local $n i64)

    (local.set $buf_end (i32.const 48))
    (local.set $write_ptr (local.get $buf_end))
    (local.set $len (i32.const 0))
    (local.set $n (local.get $value))

    (loop $extract
      (local.set $digit
        (i32.wrap_i64
          (i64.rem_u (local.get $n) (i64.const 10))))
      (local.set $write_ptr (i32.sub (local.get $write_ptr) (i32.const 1)))
      (i32.store8
        (local.get $write_ptr)
        (i32.add (local.get $digit) (i32.const 48)))
      (local.set $len (i32.add (local.get $len) (i32.const 1)))
      (local.set $n (i64.div_u (local.get $n) (i64.const 10)))
      (br_if $extract (i64.ne (local.get $n) (i64.const 0))))

    (i32.store (local.get $out) (local.get $write_ptr))
    (i32.store offset=4 (local.get $out) (local.get $len))
  )

  (func $write (param $ptr i32) (param $len i32)
    (local $errno i32)
    (i32.store (i32.const 200) (local.get $ptr))
    (i32.store (i32.const 204) (local.get $len))
    (local.set $errno
      (call $fd_write
        (i32.const 1)
        (i32.const 200)
        (i32.const 1)
        (i32.const 208)))
    (if (i32.ne (local.get $errno) (i32.const 0))
      (then (call $proc_exit (local.get $errno))))
  )

  (func (export "_start")
    (local $errno i32)
    (local $timestamp i64)
    (local $digits_ptr i32)
    (local $digits_len i32)

    (local.set $errno
      (call $clock_time_get
        (i32.const 0)    ;; CLOCKID_REALTIME
        (i64.const 0)
        (i32.const 0)))
    (if (i32.ne (local.get $errno) (i32.const 0))
      (then (call $proc_exit (local.get $errno))))

    (local.set $timestamp (i64.load (i32.const 0)))

    (call $format_u64 (local.get $timestamp) (i32.const 88))
    (local.set $digits_ptr (i32.load (i32.const 88)))
    (local.set $digits_len (i32.load offset=4 (i32.const 88)))

    (call $write (i32.const 64) (i32.const 13))
    (call $write (local.get $digits_ptr) (local.get $digits_len))
    (call $write (i32.const 80) (i32.const 1))
  )
)

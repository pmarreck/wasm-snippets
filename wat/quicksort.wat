(module
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "environ_sizes_get" (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get" (func $environ_get (param i32 i32) (result i32)))

  (memory (export "memory") 16)

  (global $collate_mode (mut i32) (i32.const 0))

  (data (i32.const 458752) "LC_ALL=\00LC_COLLATE=\00C\00en_US.UTF-8\00")
  (data (i32.const 458816) "\0a")

  (func $starts_with (param $str i32) (param $pattern i32) (result i32)
    (local $s i32)
    (local $p i32)
    (local $sc i32)
    (local $pc i32)
    (local.set $s (local.get $str))
    (local.set $p (local.get $pattern))
    (loop $loop
      (local.set $pc (i32.load8_u (local.get $p)))
      (if (i32.eqz (local.get $pc))
        (then (return (i32.const 1))))
      (local.set $sc (i32.load8_u (local.get $s)))
      (if (i32.ne (local.get $sc) (local.get $pc))
        (then (return (i32.const 0))))
      (local.set $s (i32.add (local.get $s) (i32.const 1)))
      (local.set $p (i32.add (local.get $p) (i32.const 1)))
      (br $loop))
    (i32.const 0))

  (func $equals_str (param $a i32) (param $b i32) (result i32)
    (local $ap i32)
    (local $bp i32)
    (local $ac i32)
    (local $bc i32)
    (local.set $ap (local.get $a))
    (local.set $bp (local.get $b))
    (loop $loop
      (local.set $ac (i32.load8_u (local.get $ap)))
      (local.set $bc (i32.load8_u (local.get $bp)))
      (if (i32.ne (local.get $ac) (local.get $bc))
        (then (return (i32.const 0))))
      (if (i32.eqz (local.get $ac))
        (then (return (i32.const 1))))
      (local.set $ap (i32.add (local.get $ap) (i32.const 1)))
      (local.set $bp (i32.add (local.get $bp) (i32.const 1)))
      (br $loop))
    (i32.const 0))

  (func $apply_collate_value (param $value_ptr i32) (result i32)
    (local $first i32)
    (local $first_norm i32)
    (local $second i32)
    (local $idx i32)
    (local $target_char i32)
    (local $value_char i32)
    (local $target_norm i32)
    (local $value_norm i32)

    (local.set $first (i32.load8_u (local.get $value_ptr)))
    (local.set $first_norm (call $to_lower (local.get $first)))
    (if (i32.eq (local.get $first_norm) (i32.const 99)) ;; 'c'
      (then
        (local.set $second (i32.load8_u (i32.add (local.get $value_ptr) (i32.const 1))))
        (if (i32.eqz (local.get $second))
          (then
            (global.set $collate_mode (i32.const 0))
            (return (i32.const 1))))))

    (local.set $idx (i32.const 0))
    (loop $compare
      (local.set $target_char (i32.load8_u (i32.add (i32.const 458774) (local.get $idx))))
      (local.set $value_char (i32.load8_u (i32.add (local.get $value_ptr) (local.get $idx))))
      (local.set $target_norm (call $to_lower (local.get $target_char)))
      (local.set $value_norm (call $to_lower (local.get $value_char)))
      (if (i32.ne (local.get $target_norm) (local.get $value_norm))
        (then (return (i32.const 0))))
      (if (i32.eqz (local.get $target_char))
        (then
          (if (i32.eqz (local.get $value_char))
            (then
              (global.set $collate_mode (i32.const 1))
              (return (i32.const 1)))
            (else (return (i32.const 0))))))
      (local.set $idx (i32.add (local.get $idx) (i32.const 1)))
      (br $compare))
    (i32.const 0))

  (func $init_collation
    (local $errno i32)
    (local $count i32)
    (local $i i32)
    (local $ptr i32)
    (local $value_ptr i32)

    (local.set $errno (call $environ_sizes_get (i32.const 589856) (i32.const 589860)))
    (if (i32.ne (local.get $errno) (i32.const 0))
      (then (return)))
    (local.set $count (i32.load (i32.const 589856)))
    (if (i32.eqz (local.get $count))
      (then (return)))
    (local.set $errno (call $environ_get (i32.const 393216) (i32.const 425984)))
    (if (i32.ne (local.get $errno) (i32.const 0))
      (then (return)))

    (local.set $i (i32.const 0))
    (block $first_done
      (loop $first
        (br_if $first_done (i32.ge_u (local.get $i) (local.get $count)))
        (local.set $ptr (i32.load (i32.add (i32.const 393216) (i32.shl (local.get $i) (i32.const 2)))))
        (if (call $starts_with (local.get $ptr) (i32.const 458752))
          (then
            (local.set $value_ptr (i32.add (local.get $ptr) (i32.const 7)))
            (if (call $apply_collate_value (local.get $value_ptr))
              (then (return)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $first)))

    (local.set $i (i32.const 0))
    (block $second_done
      (loop $second
        (br_if $second_done (i32.ge_u (local.get $i) (local.get $count)))
        (local.set $ptr (i32.load (i32.add (i32.const 393216) (i32.shl (local.get $i) (i32.const 2)))))
        (if (call $starts_with (local.get $ptr) (i32.const 458760))
          (then
            (local.set $value_ptr (i32.add (local.get $ptr) (i32.const 11)))
            (if (call $apply_collate_value (local.get $value_ptr))
              (then (return)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $second))))

  (func $store_line (param $index i32) (param $ptr i32) (param $len i32) (local $addr i32)
    (if (i32.ge_u (local.get $index) (i32.const 16384))
      (then (call $proc_exit (i32.const 2))))
    (local.set $addr
      (i32.add (i32.const 262144) (i32.shl (local.get $index) (i32.const 3))))
    (i32.store (local.get $addr) (local.get $ptr))
    (i32.store offset=4 (local.get $addr) (local.get $len)))

  (func $to_lower (param $ch i32) (result i32)
    (local $c i32)
    (local.set $c (local.get $ch))
    (if (i32.and
          (i32.ge_u (local.get $c) (i32.const 65))
          (i32.le_u (local.get $c) (i32.const 90)))
      (then (return (i32.add (local.get $c) (i32.const 32)))))
    (local.get $c))

  (func $compare_strings (param $aptr i32) (param $alen i32) (param $bptr i32) (param $blen i32) (result i32)
    (local $i i32)
    (local $min_len i32)
    (local $mode i32)
    (local $abyte i32)
    (local $bbyte i32)
    (local $anorm i32)
    (local $bnorm i32)
    (local.set $mode (global.get $collate_mode))
    (local.set $min_len (local.get $alen))
    (if (i32.gt_s (local.get $min_len) (local.get $blen))
      (then (local.set $min_len (local.get $blen))))
    (block $done
      (loop $cmp
        (br_if $done (i32.ge_u (local.get $i) (local.get $min_len)))
        (local.set $abyte (i32.load8_u (i32.add (local.get $aptr) (local.get $i))))
        (local.set $bbyte (i32.load8_u (i32.add (local.get $bptr) (local.get $i))))
        (local.set $anorm (local.get $abyte))
        (local.set $bnorm (local.get $bbyte))
        (if (i32.eq (local.get $mode) (i32.const 1))
          (then
            (local.set $anorm (call $to_lower (local.get $anorm)))
            (local.set $bnorm (call $to_lower (local.get $bnorm)))))
        (if (i32.ne (local.get $anorm) (local.get $bnorm))
          (then (return (i32.sub (local.get $anorm) (local.get $bnorm)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $cmp)))
    (i32.sub (local.get $alen) (local.get $blen)))

  (func $swap_entries (param $i i32) (param $j i32)
    (local $addr_i i32)
    (local $addr_j i32)
    (local $ptr_i i32)
    (local $len_i i32)
    (local $ptr_j i32)
    (local $len_j i32)
    (local.set $addr_i
      (i32.add (i32.const 262144) (i32.shl (local.get $i) (i32.const 3))))
    (local.set $addr_j
      (i32.add (i32.const 262144) (i32.shl (local.get $j) (i32.const 3))))
    (local.set $ptr_i (i32.load (local.get $addr_i)))
    (local.set $len_i (i32.load offset=4 (local.get $addr_i)))
    (local.set $ptr_j (i32.load (local.get $addr_j)))
    (local.set $len_j (i32.load offset=4 (local.get $addr_j)))
    (i32.store (local.get $addr_i) (local.get $ptr_j))
    (i32.store offset=4 (local.get $addr_i) (local.get $len_j))
    (i32.store (local.get $addr_j) (local.get $ptr_i))
    (i32.store offset=4 (local.get $addr_j) (local.get $len_i)))

  (func $partition (param $low i32) (param $high i32) (result i32)
    (local $pivot_ptr i32)
    (local $pivot_len i32)
    (local $store_index i32)
    (local $j i32)
    (local $entry_addr i32)
    (local $cmp i32)
    (local.set $entry_addr
      (i32.add (i32.const 262144) (i32.shl (local.get $high) (i32.const 3))))
    (local.set $pivot_ptr (i32.load (local.get $entry_addr)))
    (local.set $pivot_len (i32.load offset=4 (local.get $entry_addr)))
    (local.set $store_index (local.get $low))
    (local.set $j (local.get $low))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_s (local.get $j) (local.get $high)))
        (local.set $entry_addr
          (i32.add (i32.const 262144) (i32.shl (local.get $j) (i32.const 3))))
        (local.set $cmp
          (call $compare_strings
            (i32.load (local.get $entry_addr))
            (i32.load offset=4 (local.get $entry_addr))
            (local.get $pivot_ptr)
            (local.get $pivot_len)))
        (if (i32.le_s (local.get $cmp) (i32.const 0))
          (then
            (call $swap_entries (local.get $j) (local.get $store_index))
            (local.set $store_index (i32.add (local.get $store_index) (i32.const 1)))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $loop)))
    (call $swap_entries (local.get $store_index) (local.get $high))
    (local.get $store_index))

  (func $quicksort (param $low i32) (param $high i32) (local $p i32)
    (if (i32.lt_s (local.get $low) (local.get $high))
      (then
        (local.set $p (call $partition (local.get $low) (local.get $high)))
        (if (i32.gt_s (local.get $p) (local.get $low))
          (then (call $quicksort (local.get $low) (i32.sub (local.get $p) (i32.const 1)))))
        (if (i32.lt_s (local.get $p) (local.get $high))
          (then (call $quicksort (i32.add (local.get $p) (i32.const 1)) (local.get $high)))))))

  (func (export "_start")
    (local $read_total i32)
    (local $remaining i32)
    (local $errno i32)
    (local $nread i32)
    (local $pos i32)
    (local $start_line i32)
    (local $line_count i32)
    (local $had_newline i32)
    (local $byte i32)
    (local $entry_addr i32)
    (local $ptr i32)
    (local $len i32)
    (local $needs_newline i32)
    (local $last_index i32)

    (call $init_collation)

    (local.set $read_total (i32.const 0))
    (block $read_done
      (loop $read_loop
        (local.set $remaining (i32.sub (i32.const 262144) (local.get $read_total)))
        (br_if $read_done (i32.eqz (local.get $remaining)))
        (i32.store (i32.const 589824) (i32.add (i32.const 0) (local.get $read_total)))
        (i32.store offset=4 (i32.const 589824) (local.get $remaining))
        (local.set $errno
          (call $fd_read (i32.const 0) (i32.const 589824) (i32.const 1) (i32.const 589832)))
        (if (i32.ne (local.get $errno) (i32.const 0))
          (then (call $proc_exit (i32.const 1))))
        (local.set $nread (i32.load (i32.const 589832)))
        (br_if $read_done (i32.eqz (local.get $nread)))
        (local.set $read_total (i32.add (local.get $read_total) (local.get $nread)))
        (br $read_loop)))

    (local.set $had_newline (i32.const 0))
    (if (i32.gt_u (local.get $read_total) (i32.const 0))
      (then
        (local.set $pos (i32.sub (local.get $read_total) (i32.const 1)))
        (local.set $byte (i32.load8_u (local.get $pos)))
        (if (i32.eq (local.get $byte) (i32.const 10))
          (then (local.set $had_newline (i32.const 1))))))

    (local.set $start_line (i32.const 0))
    (local.set $pos (i32.const 0))
    (local.set $line_count (i32.const 0))
    (block $parse_done
      (loop $parse
        (br_if $parse_done (i32.ge_u (local.get $pos) (local.get $read_total)))
        (local.set $byte (i32.load8_u (local.get $pos)))
        (if (i32.eq (local.get $byte) (i32.const 10))
          (then
            (call $store_line
              (local.get $line_count)
              (local.get $start_line)
              (i32.sub (local.get $pos) (local.get $start_line)))
            (local.set $line_count (i32.add (local.get $line_count) (i32.const 1)))
            (local.set $start_line (i32.add (local.get $pos) (i32.const 1)))))
        (local.set $pos (i32.add (local.get $pos) (i32.const 1)))
        (br $parse)))

    (if (i32.lt_u (local.get $start_line) (local.get $read_total))
      (then
        (call $store_line
          (local.get $line_count)
          (local.get $start_line)
          (i32.sub (local.get $read_total) (local.get $start_line)))
        (local.set $line_count (i32.add (local.get $line_count) (i32.const 1)))))

    (if (i32.gt_s (local.get $line_count) (i32.const 1))
      (then (call $quicksort (i32.const 0) (i32.sub (local.get $line_count) (i32.const 1)))))

    (local.set $pos (i32.const 0))
    (local.set $last_index (i32.sub (local.get $line_count) (i32.const 1)))
    (block $emit_done
      (loop $emit
        (br_if $emit_done (i32.ge_u (local.get $pos) (local.get $line_count)))
        (local.set $entry_addr
          (i32.add (i32.const 262144) (i32.shl (local.get $pos) (i32.const 3))))
        (local.set $ptr (i32.load (local.get $entry_addr)))
        (local.set $len (i32.load offset=4 (local.get $entry_addr)))
        (i32.store (i32.const 589840) (local.get $ptr))
        (i32.store offset=4 (i32.const 589840) (local.get $len))
        (local.set $needs_newline (i32.const 0))
        (if (i32.lt_u (local.get $pos) (local.get $last_index))
          (then (local.set $needs_newline (i32.const 1)))
          (else
            (if (i32.eq (local.get $last_index) (local.get $pos))
              (then (local.set $needs_newline (local.get $had_newline))))))
        (local.set $errno
          (call $fd_write
            (i32.const 1)
            (i32.const 589840)
            (i32.const 1)
            (i32.const 589880)))
        (if (i32.ne (local.get $errno) (i32.const 0))
          (then (call $proc_exit (i32.const 1))))
        (if (i32.ne (local.get $needs_newline) (i32.const 0))
          (then
            (i32.store (i32.const 589848) (i32.const 458816))
            (i32.store offset=4 (i32.const 589848) (i32.const 1))
            (local.set $errno
              (call $fd_write
                (i32.const 1)
                (i32.const 589848)
                (i32.const 1)
                (i32.const 589880)))
            (if (i32.ne (local.get $errno) (i32.const 0))
              (then (call $proc_exit (i32.const 1))))))
        (local.set $pos (i32.add (local.get $pos) (i32.const 1)))
        (br $emit)))
  )
)

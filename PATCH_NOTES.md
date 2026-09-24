# Patch notes: kernel-7.2 `strncpy()` replacements

Kernel 7.2 removed `strncpy()` from the kernel API, so nvidia-580.173.02
no longer compiles. Each replacement below was chosen for the specific
operation at that site — not as a blanket `strncpy` → `strscpy` swap.
Applies to nvidia-580.173.02 only; `git apply` in `gpu-fix-nvidia.sh`
refuses any other source tree.

Rule of thumb used throughout:

- Destination holds a **NUL-terminated C string** → `strscpy()` (always
  terminates, unlike `strncpy()`).
- Operation copies a **fixed number of bytes that are not a C string**
  (termination handled separately) → `memcpy()`.
- Wrapper whose contract **returns the destination pointer** → split the
  call, because `strscpy()` returns a length (`ssize_t`), not `dest`.

## 0001 — `nvidia/os-interface.c`, `os_get_current_process_name()`

- Original: `strncpy(buf, current->comm, len - 1); buf[len - 1] = '\0';`
- Replacement: `strscpy(buf, current->comm, len);`
- Why: `buf` holds a NUL-terminated task name. The old code copied at most
  `len - 1` bytes and forced termination; `strscpy()` with the full length
  does exactly that in one call and always terminates.
- Assumptions: `len > 0` (callers pass real buffers; there are no in-tree
  callers — this is called from the binary blob — so this follows from the
  `(char *buf, NvU32 len)` contract). Truncation reporting differs
  (`strscpy()` returns `-E2BIG`, old code was silent) but the function
  returns `void`, so no caller can observe it.
- Cosmetic: the patch leaves one blank line where the deleted
  `buf[len - 1]` line was, preserving byte-fidelity with the tested tree.

## 0002a — `nvidia/linux_nvswitch.c`, `nvswitch_os_read_registry_dword()`

- Original: `strncpy(regkey_val, regkey_val_start, regkey_val_len);`
- Replacement: `memcpy(regkey_val, regkey_val_start, regkey_val_len);`
- Why: this is **not** string handling. The source is a substring slice
  (`regkey_val_start..regkey_val_end`) that holds no NUL, and the very next
  line writes the terminator explicitly
  (`regkey_val[regkey_val_len] = '\0'`). `strncpy()` here copied exactly
  `regkey_val_len` bytes with no padding; `memcpy()` does exactly that.
- Assumptions: `1 <= regkey_val_len <= NVSWITCH_REGKEY_VALUE_LEN` (10),
  enforced by the guard two lines above, against
  `char regkey_val[NVSWITCH_REGKEY_VALUE_LEN + 1]` — unchanged by this patch.

## 0002b — `nvidia/linux_nvswitch.c`, `nvswitch_os_strncpy()`

- Original: `return strncpy(dest, src, length);`
- Replacement: `strscpy(dest, src, length); return dest;`
- Why: the wrapper's contract returns `dest`, but `strscpy()` returns a
  byte count, so the call must be split. `strscpy()` additionally
  guarantees termination where `strncpy()` did not (silent truncation past
  `length` previously left the buffer unterminated) — strictly safer for a
  function named "strncpy".
- Limitations: no in-tree callers exist, so this is preserved purely for
  interface compatibility. If an out-of-tree caller depended on
  `strncpy()`'s exact fill/padding behavior, it would see different bytes;
  no such caller is known.

## 0003 — `nvidia-modeset/nvidia-modeset-linux.c`, `nvkms_strncpy()`

- Same pattern and reasoning as 0002b: `return strncpy(dest, src, n);`
  becomes `strscpy(dest, src, n); return dest;`.
- Limitations: declared in `nvidia-modeset-os-interface.h`, defined once,
  zero in-tree call sites — kept for interface compatibility. Same
  padding-behavior caveat as 0002b; no such caller is known.

## 0004 — `nvidia-uvm/uvm_pmm_gpu.c`, `init_chunk_split_cache_level()`

- Original: `strncpy(name, "uvm_gpu_chunk_t", sizeof(name) - 1);`
- Replacement: `strscpy(name, "uvm_gpu_chunk_t", sizeof(name));`
- Why: `name` (`char name[32]`) holds a NUL-terminated cache label and the
  source is a 15-character literal — far shorter than the field — so both
  versions copy the literal plus terminator. `strscpy()` with the full
  field size states the intent directly instead of relying on
  zero-initialisation plus `size - 1`.
- Assumptions: field larger than the literal (32 > 16), verified in-tree.
  The `else` branch already used `snprintf()` with full size — this makes
  the two branches consistent.

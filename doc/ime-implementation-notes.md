# Integrated Matrix Extension (IME / Zvvm) implementation notes

This is the status note for the initial Sail implementation loop for the draft RISC-V Integrated Matrix Extension. It documents what is implemented in this tree, how it is tested, and the known limitations that should guide the next development loop.

## Implemented pieces

- Draft extension plumbing:
  - `Ext_Zvvmm` for integer matrix multiply-accumulate.
  - `Ext_Zvvmtls` for order-preserving tile load/store.
  - `Ext_Zvvmttls` and `Ext_Zvvfmm` are registered for configuration/ISA-string plumbing, but their instructions are not implemented in this loop.
- IME `vtype` high fields:
  - `vlambda` in bits `XLEN-2:XLEN-4`.
  - `vbs` in bit `XLEN-5`.
  - `altfmt_A` in bit `XLEN-6`.
  - `altfmt_B` in bit `XLEN-7`.
- Lambda helper behavior:
  - Encodings map as `001=1`, `010=2`, `011=4`, `100=8`, `101=16`, `110=32`, `111=64`.
  - `000` is treated as dynamic/preserve where appropriate and selects the largest supported legal lambda when a concrete vtype is written.
- Vector configuration interaction:
  - `vsetvli`/`vsetivli` preserve the existing IME fields while updating the standard vector fields.
  - `vsetvl` accepts the full `vtype` value, including IME fields, and applies the lambda WARL selection helper.
- Order-preserving tile load/store:
  - `vmtl.v` and `vmts.v` decode for `Zvvmtls`.
  - Implemented for the standard vector element widths handled by the vector model (`SEW=8,16,32,64`).
  - Uses the order-preserving memory address formula with `linesize = lambda * LMUL` and `mem_off = (i / linesize) * LD + (i % linesize)`.
- Basic non-widening integer matrix multiply-accumulate:
  - `vmmacc.vv` decodes for `Zvvmm`.
  - Implemented for W=1, `SEW=8,16,32,64`, integer LMUL `1,2,4,8` where the derived accumulator group is legal.
  - Uses the specification-shaped geometry: `K_eff = lambda * LMUL`, `M = VLEN / (SEW * lambda)`, `N = VL / K_eff`, `N_max = M`, `EMUL_C = VLEN / (SEW * lambda^2)`.
  - Uses `mat_A_idx`, `mat_B_idx`, and `mat_C_idx` helpers based on `tile_reg_idx`.
  - `altfmt_A=0`/`altfmt_B=0` select signed operands; `altfmt_A=1`/`altfmt_B=1` select unsigned operands.
  - Accumulation is written back modulo the destination SEW.

## Targeted tests

The initial IME tests live under `test/first_party/src/`:

- `test_ime_tile_ls.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, and `LD=4`.
  - Checks `vmtl.v` loads offsets `[0,1,4,5]` and `vmts.v` stores only those offsets.
- `test_ime_vmmacc.S`
  - Configures `SEW=32`, `LMUL=1`, `lambda=2`, `VL=4`, `VLEN=256`.
  - Checks a signed 4x2 by 2x2 non-widening GEMM and verifies inactive C tile columns remain untouched.
- `test/first_party/src/ime_override.json`
  - Enables `Zvvmm` and `Zvvmtls` for the targeted first-party tests.
- `model/unit_tests/test_ime_vtype.sail`
  - Covers lambda encoding helpers, lambda WARL selection, and the addressability of the new high `vtype` fields.

## How to run the targeted IME checks

From the repository root:

```sh
cmake --build build --target generated_sail_riscv_model sail_riscv_sim build_rv64d_test_ime_tile_ls.S build_rv64d_test_ime_vmmacc.S -j$(nproc)
ctest --test-dir build -R 'first_party_rv64d_test_ime_(tile_ls|vmmacc)\.S' --output-on-failure -V
```

These commands assume the build directory has already been configured and that the local Sail and RISC-V first-party test toolchain prerequisites are available. The simulator runs the IME tests with:

```text
--enable-experimental-extensions --config build/config/rv64d_v256_e64.json --config-override test/first_party/src/ime_override.json
```

Latest targeted verification in this workspace completed with both IME tests passing:

```text
100% tests passed, 0 tests failed out of 2
```

## Known limitations and shortcuts

- Only the order-preserving tile load/store mode is implemented. Transposing tile load/store (`vmttl.v`, `vmtts.v`) currently decode to illegal instruction through the mode check or remain unimplemented.
- Only `vmmacc.vv` W=1 non-widening integer GEMM is implemented. Widening integer instructions (`vwmmacc.vv`, `vqmmacc.vv`, `v8wmmacc.vv`), floating-point matrix instructions, and microscaling behavior are out of scope.
- `vmmacc.vv` requires `vm=1` and `vstart=0` as in the draft restriction used for this loop; masked matrix multiply is not implemented.
- Integer row/subextension legality is simplified: enabling `Zvvmm` enables the initial non-widening integer rows implemented here instead of modeling each fine-grained row as a separate configuration flag.
- C tile-tail columns are left undisturbed by the W=1 implementation; this matches the targeted test and should be revisited if the final spec requires tail-agnostic updates for inactive physical columns.
- The first-party tests use `.word` instruction encodings for the new IME instructions so they do not depend on external assembler mnemonic support.
- The implementation is still a targeted first loop, not a full conformance suite for all legal lambdas, LMULs, element widths, masking, traps, and exception restart behavior.

## Next-loop checklist

1. Implement and test transposing tile load `vmttl.v`.
2. Implement and test transposing tile store `vmtts.v`.
3. Add widening integer matrix tests and implement `vwmmacc.vv`.
4. Add quad-widening integer matrix tests and implement `vqmmacc.vv`.
5. Add octuple-widening integer matrix tests and implement `v8wmmacc.vv`.
6. Add the floating-point matrix instruction family.
7. Add microscaling support and the associated `vtype.vbs` behavior.
8. Replace simplified row/subextension legality with the full extension implication/configuration table once the draft naming is settled.
9. Expand tests across lambda/LMUL/SEW combinations, masked/tail behavior, reserved encodings, and trap/restart cases.

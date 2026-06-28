#include "common/encoding.h"

# Test for IME unscaled floating-point matrix multiply-accumulate (vfmmacc.vv).
#
# Only the first FP step is exercised: FP32 same-width (W=1, SEW=32,
# altfmt_A=altfmt_B=0, default FP32 C, vm=1).
#
# Geometry used here:
#   SEW=32, LMUL=1, lambda=2, VL=4
#   VLEN=256 => M_tile=4, K_eff=2, N_tile=2, N_tile_max=4, EMUL_C=2
#
# Disclosed reference profile: G=1, psm=0, rnd=frm. All values are chosen to be
# exactly representable in FP32 with exact products/sums, so the result is
# rounding-mode-independent.
#
# A_tile (4x2, row-major):
#   [ 1.0,  2.0,
#     3.0,  4.0,
#     5.0,  6.0,
#     7.0,  8.0 ]
# B_tile^T stored column-major as mat_B_idx(k, j) = tile_reg_idx(j*K_eff + k):
#   column 0: [  9.0, 11.0 ]
#   column 1: [ 10.0, 12.0 ]
#
# Expected active results C += A * B^T (C initialised to 0 in the active half):
#   row0: [  31.0,  34.0 ]
#   row1: [  71.0,  78.0 ]
#   row2: [ 111.0, 122.0 ]
#   row3: [ 151.0, 166.0 ]
# The inactive physical C columns (the second EMUL_C register, v17) are seeded
# with a sentinel pattern and must remain unchanged.

.global main
main:
    mv t6, ra

    # Enable vector + floating-point state.
    li t0, (MSTATUS_VS | MSTATUS_FS)
    csrs mstatus, t0

    # Clear accrued FP exception flags before the first subtest.
    csrw fflags, x0

    # =====================================================================
    # Subtest 1: full VL=4, two active C columns, exact FP32 GEMM.
    # =====================================================================

    # --- Load the initial C tile into v16 as an EMUL_C=2 group ---
    # vtype: lambda=2, SEW=32, LMUL=2, ta, ma
    li t0, 0x20000000000000D1
    la a0, c_init
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)

    # --- Load A tile into v8 as LMUL=1 ---
    li t0, 0x20000000000000D0 # lambda=2, SEW=32, LMUL=1, ta, ma
    la a0, a_tile
    li a1, 8
    vsetvl t2, a1, t0
    vle32.v v8, (a0)

    # --- Load B tile^T into v12 as LMUL=1 ---
    la a0, b_tile
    li a1, 4
    vsetvl t2, a1, t0
    vle32.v v12, (a0)

    # --- Execute vfmmacc.vv v16, v8, v12 (VL=4) ---
    # Encoding: funct6=0x14, vm=1, vs2=12, vs1=8, funct3=0x1 (OPFVV),
    # vd=16, opcode=0x57 => .word 0x52c41857
    li a1, 4
    vsetvl t2, a1, t0
    .word 0x52c41857

    # --- Store the C tile back out of v16 ---
    li t0, 0x20000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    # --- Verify active columns against the expected FP32 bit patterns ---
    la a0, c_out
    la a2, expected
    li a3, 8
1:
    lw t0, 0(a0)
    lw t1, 0(a2)
    li a4, 1
    bne t0, t1, fail
    addi a0, a0, 4
    addi a2, a2, 4
    addi a3, a3, -1
    bnez a3, 1b

    # --- Verify inactive physical C columns (v17 half) are unchanged ---
    la a0, c_out
    la a2, c_init
    addi a0, a0, 32
    addi a2, a2, 32
    li a3, 8
2:
    lw t0, 0(a0)
    lw t1, 0(a2)
    li a4, 2
    bne t0, t1, fail
    addi a0, a0, 4
    addi a2, a2, 4
    addi a3, a3, -1
    bnez a3, 2b

    # =====================================================================
    # Subtest 2: limited VL=lambda*LMUL=2 => N_tile=1, one active C column.
    # Inactive column 1 of B and the inactive C elements hold signalling-NaN
    # sentinels; they must not be touched and must not raise FP flags.
    # =====================================================================

    csrw fflags, x0

    # --- Load C2 into v16 as an EMUL_C=2 group. Active column-0 elements are
    # zero accumulators; inactive elements are sNaN sentinels. ---
    li t0, 0x20000000000000D1
    la a0, c_init2
    li a1, 16
    vsetvl t2, a1, t0
    vle32.v v16, (a0)

    # --- Reload A tile (v8) and B2 tile (v12) at LMUL=1 ---
    li t0, 0x20000000000000D0
    la a0, a_tile
    li a1, 8
    vsetvl t2, a1, t0
    vle32.v v8, (a0)

    la a0, b_tile2
    li a1, 4
    vsetvl t2, a1, t0
    vle32.v v12, (a0)

    # --- Execute vfmmacc.vv v16, v8, v12 with VL=2 ---
    li a1, 2
    vsetvl t2, a1, t0
    .word 0x52c41857

    # --- Store C2 back ---
    li t0, 0x20000000000000D1
    la a0, c_out
    li a1, 16
    vsetvl t2, a1, t0
    vse32.v v16, (a0)

    # Active C column 0 lands in flat elements 0,2,4,6 = [31,71,111,151].
    la a0, c_out
    lw t0, 0(a0)
    li t1, 0x41f80000   # 31.0
    li a4, 3
    bne t0, t1, fail
    lw t0, 8(a0)
    li t1, 0x428e0000   # 71.0
    li a4, 4
    bne t0, t1, fail
    lw t0, 16(a0)
    li t1, 0x42de0000   # 111.0
    li a4, 5
    bne t0, t1, fail
    lw t0, 24(a0)
    li t1, 0x43170000   # 151.0
    li a4, 6
    bne t0, t1, fail

    # Inactive column 1 (flat 1,3,5,7) and the v17 half (flat 8..15) keep the
    # sentinel pattern from c_init2.
    la a0, c_out
    la a2, c_init2
    li a3, 16
    li a5, 0
3:
    # Active elements are flat 0,2,4,6 (even and < 8); skip those, check the
    # rest still hold the sentinel pattern.
    li t3, 8
    bge a5, t3, 4f          # flat >= 8 is always inactive -> check
    andi t2, a5, 1
    beqz t2, 5f             # flat < 8 and even -> active -> skip
4:
    lw t0, 0(a0)
    lw t1, 0(a2)
    li a4, 7
    bne t0, t1, fail
5:
    addi a0, a0, 4
    addi a2, a2, 4
    addi a5, a5, 1
    addi a3, a3, -1
    bnez a3, 3b

    # --- No FP exception flags must have accrued in subtest 2 ---
    csrr t0, fflags
    li a4, 8
    bnez t0, fail

    li a0, 0
    mv ra, t6
    ret

fail:
    mv a0, a4
    mv ra, t6
    ret

.balign 64
a_tile:
    .float 1, 2, 3, 4, 5, 6, 7, 8
b_tile:
    .float 9, 11, 10, 12
b_tile2:
    .float 9, 11
    .word 0x7fa00000, 0x7fa00000   # sNaN sentinels in inactive column 1
expected:
    .float 31, 34, 71, 78, 111, 122, 151, 166
c_init:
    .float 0, 0, 0, 0
    .float 0, 0, 0, 0
    # inactive physical C columns (v17 half) sentinel pattern:
    .word 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef
    .word 0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef
c_init2:
    .word 0x00000000, 0x7fa00000, 0x00000000, 0x7fa00000
    .word 0x00000000, 0x7fa00000, 0x00000000, 0x7fa00000
    .word 0x7fa00000, 0x7fa00000, 0x7fa00000, 0x7fa00000
    .word 0x7fa00000, 0x7fa00000, 0x7fa00000, 0x7fa00000
c_out:
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0
    .word 0, 0, 0, 0

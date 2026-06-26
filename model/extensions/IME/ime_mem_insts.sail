// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) tile load/store instructions.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

// vmtl.v — order-preserving tile load
union clause instruction = VMTLTYPE : (bits(3), bits(1), ime_tile_mode, bits(1), regidx, regidx, vregidx)

mapping clause encdec = VMTLTYPE(lambda_field, L, mode, vm, rs2, rs1, vd)
  <-> lambda_field @ L @ encdec_ime_tile_mode(mode) @ vm @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b111 @ encdec_vreg(vd) @ 0b0000111
  when currentlyEnabled(Ext_Zvvmtls)

function clause execute VMTLTYPE(lambda_field, L, mode, vm, rs2, rs1, vd) = {
  if mode != IME_TILE_ORDERED then return Illegal_Instruction();

  let SEW = get_sew();
  let SEW_bytes = get_sew_bytes();
  let LMUL_pow = get_lmul_pow();
  let EMUL_pow = LMUL_pow;
  let num_elem = get_num_elem(EMUL_pow, SEW);
  let lambda_value = if L == 0b1 then ime_lambda_field_to_value(lambda_field) else ime_lambda_field_to_value(vtype[vlambda]);

  if not(valid_vtype()) |
     not(valid_reg_group(vd, EMUL_pow)) |
     not(ime_lambda_supported_value_for_vsew(lambda_value, vtype[vsew])) |
     lambda_value == 0
  then return Illegal_Instruction();

  let LMUL = 2 ^ max(LMUL_pow, 0);
  let linesize = lambda_value * LMUL;
  if linesize == 0 then return Illegal_Instruction();

  let vm_val = read_vmask(num_elem, vm, zvreg);
  let vd_val = read_vreg(num_elem, SEW, LMUL_pow, vd);

  let 'n = num_elem;
  let 'm = SEW;
  let (result, mask) : (vector('n, bits('m)), bits('n)) = init_masked_result(num_elem, SEW, LMUL_pow, vd_val, vm_val);

  let LD = unsigned(X(rs2));

  foreach (i from 0 to (num_elem - 1)) {
    if mask[i] == 0b1 then {
      set_vstart(to_bits_unsafe(16, i));
      var row : int = 0;
      var remaining : int = i;
      while (remaining >= linesize) {
        row = row + 1;
        remaining = remaining - linesize
      };
      let mem_off = row * LD + remaining;
      let byte_offset = mem_off * SEW_bytes;
      match SEW {
        8  => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 1, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(8, i, vd, elem),
               Err(e)   => return e,
             },
        16 => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 2, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(16, i, vd, elem),
               Err(e)   => return e,
             },
        32 => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 4, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(32, i, vd, elem),
               Err(e)   => return e,
             },
        64 => match vmem_read(rs1, to_bits_unsafe(xlen, byte_offset), 8, Load(Vector), false, false, false) {
               Ok(elem) => write_single_element(64, i, vd, elem),
               Err(e)   => return e,
             },
      }
    } else {
      write_single_element(SEW, i, vd, result[i])
    }
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}

// vmts.v — order-preserving tile store
union clause instruction = VMTSTYPE : (bits(3), bits(1), ime_tile_mode, bits(1), regidx, regidx, vregidx)

mapping clause encdec = VMTSTYPE(lambda_field, L, mode, vm, rs2, rs1, vs3)
  <-> lambda_field @ L @ encdec_ime_tile_mode(mode) @ vm @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b111 @ encdec_vreg(vs3) @ 0b0100111
  when currentlyEnabled(Ext_Zvvmtls)

function clause execute VMTSTYPE(lambda_field, L, mode, vm, rs2, rs1, vs3) = {
  if mode != IME_TILE_ORDERED then return Illegal_Instruction();

  let SEW = get_sew();
  let SEW_bytes = get_sew_bytes();
  let LMUL_pow = get_lmul_pow();
  let EMUL_pow = LMUL_pow;
  let num_elem = get_num_elem(EMUL_pow, SEW);
  let lambda_value = if L == 0b1 then ime_lambda_field_to_value(lambda_field) else ime_lambda_field_to_value(vtype[vlambda]);

  if not(valid_vtype()) |
     not(valid_reg_group(vs3, EMUL_pow)) |
     not(ime_lambda_supported_value_for_vsew(lambda_value, vtype[vsew])) |
     lambda_value == 0
  then return Illegal_Instruction();

  let LMUL = 2 ^ max(LMUL_pow, 0);
  let linesize = lambda_value * LMUL;
  if linesize == 0 then return Illegal_Instruction();

  let vm_val = read_vmask(num_elem, vm, zvreg);
  let 'n = num_elem;
  let mask : bits('n) = init_masked_source(num_elem, LMUL_pow, vm_val);
  let LD = unsigned(X(rs2));

  foreach (i from 0 to (num_elem - 1)) {
    if mask[i] == 0b1 then {
      set_vstart(to_bits_unsafe(16, i));
      var row : int = 0;
      var remaining : int = i;
      while (remaining >= linesize) {
        row = row + 1;
        remaining = remaining - linesize
      };
      let mem_off = row * LD + remaining;
      let byte_offset = mem_off * SEW_bytes;
      let data = read_single_element(SEW, i, vs3);
      match SEW {
        8  => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 1, data[7 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
        16 => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 2, data[15 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
        32 => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 4, data[31 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
        64 => match vmem_write(rs1, to_bits_unsafe(xlen, byte_offset), 8, data[63 .. 0], Store(Vector), false, false, false) {
               Ok(true)  => (),
               Ok(false) => internal_error(__FILE__, __LINE__, "store got false from vmem_write"),
               Err(e)    => return e,
             },
      }
    }
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}


// Shared W=1 integer GEMM executor for vmmacc.vv. This mirrors the
// specification's int_gemm helper: decode geometry from vtype/vl, loop over
// active C columns j, rows i, and K, and use mat_A/mat_B/mat_C indexing.
function execute_ime_vmmacc_w1(
  EEW_C : sew_bitsize,
  lambda_value : nat,
  LMUL : nat,
  signed_A : bool,
  signed_B : bool,
  vs1 : vregidx,
  vs2 : vregidx,
  vd : vregidx
) -> ExecutionResult = {
  let epr_C : nat = vlen / EEW_C;
  let K_eff : nat = lambda_value * LMUL;
  assert(lambda_value > 0);
  assert(LMUL > 0);
  assert(EEW_C * lambda_value > 0);
  assert(EEW_C * lambda_value * lambda_value > 0);
  assert(K_eff > 0);
  let M : nat = vlen / (EEW_C * lambda_value);
  let N_max : nat = M;
  let EMUL_C : nat = vlen / (EEW_C * lambda_value * lambda_value);
  let N : nat = unsigned(vl) / K_eff;
  let EMUL_C_pow = ime_group_size_to_pow(EMUL_C);

  if K_eff == 0 |
     M == 0 |
     N == 0 |
     unsigned(vl) % K_eff != 0 |
     N > N_max |
     not(ime_group_size_legal(EMUL_C)) |
     not(valid_reg_group(vd, EMUL_C_pow))
  then return Illegal_Instruction();

  foreach (j from 0 to (N - 1)) {
    foreach (i from 0 to (M - 1)) {
      let c_flat = ime_mat_C_idx(i, j, N_max, EMUL_C, lambda_value, epr_C);
      var acc : int = signed(read_single_element(EEW_C, c_flat, vd));
      foreach (k from 0 to (K_eff - 1)) {
        let a_flat = ime_mat_A_idx(i, k, K_eff, LMUL, lambda_value, epr_C);
        let b_flat = ime_mat_B_idx(k, j, K_eff, LMUL, lambda_value, epr_C);
        let a_bits = read_single_element(EEW_C, a_flat, vs1);
        let b_bits = read_single_element(EEW_C, b_flat, vs2);
        let a_val = if signed_A then signed(a_bits) else unsigned(a_bits);
        let b_val = if signed_B then signed(b_bits) else unsigned(b_bits);
        acc = acc + a_val * b_val
      };
      write_single_element(EEW_C, c_flat, vd, to_bits_unsafe(EEW_C, acc))
    }
  };

  set_vstart(zeros());
  RETIRE_SUCCESS
}

// vmmacc.vv — non-widening integer matrix multiply-accumulate.
// This is the first concrete member of the common IME GEMM family described
// in the specification's Sail starting point under integrated-matrix-insns.
union clause instruction = IMEVMMACCTYPE : (bits(1), vregidx, vregidx, vregidx)

mapping clause encdec = IMEVMMACCTYPE(vm, vs2, vs1, vd)
  <-> 0b111000 @ vm @ encdec_vreg(vs2) @ encdec_vreg(vs1) @ 0b000 @ encdec_vreg(vd) @ 0b1010111
  when currentlyEnabled(Ext_Zvvmm)

mapping clause assembly = IMEVMMACCTYPE(vm, vs2, vs1, vd)
  <-> "vmmacc.vv" ^ spc() ^ vreg_name(vd) ^ sep() ^ vreg_name(vs1) ^ sep() ^ vreg_name(vs2) ^ maybe_vmask(vm)

function clause execute IMEVMMACCTYPE(vm, vs2, vs1, vd) = {
  let SEW = get_sew();
  let LMUL_pow = get_lmul_pow();
  let lambda_value = ime_lambda_field_to_value(vtype[vlambda]);
  let lambda_nat = ime_lambda_field_to_nat(vtype[vlambda]);
  let LMUL = ime_lmul_value_nat(LMUL_pow);
  let signed_A = vtype[altfmt_A] == 0b0;
  let signed_B = vtype[altfmt_B] == 0b0;

  if vm != 0b1 |
     not(valid_vtype()) |
     unsigned(vstart) != 0 |
     lambda_value == 0 |
     LMUL == 0 |
     not(valid_reg_group(vs1, LMUL_pow)) |
     not(valid_reg_group(vs2, LMUL_pow))
  then return Illegal_Instruction();

  match SEW {
    8  => execute_ime_vmmacc_w1(8, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
    16 => execute_ime_vmmacc_w1(16, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
    32 => execute_ime_vmmacc_w1(32, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
    64 => execute_ime_vmmacc_w1(64, lambda_nat, LMUL, signed_A, signed_B, vs1, vs2, vd),
  }
}

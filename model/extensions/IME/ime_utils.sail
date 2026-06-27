// =======================================================================================
// Integrated Matrix Extension (IME / Zvvm) shared helpers.
// SPDX-License-Identifier: BSD-2-Clause
// =======================================================================================

function ime_vtype_fields_enabled() -> bool =
  currentlyEnabled(Ext_Zvvmm) |
  currentlyEnabled(Ext_Zvvmtls) |
  currentlyEnabled(Ext_Zvvmttls) |
  currentlyEnabled(Ext_Zvvfmm)

function ime_lambda_field_to_value(field : bits(3)) -> int =
  match field {
    0b000 => 0,
    0b001 => 1,
    0b010 => 2,
    0b011 => 4,
    0b100 => 8,
    0b101 => 16,
    0b110 => 32,
    0b111 => 64,
  }

function ime_lambda_value_to_field(value : int) -> bits(3) =
  if value == 1 then 0b001
  else if value == 2 then 0b010
  else if value == 4 then 0b011
  else if value == 8 then 0b100
  else if value == 16 then 0b101
  else if value == 32 then 0b110
  else if value == 64 then 0b111
  else 0b000

function ime_lambda_supported_value_for_vsew(lambda_value : int, sew : bits(3)) -> bool = {
  let sew_bits = 2 ^ (unsigned(sew) + 3);
  lambda_value > 0 & lambda_value <= (vlen / sew_bits)
}

function ime_lambda_supported_for_vsew(field : bits(3), sew : bits(3)) -> bool =
  ime_lambda_supported_value_for_vsew(ime_lambda_field_to_value(field), sew)

function ime_largest_supported_lambda_for_vsew(sew : bits(3)) -> bits(3) =
  if ime_lambda_supported_value_for_vsew(64, sew) then 0b111
  else if ime_lambda_supported_value_for_vsew(32, sew) then 0b110
  else if ime_lambda_supported_value_for_vsew(16, sew) then 0b101
  else if ime_lambda_supported_value_for_vsew(8, sew) then 0b100
  else if ime_lambda_supported_value_for_vsew(4, sew) then 0b011
  else if ime_lambda_supported_value_for_vsew(2, sew) then 0b010
  else 0b001

function ime_select_vtype_lambda(requested : bits(3), sew : bits(3)) -> bits(3) =
  if requested != 0b000 & ime_lambda_supported_for_vsew(requested, sew)
  then requested
  else ime_largest_supported_lambda_for_vsew(sew)

function ime_vtype_fields_clear(vt : Vtype) -> bool =
  vt[vlambda] == 0b000 &
  vt[vbs] == 0b0 &
  vt[altfmt_A] == 0b0 &
  vt[altfmt_B] == 0b0

function ime_vtype_fields_legal(vt : Vtype) -> bool =
  ime_vtype_fields_enabled() | ime_vtype_fields_clear(vt)

function ime_lambda_field_to_nat(field : bits(3)) -> nat =
  match field {
    0b000 => 0,
    0b001 => 1,
    0b010 => 2,
    0b011 => 4,
    0b100 => 8,
    0b101 => 16,
    0b110 => 32,
    0b111 => 64,
  }

function ime_lmul_value_nat(LMUL_pow : int) -> nat =
  if LMUL_pow == 0 then 1
  else if LMUL_pow == 1 then 2
  else if LMUL_pow == 2 then 4
  else if LMUL_pow == 3 then 8
  else 0

function ime_group_size_to_pow(group : nat) -> int =
  if group == 1 then 0
  else if group == 2 then 1
  else if group == 4 then 2
  else if group == 8 then 3
  else 4

function ime_group_size_legal(group : nat) -> bool =
  group == 1 | group == 2 | group == 4 | group == 8

// Map a sequential tile element index to the flat architectural element
// index within a vector register group. This follows the Sail starting point
// in the IME specification: tile_reg_idx(i, LMUL, lambda, elems_per_reg).
function ime_tile_reg_idx(i : nat, group : nat, lambda_value : nat, elems_per_reg : nat) -> nat = {
  let linesize : nat = lambda_value * group;
  assert(linesize > 0);
  assert(lambda_value > 0);
  let line : nat = i / linesize;
  let elem_in_line : nat = i % linesize;
  let regoff : nat = elem_in_line / lambda_value;
  let elementoff : nat = line * lambda_value + elem_in_line % lambda_value;
  regoff * elems_per_reg + elementoff
}

// Memory element offset for the order-preserving tile traversal. The active
// tile is walked row-major across `linesize = lambda * LMUL` storage elements
// per row: row = i / linesize, col = i % linesize, offset = row * LD + col.
function ime_tile_ordered_mem_off(i : nat, linesize : nat, LD : nat) -> nat = {
  assert(linesize > 0);
  let row = i / linesize;
  let col = i % linesize;
  row * LD + col
}

// Memory element offset for the transposing tile traversal. The active tile
// has `rows` storage-element rows and `cols = lambda * LMUL` storage-element
// columns; the flat index i selects (row, col) row-major but addresses the
// transpose: offset = col * LD + row. For a 2x2 tile with LD=4 this yields
// the offsets [0, 4, 1, 5] for flat indices [0, 1, 2, 3].
function ime_tile_transposed_mem_off(i : nat, rows : nat, cols : nat, LD : nat) -> nat = {
  assert(cols > 0);
  assert(rows > 0);
  let row = i / cols;
  let col = i % cols;
  col * LD + row
}

function ime_mat_A_idx(i : nat, k : nat, K_eff : nat, LMUL : nat, lambda_value : nat, epr : nat) -> nat =
  ime_tile_reg_idx(i * K_eff + k, LMUL, lambda_value, epr)

function ime_mat_B_idx(k : nat, j : nat, K_eff : nat, LMUL : nat, lambda_value : nat, epr : nat) -> nat =
  ime_tile_reg_idx(j * K_eff + k, LMUL, lambda_value, epr)

function ime_mat_C_idx(i : nat, j : nat, N_max : nat, EMUL_C : nat, lambda_value : nat, epr : nat) -> nat =
  ime_tile_reg_idx(i * N_max + j, EMUL_C, lambda_value, epr)

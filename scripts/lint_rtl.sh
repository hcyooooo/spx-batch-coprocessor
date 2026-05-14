#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERILATOR="${VERILATOR:-verilator}"

RTL_FILES=(
  "${REPO_ROOT}/rtl/common/spx_thashx4_pkg.sv"
  "${REPO_ROOT}/rtl/core/spx_keccak_round.sv"
  "${REPO_ROOT}/rtl/core/spx_keccakx4_core.sv"
  "${REPO_ROOT}/rtl/core/spx_thashx4_core.sv"
)

echo "Linting standalone SPHINCS+ thashx4 RTL with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  --top-module spx_thashx4_core \
  "${RTL_FILES[@]}"

echo "Linting standalone SPHINCS+ coprocessor wrapper with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  --top-module spx_cop_wrapper \
  "${RTL_FILES[@]}" \
  "${REPO_ROOT}/rtl/wrapper/spx_cop_wrapper.sv"

echo "Linting standalone SPHINCS+ CV-X-IF-style adapter with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  --top-module spx_cvxif_adapter \
  "${RTL_FILES[@]}" \
  "${REPO_ROOT}/rtl/wrapper/spx_cop_wrapper.sv" \
  "${REPO_ROOT}/rtl/cvxif/spx_cvxif_adapter.sv"

echo "Linting standalone SPHINCS+ coarse CV-X-IF-style adapter with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  --top-module spx_cvxif_adapter_coarse \
  "${RTL_FILES[@]}" \
  "${REPO_ROOT}/rtl/wrapper/spx_cop_wrapper.sv" \
  "${REPO_ROOT}/rtl/cvxif/spx_cvxif_adapter_coarse.sv"

echo "Linting standalone SPHINCS+ descriptor adapter with ${VERILATOR}"
for width in 1 2 4; do
  "${VERILATOR}" \
    -sv \
    --lint-only \
    --timing \
    --Wall \
    -GMEM_WORDS_PER_CYCLE="${width}" \
    --top-module spx_descriptor_adapter \
    "${RTL_FILES[@]}" \
    "${REPO_ROOT}/rtl/cvxif/spx_descriptor_adapter.sv"
done

echo "Linting standalone SPHINCS+ CV-X-IF descriptor-control adapter with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  --top-module spx_cvxif_desc_adapter \
  "${REPO_ROOT}/rtl/cvxif/spx_cvxif_desc_adapter.sv"

echo "Linting CV32E40X-facing SPHINCS+ CV-X-IF real adapter with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  -Wno-UNUSEDPARAM \
  --top-module tb_spx_cvxif_real_adapter_lint \
  "${REPO_ROOT}/third_party/cv32e40x/rtl/cv32e40x_if_xif.sv" \
  "${REPO_ROOT}/rtl/cvxif/spx_cvxif_real_adapter.sv" \
  "${REPO_ROOT}/sim/tb/tb_spx_cvxif_real_adapter_lint.sv"

echo "Linting standalone SPHINCS+ memory master shim mock with ${VERILATOR}"
"${VERILATOR}" \
  -sv \
  --lint-only \
  --timing \
  --Wall \
  --top-module spx_mem_master_shim_mock \
  "${REPO_ROOT}/rtl/mem/spx_mem_master_shim_mock.sv"

echo "PASS rtl lint"

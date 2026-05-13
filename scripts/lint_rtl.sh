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

echo "PASS rtl lint"

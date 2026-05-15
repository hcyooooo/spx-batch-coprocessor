CC ?= gcc
VERILATOR ?= verilator

BUILD_DIR := build
VECTOR_DIR := vectors

RISCV_GCC_CANDIDATES := riscv32-corev-elf-gcc riscv32-unknown-elf-gcc riscv64-unknown-elf-gcc
RISCV_GCC := $(firstword $(foreach tool,$(RISCV_GCC_CANDIDATES),$(shell command -v $(tool) 2>/dev/null)))
RISCV_GCC_NAME := $(notdir $(RISCV_GCC))
RISCV_TOOL_PREFIX := $(RISCV_GCC_NAME:%-gcc=%)
RISCV_OBJDUMP := $(RISCV_TOOL_PREFIX)-objdump
RISCV_OBJCOPY := $(RISCV_TOOL_PREFIX)-objcopy
RISCV_CFLAGS := -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles \
	-ffreestanding -fno-builtin -msmall-data-limit=0 -O2 -Wall -Wextra
RISCV_LDFLAGS := -T ../sw/tests/spx_cvxif_smoke.ld -Wl,--build-id=none

RTL_PKG := ../rtl/common/spx_thashx4_pkg.sv
RTL_KECCAK := \
	../rtl/core/spx_keccak_round.sv \
	../rtl/core/spx_keccakx4_core.sv
RTL_THASH := \
	$(RTL_KECCAK) \
	../rtl/core/spx_thashx4_core.sv
RTL_WOTS_CHAIN := \
	$(RTL_THASH) \
	../rtl/core/spx_wots_chainx4_core.sv
RTL_COP_WRAPPER := \
	$(RTL_THASH) \
	../rtl/wrapper/spx_cop_wrapper.sv
RTL_CVXIF_ADAPTER := \
	$(RTL_COP_WRAPPER) \
	../rtl/cvxif/spx_cvxif_adapter.sv
RTL_CVXIF_ADAPTER_COARSE := \
	$(RTL_COP_WRAPPER) \
	../rtl/cvxif/spx_cvxif_adapter_coarse.sv
RTL_DESCRIPTOR_ADAPTER := \
	$(RTL_WOTS_CHAIN) \
	../rtl/cvxif/spx_descriptor_adapter.sv
RTL_CVXIF_DESC_ADAPTER := \
	$(RTL_DESCRIPTOR_ADAPTER) \
	../rtl/cvxif/spx_cvxif_desc_adapter.sv
RTL_MEM_MASTER_SHIM := \
	../rtl/mem/spx_mem_master_shim_mock.sv
RTL_CVXIF_REAL_ADAPTER := \
	../third_party/cv32e40x/rtl/cv32e40x_if_xif.sv \
	../rtl/cvxif/spx_cvxif_real_adapter.sv \
	$(RTL_CVXIF_DESC_ADAPTER) \
	$(RTL_MEM_MASTER_SHIM)
RTL_CVXIF_REAL_ADAPTER_NO_XIF := \
	../rtl/cvxif/spx_cvxif_real_adapter.sv \
	$(RTL_CVXIF_DESC_ADAPTER) \
	$(RTL_MEM_MASTER_SHIM)

CV32E40X_RTL_DIR := ../third_party/cv32e40x/rtl
CV32E40X_BHV_DIR := ../third_party/cv32e40x/bhv
CV32E40X_INC := +incdir+$(CV32E40X_RTL_DIR)/include
CV32E40X_CORE_RTL := \
	$(CV32E40X_RTL_DIR)/include/cv32e40x_pkg.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_if_c_obi.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_if_xif.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_align_check.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_if_stage.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_csr.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_debug_triggers.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_cs_registers.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_register_file.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_register_file_wrapper.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_write_buffer.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_lsu_response_filter.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_load_store_unit.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_id_stage.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_i_decoder.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_m_decoder.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_a_decoder.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_b_decoder.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_decoder.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_compressed_decoder.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_sequencer.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_alignment_buffer.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_prefetch_unit.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_mult.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_int_controller.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_clic_int_controller.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_ex_stage.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_wb_stage.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_div.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_alu.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_ff_one.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_popcnt.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_alu_b_cpop.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_controller_fsm.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_controller_bypass.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_controller.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_instr_obi_interface.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_data_obi_interface.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_prefetcher.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_sleep_unit.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_core.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_mpu.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_pma.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_pc_target.sv \
	$(CV32E40X_RTL_DIR)/cv32e40x_wpt.sv \
	$(CV32E40X_BHV_DIR)/cv32e40x_sim_clock_gate.sv

GEN := $(BUILD_DIR)/gen_thashx4_vectors
SMOKE_ELF := $(BUILD_DIR)/spx_cvxif_smoke.elf
SMOKE_DUMP := $(BUILD_DIR)/spx_cvxif_smoke.dump
SMOKE_HEX := $(BUILD_DIR)/spx_cvxif_smoke.hex
SMOKE_GCC_VERSION := $(BUILD_DIR)/spx_cvxif_smoke.gcc.txt
WOTS_SMOKE_ELF := $(BUILD_DIR)/spx_cvxif_wots_chain_smoke.elf
WOTS_SMOKE_DUMP := $(BUILD_DIR)/spx_cvxif_wots_chain_smoke.dump
WOTS_SMOKE_HEX := $(BUILD_DIR)/spx_cvxif_wots_chain_smoke.hex
WOTS_SMOKE_GCC_VERSION := $(BUILD_DIR)/spx_cvxif_wots_chain_smoke.gcc.txt
WOTS_ERROR_SMOKE_ELF := $(BUILD_DIR)/spx_cvxif_wots_chain_error_smoke.elf
WOTS_ERROR_SMOKE_DUMP := $(BUILD_DIR)/spx_cvxif_wots_chain_error_smoke.dump
WOTS_ERROR_SMOKE_HEX := $(BUILD_DIR)/spx_cvxif_wots_chain_error_smoke.hex
WOTS_ERROR_SMOKE_GCC_VERSION := $(BUILD_DIR)/spx_cvxif_wots_chain_error_smoke.gcc.txt
ERROR_SMOKE_ELF := $(BUILD_DIR)/spx_cvxif_error_smoke.elf
ERROR_SMOKE_DUMP := $(BUILD_DIR)/spx_cvxif_error_smoke.dump
ERROR_SMOKE_HEX := $(BUILD_DIR)/spx_cvxif_error_smoke.hex
ERROR_SMOKE_GCC_VERSION := $(BUILD_DIR)/spx_cvxif_error_smoke.gcc.txt
CV32E40X_SMOKE_BIN := $(BUILD_DIR)/obj_cv32e40x_spx_core_smoke/tb_cv32e40x_spx_core_smoke
WOTS_PK_GROUPING_TEST := $(BUILD_DIR)/test_wots_pk_grouping
SIGN_SCHEDULE_TEST := $(BUILD_DIR)/test_sign_schedule_model

.PHONY: all test vectors test-wots-pk-grouping test-sign-schedule-model lint lint-spx-cvxif check-riscv-gcc build-cv32e40x-smoke build-cv32e40x-wots-chain-smoke build-cv32e40x-wots-chain-error-smoke build-cv32e40x-error-smoke build-cv32e40x-core-smoke-sim sim-keccakx4 sim-thashx4 sim-wots-chainx4 sim-wots-chainx4-mixed sim-wots-chain-descriptor sim-cop-wrapper sim-cvxif-adapter sim-cvxif-adapter-coarse sim-descriptor-adapter sim-descriptor-adapter-1w sim-descriptor-adapter-2w sim-descriptor-adapter-4w sim-cvxif-desc-adapter sim-cvxif-desc-adapter-wait sim-mem-master-shim sim-cvxif-real-adapter sim-cv32e40x-core-smoke sim-cv32e40x-wots-chain-smoke sim-cv32e40x-wots-chain-smoke-wait1 sim-cv32e40x-wots-chain-smoke-wait2 sim-cv32e40x-wots-chain-smoke-split sim-cv32e40x-wots-chain-smoke-random50 sim-cv32e40x-wots-chain-smoke-random75 sim-cv32e40x-wots-chain-smoke-regress sim-cv32e40x-wots-chain-error sim-cv32e40x-core-smoke-wait1 sim-cv32e40x-core-smoke-wait2 sim-cv32e40x-core-smoke-split sim-cv32e40x-core-smoke-random50 sim-cv32e40x-core-smoke-random75 sim-cv32e40x-core-smoke-regress sim-cv32e40x-core-perf sim-cv32e40x-core-smoke-error clean distclean

all: test

test: test-wots-pk-grouping test-sign-schedule-model sim-keccakx4 sim-thashx4 sim-wots-chainx4 sim-wots-chainx4-mixed sim-wots-chain-descriptor sim-cop-wrapper sim-cvxif-adapter sim-cvxif-adapter-coarse sim-descriptor-adapter sim-cvxif-desc-adapter sim-cvxif-desc-adapter-wait sim-mem-master-shim sim-cvxif-real-adapter sim-cv32e40x-core-smoke-regress sim-cv32e40x-wots-chain-smoke-regress sim-cv32e40x-wots-chain-error

lint:
	../scripts/lint_rtl.sh

lint-spx-cvxif:
	$(VERILATOR) -sv --lint-only --timing --Wall -Wno-UNUSEDPARAM \
		--top-module tb_spx_cvxif_real_adapter_lint \
		../third_party/cv32e40x/rtl/cv32e40x_if_xif.sv \
		../rtl/cvxif/spx_cvxif_real_adapter.sv \
		tb/tb_spx_cvxif_real_adapter_lint.sv

$(BUILD_DIR):
	mkdir -p $@

check-riscv-gcc:
	@test -n "$(RISCV_GCC)" || { \
		echo "No RISC-V GCC found. Tried: $(RISCV_GCC_CANDIDATES)"; \
		exit 1; \
	}
	@echo "Using RISC-V GCC: $(RISCV_GCC_NAME)"

$(SMOKE_ELF): ../sw/tests/spx_cvxif_smoke.c ../sw/tests/spx_cvxif_smoke.ld | $(BUILD_DIR) check-riscv-gcc
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) \
		-Wl,-Map=$(BUILD_DIR)/spx_cvxif_smoke.map \
		-o $@ ../sw/tests/spx_cvxif_smoke.c
	$(RISCV_GCC) --version > $(SMOKE_GCC_VERSION)

$(WOTS_SMOKE_ELF): ../sw/tests/spx_cvxif_wots_chain_smoke.c ../sw/tests/spx_cvxif_smoke.ld | $(BUILD_DIR) check-riscv-gcc
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) \
		-Wl,-Map=$(BUILD_DIR)/spx_cvxif_wots_chain_smoke.map \
		-o $@ ../sw/tests/spx_cvxif_wots_chain_smoke.c
	$(RISCV_GCC) --version > $(WOTS_SMOKE_GCC_VERSION)

$(WOTS_ERROR_SMOKE_ELF): ../sw/tests/spx_cvxif_wots_chain_error_smoke.c ../sw/tests/spx_cvxif_smoke.ld | $(BUILD_DIR) check-riscv-gcc
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) \
		-Wl,-Map=$(BUILD_DIR)/spx_cvxif_wots_chain_error_smoke.map \
		-o $@ ../sw/tests/spx_cvxif_wots_chain_error_smoke.c
	$(RISCV_GCC) --version > $(WOTS_ERROR_SMOKE_GCC_VERSION)

$(ERROR_SMOKE_ELF): ../sw/tests/spx_cvxif_error_smoke.c ../sw/tests/spx_cvxif_smoke.ld | $(BUILD_DIR) check-riscv-gcc
	$(RISCV_GCC) $(RISCV_CFLAGS) $(RISCV_LDFLAGS) \
		-Wl,-Map=$(BUILD_DIR)/spx_cvxif_error_smoke.map \
		-o $@ ../sw/tests/spx_cvxif_error_smoke.c
	$(RISCV_GCC) --version > $(ERROR_SMOKE_GCC_VERSION)

$(SMOKE_DUMP): $(SMOKE_ELF)
	$(RISCV_OBJDUMP) -d -s $< > $@

$(WOTS_SMOKE_DUMP): $(WOTS_SMOKE_ELF)
	$(RISCV_OBJDUMP) -d -s $< > $@

$(WOTS_ERROR_SMOKE_DUMP): $(WOTS_ERROR_SMOKE_ELF)
	$(RISCV_OBJDUMP) -d -s $< > $@

$(ERROR_SMOKE_DUMP): $(ERROR_SMOKE_ELF)
	$(RISCV_OBJDUMP) -d -s $< > $@

$(SMOKE_HEX): $(SMOKE_ELF)
	$(RISCV_OBJCOPY) -O verilog $< $@

$(WOTS_SMOKE_HEX): $(WOTS_SMOKE_ELF)
	$(RISCV_OBJCOPY) -O verilog $< $@

$(WOTS_ERROR_SMOKE_HEX): $(WOTS_ERROR_SMOKE_ELF)
	$(RISCV_OBJCOPY) -O verilog $< $@

$(ERROR_SMOKE_HEX): $(ERROR_SMOKE_ELF)
	$(RISCV_OBJCOPY) -O verilog $< $@

build-cv32e40x-smoke: $(SMOKE_ELF) $(SMOKE_DUMP) $(SMOKE_HEX)
	@echo "Built $(SMOKE_ELF)"
	@echo "Built $(SMOKE_DUMP)"
	@echo "Built $(SMOKE_HEX)"

build-cv32e40x-wots-chain-smoke: $(WOTS_SMOKE_ELF) $(WOTS_SMOKE_DUMP) $(WOTS_SMOKE_HEX)
	@echo "Built $(WOTS_SMOKE_ELF)"
	@echo "Built $(WOTS_SMOKE_DUMP)"
	@echo "Built $(WOTS_SMOKE_HEX)"

build-cv32e40x-wots-chain-error-smoke: $(WOTS_ERROR_SMOKE_ELF) $(WOTS_ERROR_SMOKE_DUMP) $(WOTS_ERROR_SMOKE_HEX)
	@echo "Built $(WOTS_ERROR_SMOKE_ELF)"
	@echo "Built $(WOTS_ERROR_SMOKE_DUMP)"
	@echo "Built $(WOTS_ERROR_SMOKE_HEX)"

build-cv32e40x-error-smoke: $(ERROR_SMOKE_ELF) $(ERROR_SMOKE_DUMP) $(ERROR_SMOKE_HEX)
	@echo "Built $(ERROR_SMOKE_ELF)"
	@echo "Built $(ERROR_SMOKE_DUMP)"
	@echo "Built $(ERROR_SMOKE_HEX)"

$(GEN): gen_thashx4_vectors.c ../sw/spx_model/keccakx4.c ../sw/spx_model/keccakx4.h ../sw/spx_model/wots_chainx4_model.c ../sw/spx_model/wots_chainx4_model.h ../sw/spx_model/descriptor_ext_model.c ../sw/spx_model/descriptor_ext_model.h | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -O2 -I../sw/spx_model \
		-o $@ gen_thashx4_vectors.c ../sw/spx_model/keccakx4.c \
		../sw/spx_model/wots_chainx4_model.c \
		../sw/spx_model/descriptor_ext_model.c

vectors: $(GEN)
	mkdir -p $(VECTOR_DIR)
	./$(GEN) $(VECTOR_DIR)

$(WOTS_PK_GROUPING_TEST): ../sw/tests/test_wots_pk_grouping.c ../sw/spx_model/wots_pk_grouping_model.c ../sw/spx_model/wots_pk_grouping_model.h ../sw/spx_model/wots_chainx4_model.c ../sw/spx_model/wots_chainx4_model.h ../sw/spx_model/keccakx4.c ../sw/spx_model/keccakx4.h | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -O2 -I../sw/spx_model \
		-o $@ ../sw/tests/test_wots_pk_grouping.c \
		../sw/spx_model/wots_pk_grouping_model.c \
		../sw/spx_model/wots_chainx4_model.c \
		../sw/spx_model/keccakx4.c

test-wots-pk-grouping: $(WOTS_PK_GROUPING_TEST)
	./$(WOTS_PK_GROUPING_TEST)

$(SIGN_SCHEDULE_TEST): ../sw/tests/test_sign_schedule_model.c ../sw/spx_model/sign_schedule_model.c ../sw/spx_model/sign_schedule_model.h ../sw/spx_model/wots_pk_grouping_model.h ../sw/spx_model/descriptor_ext_model.h ../sw/spx_model/wots_chainx4_model.h | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -O2 -I../sw/spx_model \
		-o $@ ../sw/tests/test_sign_schedule_model.c \
		../sw/spx_model/sign_schedule_model.c

test-sign-schedule-model: $(SIGN_SCHEDULE_TEST)
	./$(SIGN_SCHEDULE_TEST)

sim-keccakx4: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_keccakx4_core \
		-Mdir $(BUILD_DIR)/obj_keccakx4_core \
		-o tb_keccakx4_core \
		$(RTL_PKG) $(RTL_KECCAK) tb/tb_keccakx4_core.sv
	./$(BUILD_DIR)/obj_keccakx4_core/tb_keccakx4_core \
		+VECTORS=$(VECTOR_DIR)/keccakx4_vectors.hex

sim-thashx4: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_thashx4_core \
		-Mdir $(BUILD_DIR)/obj_thashx4_core \
		-o tb_thashx4_core \
		$(RTL_PKG) $(RTL_THASH) tb/tb_thashx4_core.sv
	./$(BUILD_DIR)/obj_thashx4_core/tb_thashx4_core \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-wots-chainx4: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_wots_chainx4_core \
		-Mdir $(BUILD_DIR)/obj_wots_chainx4_core \
		-o tb_wots_chainx4_core \
		$(RTL_PKG) $(RTL_WOTS_CHAIN) tb/tb_wots_chainx4_core.sv
	./$(BUILD_DIR)/obj_wots_chainx4_core/tb_wots_chainx4_core \
		+VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex

sim-wots-chainx4-mixed: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_wots_chainx4_mixed \
		-Mdir $(BUILD_DIR)/obj_wots_chainx4_mixed \
		-o tb_wots_chainx4_mixed \
		$(RTL_PKG) $(RTL_WOTS_CHAIN) tb/tb_wots_chainx4_mixed.sv
	./$(BUILD_DIR)/obj_wots_chainx4_mixed/tb_wots_chainx4_mixed \
		+VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex

sim-wots-chain-descriptor: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_wots_chain_descriptor \
		-Mdir $(BUILD_DIR)/obj_wots_chain_descriptor \
		-o tb_wots_chain_descriptor \
		$(RTL_PKG) $(RTL_DESCRIPTOR_ADAPTER) tb/tb_wots_chain_descriptor.sv
	./$(BUILD_DIR)/obj_wots_chain_descriptor/tb_wots_chain_descriptor \
		+VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-cop-wrapper: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_cop_wrapper \
		-Mdir $(BUILD_DIR)/obj_spx_cop_wrapper \
		-o tb_spx_cop_wrapper \
		$(RTL_PKG) $(RTL_COP_WRAPPER) tb/tb_spx_cop_wrapper.sv
	./$(BUILD_DIR)/obj_spx_cop_wrapper/tb_spx_cop_wrapper \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-cvxif-adapter: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_cvxif_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_cvxif_adapter \
		-o tb_spx_cvxif_adapter \
		$(RTL_PKG) $(RTL_CVXIF_ADAPTER) tb/tb_spx_cvxif_adapter.sv
	./$(BUILD_DIR)/obj_spx_cvxif_adapter/tb_spx_cvxif_adapter \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-cvxif-adapter-coarse: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_cvxif_adapter_coarse \
		-Mdir $(BUILD_DIR)/obj_spx_cvxif_adapter_coarse \
		-o tb_spx_cvxif_adapter_coarse \
		$(RTL_PKG) $(RTL_CVXIF_ADAPTER_COARSE) tb/tb_spx_cvxif_adapter_coarse.sv
	./$(BUILD_DIR)/obj_spx_cvxif_adapter_coarse/tb_spx_cvxif_adapter_coarse \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-descriptor-adapter: sim-descriptor-adapter-1w sim-descriptor-adapter-2w sim-descriptor-adapter-4w

sim-descriptor-adapter-1w: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		-GMEM_WORDS_PER_CYCLE=1 \
		--top-module tb_spx_descriptor_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_descriptor_adapter_1w \
		-o tb_spx_descriptor_adapter_1w \
		$(RTL_PKG) $(RTL_DESCRIPTOR_ADAPTER) tb/tb_spx_descriptor_adapter.sv
	./$(BUILD_DIR)/obj_spx_descriptor_adapter_1w/tb_spx_descriptor_adapter_1w \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-descriptor-adapter-2w: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		-GMEM_WORDS_PER_CYCLE=2 \
		--top-module tb_spx_descriptor_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_descriptor_adapter_2w \
		-o tb_spx_descriptor_adapter_2w \
		$(RTL_PKG) $(RTL_DESCRIPTOR_ADAPTER) tb/tb_spx_descriptor_adapter.sv
	./$(BUILD_DIR)/obj_spx_descriptor_adapter_2w/tb_spx_descriptor_adapter_2w \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-descriptor-adapter-4w: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		-GMEM_WORDS_PER_CYCLE=4 \
		--top-module tb_spx_descriptor_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_descriptor_adapter_4w \
		-o tb_spx_descriptor_adapter_4w \
		$(RTL_PKG) $(RTL_DESCRIPTOR_ADAPTER) tb/tb_spx_descriptor_adapter.sv
	./$(BUILD_DIR)/obj_spx_descriptor_adapter_4w/tb_spx_descriptor_adapter_4w \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-cvxif-desc-adapter: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_cvxif_desc_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_cvxif_desc_adapter \
		-o tb_spx_cvxif_desc_adapter \
		$(RTL_PKG) $(RTL_CVXIF_DESC_ADAPTER) tb/tb_spx_cvxif_desc_adapter.sv
	./$(BUILD_DIR)/obj_spx_cvxif_desc_adapter/tb_spx_cvxif_desc_adapter \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-cvxif-desc-adapter-wait: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_cvxif_desc_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_cvxif_desc_adapter_wait \
		-o tb_spx_cvxif_desc_adapter_wait \
		$(RTL_PKG) $(RTL_CVXIF_DESC_ADAPTER) tb/tb_spx_cvxif_desc_adapter.sv
	./$(BUILD_DIR)/obj_spx_cvxif_desc_adapter_wait/tb_spx_cvxif_desc_adapter_wait \
		+PHASE35B_WAIT \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-mem-master-shim: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_mem_master_shim_mock \
		-Mdir $(BUILD_DIR)/obj_spx_mem_master_shim_mock \
		-o tb_spx_mem_master_shim_mock \
		$(RTL_PKG) $(RTL_CVXIF_DESC_ADAPTER) $(RTL_MEM_MASTER_SHIM) \
		tb/tb_spx_mem_master_shim_mock.sv
	./$(BUILD_DIR)/obj_spx_mem_master_shim_mock/tb_spx_mem_master_shim_mock \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

sim-cvxif-real-adapter: vectors
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		--top-module tb_spx_cvxif_real_adapter \
		-Mdir $(BUILD_DIR)/obj_spx_cvxif_real_adapter \
		-o tb_spx_cvxif_real_adapter \
		$(RTL_PKG) $(RTL_CVXIF_REAL_ADAPTER) tb/tb_spx_cvxif_real_adapter.sv
	./$(BUILD_DIR)/obj_spx_cvxif_real_adapter/tb_spx_cvxif_real_adapter \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex

$(CV32E40X_SMOKE_BIN): $(RTL_PKG) $(CV32E40X_CORE_RTL) $(RTL_CVXIF_REAL_ADAPTER_NO_XIF) tb/tb_cv32e40x_spx_core_smoke.sv | $(BUILD_DIR)
	$(VERILATOR) -sv --binary --timing -Wno-fatal \
		$(CV32E40X_INC) \
		--top-module tb_cv32e40x_spx_core_smoke \
		-Mdir $(BUILD_DIR)/obj_cv32e40x_spx_core_smoke \
		-o tb_cv32e40x_spx_core_smoke \
		$(RTL_PKG) $(CV32E40X_CORE_RTL) $(RTL_CVXIF_REAL_ADAPTER_NO_XIF) \
		tb/tb_cv32e40x_spx_core_smoke.sv

build-cv32e40x-core-smoke-sim: $(CV32E40X_SMOKE_BIN)
	@echo "Built $(CV32E40X_SMOKE_BIN)"

sim-cv32e40x-core-smoke: build-cv32e40x-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=zero_wait

sim-cv32e40x-wots-chain-smoke: build-cv32e40x-wots-chain-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_SMOKE \
		+SMOKE_HEX=$(WOTS_SMOKE_HEX) \
		+WOTS_VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+WOTS_MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=zero_wait

sim-cv32e40x-wots-chain-smoke-wait1: build-cv32e40x-wots-chain-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_SMOKE \
		+SMOKE_HEX=$(WOTS_SMOKE_HEX) \
		+WOTS_VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+WOTS_MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+SMOKE_READ_LATENCY=1 +SMOKE_WRITE_LATENCY=1 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=wait1

sim-cv32e40x-wots-chain-smoke-wait2: build-cv32e40x-wots-chain-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_SMOKE \
		+SMOKE_HEX=$(WOTS_SMOKE_HEX) \
		+WOTS_VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+WOTS_MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+SMOKE_READ_LATENCY=2 +SMOKE_WRITE_LATENCY=2 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=wait2

sim-cv32e40x-wots-chain-smoke-split: build-cv32e40x-wots-chain-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_SMOKE \
		+SMOKE_HEX=$(WOTS_SMOKE_HEX) \
		+WOTS_VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+WOTS_MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+SMOKE_READ_LATENCY=2 +SMOKE_WRITE_LATENCY=4 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=split_read2_write4

sim-cv32e40x-wots-chain-smoke-random50: build-cv32e40x-wots-chain-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_SMOKE \
		+SMOKE_HEX=$(WOTS_SMOKE_HEX) \
		+WOTS_VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+WOTS_MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=50 \
		+SMOKE_MODE=random_ready50

sim-cv32e40x-wots-chain-smoke-random75: build-cv32e40x-wots-chain-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_SMOKE \
		+SMOKE_HEX=$(WOTS_SMOKE_HEX) \
		+WOTS_VECTORS=$(VECTOR_DIR)/wots_chainx4_vectors.hex \
		+WOTS_MIXED_VECTORS=$(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=75 \
		+SMOKE_MODE=random_ready75

sim-cv32e40x-core-smoke-wait1: build-cv32e40x-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=1 +SMOKE_WRITE_LATENCY=1 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=wait1

sim-cv32e40x-core-smoke-wait2: build-cv32e40x-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=2 +SMOKE_WRITE_LATENCY=2 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=wait2

sim-cv32e40x-core-smoke-split: build-cv32e40x-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=2 +SMOKE_WRITE_LATENCY=4 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=split

sim-cv32e40x-core-smoke-random50: build-cv32e40x-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=50 \
		+SMOKE_MODE=random50

sim-cv32e40x-core-smoke-random75: build-cv32e40x-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=75 \
		+SMOKE_MODE=random75

sim-cv32e40x-core-smoke-error: build-cv32e40x-error-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+SMOKE_HEX=$(ERROR_SMOKE_HEX) \
		+VECTORS_IB1=$(VECTOR_DIR)/thashx4_inblocks1.hex \
		+VECTORS_IB2=$(VECTOR_DIR)/thashx4_inblocks2.hex \
		+EXPECTED=$(VECTOR_DIR)/thashx4_expected.hex \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=error

sim-cv32e40x-wots-chain-error: build-cv32e40x-wots-chain-error-smoke vectors build-cv32e40x-core-smoke-sim
	./$(CV32E40X_SMOKE_BIN) \
		+WOTS_CHAIN_ERROR_SMOKE \
		+SMOKE_HEX=$(WOTS_ERROR_SMOKE_HEX) \
		+SMOKE_READ_LATENCY=0 +SMOKE_WRITE_LATENCY=0 +SMOKE_REQ_READY_PCT=100 \
		+SMOKE_MODE=wots_chain_error

sim-cv32e40x-core-smoke-regress: sim-cv32e40x-core-smoke sim-cv32e40x-core-smoke-wait1 sim-cv32e40x-core-smoke-wait2 sim-cv32e40x-core-smoke-split sim-cv32e40x-core-smoke-random50 sim-cv32e40x-core-smoke-random75 sim-cv32e40x-core-smoke-error

sim-cv32e40x-wots-chain-smoke-regress: sim-cv32e40x-wots-chain-smoke sim-cv32e40x-wots-chain-smoke-wait1 sim-cv32e40x-wots-chain-smoke-wait2 sim-cv32e40x-wots-chain-smoke-split sim-cv32e40x-wots-chain-smoke-random50 sim-cv32e40x-wots-chain-smoke-random75

sim-cv32e40x-core-perf: sim-cv32e40x-core-smoke

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -f $(VECTOR_DIR)/keccakx4_vectors.hex
	rm -f $(VECTOR_DIR)/thashx4_inblocks1.hex
	rm -f $(VECTOR_DIR)/thashx4_inblocks2.hex
	rm -f $(VECTOR_DIR)/thashx4_expected.hex
	rm -f $(VECTOR_DIR)/wots_chainx4_vectors.hex
	rm -f $(VECTOR_DIR)/wots_chainx4_mixed_vectors.hex

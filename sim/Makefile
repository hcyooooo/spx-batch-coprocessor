CC ?= gcc
VERILATOR ?= verilator

BUILD_DIR := build
VECTOR_DIR := vectors

RTL_PKG := ../rtl/common/spx_thashx4_pkg.sv
RTL_KECCAK := \
	../rtl/core/spx_keccak_round.sv \
	../rtl/core/spx_keccakx4_core.sv
RTL_THASH := \
	$(RTL_KECCAK) \
	../rtl/core/spx_thashx4_core.sv
RTL_COP_WRAPPER := \
	$(RTL_THASH) \
	../rtl/wrapper/spx_cop_wrapper.sv
RTL_CVXIF_ADAPTER := \
	$(RTL_COP_WRAPPER) \
	../rtl/cvxif/spx_cvxif_adapter.sv
RTL_CVXIF_ADAPTER_COARSE := \
	$(RTL_COP_WRAPPER) \
	../rtl/cvxif/spx_cvxif_adapter_coarse.sv

GEN := $(BUILD_DIR)/gen_thashx4_vectors

.PHONY: all test vectors lint sim-keccakx4 sim-thashx4 sim-cop-wrapper sim-cvxif-adapter sim-cvxif-adapter-coarse clean distclean

all: test

test: sim-keccakx4 sim-thashx4 sim-cop-wrapper sim-cvxif-adapter sim-cvxif-adapter-coarse

lint:
	../scripts/lint_rtl.sh

$(BUILD_DIR):
	mkdir -p $@

$(GEN): gen_thashx4_vectors.c ../sw/spx_model/keccakx4.c ../sw/spx_model/keccakx4.h | $(BUILD_DIR)
	$(CC) -std=c99 -Wall -Wextra -O2 -I../sw/spx_model \
		-o $@ gen_thashx4_vectors.c ../sw/spx_model/keccakx4.c

vectors: $(GEN)
	mkdir -p $(VECTOR_DIR)
	./$(GEN) $(VECTOR_DIR)

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

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -f $(VECTOR_DIR)/keccakx4_vectors.hex
	rm -f $(VECTOR_DIR)/thashx4_inblocks1.hex
	rm -f $(VECTOR_DIR)/thashx4_inblocks2.hex
	rm -f $(VECTOR_DIR)/thashx4_expected.hex

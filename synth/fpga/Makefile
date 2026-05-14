VIVADO ?= vivado
TOP ?= spx_thashx4_core
PART ?= xc7a35tcpg236-1
CLOCK_PERIOD_NS ?= 10.0
MEM_WORDS_PER_CYCLE ?= 1

.PHONY: all synth synth-thashx4 synth-keccakx4 synth-wots-chainx4 synth-cop-wrapper synth-descriptor-adapter synth-descriptor-adapter-1w synth-descriptor-adapter-2w synth-descriptor-adapter-4w clean

all: synth-thashx4

synth:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs $(TOP) $(PART) $(CLOCK_PERIOD_NS)

synth-thashx4:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_thashx4_core $(PART) $(CLOCK_PERIOD_NS)

synth-keccakx4:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_keccakx4_core $(PART) $(CLOCK_PERIOD_NS)

synth-wots-chainx4:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_wots_chainx4_core $(PART) $(CLOCK_PERIOD_NS)

synth-cop-wrapper:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_cop_wrapper $(PART) $(CLOCK_PERIOD_NS)

synth-descriptor-adapter:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_descriptor_adapter $(PART) $(CLOCK_PERIOD_NS) $(MEM_WORDS_PER_CYCLE)

synth-descriptor-adapter-1w:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_descriptor_adapter $(PART) $(CLOCK_PERIOD_NS) 1

synth-descriptor-adapter-2w:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_descriptor_adapter $(PART) $(CLOCK_PERIOD_NS) 2

synth-descriptor-adapter-4w:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_descriptor_adapter $(PART) $(CLOCK_PERIOD_NS) 4

clean:
	rm -rf build .Xil vivado*.jou vivado*.log

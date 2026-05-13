VIVADO ?= vivado
TOP ?= spx_thashx4_core
PART ?= xc7a35tcpg236-1
CLOCK_PERIOD_NS ?= 10.0

.PHONY: all synth synth-thashx4 synth-keccakx4 synth-cop-wrapper clean

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

synth-cop-wrapper:
	$(VIVADO) -mode batch -source synth_vivado.tcl \
		-tclargs spx_cop_wrapper $(PART) $(CLOCK_PERIOD_NS)

clean:
	rm -rf build .Xil vivado*.jou vivado*.log

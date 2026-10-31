# Simulate the bitonic sorter with Icarus Verilog (no Xilinx tools needed).
#
#   make         run the self-checking testbench (fails if any vector is wrong)
#   make demo    run the original single-vector testbench (sorter_tb.v)
#   make clean

IVERILOG ?= iverilog
VVP      ?= vvp
BUILD    := build
RTL      := ../pe.v ../parallel_sorter.v

.PHONY: all test demo clean
all: test

test: $(BUILD)/random.vvp
	@$(VVP) $< | tee $(BUILD)/random.log
	@grep -q "RESULT: PASS" $(BUILD)/random.log

demo: $(BUILD)/demo.vvp
	@$(VVP) $<

$(BUILD)/random.vvp: sorter_random_tb.v $(RTL) | $(BUILD)
	$(IVERILOG) -o $@ $(RTL) sorter_random_tb.v

$(BUILD)/demo.vvp: ../sorter_tb.v $(RTL) | $(BUILD)
	$(IVERILOG) -o $@ $(RTL) ../sorter_tb.v

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)

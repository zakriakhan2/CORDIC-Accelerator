SRC_DIR := src
TB_DIR  := testbench
SRCS    := $(SRC_DIR)/Controller.sv $(SRC_DIR)/Datapath.sv $(SRC_DIR)/top.sv $(TB_DIR)/sims.sv
SIM_OUT := sim.vvp
WAVE    := waves.vcd

.PHONY: all run wave clean

all: run

$(SIM_OUT): $(SRCS)
	iverilog -g2012 -o $(SIM_OUT) $(SRCS)

run: $(SIM_OUT)
	vvp $(SIM_OUT)

wave: $(SIM_OUT)
	vvp $(SIM_OUT)
	gtkwave $(WAVE) &

clean:
	rm -f $(SIM_OUT) $(WAVE)

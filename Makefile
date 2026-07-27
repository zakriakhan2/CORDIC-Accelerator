TB      := tb_cordic_top_selfcheck
SRCS    := cordic_controller.sv cordic_datapath.sv cordic_top.sv $(TB).sv
SIM_OUT := sim.vvp
WAVE    := waves.vcd

.PHONY: all run wave clean

all: run

$(SIM_OUT): $(SRCS)
	iverilog -g2012 -o $(SIM_OUT) $(SRCS)

# Build and execute the self-checking testbench; nonzero exit on any failure.
run: $(SIM_OUT)
	vvp $(SIM_OUT)

# Same as run, but also opens the resulting waveform in gtkwave.
wave: $(SIM_OUT)
	vvp $(SIM_OUT)
	gtkwave $(WAVE) &

clean:
	rm -f $(SIM_OUT) $(WAVE)

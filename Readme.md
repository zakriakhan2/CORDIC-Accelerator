# CORDIC Sin/Cos Accelerator

A 16-iteration, rotation-mode CORDIC core in SystemVerilog that computes
`cos(angle)` and `sin(angle)` using only additions, subtractions, and
shifts — no multipliers. Built from three files (`cordic_controller`,
`cordic_datapath`, `cordic_top`) plus a self-checking testbench.

## 1. How CORDIC works (the math)

CORDIC (COordinate Rotation DIgital Computer) computes sin/cos by rotating
the vector `(x, y) = (1, 0)` by the target angle, one small step at a
time, instead of evaluating a trig function directly.

Each iteration `i` rotates the current vector by a *fixed* angle
`atan(2^-i)` — in whichever direction (`+` or `-`) reduces the remaining
angle `z` toward zero:

```
sigma   = +1 if z >= 0, else -1
x_next  = x - sigma * (y >> i)
y_next  = y + sigma * (x >> i)
z_next  = z - sigma * atan(2^-i)
```

Because each step only requires a shift and an add/subtract (no
multiply), this is cheap in hardware. After enough iterations, `z → 0`
and `(x, y)` has been rotated by the full original angle.

**Gain compensation:** each rotation step also scales the vector length
by `sqrt(1 + 2^-2i)`, so after 16 iterations the vector is longer than it
started by a constant factor `K ≈ 1.6468`. Rather than dividing by `K` at
the end, this design starts `x` at `1/K` instead of `1`, so the gain
cancels out automatically and the final `x`/`y` come out already
normalized to `cos`/`sin`.

**Convergence range:** each iteration can only correct the angle by at
most `atan(2^-i)`. Summed over all 16 iterations, the maximum angle this
algorithm can converge on is:

```
sum(atan(2^-i) for i = 0..15) ≈ 99.88 degrees
```

Angles outside roughly **±99.88°** will not converge — `z` won't reach
zero and `x`/`y` will not be valid cos/sin. This is a property of vanilla
CORDIC, not a bug. Extending the range to the full ±180° requires a
quadrant pre-rotation stage (not implemented here — see "Known
limitations" below).

## 2. Fixed-point format

All angle/coordinate values are 16-bit **signed Q2.13** fixed point:
1 sign bit, 2 integer bits, 13 fractional bits, representing **radians**.

```
value_real = value_int / 8192.0
```

Range: roughly `-4.0` to `+3.9999` radians. `angle_in` must be provided
already converted to this format, e.g. for 45°:

```
angle_rad = 45 * pi / 180        = 0.785398
angle_in  = round(0.785398 * 8192) = 6434
```

## 3. Module breakdown

### `cordic_controller.sv`
A 3-state FSM (`IDLE → CALCULATE → DONE → IDLE`) that sequences the
datapath:

- **IDLE**: waits for `start`. Asserts `load` for exactly one cycle when
  `start` is seen, to latch the initial `x`/`y`/`z` values.
- **CALCULATE**: asserts `shift_en` for exactly 16 cycles (one per CORDIC
  iteration), counted by an internal 4-bit counter.
- **DONE**: asserts `valid` for exactly one cycle, then returns to IDLE.

### `cordic_datapath.sv`
Holds the `x_q`, `y_q`, `z_q` registers and does the actual math.

- On `load`: `x_q ← 1/K` (gain-precompensated), `y_q ← 0`, `z_q ←
  angle_in`, and the 16-entry `atan(2^-i)` lookup table is loaded.
- On `shift_en`: performs one CORDIC iteration (add/subtract + shift, per
  the equations above) using `atan_queue[0]` as the current step's
  arctangent constant.
- **Arctangent lookup trick:** instead of indexing the LUT with a
  variable shift count (which needs a mux), the datapath always reads
  `atan_queue[0]` and shifts the *entire array* left by one position
  every iteration. This means `atan_queue[0]` naturally holds
  `atan(2^-i)` on iteration `i`, with no indexing logic needed.

### `cordic_top.sv`
Just wires the controller's `load`/`shift_en` outputs into the
datapath's `load`/`shift_en` inputs. `clk`, `rst`, `start`, `angle_in` go
in; `x_reg` (cos), `y_reg` (sin), `z_reg` (residual angle), and `valid`
come out. `load`/`shift_en` never leave this module — they're purely
internal wiring between the two submodules.

## 4. Timing (one transaction)

```
cycle:     1      2      3     ...    17     18     19
state:    IDLE  CALC   CALC          CALC   DONE   IDLE
start:     1     0      0             0      0      0
load:      1     0      0             0      0      0
shift_en:  0     1      1             1      0      0
valid:     0     0      0             0      1      0
```

`start` only needs to pulse for one cycle. 16 cycles after `load`,
`valid` pulses for one cycle and `x_reg`/`y_reg`/`z_reg` hold the result
until the next `load`.

## 5. Testbench (`tb_cordic_top_selfcheck.sv`)

Self-checking — no waveform inspection required to know if something's
broken. It checks three independent things and prints a final
`TOTAL CHECKS / ERRORS` summary, exiting via `$fatal` (nonzero status) on
any failure:

1. **Functional accuracy** — sweeps angles from 0° to ±99° (within the
   convergence range), compares `x_reg`/`y_reg` against `$cos`/`$sin`
   with a 0.01 tolerance, and checks that `valid` lands exactly 16 cycles
   after `start`.
2. **Protocol timing** — a background monitor taps `dut.load` and
   `dut.shift_en` and checks every transaction: `load` never exceeds 1
   cycle, `shift_en` is high for exactly 16 cycles, `valid` never exceeds
   1 cycle.
3. **Reset behavior** — starts a calculation, asserts `rst` mid-way
   through, and verifies the FSM/datapath land cleanly at zero instead of
   hanging or corrupting.

It also includes an **informational-only** section (not scored pass/fail)
that runs ±179° through the core and prints the result, to document the
expected divergence at that range rather than have it look like an
unexplained failure.

A `$dumpfile("waves.vcd")` / `$dumpvars` block is included, so `make
wave` produces a waveform you can inspect in gtkwave.

## 6. Building and running (Ubuntu, Icarus Verilog)

Install Icarus Verilog if you don't have it:

```bash
sudo apt install iverilog gtkwave
```

Then, from this directory:

```bash
make run     # compile + run the self-checking testbench
make wave    # same, then opens the waveform in gtkwave
make clean   # remove build/sim artifacts
```

`make run` exits with status 0 if all checks passed, nonzero otherwise —
safe to use in a CI/regression script.

## 7. Known limitations

- **±99.88° convergence limit** — inherent to vanilla rotation-mode
  CORDIC with 16 iterations, not a bug. Extending to the full ±180°
  requires a quadrant pre-rotation stage before the iteration loop (fold
  the input into the convergent range, then correct the sign of
  `x`/`y` afterward) — not yet implemented.
- **`ITER = 16`** is declared as a separate `localparam` in both
  `cordic_controller.sv` and `cordic_datapath.sv`. They agree today, but
  nothing enforces that if one is changed without the other.

## 8. File structure

```
cordic_controller.sv           Controller FSM
cordic_datapath.sv             x/y/z registers, atan LUT, iteration math
cordic_top.sv                  Top-level wrapper (controller + datapath)
tb_cordic_top_selfcheck.sv     Self-checking testbench
Makefile                       Build/run/wave/clean targets
.gitignore                     Icarus build artifacts, editor/OS junk
README.md                      This file
```

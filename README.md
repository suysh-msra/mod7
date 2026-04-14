# mod7
finds whether an input number is divisible by 7 using a reduction step.
not as cool as mod3, unfortunately.
# Divisibility-by-7 Hardware Checker

Hardware modules that determine whether an N-bit unsigned integer is divisible
by 7, verified with SystemVerilog Assertions (SVA) for formal proof.

## Mathematical Basis

Any non-negative integer X can be written in octal (base-8) as:

```
X = d_{k-1} * 8^{k-1} + ... + d_1 * 8 + d_0       (each d_i in 0..7)
```

Since `8 = 7 + 1`, the binomial theorem gives `8^n mod 7 = 1` for all n >= 0.
Therefore:

```
X mod 7 = (d_{k-1} + d_{k-2} + ... + d_1 + d_0) mod 7
```

The sum of face values `R = sum(d_i)` is the **reduced number**.  It is
strictly smaller than X whenever X >= 8, and it preserves the mod-7 residue.
This is the octal analogue of "casting out nines" in decimal arithmetic.

### Worked Example

```
Input:  110 010 101  (binary)  =  6*64 + 2*8 + 5  =  405

Face values:  d2=6, d1=2, d0=5
Reduced:      6 + 2 + 5 = 13
13 mod 7 = 6 != 0   -->  405 is NOT divisible by 7
```

## Repository Structure

```
mod_7/
  rtl/
    div7_combo.v          Combinational systolic pipeline
    div7_seq.v            Sequential FSM iterative reducer
  formal/
    div7_combo_sva.sv     SVA bind module for div7_combo
    div7_seq_sva.sv       SVA bind module for div7_seq
  README.md               This file
```

## Module Descriptions

### div7_combo -- Combinational / Pipelined Systolic Reducer

Each stage splits its input into 3-bit groups and sums their face values,
producing a dramatically smaller output (N bits shrinks to roughly
log2(N) + 2 bits in a single pass).  Successive stages are progressively
smaller, forming a systolic pipeline.

```
data_in [WIDTH]  -->  Stage 0  -->  [reg?]  -->  Stage 1  -->  [reg?]  --> ... --> mod-7 check
         N bits       sum triplets   ~log2(N)b    sum triplets  ~log2(log2(N))b
```

When `PIPELINE=1`, a register separates each stage for high-frequency
operation.  When `PIPELINE=0`, the entire chain is purely combinational.

| Parameter | Default | Description                                 |
|-----------|---------|---------------------------------------------|
| WIDTH     | 24      | Input bit-width (>= 1)                      |
| PIPELINE  | 1       | 0 = pure combinational; 1 = registered stages |

| Derived constant | Meaning                                        |
|------------------|------------------------------------------------|
| STAGES           | Number of reduction stages (elaboration-time)  |
| LATENCY          | Pipeline latency in clock cycles (PIPELINE ? STAGES : 0) |
| FINAL_W          | Bit-width of the value entering the mod-7 check|

**Typical STAGES values:**

| WIDTH | STAGES | Final width |
|-------|--------|-------------|
| 8     | 1      | 4           |
| 16    | 2      | 4           |
| 24    | 2      | 4           |
| 32    | 3      | 4           |
| 64    | 3      | 4           |
| 128   | 3      | 4           |

**Ports:**

| Port            | Direction | Width | Description                      |
|-----------------|-----------|-------|----------------------------------|
| clk             | input     | 1     | Clock (unused when PIPELINE=0)   |
| rst_n           | input     | 1     | Active-low reset (unused when PIPELINE=0) |
| data_in         | input     | WIDTH | Unsigned integer to test         |
| divisible_by_7  | output    | 1     | 1 if data_in is divisible by 7   |

### div7_seq -- Sequential FSM Reducer

Loads the input on a `start` pulse, then iteratively applies one full
reduction per clock cycle until the working value is below 8.  At that
point, a simple comparison yields the result.

```
        +------+       +--------+       +------+
 start  |      | load  |        | val<8 |      |
------->| IDLE |------>| REDUCE |------>| DONE |---> valid, divisible_by_7
        |      |       |  (loop)|       |      |
        +------+       +--------+       +------+
                          ^  |
                          +--+  val >= 8
```

Convergence is extremely fast: typically 2-3 cycles for any practical
input width (the reduction maps N bits to ~log2(N) bits each cycle).

| Parameter | Default | Description            |
|-----------|---------|------------------------|
| WIDTH     | 24      | Input bit-width (>= 1) |

**Ports:**

| Port            | Direction | Width | Description                           |
|-----------------|-----------|-------|---------------------------------------|
| clk             | input     | 1     | Clock                                 |
| rst_n           | input     | 1     | Active-low async reset                |
| start           | input     | 1     | Pulse to load data_in and begin       |
| data_in         | input     | WIDTH | Unsigned integer to test              |
| valid           | output    | 1     | High for one cycle when result is ready |
| divisible_by_7  | output    | 1     | Meaningful when valid == 1            |

## Formal Verification

The SVA files in `formal/` use `bind` directives to automatically attach
assertions to every instance of the corresponding RTL module.  No
modifications to the RTL are needed.

### Assertions Summary

**div7_combo_sva.sv:**

| Label             | Type   | Description                                    |
|-------------------|--------|------------------------------------------------|
| ap_output_correct | assert | Output matches `data_in % 7 == 0` (with pipeline delay) |
| ap_mod7_preserved | assert | Each stage preserves the mod-7 residue (hierarchical) |
| cp_div_seen       | cover  | Divisible input observed                       |
| cp_notdiv_seen    | cover  | Non-divisible input observed                   |

**div7_seq_sva.sv:**

| Label              | Type   | Description                                     |
|--------------------|--------|-------------------------------------------------|
| ap_invariant       | assert | REDUCE state: `work_reg % 7 == saved_input % 7` |
| ap_strict_reduce   | assert | `work_reg` decreases every REDUCE cycle (when >= 8) |
| ap_output_correct  | assert | `valid -> (div_by_7 == saved_input % 7 == 0)`   |
| ap_liveness        | assert | FSM reaches DONE within bounded cycles           |
| ap_valid_only_done | assert | `valid` only in DONE state                       |
| ap_no_bad_state    | assert | FSM stays in legal states                        |
| cp_div_result      | cover  | Divisible result completed                       |
| cp_notdiv_result   | cover  | Non-divisible result completed                   |
| cp_fast_done       | cover  | Fast convergence (input already < 8)             |

### Running with JasperGold

```tcl
# Example JasperGold setup (adapt paths as needed)
clear -all
analyze -verilog rtl/div7_combo.v
analyze -sv      formal/div7_combo_sva.sv
elaborate -top div7_combo -parameter WIDTH 24 -parameter PIPELINE 1

clock clk
reset ~rst_n

prove -all
```

For the sequential module, replace the file names and top module:

```tcl
clear -all
analyze -verilog rtl/div7_seq.v
analyze -sv      formal/div7_seq_sva.sv
elaborate -top div7_seq -parameter WIDTH 24

clock clk
reset ~rst_n

prove -all
```

### Running with SymbiYosys (open-source)

Create an `.sby` file:

```ini
[tasks]
combo_pipe
combo_comb
seq

[options]
combo_pipe: mode prove
combo_comb: mode prove
seq:        mode prove

[engines]
smtbmc z3

[script]
combo_pipe: read_verilog -formal rtl/div7_combo.v
combo_pipe: read_verilog -sv     formal/div7_combo_sva.sv
combo_pipe: hierarchy -top div7_combo
combo_pipe: chparam -set WIDTH 16 -set PIPELINE 1 div7_combo

combo_comb: read_verilog -formal rtl/div7_combo.v
combo_comb: read_verilog -sv     formal/div7_combo_sva.sv
combo_comb: hierarchy -top div7_combo
combo_comb: chparam -set WIDTH 16 -set PIPELINE 0 div7_combo

seq: read_verilog -formal rtl/div7_seq.v
seq: read_verilog -sv     formal/div7_seq_sva.sv
seq: hierarchy -top div7_seq
seq: chparam -set WIDTH 16 div7_seq

[files]
rtl/div7_combo.v
rtl/div7_seq.v
formal/div7_combo_sva.sv
formal/div7_seq_sva.sv
```

Then run:

```bash
sby -f div7.sby
```

## Instantiation Examples

### Combinational (pure logic, no clock)

```verilog
div7_combo #(
    .WIDTH   (32),
    .PIPELINE(0)
) u_div7 (
    .clk           (1'b0),        // unused
    .rst_n         (1'b1),        // unused
    .data_in       (my_input),
    .divisible_by_7(is_div7)
);
```

### Pipelined (3-stage pipeline for 32-bit input)

```verilog
div7_combo #(
    .WIDTH   (32),
    .PIPELINE(1)
) u_div7 (
    .clk           (clk),
    .rst_n         (rst_n),
    .data_in       (my_input),
    .divisible_by_7(is_div7)      // valid STAGES cycles after input
);
```

### Sequential

```verilog
div7_seq #(
    .WIDTH(32)
) u_div7 (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (go),
    .data_in       (my_input),
    .valid         (result_ready),
    .divisible_by_7(is_div7)
);
```
**FUTURE SCOPE**
To expand upon this idea (if mathematically possible) to find highest power of 7.

//-----------------------------------------------------------------------------
// SVA assertion module for div7_seq
//
// Properties verified:
//   P1 (ap_invariant)       -- In REDUCE state, work_reg preserves the
//        mod-7 residue of the originally latched input.
//   P2 (ap_strict_reduce)   -- Each REDUCE cycle with work_reg >= 8
//        produces a strictly smaller value on the next cycle.
//   P3 (ap_output_correct)  -- When valid is asserted, divisible_by_7
//        matches the golden reference (saved_input % 7 == 0).
//   P4 (ap_liveness)        -- The FSM reaches DONE within a bounded
//        number of cycles after entering REDUCE.
//   P5 (ap_valid_only_done) -- valid is asserted only in the DONE state.
//   P6 (ap_no_bad_state)    -- FSM never enters an undefined state.
//
// Cover points:
//   C1 (cp_div_result)      -- An input divisible by 7 completes.
//   C2 (cp_notdiv_result)   -- An input NOT divisible by 7 completes.
//   C3 (cp_fast_done)       -- Input < 8 goes to DONE in one REDUCE cycle.
//-----------------------------------------------------------------------------

module div7_seq_sva #(
    parameter WIDTH = 24
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             start,
    input  logic [WIDTH-1:0] data_in,
    input  logic             valid,
    input  logic             divisible_by_7,
    // Internal signals (connected via bind)
    input  logic [1:0]       state,
    input  logic [WIDTH-1:0] work_reg,
    input  logic [WIDTH-1:0] saved_input
);

    // -------------------------------------------------------------------
    // FSM encoding (must match RTL)
    // -------------------------------------------------------------------
    localparam [1:0] S_IDLE   = 2'd0,
                     S_REDUCE = 2'd1,
                     S_DONE   = 2'd2;

    // -------------------------------------------------------------------
    // Liveness bound computation
    //
    // Computes the worst-case number of REDUCE cycles for a WIDTH-bit
    // input.  Each iteration dramatically shrinks the bit-width:
    //   N bits  ->  ~log2(N) bits.
    // When the width stabilises (~4 bits), at most one more cycle is
    // needed because values still decrease monotonically (max 14 -> 7).
    // -------------------------------------------------------------------
    function automatic integer max_reduce_iters(input integer w);
        integer bits, ng, max_val, new_bits, iters;
        bits  = w;
        iters = 0;
        forever begin
            iters = iters + 1;
            if (bits <= 3) return iters;
            ng      = (bits + 2) / 3;
            max_val = 7 * ng;
            if (max_val < 8) return iters;
            new_bits = $clog2(max_val + 1);
            if (new_bits >= bits) begin
                iters = iters + 1;
                return iters;
            end
            bits = new_bits;
        end
    endfunction

    localparam MAX_CYCLES = max_reduce_iters(WIDTH);

    // -------------------------------------------------------------------
    // P1 -- Mod-7 invariant in REDUCE state
    // -------------------------------------------------------------------
    ap_invariant: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == S_REDUCE) |-> (work_reg % 7 == saved_input % 7)
    ) else $error("P1 FAIL: work_reg mod-7 != saved_input mod-7");

    // -------------------------------------------------------------------
    // P2 -- Strict reduction: value decreases each REDUCE cycle
    //        when work_reg >= 8 (more than one triplet)
    // -------------------------------------------------------------------
    ap_strict_reduce: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == S_REDUCE && work_reg >= 8) |=> (work_reg < $past(work_reg))
    ) else $error("P2 FAIL: work_reg did not decrease after reduction");

    // -------------------------------------------------------------------
    // P3 -- Output correctness
    // -------------------------------------------------------------------
    ap_output_correct: assert property (
        @(posedge clk) disable iff (!rst_n)
        valid |-> (divisible_by_7 == (saved_input % 7 == 0))
    ) else $error("P3 FAIL: divisible_by_7 does not match saved_input %% 7");

    // -------------------------------------------------------------------
    // P4 -- Liveness (bounded convergence)
    //        From entering REDUCE, the FSM must reach DONE within
    //        MAX_CYCLES cycles.
    // -------------------------------------------------------------------
    ap_liveness: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == S_REDUCE && $past(state) != S_REDUCE)
        |-> ##[1:MAX_CYCLES] (state == S_DONE)
    ) else $error("P4 FAIL: FSM did not reach DONE within %0d cycles", MAX_CYCLES);

    // -------------------------------------------------------------------
    // P5 -- valid only in DONE
    // -------------------------------------------------------------------
    ap_valid_only_done: assert property (
        @(posedge clk) disable iff (!rst_n)
        valid |-> (state == S_DONE)
    ) else $error("P5 FAIL: valid asserted outside DONE state");

    // -------------------------------------------------------------------
    // P6 -- No illegal FSM states
    // -------------------------------------------------------------------
    ap_no_bad_state: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == S_IDLE) || (state == S_REDUCE) || (state == S_DONE)
    ) else $error("P6 FAIL: FSM in illegal state %0b", state);

    // -------------------------------------------------------------------
    // Cover points
    // -------------------------------------------------------------------
    cp_div_result: cover property (
        @(posedge clk) disable iff (!rst_n)
        valid && divisible_by_7
    );

    cp_notdiv_result: cover property (
        @(posedge clk) disable iff (!rst_n)
        valid && !divisible_by_7
    );

    cp_fast_done: cover property (
        @(posedge clk) disable iff (!rst_n)
        (state == S_REDUCE && work_reg < 8)
    );

endmodule

// -------------------------------------------------------------------
// Bind directive -- attaches the checker to every instance of div7_seq
// -------------------------------------------------------------------
bind div7_seq div7_seq_sva #(
    .WIDTH(WIDTH)
) u_sva (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (start),
    .data_in       (data_in),
    .valid         (valid),
    .divisible_by_7(divisible_by_7),
    .state         (state),
    .work_reg      (work_reg),
    .saved_input   (saved_input)
);

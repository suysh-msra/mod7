//-----------------------------------------------------------------------------
// SVA assertion module for div7_combo
//
// Properties verified:
//   P1 (ap_output_correct)  -- The divisible_by_7 output matches the golden
//        reference (data_in % 7 == 0), accounting for pipeline latency.
//   P2 (ap_mod7_preserved)  -- Each internal stage preserves the mod-7
//        residue of its input (requires hierarchical access; see generate
//        block below).
//   C1 (cp_div_seen)        -- Cover: an input divisible by 7 is observed.
//   C2 (cp_notdiv_seen)     -- Cover: an input NOT divisible by 7 is seen.
//-----------------------------------------------------------------------------

module div7_combo_sva #(
    parameter WIDTH    = 24,
    parameter PIPELINE = 1
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] data_in,
    input  logic             divisible_by_7
);

    // -------------------------------------------------------------------
    // Recompute pipeline latency (mirrors RTL elaboration functions)
    // -------------------------------------------------------------------
    function automatic integer ceil_div3(input integer x);
        return (x + 2) / 3;
    endfunction

    function automatic integer reduce_width(input integer w);
        integer ng, max_sum, bits;
        ng = ceil_div3(w);
        if (ng <= 1) return w;
        max_sum = 7 * ng;
        bits = $clog2(max_sum + 1);
        return bits;
    endfunction

    function automatic integer calc_stages(input integer w);
        integer ww, rw, cnt;
        ww = w; cnt = 0; rw = reduce_width(ww);
        while (rw < ww) begin
            cnt = cnt + 1;
            ww  = rw;
            rw  = reduce_width(ww);
        end
        return cnt;
    endfunction

    function automatic integer stage_w(input integer s);
        integer idx, w;
        w = WIDTH;
        for (idx = 0; idx < s; idx = idx + 1)
            w = reduce_width(w);
        return w;
    endfunction

    localparam STAGES  = calc_stages(WIDTH);
    localparam LATENCY = (PIPELINE != 0) ? STAGES : 0;
    localparam FINAL_W = stage_w(STAGES);

    // -------------------------------------------------------------------
    // P1 -- Output correctness
    // -------------------------------------------------------------------
    generate
    if (LATENCY > 0) begin : g_pipe_track
        // Shift register that shadows the pipeline latency
        logic [WIDTH-1:0] data_pipe [0:LATENCY-1];

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                for (int k = 0; k < LATENCY; k++) data_pipe[k] <= '0;
            end else begin
                data_pipe[0] <= data_in;
                for (int k = 1; k < LATENCY; k++)
                    data_pipe[k] <= data_pipe[k-1];
            end
        end

        ap_output_correct: assert property (
            @(posedge clk) disable iff (!rst_n)
            divisible_by_7 == (data_pipe[LATENCY-1] % 7 == 0)
        ) else $error("P1 FAIL: divisible_by_7 mismatch (pipelined, latency=%0d)",
                       LATENCY);

        // Cover: divisible input propagates through the pipeline
        cp_div_seen: cover property (
            @(posedge clk) disable iff (!rst_n)
            divisible_by_7 == 1'b1
        );

        cp_notdiv_seen: cover property (
            @(posedge clk) disable iff (!rst_n)
            divisible_by_7 == 1'b0
        );

    end else begin : g_comb_check
        // Purely combinational -- no latency
        ap_output_correct: assert property (
            @(posedge clk) disable iff (!rst_n)
            divisible_by_7 == (data_in % 7 == 0)
        ) else $error("P1 FAIL: divisible_by_7 mismatch (combinational)");

        cp_div_seen: cover property (
            @(posedge clk) disable iff (!rst_n)
            divisible_by_7 == 1'b1
        );

        cp_notdiv_seen: cover property (
            @(posedge clk) disable iff (!rst_n)
            divisible_by_7 == 1'b0
        );
    end
    endgenerate

    // -------------------------------------------------------------------
    // P2 -- Per-stage mod-7 preservation  (hierarchical access)
    //
    // These assertions reach into the DUT generate hierarchy.  Because the
    // bind instantiates this module *inside* the DUT scope, the relative
    // path g_reduce.stg[s] is valid.
    //
    // Each stage's combinational sum must satisfy:
    //   sum_comb % 7 == stage_input % 7
    //
    // When PIPELINE=1, the registered value must also preserve the residue
    // of the input that was captured on the same clock edge.
    // -------------------------------------------------------------------
    generate
    if (STAGES > 0) begin : g_stage_checks
        genvar gs;
        for (gs = 0; gs < STAGES; gs = gs + 1) begin : chk
            localparam S_IN_W  = stage_w(gs);
            localparam S_OUT_W = stage_w(gs + 1);

            // Combinational residue invariant
            ap_mod7_preserved: assert property (
                @(posedge clk) disable iff (!rst_n)
                (g_reduce.stg[gs].sum_comb % 7) ==
                (g_reduce.stg[gs].stg_in   % 7)
            ) else $error("P2 FAIL: stage %0d mod-7 mismatch", gs);
        end
    end
    endgenerate

endmodule

// -------------------------------------------------------------------
// Bind directive -- attaches the checker to every instance of div7_combo
// -------------------------------------------------------------------
bind div7_combo div7_combo_sva #(
    .WIDTH   (WIDTH),
    .PIPELINE(PIPELINE)
) u_sva (
    .clk           (clk),
    .rst_n         (rst_n),
    .data_in       (data_in),
    .divisible_by_7(divisible_by_7)
);

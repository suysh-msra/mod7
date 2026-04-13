//-----------------------------------------------------------------------------
// Module: mod7_1024_systolic
//
// Pipelined systolic divisibility-by-7 checker for wide inputs.
//
// Exploits  64 = 63 + 1 = 7x9 + 1  =>  64 ≡ 1 (mod 7).
// Grouping the input into 6-bit digits and summing their face values
// preserves the mod-7 residue while dramatically shrinking the number.
//
// Architecture
// ~~~~~~~~~~~~
// A chain of progressively narrower reduction stages, each registered:
//
//   data_in [WIDTH] -> Stage 0 -> [reg] -> Stage 1 -> [reg] -> ... -> LUT
//        1024b         171 PEs     14b       3 PEs      8b
//
// Each "PE" (processing element) extracts a 6-bit face value and feeds a
// parallel adder tree.  All PEs within a stage operate concurrently.
//
// Parameters
//   WIDTH    -- input bit-width (default 1024)
//   LUT_TYPE -- 64: 6-bit LUT + subtract-63 correction
//               128: 7-bit LUT, direct lookup
//
// Pipeline latency: STAGES clock cycles  (3 for WIDTH=1024)
// Throughput:       1 result / cycle  (after pipeline fill)
//-----------------------------------------------------------------------------

module mod7_1024_systolic #(
    parameter WIDTH    = 1024,
    parameter LUT_TYPE = 64
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] data_in,
    output wire             divisible_by_7
);

    // -------------------------------------------------------------------
    // Elaboration-time helpers (6-bit grouping)
    // -------------------------------------------------------------------
    function integer clog2f;
        input integer value;
        integer tmp;
        begin
            clog2f = 0;
            tmp    = value - 1;
            while (tmp > 0) begin
                clog2f = clog2f + 1;
                tmp    = tmp >> 1;
            end
        end
    endfunction

    function integer ceil_div6;
        input integer x;
        begin
            ceil_div6 = (x + 5) / 6;
        end
    endfunction

    function integer reduce6_width;
        input integer w;
        integer ng;
        begin
            ng = ceil_div6(w);
            if (ng <= 1)
                reduce6_width = w;
            else
                reduce6_width = clog2f(63 * ng + 1);
        end
    endfunction

    function integer stage_w;
        input integer s;
        integer idx, w;
        begin
            w = WIDTH;
            for (idx = 0; idx < s; idx = idx + 1)
                w = reduce6_width(w);
            stage_w = w;
        end
    endfunction

    function integer calc_stages;
        integer w, rw, cnt;
        begin
            w   = WIDTH;
            cnt = 0;
            rw  = reduce6_width(w);
            while (rw < w) begin
                cnt = cnt + 1;
                w   = rw;
                rw  = reduce6_width(w);
            end
            calc_stages = cnt;
        end
    endfunction

    // -------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------
    localparam STAGES  = calc_stages();
    localparam FINAL_W = stage_w(STAGES);
    localparam LATENCY = STAGES;

    // -------------------------------------------------------------------
    // Implementation
    // -------------------------------------------------------------------
    generate
    if (STAGES == 0) begin : g_trivial
        // No reduction possible (WIDTH <= 7).  Direct LUT check.
        if (LUT_TYPE == 128) begin : g_l128
            wire [6:0] v = {{(7 - FINAL_W){1'b0}}, data_in[FINAL_W-1:0]};
            mod7_lut128 u_lut (.val_in(v), .divisible_by_7(divisible_by_7));
        end else begin : g_l64
            wire [6:0] v = {{(7 - FINAL_W){1'b0}}, data_in[FINAL_W-1:0]};
            wire [6:0] s1 = v - 7'd63;
            wire [5:0] adj = (v <= 7'd63) ? v[5:0] : s1[5:0];
            mod7_lut64 u_lut (.val_in(adj), .divisible_by_7(divisible_by_7));
        end

    end else begin : g_reduce
        // Wide bus connecting consecutive stages (only lower bits used).
        wire [WIDTH-1:0] stage_conn [0:STAGES];
        assign stage_conn[0] = data_in;

        genvar s;
        for (s = 0; s < STAGES; s = s + 1) begin : stg
            localparam S_IN_W  = stage_w(s);
            localparam S_OUT_W = stage_w(s + 1);
            localparam N_GRP   = ceil_div6(S_IN_W);
            localparam PAD_W   = N_GRP * 6;

            wire [S_IN_W-1:0] stg_in;
            assign stg_in = stage_conn[s][S_IN_W-1:0];

            // Zero-pad to a multiple of 6 for clean slicing
            wire [PAD_W-1:0] padded;
            if (PAD_W > S_IN_W) begin : g_pad
                assign padded = {{(PAD_W - S_IN_W){1'b0}}, stg_in};
            end else begin : g_nopad
                assign padded = stg_in;
            end

            // Parallel adder tree -- N_GRP "PEs" operating concurrently
            reg [S_OUT_W-1:0] sum_comb;
            integer i;
            always @(*) begin
                sum_comb = {S_OUT_W{1'b0}};
                for (i = 0; i < N_GRP; i = i + 1)
                    sum_comb = sum_comb + padded[i*6 +: 6];
            end

            // Pipeline register
            reg [S_OUT_W-1:0] sum_reg;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    sum_reg <= {S_OUT_W{1'b0}};
                else
                    sum_reg <= sum_comb;
            end

            assign stage_conn[s+1] = {{(WIDTH - S_OUT_W){1'b0}}, sum_reg};
        end

        // -------------------------------------------------------------
        // Final LUT check on the reduced 7-bit value
        // -------------------------------------------------------------
        wire [6:0] final_val = stage_conn[STAGES][6:0];

        if (LUT_TYPE == 128) begin : g_lut128
            mod7_lut128 u_lut (
                .val_in        (final_val),
                .divisible_by_7(divisible_by_7)
            );
        end else begin : g_lut64
            // Correction: subtract 63 (≡ 0 mod 7) to bring 7-bit
            // value into the 6-bit LUT range.  Max final_val from
            // the reduction chain is 126; 126 − 63 = 63.
            wire [6:0] s1  = final_val - 7'd63;
            wire [5:0] adj = (final_val <= 7'd63) ? final_val[5:0]
                                                  : s1[5:0];
            mod7_lut64 u_lut (
                .val_in        (adj),
                .divisible_by_7(divisible_by_7)
            );
        end
    end
    endgenerate

endmodule

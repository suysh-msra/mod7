//-----------------------------------------------------------------------------
// Module: mod7_combo
//
// Parameterized divisibility-by-7 checker using octal face-value reduction.
// Exploits 8 ≡ 1 (mod 7): the sum of 3-bit (octal) digit face values of a
// number preserves its mod-7 residue while producing a much smaller number.
//
// Architecture: multi-stage systolic pipeline.  Each stage splits its input
// into 3-bit groups and sums the face values, shrinking the bit-width
// dramatically (N -> ~log2(N)).  Optional pipeline registers (PIPELINE=1)
// separate stages for high-frequency operation.
//
// Parameters
//   WIDTH    -- input bit-width  (>= 1)
//   PIPELINE -- 0: purely combinational;  1: registered between stages
//
// Pipeline latency (PIPELINE=1): STAGES clock cycles
// Pipeline latency (PIPELINE=0): 0 (purely combinational)
//-----------------------------------------------------------------------------

module mod7_combo #(
    parameter WIDTH    = 24,
    parameter PIPELINE = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] data_in,
    output wire             divisible_by_7
);

    // -------------------------------------------------------------------
    // Elaboration-time helper functions
    // -------------------------------------------------------------------

    // ceil(log2(value))  -- returns minimum bits to represent 0..value-1
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

    function integer ceil_div3;
        input integer x;
        begin
            ceil_div3 = (x + 2) / 3;
        end
    endfunction

    // Bit-width after one full reduction of a w-bit value.
    // If only one triplet exists, no width reduction is possible.
    function integer reduce_width;
        input integer w;
        integer ng;
        begin
            ng = ceil_div3(w);
            if (ng <= 1)
                reduce_width = w;
            else
                reduce_width = clog2f(7 * ng + 1);
        end
    endfunction

    // Input bit-width at stage s (stage 0 = original WIDTH)
    function integer stage_w;
        input integer s;
        integer i, w;
        begin
            w = WIDTH;
            for (i = 0; i < s; i = i + 1)
                w = reduce_width(w);
            stage_w = w;
        end
    endfunction

    // Total number of reduction stages (iterate until width stabilises)
    function integer calc_stages;
        integer w, rw, cnt;
        begin
            w   = WIDTH;
            cnt = 0;
            rw  = reduce_width(w);
            while (rw < w) begin
                cnt = cnt + 1;
                w   = rw;
                rw  = reduce_width(w);
            end
            calc_stages = cnt;
        end
    endfunction

    // -------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------
    localparam STAGES  = calc_stages();
    localparam FINAL_W = stage_w(STAGES);
    localparam LATENCY = (PIPELINE != 0) ? STAGES : 0;

    // -------------------------------------------------------------------
    // Implementation
    // -------------------------------------------------------------------
    generate
    if (STAGES == 0) begin : g_trivial
        // WIDTH is small enough that no reduction helps; check directly.
        assign divisible_by_7 = (data_in % 7 == 0);

    end else begin : g_reduce
        // Wide bus array connecting consecutive stages.
        // Each element is WIDTH bits; only the lower stage_w(s) bits
        // carry meaningful data at stage s.
        wire [WIDTH-1:0] stage_conn [0:STAGES];
        assign stage_conn[0] = data_in;

        genvar s;
        for (s = 0; s < STAGES; s = s + 1) begin : stg
            localparam S_IN_W  = stage_w(s);
            localparam S_OUT_W = stage_w(s + 1);
            localparam N_GRP   = ceil_div3(S_IN_W);
            localparam PAD_W   = N_GRP * 3;

            // Extract meaningful bits from the inter-stage bus
            wire [S_IN_W-1:0] stg_in;
            assign stg_in = stage_conn[s][S_IN_W-1:0];

            // Zero-pad to a multiple of 3 for clean triplet slicing
            wire [PAD_W-1:0] padded;
            if (PAD_W > S_IN_W) begin : g_pad
                assign padded = {{(PAD_W - S_IN_W){1'b0}}, stg_in};
            end else begin : g_nopad
                assign padded = stg_in;
            end

            // Combinational: sum all 3-bit face values
            reg [S_OUT_W-1:0] sum_comb;
            integer i;
            always @(*) begin
                sum_comb = {S_OUT_W{1'b0}};
                for (i = 0; i < N_GRP; i = i + 1)
                    sum_comb = sum_comb + padded[i*3 +: 3];
            end

            // Drive the next stage's bus (with optional pipeline register)
            if (PIPELINE != 0) begin : g_pipe
                reg [S_OUT_W-1:0] sum_reg;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n)
                        sum_reg <= {S_OUT_W{1'b0}};
                    else
                        sum_reg <= sum_comb;
                end
                assign stage_conn[s+1] =
                    {{(WIDTH - S_OUT_W){1'b0}}, sum_reg};
            end else begin : g_nopipe
                assign stage_conn[s+1] =
                    {{(WIDTH - S_OUT_W){1'b0}}, sum_comb};
            end
        end

        // Final mod-7 check on the small reduced value
        wire [FINAL_W-1:0] final_val;
        assign final_val     = stage_conn[STAGES][FINAL_W-1:0];
        assign divisible_by_7 = (final_val % 7 == 0);
    end
    endgenerate

endmodule

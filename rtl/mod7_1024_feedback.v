//-----------------------------------------------------------------------------
// Module: mod7_1024_feedback
//
// Sequential (feedback) divisibility-by-7 checker for wide inputs.
//
// Uses the same 6-bit face-value reduction as mod7_1024_systolic but
// applies it iteratively through a single reduction unit with a mux:
//
//   data_in --->[ MUX ]---> [ REDUCE (parallel adder tree) ] ---> face_sum
//                 ^    work_reg                                      |
//                 |                                                  v
//                 +----- feedback -----<------- [ work_reg ] <-------+
//                                                    |
//                                          if small: [ LUT ] -> result
//
// Parameters
//   WIDTH    -- input bit-width (default 1024)
//   LUT_TYPE -- 64:  reduce until <= 63,  then 6-bit LUT lookup
//               128: reduce until <= 127, then 7-bit LUT lookup
//
// Typical latency from start to valid (WIDTH = 1024):
//   LUT_TYPE = 128: 4 cycles  (1024 -> 14 -> 8 -> 7b, fits LUT)
//   LUT_TYPE =  64: 4-5 cycles (may need one extra cycle for 64-66)
//-----------------------------------------------------------------------------

module mod7_1024_feedback #(
    parameter WIDTH    = 1024,
    parameter LUT_TYPE = 64
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [WIDTH-1:0] data_in,
    output reg              valid,
    output reg              divisible_by_7
);

    // -------------------------------------------------------------------
    // Elaboration-time helper
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

    // -------------------------------------------------------------------
    // Derived constants
    // -------------------------------------------------------------------
    localparam N_GRP   = (WIDTH + 5) / 6;
    localparam PAD_W   = N_GRP * 6;
    localparam SUM_W   = clog2f(63 * N_GRP + 1);
    localparam LUT_MAX = (LUT_TYPE == 128) ? 127 : 63;

    // -------------------------------------------------------------------
    // FSM encoding
    // -------------------------------------------------------------------
    localparam [1:0] S_IDLE   = 2'd0,
                     S_REDUCE = 2'd1,
                     S_DONE   = 2'd2;

    reg [1:0]       state;
    reg [WIDTH-1:0] work_reg;

    // -------------------------------------------------------------------
    // Combinational 6-bit face-value reduction
    // All N_GRP PEs (adders) operate in parallel.
    // -------------------------------------------------------------------
    wire [PAD_W-1:0] padded;
    generate
        if (PAD_W > WIDTH) begin : g_pad
            assign padded = {{(PAD_W - WIDTH){1'b0}}, work_reg};
        end else begin : g_nopad
            assign padded = work_reg[PAD_W-1:0];
        end
    endgenerate

    reg [SUM_W-1:0] face_sum;
    integer i;
    always @(*) begin
        face_sum = {SUM_W{1'b0}};
        for (i = 0; i < N_GRP; i = i + 1)
            face_sum = face_sum + padded[i*6 +: 6];
    end

    // -------------------------------------------------------------------
    // LUT -- always connected, read when entering DONE
    // -------------------------------------------------------------------
    wire lut_result;
    generate
        if (LUT_TYPE == 128) begin : g_lut128
            mod7_lut128 u_lut (
                .val_in        (work_reg[6:0]),
                .divisible_by_7(lut_result)
            );
        end else begin : g_lut64
            mod7_lut64 u_lut (
                .val_in        (work_reg[5:0]),
                .divisible_by_7(lut_result)
            );
        end
    endgenerate

    // -------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            work_reg       <= {WIDTH{1'b0}};
            valid          <= 1'b0;
            divisible_by_7 <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    valid <= 1'b0;
                    if (start) begin
                        work_reg <= data_in;
                        state    <= S_REDUCE;
                    end
                end

                S_REDUCE: begin
                    if (work_reg <= LUT_MAX) begin
                        state          <= S_DONE;
                        valid          <= 1'b1;
                        divisible_by_7 <= lut_result;
                    end else begin
                        work_reg <= {{(WIDTH - SUM_W){1'b0}}, face_sum};
                    end
                end

                S_DONE: begin
                    if (start) begin
                        work_reg       <= data_in;
                        state          <= S_REDUCE;
                        valid          <= 1'b0;
                        divisible_by_7 <= 1'b0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

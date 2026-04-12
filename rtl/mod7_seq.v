//-----------------------------------------------------------------------------
// Module: mod7_seq
//
// Sequential (FSM-based) divisibility-by-7 checker.  Uses the same octal
// face-value reduction as div7_combo but applies it iteratively: each clock
// cycle performs one full reduction pass, shrinking the working value until
// it fits in 3 bits (0-7).  Convergence is very fast -- typically 2-3 cycles
// for any practical WIDTH.
//
// Parameters
//   WIDTH -- input bit-width (>= 1)
//
// Interface
//   start    -- pulse high for one cycle to load data_in and begin
//   valid    -- asserted for one cycle when the result is ready
//   divisible_by_7 -- meaningful when valid == 1
//
// FSM states
//   IDLE    -- waiting for start
//   REDUCE  -- iteratively reducing; one pass per cycle
//   DONE    -- result available (valid == 1)
//-----------------------------------------------------------------------------

module mod7_seq #(
    parameter WIDTH = 24
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [WIDTH-1:0] data_in,
    output reg              valid,
    output reg              divisible_by_7
);

    // -------------------------------------------------------------------
    // FSM encoding
    // -------------------------------------------------------------------
    localparam [1:0] S_IDLE   = 2'd0,
                     S_REDUCE = 2'd1,
                     S_DONE   = 2'd2;

    reg [1:0]       state;
    reg [WIDTH-1:0] work_reg;
    reg [WIDTH-1:0] saved_input;  // retained for formal-verification reference

    // -------------------------------------------------------------------
    // Combinational reduction -- sum of 3-bit face values of work_reg
    // -------------------------------------------------------------------
    localparam N_GRP = (WIDTH + 2) / 3;
    localparam PAD_W = N_GRP * 3;

    wire [PAD_W-1:0] padded;
    generate
        if (PAD_W > WIDTH) begin : g_pad
            assign padded = {{(PAD_W - WIDTH){1'b0}}, work_reg};
        end else begin : g_nopad
            assign padded = work_reg;
        end
    endgenerate

    reg [WIDTH-1:0] triplet_sum;
    integer i;
    always @(*) begin
        triplet_sum = {WIDTH{1'b0}};
        for (i = 0; i < N_GRP; i = i + 1)
            triplet_sum = triplet_sum + padded[i*3 +: 3];
    end

    // -------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            work_reg       <= {WIDTH{1'b0}};
            saved_input    <= {WIDTH{1'b0}};
            valid          <= 1'b0;
            divisible_by_7 <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    valid <= 1'b0;
                    if (start) begin
                        work_reg    <= data_in;
                        saved_input <= data_in;
                        state       <= S_REDUCE;
                    end
                end

                S_REDUCE: begin
                    // Terminate when the value fits in one triplet (0-7).
                    // Note: reduction of a single-triplet value returns
                    // itself, so we must stop here to avoid an infinite loop
                    // (e.g. 7 -> 7 -> 7 ...).
                    if (work_reg < 8) begin
                        state          <= S_DONE;
                        valid          <= 1'b1;
                        divisible_by_7 <= (work_reg == {WIDTH{1'b0}})
                                        | (work_reg == {{(WIDTH-3){1'b0}}, 3'd7});
                    end else begin
                        work_reg <= triplet_sum;
                    end
                end

                S_DONE: begin
                    if (start) begin
                        work_reg       <= data_in;
                        saved_input    <= data_in;
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

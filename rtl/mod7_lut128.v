//-----------------------------------------------------------------------------
// Module: mod7_lut128
//
// 128-entry lookup table for divisibility by 7, covering inputs 0-127.
//
// The polynomial product tree with primes {2,3,5,7} generates all
// 7-smooth multiples of 7.  For the range [64,127] three additional
// primes are required:
//
//   7 x 11 = 77       (11 is prime)
//   7 x 13 = 91       (13 is prime)
//   7 x 17 = 119      (17 is prime)
//
// 7-smooth multiples in [64,127] from the polynomial tree:
//   7 x 10  = 70      7 x 12 = 84      7 x 14 = 98
//   7 x 15  = 105     7 x 16 = 112     7 x 18 = 126
//
// Complete set of multiples of 7 in [0,127]:
//   {0, 7, 14, 21, 28, 35, 42, 49, 56, 63,
//    70, 77, 84, 91, 98, 105, 112, 119, 126}
//
// LUT bit i = 1  iff  i mod 7 == 0.
//-----------------------------------------------------------------------------

module mod7_lut128 (
    input  wire [6:0] val_in,
    output wire       divisible_by_7
);

    localparam [127:0] LUT = 128'h40810204081020408102040810204081;

    assign divisible_by_7 = LUT[val_in];

endmodule

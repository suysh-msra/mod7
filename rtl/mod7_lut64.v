//-----------------------------------------------------------------------------
// Module: div7_lut64
//
// 64-entry lookup table for divisibility by 7, covering inputs 0-63.
//
// LUT Generation via Binary Polynomial Multiplication
// ====================================================
// In binary, integers map to polynomials in x = 2:
//   7  = 111   = x^2 + x + 1
//   2  = 10    = x
//   3  = 11    = x + 1
//   5  = 101   = x^2 + 1
//
// Multiplying these polynomials with carry (standard binary multiplication)
// produces all multiples of 7 whose co-factor is 7-smooth (prime factors
// drawn from {2, 3, 5, 7}).  Since every integer 1..9 factors into these
// primes, the recursive product tree generates ALL multiples of 7 in [0,63]:
//
//   Base: 7
//   7 x 2       = 14       7 x 5       = 35
//   7 x 3       = 21       7 x 7       = 49
//   7 x 2^2     = 28       7 x 2 x 3   = 42
//   7 x 2^3     = 56       7 x 3^2     = 63
//   0  (trivially divisible)
//
// LUT bit i = 1  iff  i in {0,7,14,21,28,35,42,49,56,63}.
//-----------------------------------------------------------------------------

module div7_lut64 (
    input  wire [5:0] val_in,
    output wire       divisible_by_7
);

    localparam [63:0] LUT = 64'h8102040810204081;

    assign divisible_by_7 = LUT[val_in];

endmodule

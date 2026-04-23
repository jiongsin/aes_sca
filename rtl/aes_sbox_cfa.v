module aes_sbox_cfa (
    input  [7:0] data_in,
    output [7:0] data_out
);
    wire [7:0] mapped;
    wire [3:0] high_nibble;
    wire [3:0] low_nibble;
    
    wire [3:0] high_squared_scaled;
    wire [3:0] low_squared;
    wire [3:0] high_times_low;
    wire [3:0] middle_sum;
    wire [3:0] middle_inverse;
    
    wire [3:0] high_xor_low;
    wire [3:0] high_out;
    wire [3:0] low_out;
    wire [7:0] inverse_data;

    // Step 1 Isomorphic Mapping
    assign mapped[7] = data_in[7] ^ data_in[5];
    assign mapped[6] = data_in[7] ^ data_in[6] ^ data_in[4] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign mapped[5] = data_in[7] ^ data_in[5] ^ data_in[3] ^ data_in[2];
    assign mapped[4] = data_in[7] ^ data_in[5] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign mapped[3] = data_in[7] ^ data_in[6] ^ data_in[2] ^ data_in[1];
    assign mapped[2] = data_in[7] ^ data_in[4] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign mapped[1] = data_in[6] ^ data_in[4] ^ data_in[1];
    assign mapped[0] = data_in[6] ^ data_in[1] ^ data_in[0];

    assign high_nibble = mapped[7:4];
    assign low_nibble = mapped[3:0];

    // Step 2 Calculate middle values in the small field
    // Square high nibble and multiply by constant
    assign high_squared_scaled[3] = high_nibble[3] ^ high_nibble[1];
    assign high_squared_scaled[2] = high_nibble[3] ^ high_nibble[2] ^ high_nibble[1];
    assign high_squared_scaled[1] = high_nibble[3] ^ high_nibble[0];
    assign high_squared_scaled[0] = high_nibble[2] ^ high_nibble[1] ^ high_nibble[0];

    // Square low nibble
    assign low_squared[3] = low_nibble[3];
    assign low_squared[2] = low_nibble[3] ^ low_nibble[2];
    assign low_squared[1] = low_nibble[2] ^ low_nibble[1];
    assign low_squared[0] = low_nibble[3] ^ low_nibble[1] ^ low_nibble[0];

    // Multiply high and low nibbles
    gf_mul_4bit mul_high_low (
        .a(high_nibble),
        .b(low_nibble),
        .p(high_times_low)
    );

    // Add middle parts together
    assign middle_sum = high_squared_scaled ^ low_squared ^ high_times_low;

    // Inverse the middle sum using the new structural block
    gf_inv_4bit inv_middle (
        .x(middle_sum),
        .y(middle_inverse)
    );

    // Multiply by inverse to get outputs
    gf_mul_4bit mul_high_out (
        .a(high_nibble),
        .b(middle_inverse),
        .p(high_out)
    );

    assign high_xor_low = high_nibble ^ low_nibble;

    gf_mul_4bit mul_low_out (
        .a(high_xor_low),
        .b(middle_inverse),
        .p(low_out)
    );

    assign inverse_data = {high_out, low_out};

    // Step 3 Inverse Mapping and final mix
    assign data_out[7] = inverse_data[7] ^ inverse_data[6] ^ inverse_data[5] ^ inverse_data[1] ^ 1'b0;
    assign data_out[6] = inverse_data[6] ^ inverse_data[2] ^ 1'b1;
    assign data_out[5] = inverse_data[6] ^ inverse_data[5] ^ inverse_data[4] ^ inverse_data[3] ^ inverse_data[2] ^ inverse_data[1] ^ 1'b1;
    assign data_out[4] = inverse_data[5] ^ inverse_data[4] ^ inverse_data[3] ^ inverse_data[2] ^ inverse_data[1] ^ 1'b0;
    assign data_out[3] = inverse_data[7] ^ inverse_data[6] ^ inverse_data[5] ^ inverse_data[4] ^ inverse_data[3] ^ inverse_data[1] ^ 1'b0;
    assign data_out[2] = inverse_data[7] ^ inverse_data[2] ^ inverse_data[1] ^ inverse_data[0] ^ 1'b0;
    assign data_out[1] = inverse_data[7] ^ inverse_data[6] ^ inverse_data[2] ^ inverse_data[1] ^ inverse_data[0] ^ 1'b1;
    assign data_out[0] = inverse_data[7] ^ inverse_data[6] ^ inverse_data[5] ^ inverse_data[4] ^ inverse_data[2] ^ inverse_data[0] ^ 1'b1;

endmodule

module gf_mul_4bit (
    input  [3:0] a,
    input  [3:0] b,
    output [3:0] p
);
    // Small Galois Field multiplier logic
    assign p[0] = (a[0]&b[0]) ^ (a[3]&b[1]) ^ (a[2]&b[2]) ^ (a[1]&b[3]);
    assign p[1] = (a[1]&b[0]) ^ (a[0]&b[1]) ^ (a[3]&b[2]) ^ (a[2]&b[3]) ^ (a[3]&b[1]) ^ (a[2]&b[2]) ^ (a[1]&b[3]);
    assign p[2] = (a[2]&b[0]) ^ (a[1]&b[1]) ^ (a[0]&b[2]) ^ (a[3]&b[3]) ^ (a[3]&b[2]) ^ (a[2]&b[3]);
    assign p[3] = (a[3]&b[0]) ^ (a[2]&b[1]) ^ (a[1]&b[2]) ^ (a[0]&b[3]) ^ (a[3]&b[3]);
endmodule

module gf_inv_4bit (
    input  [3:0] x,
    output [3:0] y
);
    // Wire declarations for inputs and inverted inputs
    wire x3 = x[3];
    wire x2 = x[2];
    wire x1 = x[1];
    wire x0 = x[0];
    
    wire nx3 = ~x[3];
    wire nx2 = ~x[2];
    wire nx1 = ~x[1];
    wire nx0 = ~x[0];

    // Equations using only AND XOR and NOT gates
    // You can apply masking directly to these AND terms
    
    // Bit 3 logic
    assign y[3] = (nx3 & nx2 & x1) ^ 
                  (nx3 & x2 & nx1) ^ 
                  (x3 & nx1 & nx0) ^ 
                  (x3 & nx2 & x1 & nx0) ^ 
                  (x3 & x2 & x1 & x0);

    // Bit 2 logic
    assign y[2] = (nx3 & x2 & x1) ^ 
                  (x3 & nx2 & x1) ^ 
                  (nx3 & nx2 & x1 & x0) ^ 
                  (nx3 & x2 & nx1 & nx0) ^ 
                  (x3 & nx2 & nx1 & nx0) ^ 
                  (x3 & x2 & nx1 & x0);

    // Bit 1 logic
    assign y[1] = (nx3 & x2 & x1) ^ 
                  (x3 & nx2 & nx1) ^ 
                  (nx2 & x1 & x0) ^ 
                  (nx3 & x2 & nx1 & x0) ^ 
                  (x3 & x2 & x1 & nx0);

    // Bit 0 logic
    assign y[0] = (nx3 & x2 & nx1) ^ 
                  (nx3 & x1 & nx0) ^ 
                  (nx3 & nx2 & nx1 & x0) ^ 
                  (x3 & nx2 & nx1 & nx0) ^ 
                  (x3 & nx2 & x1 & x0) ^ 
                  (x3 & x2 & x1 & nx0);

endmodule

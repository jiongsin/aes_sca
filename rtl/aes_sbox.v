module aes_sbox (
    input  [7:0] data_in,
    output [7:0] data_out
);
    wire [7:0] mapped, inverted, restored;

    isomorphic_mapping map_unit      (.in(data_in),  .out(mapped));
    multiplicative_inverter inv_unit (.in(mapped),   .out(inverted));
    inverse_mapping restore_unit     (.in(inverted), .out(restored));
    affine_transformation aff_unit   (.in(restored), .out(data_out));
endmodule

module affine_transformation (
    input  [7:0] in,
    output [7:0] out
);
    assign out[0] = in[0] ^ in[4] ^ in[5] ^ in[6] ^ in[7] ^ 1'b1;
    assign out[1] = in[1] ^ in[5] ^ in[6] ^ in[7] ^ in[0] ^ 1'b1;
    assign out[2] = in[2] ^ in[6] ^ in[7] ^ in[0] ^ in[1] ^ 1'b0;
    assign out[3] = in[3] ^ in[7] ^ in[0] ^ in[1] ^ in[2] ^ 1'b0;
    assign out[4] = in[4] ^ in[0] ^ in[1] ^ in[2] ^ in[3] ^ 1'b0;
    assign out[5] = in[5] ^ in[1] ^ in[2] ^ in[3] ^ in[4] ^ 1'b1;
    assign out[6] = in[6] ^ in[2] ^ in[3] ^ in[4] ^ in[5] ^ 1'b1;
    assign out[7] = in[7] ^ in[3] ^ in[4] ^ in[5] ^ in[6] ^ 1'b0;
endmodule

module isomorphic_mapping (
    input  [7:0] in,
    output [7:0] out
);
    assign out[7] = in[7] ^ in[5];
    assign out[6] = in[7] ^ in[6] ^ in[4] ^ in[3] ^ in[2] ^ in[1];
    assign out[5] = in[7] ^ in[5] ^ in[3] ^ in[2];
    assign out[4] = in[7] ^ in[5] ^ in[3] ^ in[2] ^ in[1];
    assign out[3] = in[7] ^ in[6] ^ in[2] ^ in[1];
    assign out[2] = in[7] ^ in[4] ^ in[3] ^ in[2] ^ in[1];
    assign out[1] = in[6] ^ in[4] ^ in[1];
    assign out[0] = in[6] ^ in[1] ^ in[0];
endmodule

module inverse_mapping (
    input  [7:0] in,
    output [7:0] out
);
    assign out[7] = in[7] ^ in[6] ^ in[5] ^ in[1];
    assign out[6] = in[6] ^ in[2];
    assign out[5] = in[6] ^ in[5] ^ in[1];
    assign out[4] = in[6] ^ in[5] ^ in[4] ^ in[2] ^ in[1];
    assign out[3] = in[5] ^ in[4] ^ in[3] ^ in[2] ^ in[1];
    assign out[2] = in[7] ^ in[4] ^ in[3] ^ in[2] ^ in[1];
    assign out[1] = in[5] ^ in[4];
    assign out[0] = in[6] ^ in[5] ^ in[4] ^ in[2] ^ in[0];
endmodule

module multiplicative_inverter (
    input  [7:0] in,
    output [7:0] out
);
    wire [3:0] b = in[7:4], c = in[3:0];
    wire [3:0] b_sq, b_sq_lambda, b_plus_c, c_mul_bplusc, combined, combined_inv;
    wire [3:0] out_h, out_l;

    assign b_sq[3] = b[3];
    assign b_sq[2] = b[3] ^ b[2];
    assign b_sq[1] = b[2] ^ b[1];
    assign b_sq[0] = b[3] ^ b[1] ^ b[0];

    assign b_sq_lambda[3] = b_sq[2] ^ b_sq[0];
    assign b_sq_lambda[2] = b_sq[3] ^ b_sq[2] ^ b_sq[1] ^ b_sq[0];
    assign b_sq_lambda[1] = b_sq[3];
    assign b_sq_lambda[0] = b_sq[2];

    assign b_plus_c = b ^ c; 
    gf4_multiplier mul_inst (.q(c), .a(b_plus_c), .k(c_mul_bplusc));
    assign combined = b_sq_lambda ^ c_mul_bplusc;

    gf4_inverter inv4_inst (.q(combined), .q_inv(combined_inv));

    gf4_multiplier mul_high (.q(b), .a(combined_inv), .k(out_h));
    gf4_multiplier mul_low (.q(b_plus_c), .a(combined_inv), .k(out_l));

    assign out = {out_h, out_l};
endmodule

module gf4_multiplier (
    input  [3:0] q, a,
    output [3:0] k
);
    wire [1:0] qh = q[3:2], ql = q[1:0];
    wire [1:0] ah = a[3:2], al = a[1:0];
    wire [1:0] mul_hh, mul_ll, mul_hl_lh, ph_phi;

    gf2_multiplier m1 (.q(qh), .a(ah), .k(mul_hh));
    gf2_multiplier m2 (.q(ql), .a(al), .k(mul_ll));
    gf2_multiplier m3 (.q(qh ^ ql), .a(ah ^ al), .k(mul_hl_lh));

    assign ph_phi[1] = mul_hh[1] ^ mul_hh[0];
    assign ph_phi[0] = mul_hh[1];
    
    assign k = {(mul_hl_lh ^ mul_ll), (ph_phi ^ mul_ll)};
endmodule

module gf2_multiplier (
    input  [1:0] q, a,
    output [1:0] k
);
    assign k[1] = (q[1] & a[1]) ^ (q[0] & a[1]) ^ (q[1] & a[0]);
    assign k[0] = (q[1] & a[1]) ^ (q[0] & a[0]);
endmodule

module gf4_inverter (
    input  [3:0] q,
    output [3:0] q_inv
);
    assign q_inv[3] = q[3] ^ (q[3] & q[2] & q[1]) ^ (q[3] & q[0]) ^ q[2];
    assign q_inv[2] = (q[3] & q[2] & q[1]) ^ (q[3] & q[2] & q[0]) ^ (q[3] & q[0]) ^ (q[2] & q[1]) ^ q[2];
    assign q_inv[1] = (q[3] & q[2] & q[1]) ^ (q[3] & q[1] & q[0]) ^ (q[2] & q[0]) ^ q[3] ^ q[2] ^ q[1];
    assign q_inv[0] = (q[3] & q[2] & q[1]) ^ (q[3] & q[2] & q[0]) ^ (q[3] & q[1] & q[0]) ^ 
                      (q[2] & q[1] & q[0]) ^ (q[3] & q[0]) ^ (q[3] & q[1]) ^ (q[2] & q[1]) ^ 
                      q[2] ^ q[0] ^ q[1];
endmodule

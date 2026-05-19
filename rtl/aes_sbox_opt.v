module aes_sbox_opt (
    input  [7:0] data_in,
    output [7:0] data_out
);
    wire [7:0] mapped, inverted, restored;

    isomorphic_mapping_opt map_unit      (.data_in(data_in),  .data_out(mapped));
    multiplicative_inverter_opt inv_unit (.data_in(mapped),   .data_out(inverted));
    inverse_mapping_opt restore_unit     (.data_in(inverted), .data_out(restored));
    affine_transformation_opt aff_unit   (.data_in(restored), .data_out(data_out));
endmodule

module affine_transformation_opt (
    input  [7:0] data_in,
    output [7:0] data_out
);
    assign data_out[0] = data_in[0] ^ data_in[4] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ 1'b1;
    assign data_out[1] = data_in[1] ^ data_in[5] ^ data_in[6] ^ data_in[7] ^ data_in[0] ^ 1'b1;
    assign data_out[2] = data_in[2] ^ data_in[6] ^ data_in[7] ^ data_in[0] ^ data_in[1] ^ 1'b0;
    assign data_out[3] = data_in[3] ^ data_in[7] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ 1'b0;
    assign data_out[4] = data_in[4] ^ data_in[0] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ 1'b0;
    assign data_out[5] = data_in[5] ^ data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ 1'b1;
    assign data_out[6] = data_in[6] ^ data_in[2] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ 1'b1;
    assign data_out[7] = data_in[7] ^ data_in[3] ^ data_in[4] ^ data_in[5] ^ data_in[6] ^ 1'b0;
endmodule

module isomorphic_mapping_opt (
    input  [7:0] data_in,
    output [7:0] data_out
);
    assign data_out[7] = data_in[7] ^ data_in[5];
    assign data_out[6] = data_in[7] ^ data_in[6] ^ data_in[4] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign data_out[5] = data_in[7] ^ data_in[5] ^ data_in[3] ^ data_in[2];
    assign data_out[4] = data_in[7] ^ data_in[5] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign data_out[3] = data_in[7] ^ data_in[6] ^ data_in[2] ^ data_in[1];
    assign data_out[2] = data_in[7] ^ data_in[4] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign data_out[1] = data_in[6] ^ data_in[4] ^ data_in[1];
    assign data_out[0] = data_in[6] ^ data_in[1] ^ data_in[0];
endmodule

module inverse_mapping_opt (
    input  [7:0] data_in,
    output [7:0] data_out
);
    assign data_out[7] = data_in[7] ^ data_in[6] ^ data_in[5] ^ data_in[1];
    assign data_out[6] = data_in[6] ^ data_in[2];
    assign data_out[5] = data_in[6] ^ data_in[5] ^ data_in[1];
    assign data_out[4] = data_in[6] ^ data_in[5] ^ data_in[4] ^ data_in[2] ^ data_in[1];
    assign data_out[3] = data_in[5] ^ data_in[4] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign data_out[2] = data_in[7] ^ data_in[4] ^ data_in[3] ^ data_in[2] ^ data_in[1];
    assign data_out[1] = data_in[5] ^ data_in[4];
    assign data_out[0] = data_in[6] ^ data_in[5] ^ data_in[4] ^ data_in[2] ^ data_in[0];
endmodule

module multiplicative_inverter_opt (
    input  [7:0] data_in,
    output [7:0] data_out
);
    wire [3:0] b = data_in[7:4], c = data_in[3:0];
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
    gf4_multiplier_opt mul_inst (.q(c), .a(b_plus_c), .k(c_mul_bplusc));
    assign combined = b_sq_lambda ^ c_mul_bplusc;

    gf4_inverter_opt inv4_inst (.q(combined), .q_inv(combined_inv));

    gf4_multiplier_opt mul_high (.q(b), .a(combined_inv), .k(out_h));
    gf4_multiplier_opt mul_low (.q(b_plus_c), .a(combined_inv), .k(out_l));

    assign data_out = {out_h, out_l};
endmodule

module gf4_multiplier_opt (
    input  [3:0] q, a,
    output [3:0] k
);
    wire [1:0] qh = q[3:2], ql = q[1:0];
    wire [1:0] ah = a[3:2], al = a[1:0];
    wire [1:0] mul_hh, mul_ll, mul_hl_lh, ph_phi;

    gf2_multiplier_opt m1 (.q(qh), .a(ah), .k(mul_hh));
    gf2_multiplier_opt m2 (.q(ql), .a(al), .k(mul_ll));
    gf2_multiplier_opt m3 (.q(qh ^ ql), .a(ah ^ al), .k(mul_hl_lh));

    assign ph_phi[1] = mul_hh[1] ^ mul_hh[0];
    assign ph_phi[0] = mul_hh[1];
    
    assign k = {(mul_hl_lh ^ mul_ll), (ph_phi ^ mul_ll)};
endmodule

module gf2_multiplier_opt (
    input  [1:0] q, a,
    output [1:0] k
);
    assign k[1] = (q[1] & a[1]) ^ (q[0] & a[1]) ^ (q[1] & a[0]);
    assign k[0] = (q[1] & a[1]) ^ (q[0] & a[0]);
endmodule

module gf4_inverter_opt (
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

// -----------------------------------------------------------------------------
// Module: aes_sbox_sca
// Description: Masked side-channel-aware AES S-box top level.
//              Maps shared input bytes into composite-field form, performs masked inversion, and restores the affine-transformed shared output bytes.
// -----------------------------------------------------------------------------
module aes_sbox_sca (
    input clk,
    input rst_n,
    input  [7:0] data_in_0,
    input  [7:0] data_in_1,
    input  [35:0] random_bits,
    output [7:0] data_out_0,
    output [7:0] data_out_1
);
    wire [7:0] mapped_0, mapped_1;
    wire [7:0] inverted_0, inverted_1;

    isomorphic_mapping_sca map_unit (
        .data_in_0(data_in_0), .data_in_1(data_in_1),
        .data_out_0(mapped_0), .data_out_1(mapped_1)
    );

    multiplicative_inverter_sca inv_unit (
        .clk(clk),
        .rst_n(rst_n),
        .data_in_0(mapped_0), .data_in_1(mapped_1),
        .r(random_bits),
        .data_out_0(inverted_0), .data_out_1(inverted_1)
    );

    merged_inverse_affine_sca restore_and_aff_unit (
        .data_in_0(inverted_0), .data_in_1(inverted_1),
        .data_out_0(data_out_0), .data_out_1(data_out_1)
    );
endmodule

// -----------------------------------------------------------------------------
// Module: isomorphic_mapping_sca
// Description: Composite-field isomorphic mapping for shared S-box inputs.
//              Applies the linear basis transformation independently to each masked share.
// -----------------------------------------------------------------------------
module isomorphic_mapping_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    wire s0_0 = data_in_0[7] ^ data_in_0[5];
    wire s1_0 = data_in_0[3] ^ data_in_0[2];
    wire s2_0 = data_in_0[6] ^ data_in_0[1];
    wire s3_0 = data_in_0[4] ^ s1_0;
    wire s4_0 = s0_0 ^ s1_0;

    assign data_out_0[7] = s0_0;
    assign data_out_0[6] = data_in_0[7] ^ s2_0 ^ s3_0;
    assign data_out_0[5] = s4_0;
    assign data_out_0[4] = s4_0 ^ data_in_0[1];
    assign data_out_0[3] = data_in_0[7] ^ s2_0 ^ data_in_0[2];
    assign data_out_0[2] = data_in_0[7] ^ s3_0 ^ data_in_0[1];
    assign data_out_0[1] = s2_0 ^ data_in_0[4];
    assign data_out_0[0] = s2_0 ^ data_in_0[0];

    wire s0_1 = data_in_1[7] ^ data_in_1[5];
    wire s1_1 = data_in_1[3] ^ data_in_1[2];
    wire s2_1 = data_in_1[6] ^ data_in_1[1];
    wire s3_1 = data_in_1[4] ^ s1_1;
    wire s4_1 = s0_1 ^ s1_1;

    assign data_out_1[7] = s0_1;
    assign data_out_1[6] = data_in_1[7] ^ s2_1 ^ s3_1;
    assign data_out_1[5] = s4_1;
    assign data_out_1[4] = s4_1 ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[7] ^ s2_1 ^ data_in_1[2];
    assign data_out_1[2] = data_in_1[7] ^ s3_1 ^ data_in_1[1];
    assign data_out_1[1] = s2_1 ^ data_in_1[4];
    assign data_out_1[0] = s2_1 ^ data_in_1[0];
endmodule

// -----------------------------------------------------------------------------
// Module: multiplicative_inverter_sca
// Description: Masked composite-field multiplicative inverter.
//              Splits mapped shares into GF(2^4) components and uses DOM-protected operations with supplied randomness to compute the inverse.
// -----------------------------------------------------------------------------
module multiplicative_inverter_sca (
    input clk,
    input rst_n,
    input  [7:0] data_in_0, data_in_1,
    input  [35:0] r,
    output [7:0] data_out_0, data_out_1
);
    wire [3:0] b_0 = data_in_0[7:4], c_0 = data_in_0[3:0];
    wire [3:0] b_1 = data_in_1[7:4], c_1 = data_in_1[3:0];

    wire [3:0] b_plus_c_0 = b_0 ^ c_0;
    wire [3:0] b_plus_c_1 = b_1 ^ c_1;

    wire [3:0] c_mul_bplusc_0, c_mul_bplusc_1;

    gf4_multiplier_sca mul_inst (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(c_0), .q_1(c_1), .a_0(b_plus_c_0), .a_1(b_plus_c_1),
        .r(r[8:0]), .k_0(c_mul_bplusc_0), .k_1(c_mul_bplusc_1)
    );

    reg [3:0] b_0_d1, b_1_d1, b_plus_c_0_d1, b_plus_c_1_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_0_d1        <= 4'd0;
            b_1_d1        <= 4'd0;
            b_plus_c_0_d1 <= 4'd0;
            b_plus_c_1_d1 <= 4'd0;
        end else begin
            b_0_d1        <= b_0; 
            b_1_d1        <= b_1;
            b_plus_c_0_d1 <= b_plus_c_0; 
            b_plus_c_1_d1 <= b_plus_c_1;
        end
    end

    wire [3:0] b_sq_0_d1, b_sq_1_d1;
    wire [3:0] b_sq_lambda_0_d1, b_sq_lambda_1_d1;

    assign b_sq_0_d1[3] = b_0_d1[3];
    assign b_sq_0_d1[2] = b_0_d1[3] ^ b_0_d1[2];
    assign b_sq_0_d1[1] = b_0_d1[2] ^ b_0_d1[1];
    assign b_sq_0_d1[0] = b_0_d1[3] ^ b_0_d1[1] ^ b_0_d1[0];

    assign b_sq_1_d1[3] = b_1_d1[3];
    assign b_sq_1_d1[2] = b_1_d1[3] ^ b_1_d1[2];
    assign b_sq_1_d1[1] = b_1_d1[2] ^ b_1_d1[1];
    assign b_sq_1_d1[0] = b_1_d1[3] ^ b_1_d1[1] ^ b_1_d1[0];

    assign b_sq_lambda_0_d1[3] = b_sq_0_d1[2] ^ b_sq_0_d1[0];
    assign b_sq_lambda_0_d1[2] = b_sq_0_d1[3] ^ b_sq_0_d1[2] ^ b_sq_0_d1[1] ^ b_sq_0_d1[0];
    assign b_sq_lambda_0_d1[1] = b_sq_0_d1[3];
    assign b_sq_lambda_0_d1[0] = b_sq_0_d1[2];

    assign b_sq_lambda_1_d1[3] = b_sq_1_d1[2] ^ b_sq_1_d1[0];
    assign b_sq_lambda_1_d1[2] = b_sq_1_d1[3] ^ b_sq_1_d1[2] ^ b_sq_1_d1[1] ^ b_sq_1_d1[0];
    assign b_sq_lambda_1_d1[1] = b_sq_1_d1[3];
    assign b_sq_lambda_1_d1[0] = b_sq_1_d1[2];

    wire [3:0] combined_0 = b_sq_lambda_0_d1 ^ c_mul_bplusc_0;
    wire [3:0] combined_1 = b_sq_lambda_1_d1 ^ c_mul_bplusc_1;

    wire [3:0] combined_inv_0, combined_inv_1;

    gf4_inverter_sca inv4_inst (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(combined_0), .q_1(combined_1),
        .r(r[17:9]), .q_inv_0(combined_inv_0), .q_inv_1(combined_inv_1)
    );

    reg [3:0] b_0_d2, b_1_d2, b_plus_c_0_d2, b_plus_c_1_d2;
    reg [3:0] b_0_d3, b_1_d3, b_plus_c_0_d3, b_plus_c_1_d3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_0_d2        <= 4'd0; 
            b_1_d2        <= 4'd0;
            b_plus_c_0_d2 <= 4'd0; 
            b_plus_c_1_d2 <= 4'd0;
            b_0_d3        <= 4'd0; 
            b_1_d3        <= 4'd0;
            b_plus_c_0_d3 <= 4'd0; 
            b_plus_c_1_d3 <= 4'd0;
        end else begin
            b_0_d2        <= b_0_d1; 
            b_1_d2        <= b_1_d1;
            b_plus_c_0_d2 <= b_plus_c_0_d1; 
            b_plus_c_1_d2 <= b_plus_c_1_d1;

            b_0_d3        <= b_0_d2; 
            b_1_d3        <= b_1_d2;
            b_plus_c_0_d3 <= b_plus_c_0_d2; 
            b_plus_c_1_d3 <= b_plus_c_1_d2;
        end
    end

    wire [3:0] out_h_0, out_h_1, out_l_0, out_l_1;

    gf4_multiplier_sca mul_high (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(b_0_d3), .q_1(b_1_d3), .a_0(combined_inv_0), .a_1(combined_inv_1),
        .r(r[26:18]), .k_0(out_h_0), .k_1(out_h_1)
    );

    gf4_multiplier_sca mul_low (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(b_plus_c_0_d3), .q_1(b_plus_c_1_d3), .a_0(combined_inv_0), .a_1(combined_inv_1),
        .r(r[35:27]), .k_0(out_l_0), .k_1(out_l_1)
    );

    assign data_out_0 = {out_h_0, out_l_0};
    assign data_out_1 = {out_h_1, out_l_1};
endmodule

// -----------------------------------------------------------------------------
// Module: merged_inverse_affine_sca
// Description: Inverse mapping and AES affine transform for shared S-box outputs.
//              Combines the composite-field restore step with the affine layer while preserving the two-share representation.
// -----------------------------------------------------------------------------
module merged_inverse_affine_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    wire [7:0] inv_0, inv_1;

    wire s0_0 = data_in_0[6] ^ data_in_0[5];
    wire s1_0 = data_in_0[2] ^ data_in_0[1];
    wire s2_0 = data_in_0[5] ^ data_in_0[4];
    wire s3_0 = data_in_0[4] ^ s1_0;
    wire s4_0 = s0_0 ^ data_in_0[1];

    assign inv_0[7] = data_in_0[7] ^ s4_0;
    assign inv_0[6] = data_in_0[6] ^ data_in_0[2];
    assign inv_0[5] = s4_0;
    assign inv_0[4] = s0_0 ^ s3_0;
    assign inv_0[3] = s2_0 ^ data_in_0[3] ^ s1_0;
    assign inv_0[2] = data_in_0[7] ^ data_in_0[3] ^ s3_0;
    assign inv_0[1] = s2_0;
    assign inv_0[0] = data_in_0[6] ^ s2_0 ^ data_in_0[2] ^ data_in_0[0];

    wire s0_1 = data_in_1[6] ^ data_in_1[5];
    wire s1_1 = data_in_1[2] ^ data_in_1[1];
    wire s2_1 = data_in_1[5] ^ data_in_1[4];
    wire s3_1 = data_in_1[4] ^ s1_1;
    wire s4_1 = s0_1 ^ data_in_1[1];

    assign inv_1[7] = data_in_1[7] ^ s4_1;
    assign inv_1[6] = data_in_1[6] ^ data_in_1[2];
    assign inv_1[5] = s4_1;
    assign inv_1[4] = s0_1 ^ s3_1;
    assign inv_1[3] = s2_1 ^ data_in_1[3] ^ s1_1;
    assign inv_1[2] = data_in_1[7] ^ data_in_1[3] ^ s3_1;
    assign inv_1[1] = s2_1;
    assign inv_1[0] = data_in_1[6] ^ s2_1 ^ data_in_1[2] ^ data_in_1[0];

    wire t0_0 = inv_0[0] ^ inv_0[1];
    wire t1_0 = inv_0[2] ^ inv_0[3];
    wire t2_0 = inv_0[4] ^ inv_0[5];
    wire t3_0 = inv_0[6] ^ inv_0[7];

    assign data_out_0[0] = inv_0[0] ^ t2_0 ^ t3_0 ^ 1'b1;
    assign data_out_0[1] = inv_0[5] ^ t0_0 ^ t3_0 ^ 1'b1;
    assign data_out_0[2] = inv_0[2] ^ t0_0 ^ t3_0;
    assign data_out_0[3] = inv_0[7] ^ t0_0 ^ t1_0;
    assign data_out_0[4] = inv_0[4] ^ t0_0 ^ t1_0;
    assign data_out_0[5] = inv_0[1] ^ t1_0 ^ t2_0 ^ 1'b1;
    assign data_out_0[6] = inv_0[6] ^ t1_0 ^ t2_0 ^ 1'b1;
    assign data_out_0[7] = inv_0[3] ^ t2_0 ^ t3_0;

    wire t0_1 = inv_1[0] ^ inv_1[1];
    wire t1_1 = inv_1[2] ^ inv_1[3];
    wire t2_1 = inv_1[4] ^ inv_1[5];
    wire t3_1 = inv_1[6] ^ inv_1[7];

    assign data_out_1[0] = inv_1[0] ^ t2_1 ^ t3_1;
    assign data_out_1[1] = inv_1[5] ^ t0_1 ^ t3_1;
    assign data_out_1[2] = inv_1[2] ^ t0_1 ^ t3_1;
    assign data_out_1[3] = inv_1[7] ^ t0_1 ^ t1_1;
    assign data_out_1[4] = inv_1[4] ^ t0_1 ^ t1_1;
    assign data_out_1[5] = inv_1[1] ^ t1_1 ^ t2_1;
    assign data_out_1[6] = inv_1[6] ^ t1_1 ^ t2_1;
    assign data_out_1[7] = inv_1[3] ^ t2_1 ^ t3_1;
endmodule

// -----------------------------------------------------------------------------
// Module: gf4_inverter_sca
// Description: Masked GF(2^4) inverter used inside the composite-field S-box.
//              Computes inverse shares with DOM AND gates and random-bit inputs.
// -----------------------------------------------------------------------------
module gf4_inverter_sca (
    input clk,
    input rst_n,
    input  [3:0] q_0, q_1,
    input  [8:0] r,
    output [3:0] q_inv_0, q_inv_1
);
    wire [1:0] qh_0 = q_0[3:2], ql_0 = q_0[1:0];
    wire [1:0] qh_1 = q_1[3:2], ql_1 = q_1[1:0];

    wire [1:0] qh_mul_ql_0, qh_mul_ql_1;

    gf2_multiplier_sca m_det (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(qh_0), .q_1(qh_1), .a_0(ql_0), .a_1(ql_1),
        .r(r[2:0]), .k_0(qh_mul_ql_0), .k_1(qh_mul_ql_1)
    );

    reg [1:0] qh_0_d1, qh_1_d1, ql_0_d1, ql_1_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qh_0_d1 <= 2'd0;
            qh_1_d1 <= 2'd0;
            ql_0_d1 <= 2'd0;
            ql_1_d1 <= 2'd0;
        end else begin
            qh_0_d1 <= qh_0; 
            qh_1_d1 <= qh_1;
            ql_0_d1 <= ql_0; 
            ql_1_d1 <= ql_1;
        end
    end

    wire [1:0] qh_sq_phi_0_d1 = {qh_0_d1[0], qh_0_d1[1]};
    wire [1:0] qh_sq_phi_1_d1 = {qh_1_d1[0], qh_1_d1[1]};

    wire [1:0] ql_sq_0_d1 = {ql_0_d1[1], ql_0_d1[1] ^ ql_0_d1[0]};
    wire [1:0] ql_sq_1_d1 = {ql_1_d1[1], ql_1_d1[1] ^ ql_1_d1[0]};

    wire [1:0] det_0 = qh_sq_phi_0_d1 ^ ql_sq_0_d1 ^ qh_mul_ql_0;
    wire [1:0] det_1 = qh_sq_phi_1_d1 ^ ql_sq_1_d1 ^ qh_mul_ql_1;

    wire [1:0] inv_det_0 = {det_0[1], det_0[1] ^ det_0[0]};
    wire [1:0] inv_det_1 = {det_1[1], det_1[1] ^ det_1[0]};

    wire [1:0] q_inv_h_0, q_inv_h_1;
    gf2_multiplier_sca m_h (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(qh_0_d1), .q_1(qh_1_d1), .a_0(inv_det_0), .a_1(inv_det_1),
        .r(r[5:3]), .k_0(q_inv_h_0), .k_1(q_inv_h_1)
    );

    wire [1:0] q_inv_l_0, q_inv_l_1;
    gf2_multiplier_sca m_l (
        .clk(clk),
        .rst_n(rst_n),
        .q_0(qh_0_d1 ^ ql_0_d1), .q_1(qh_1_d1 ^ ql_1_d1), .a_0(inv_det_0), .a_1(inv_det_1),
        .r(r[8:6]), .k_0(q_inv_l_0), .k_1(q_inv_l_1)
    );

    assign q_inv_0 = {q_inv_h_0, q_inv_l_0};
    assign q_inv_1 = {q_inv_h_1, q_inv_l_1};
endmodule

// -----------------------------------------------------------------------------
// Module: gf4_multiplier_sca
// Description: Masked GF(2^4) multiplier.
//              Builds nibble multiplication from shared GF(2) products and DOM-protected cross terms.
// -----------------------------------------------------------------------------
module gf4_multiplier_sca (
    input clk,
    input rst_n,
    input  [3:0] q_0, q_1, a_0, a_1,
    input  [8:0] r,
    output [3:0] k_0, k_1
);
    wire [1:0] qh_0 = q_0[3:2], ql_0 = q_0[1:0];
    wire [1:0] qh_1 = q_1[3:2], ql_1 = q_1[1:0];
    wire [1:0] ah_0 = a_0[3:2], al_0 = a_0[1:0];
    wire [1:0] ah_1 = a_1[3:2], al_1 = a_1[1:0];

    wire [1:0] mul_hh_0, mul_hh_1;
    wire [1:0] mul_ll_0, mul_ll_1;
    wire [1:0] mul_hl_lh_0, mul_hl_lh_1;

    gf2_multiplier_sca m1 (.clk(clk), .rst_n(rst_n), .q_0(qh_0), .q_1(qh_1), .a_0(ah_0), .a_1(ah_1), .r(r[2:0]), .k_0(mul_hh_0), .k_1(mul_hh_1));
    gf2_multiplier_sca m2 (.clk(clk), .rst_n(rst_n), .q_0(ql_0), .q_1(ql_1), .a_0(al_0), .a_1(al_1), .r(r[5:3]), .k_0(mul_ll_0), .k_1(mul_ll_1));
    gf2_multiplier_sca m3 (.clk(clk), .rst_n(rst_n), .q_0(qh_0 ^ ql_0), .q_1(qh_1 ^ ql_1), .a_0(ah_0 ^ al_0), .a_1(ah_1 ^ al_1), .r(r[8:6]), .k_0(mul_hl_lh_0), .k_1(mul_hl_lh_1));

    wire [1:0] ph_phi_0, ph_phi_1;
    assign ph_phi_0[1] = mul_hh_0[1] ^ mul_hh_0[0];
    assign ph_phi_0[0] = mul_hh_0[1];
    assign ph_phi_1[1] = mul_hh_1[1] ^ mul_hh_1[0];
    assign ph_phi_1[0] = mul_hh_1[1];

    assign k_0 = {(mul_hl_lh_0 ^ mul_ll_0), (ph_phi_0 ^ mul_ll_0)};
    assign k_1 = {(mul_hl_lh_1 ^ mul_ll_1), (ph_phi_1 ^ mul_ll_1)};
endmodule

// -----------------------------------------------------------------------------
// Module: gf2_multiplier_sca
// Description: Masked GF(2) multiplier for single-bit shares.
//              Uses the DOM AND primitive to produce protected product shares.
// -----------------------------------------------------------------------------
module gf2_multiplier_sca (
    input clk,
    input rst_n,
    input  [1:0] q_0, q_1, a_0, a_1,
    input  [2:0] r,
    output [1:0] k_0, k_1
);
    wire t0_0, t0_1, t1_0, t1_1, t2_0, t2_1;

    dom_and_sca and0 (
        .clk(clk),
        .rst_n(rst_n),
        .a_0(q_0[0]), .a_1(q_1[0]), .b_0(a_0[0]), .b_1(a_1[0]), .z(r[0]),
        .c_0(t0_0), .c_1(t0_1)
    );

    dom_and_sca and1 (
        .clk(clk),
        .rst_n(rst_n),
        .a_0(q_0[1]), .a_1(q_1[1]), .b_0(a_0[1]), .b_1(a_1[1]), .z(r[1]),
        .c_0(t1_0), .c_1(t1_1)
    );

    dom_and_sca and2 (
        .clk(clk),
        .rst_n(rst_n),
        .a_0(q_0[1] ^ q_0[0]), .a_1(q_1[1] ^ q_1[0]),
        .b_0(a_0[1] ^ a_0[0]), .b_1(a_1[1] ^ a_1[0]), .z(r[2]),
        .c_0(t2_0), .c_1(t2_1)
    );

    assign k_0[1] = t2_0 ^ t0_0;
    assign k_1[1] = t2_1 ^ t0_1;

    assign k_0[0] = t1_0 ^ t0_0;
    assign k_1[0] = t1_1 ^ t0_1;
endmodule

// -----------------------------------------------------------------------------
// Module: dom_and_sca
// Description: Domain-oriented masked AND gate.
//              Combines two-share operands with one random bit to generate first-order protected AND output shares.
// -----------------------------------------------------------------------------
module dom_and_sca (
    input clk,
    input rst_n,
    input a_0, a_1, b_0, b_1, z,
    output c_0, c_1
);
    wire inner_0 = a_0 & b_0;
    wire inner_1 = a_1 & b_1;

    wire cross_0_comb = (a_0 & b_1) ^ z;
    wire cross_1_comb = (a_1 & b_0) ^ z;

    reg cross_0_reg, cross_1_reg;
    reg inner_0_reg, inner_1_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cross_0_reg <= 1'b0;
            cross_1_reg <= 1'b0;
            inner_0_reg <= 1'b0;
            inner_1_reg <= 1'b0;
        end else begin
            cross_0_reg <= cross_0_comb;
            cross_1_reg <= cross_1_comb;
            inner_0_reg <= inner_0;
            inner_1_reg <= inner_1;
        end
    end

    assign c_0 = inner_0_reg ^ cross_0_reg;
    assign c_1 = inner_1_reg ^ cross_1_reg;
endmodule


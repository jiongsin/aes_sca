module aes_operation #(
    parameter MODE = 128
) (
    input clk, rst_n, valid_in,
    input [MODE-1:0] key,
    input [127:0] data_in,
    output reg valid_out,
    output reg [127:0] data_out
);

    localparam Nr = (MODE == 192) ? 12 : (MODE == 256) ? 14 : 10;

    localparam S_IDLE       = 2'b00;
    localparam S_INIT       = 2'b01;
    localparam S_CALC       = 2'b10;
    localparam S_DONE       = 2'b11;

    reg [1:0]   state;
    reg [3:0]   round_ctr;
    reg [127:0] state_reg, current_data_in;
    reg [MODE-1:0] full_key_reg;

    wire [3:0] rcon_step = round_ctr;
    wire [MODE-1:0] next_key_gen;
    wire [127:0]    round_out;

    key_expansion_otf #(MODE) key_gen_unit (
        .key_in(full_key_reg),
        .round_step(rcon_step),
        .key_out(next_key_gen)
    );

    aes_round u_round (
        .data_in(state_reg),
        .round_key_in(full_key_reg[MODE-1 -: 128]),
        .is_last_round(round_ctr == Nr),
        .data_out(round_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
			round_ctr <= 4'd0;
			data_out <= 4'd0;
            valid_out <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    valid_out <= 1'b0;
					round_ctr <= 4'd0;
					data_out <= 4'd0;
                    if (valid_in) begin
                        current_data_in <= data_in;
                        full_key_reg <= key;
                        state <= S_INIT;
                    end
                end

                S_INIT: begin
                    state_reg <= current_data_in ^ (full_key_reg[MODE-1 -: 128]);
                    full_key_reg <= next_key_gen;
                    round_ctr <= round_ctr + 1'b1;
                    state <= S_CALC;
                end

                S_CALC: begin
                    state_reg <= round_out;
                    if (round_ctr == Nr) state <= S_DONE;
                    else begin
                        round_ctr <= round_ctr + 1'b1;
                        full_key_reg <= next_key_gen;
                    end
                end

                S_DONE: begin
                    data_out <= state_reg;
                    valid_out <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule

module aes_round (
    input  [127:0] data_in,
    input  [127:0] round_key_in,
    input  is_last_round,
    output wire [127:0] data_out
);

    wire [127:0] sbox_out, shift_out, mix_out;

    genvar i;
    generate
        for (i=0; i<16; i=i+1) begin : sbox_gen
            aes_sbox sbox_inst (
                .in(data_in[8*i +: 8]),
                .out(sbox_out[8*i +: 8])
            );
        end
    endgenerate

    aes_shift_rows shift_u (
        .data_in(sbox_out),
        .data_out(shift_out)
    );

    aes_mix_columns mix_u (
        .data_in(shift_out),
        .data_out(mix_out)
    );

    assign data_out = is_last_round ? (shift_out ^ round_key_in) : (mix_out ^ round_key_in);

endmodule

module aes_shift_rows (
    input  [127:0] data_in,
    output [127:0] data_out
);
    // Row 0
    assign data_out[127:120] = data_in[127:120];
    assign data_out[ 95: 88] = data_in[ 95: 88];
    assign data_out[ 63: 56] = data_in[ 63: 56];
    assign data_out[ 31: 24] = data_in[ 31: 24];
    // Row 1
    assign data_out[119:112] = data_in[ 87: 80];
    assign data_out[ 87: 80] = data_in[ 55: 48];
    assign data_out[ 55: 48] = data_in[ 23: 16];
    assign data_out[ 23: 16] = data_in[119:112];
    // Row 2
    assign data_out[111:104] = data_in[ 47: 40];
    assign data_out[ 79: 72] = data_in[ 15:  8];
    assign data_out[ 47: 40] = data_in[111:104];
    assign data_out[ 15:  8] = data_in[ 79: 72];
    // Row 3
    assign data_out[103: 96] = data_in[  7:  0];
    assign data_out[ 71: 64] = data_in[103: 96];
    assign data_out[ 39: 32] = data_in[ 71: 64];
    assign data_out[  7:  0] = data_in[ 39: 32];
endmodule

module aes_mix_columns (
    input  [127:0] data_in,
    output [127:0] data_out
);
    genvar i;
    generate
        for (i=0; i<4; i=i+1) begin : col
            wire [7:0] s0 = data_in[i*32 + 24 +: 8];
            wire [7:0] s1 = data_in[i*32 + 16 +: 8];
            wire [7:0] s2 = data_in[i*32 +  8 +: 8];
            wire [7:0] s3 = data_in[i*32 +  0 +: 8];

            wire [7:0] t  = s0 ^ s1 ^ s2 ^ s3;
            wire [7:0] v0 = s0 ^ s1;
            wire [7:0] v1 = s1 ^ s2;
            wire [7:0] v2 = s2 ^ s3;
            wire [7:0] v3 = s3 ^ s0;

            function [7:0] xtime(input [7:0] x);
                begin
                    xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h0);
                end
            endfunction

            wire [7:0] x_v0 = xtime(v0);
            wire [7:0] x_v1 = xtime(v1);
            wire [7:0] x_v2 = xtime(v2);
            wire [7:0] x_v3 = xtime(v3);

            assign data_out[i*32 + 24 +: 8] = s0 ^ t ^ x_v0;
            assign data_out[i*32 + 16 +: 8] = s1 ^ t ^ x_v1;
            assign data_out[i*32 +  8 +: 8] = s2 ^ t ^ x_v2;
            assign data_out[i*32 +  0 +: 8] = s3 ^ t ^ x_v3;
        end
    endgenerate
endmodule

module key_expansion_otf #(
    parameter MODE = 128
)(
    input  [MODE-1:0] key_in,
    input  [3:0]      round_step,
    output [MODE-1:0] key_out
);
    localparam Nk = MODE / 32;
    wire [31:0] w [0:Nk-1];
    
    genvar i;
    generate
        for (i = 0; i < Nk; i = i + 1) assign w[i] = key_in[MODE-1 - i*32 -: 32];
    endgenerate

    function [31:0] rcon_val(input [3:0] r);
        case(r)
            4'd0: rcon_val = 32'h01000000; 4'd1: rcon_val = 32'h02000000;
            4'd2: rcon_val = 32'h04000000; 4'd3: rcon_val = 32'h08000000;
            4'd4: rcon_val = 32'h10000000; 4'd5: rcon_val = 32'h20000000;
            4'd6: rcon_val = 32'h40000000; 4'd7: rcon_val = 32'h80000000;
            4'd8: rcon_val = 32'h1B000000; 4'd9: rcon_val = 32'h36000000;
            default: rcon_val = 32'h00000000;
        endcase
    endfunction

    wire [31:0] g_in = w[Nk-1];
    wire [31:0] rot_w = {g_in[23:0], g_in[31:24]};
    wire [31:0] sub_rot_w;
    
    aes_sbox s0 (.in(rot_w[31:24]), .out(sub_rot_w[31:24]));
    aes_sbox s1 (.in(rot_w[23:16]), .out(sub_rot_w[23:16]));
    aes_sbox s2 (.in(rot_w[15:8]),  .out(sub_rot_w[15:8]));
    aes_sbox s3 (.in(rot_w[7:0]),   .out(sub_rot_w[7:0]));

    wire [31:0] g_func = sub_rot_w ^ rcon_val(round_step);

    wire [31:0] sub_mid_w;
    generate
        if (MODE == 256) begin : AES_256_SUBWORD
            wire [31:0] mid_in = w[3];
            aes_sbox sm0 (.in(mid_in[31:24]), .out(sub_mid_w[31:24]));
            aes_sbox sm1 (.in(mid_in[23:16]), .out(sub_mid_w[23:16]));
            aes_sbox sm2 (.in(mid_in[15:8]),  .out(sub_mid_w[15:8]));
            aes_sbox sm3 (.in(mid_in[7:0]),   .out(sub_mid_w[7:0]));
        end else assign sub_mid_w = 32'd0;
    endgenerate

    wire [31:0] next_w [0:Nk-1];
    assign next_w[0] = w[0] ^ g_func;

    generate
        for (i = 1; i < Nk; i = i + 1) begin : WORD_GEN
            wire [31:0] trans_w = (MODE == 256 && i == 4) ? sub_mid_w : next_w[i-1];
            assign next_w[i] = w[i] ^ trans_w;
        end
    endgenerate

    for (i = 0; i < Nk; i = i + 1) begin : REPACK
        assign key_out[MODE-1 - i*32 -: 32] = next_w[i];
    end
endmodule

module aes_sbox (
    input  [7:0] in,
    output [7:0] out
);
    wire [7:0] mapped_in, inv_core_out, mux2_in;

    isomorphic_mapping delta_unit (
        .in(in), 
        .out(mapped_in)
    );

    multiplicative_inversion_core inv_core (
        .in(mapped_in), 
        .out(inv_core_out)
    );

    inverse_isomorphic_mapping inv_delta_unit (
        .in(inv_core_out), 
        .out(mux2_in)
    );

    affine_trans aff_unit (
        .in(mux2_in), 
        .out(out)
    );
endmodule

module affine_trans (
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

module inverse_isomorphic_mapping (
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

module multiplicative_inversion_core (
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
    input  [3:0] q,
    input  [3:0] a,
    output [3:0] k
);
    wire [1:0] qh = q[3:2], ql = q[1:0];
    wire [1:0] ah = a[3:2], al = a[1:0];
    wire [1:0] mul_hh, mul_ll, mul_hl_lh, ph_phi;

    gf2_multiplier m1 (.q(qh), .a(ah), .k(mul_hh));
    gf2_multiplier m2 (.q(ql), .a(al), .k(mul_ll));
    gf2_multiplier m3 (.q(qh ^ ql), .a(ah ^ al), .k(mul_hl_lh));

    assign k[3:2] = mul_hl_lh ^ mul_ll; 

    assign ph_phi[1] = mul_hh[1] ^ mul_hh[0];
    assign ph_phi[0] = mul_hh[1];
    
    assign k[1:0] = ph_phi ^ mul_ll;
endmodule

module gf2_multiplier (
    input  [1:0] q,
    input  [1:0] a,
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

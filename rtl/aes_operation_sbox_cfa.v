module aes_operation_sbox_cfa #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [MODE-1:0] key_in,
    input [127:0]  data_in,
    output reg     valid_out,
    output reg [127:0] data_out
);

    `ifdef AES_256
        localparam Nr = 14;
    `elsif AES_192
        localparam Nr = 12;
    `else
        localparam Nr = 10;
    `endif

    localparam S_IDLE = 1'b0;
    localparam S_CALC = 1'b1;

    reg state, next_state;
    reg [3:0] round_ctr, next_round_ctr;
    reg [127:0] state_reg, next_state_reg;
    reg [MODE-1:0] key_reg, next_key_reg;
    reg next_valid_out;

    wire [127:0] round_key;
    wire [MODE-1:0] generated_next_key_reg;
    wire [127:0] round_state_out;

    aes_key_expansion_sbox_cfa #(MODE) u_key_ext (
        .round_ctr(round_ctr),
        .key_reg(key_reg),
        .round_key(round_key),
        .next_key_reg(generated_next_key_reg)
    );

    aes_round_sbox_cfa u_round (
        .state_in(state_reg),
        .key_in(round_key),
        .is_final_round(round_ctr == Nr),
        .state_out(round_state_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            round_ctr  <= 4'd0;
            state_reg  <= 128'd0;
            key_reg    <= {MODE{1'b0}};
            valid_out  <= 1'b0;
            data_out   <= 128'd0;
        end else begin
            state      <= next_state;
            round_ctr  <= next_round_ctr;
            state_reg  <= next_state_reg;
            key_reg    <= next_key_reg;
            valid_out  <= next_valid_out;
            data_out   <= next_valid_out ? next_state_reg : 128'd0;
        end
    end

    always @(*) begin
        next_state      = state;
        next_round_ctr  = round_ctr;
        next_state_reg  = state_reg;
        next_key_reg    = key_reg;
        next_valid_out  = 1'b0;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_state      = S_CALC;
                    next_state_reg  = data_in ^ key_in[MODE-1 -: 128];
                    next_key_reg    = key_in;
                    next_round_ctr  = 4'd1;
                end
            end

            S_CALC: begin
                next_state_reg = round_state_out;
                next_key_reg   = generated_next_key_reg;

                if (round_ctr == Nr) begin
                    next_valid_out = 1'b1;
                    next_state     = S_IDLE;
                end else begin
                    next_round_ctr = round_ctr + 4'd1;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end
endmodule

module aes_round_sbox_cfa (
    input  [127:0] state_in,
    input  [127:0] key_in,
    input  is_final_round,
    output [127:0] state_out
);

    wire [127:0] sub_out;
    
    genvar i;
    generate
        for (i=0; i<16; i=i+1) begin : sbox_array
            aes_sbox_sbox_cfa sb (
                .data_in(state_in[8*(15-i) +: 8]), 
                .data_out(sub_out[8*(15-i) +: 8])
            );
        end
    endgenerate

    wire [127:0] shift_out;
    
    assign shift_out = {
        sub_out[127:120], sub_out[87:80],   sub_out[47:40],   sub_out[7:0],     
        sub_out[95:88],   sub_out[55:48],   sub_out[15:8],    sub_out[103:96],  
        sub_out[63:56],   sub_out[23:16],   sub_out[111:104], sub_out[71:64],   
        sub_out[31:24],   sub_out[119:112], sub_out[79:72],   sub_out[39:32]    
    };

    wire [127:0] mix_out;
    
    aes_mix_columns_sbox_cfa mix0 (.data_in(shift_out[127:96]), .data_out(mix_out[127:96]));
    aes_mix_columns_sbox_cfa mix1 (.data_in(shift_out[95:64]),  .data_out(mix_out[95:64]));
    aes_mix_columns_sbox_cfa mix2 (.data_in(shift_out[63:32]),  .data_out(mix_out[63:32]));
    aes_mix_columns_sbox_cfa mix3 (.data_in(shift_out[31:0]),   .data_out(mix_out[31:0]));

    assign state_out = is_final_round ? (shift_out ^ key_in) : (mix_out ^ key_in);
endmodule

module aes_mix_columns_sbox_cfa (
    input  [31:0] data_in,
    output [31:0] data_out
);

    wire [7:0] s0, s1, s2, s3, mix_all;
    assign s0 = data_in[31:24];
    assign s1 = data_in[23:16];
    assign s2 = data_in[15:8];
    assign s3 = data_in[7:0];

    function [7:0] xtime(input [7:0] x);
        begin
            xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h0);
        end
    endfunction

    assign mix_all = s0 ^ s1 ^ s2 ^ s3;
    assign data_out[31:24] = s0 ^ mix_all ^ xtime(s0 ^ s1);
    assign data_out[23:16] = s1 ^ mix_all ^ xtime(s1 ^ s2);
    assign data_out[15:8]  = s2 ^ mix_all ^ xtime(s2 ^ s3);
    assign data_out[7:0]   = s3 ^ mix_all ^ xtime(s3 ^ s0);
endmodule

module aes_key_expansion_sbox_cfa #(
    parameter MODE = 128
) (
    input [3:0] round_ctr,
    input [MODE-1:0] key_reg,
    output [127:0] round_key,
    output [MODE-1:0] next_key_reg
);

    `ifdef AES_256
        localparam Nk = 8;
    `elsif AES_192
        localparam Nk = 6;
    `else
        localparam Nk = 4;
    `endif

    wire [5:0] i0 = ((round_ctr - 4'd1) * 4) + 0 + Nk;
    wire [5:0] i2 = ((round_ctr - 4'd1) * 4) + 2 + Nk;

    wire [31:0] k_f0 = key_reg[MODE-1   -: 32];
    wire [31:0] k_f1 = key_reg[MODE-33  -: 32];
    wire [31:0] k_f2 = key_reg[MODE-65  -: 32];
    wire [31:0] k_f3 = key_reg[MODE-97  -: 32];

    wire [31:0] w0_no_sbox = k_f0 ^ key_reg[31:0];
    wire [31:0] w1_no_sbox = k_f1 ^ w0_no_sbox;

    reg  [31:0] sbox_in_word;
    wire [31:0] sbox_out_word;

    always @(*) begin
        sbox_in_word = {key_reg[23:0], key_reg[31:24]}; 
        `ifdef AES_256
        if (i0 % 8 == 4) begin
            sbox_in_word = key_reg[31:0]; 
        end
        `elsif AES_192
        if (i2 % 6 == 0) begin
            sbox_in_word = {w1_no_sbox[23:0], w1_no_sbox[31:24]}; 
        end
        `endif
    end

    aes_sbox_sbox_cfa ks0 (.data_in(sbox_in_word[31:24]), .data_out(sbox_out_word[31:24]));
    aes_sbox_sbox_cfa ks1 (.data_in(sbox_in_word[23:16]), .data_out(sbox_out_word[23:16]));
    aes_sbox_sbox_cfa ks2 (.data_in(sbox_in_word[15:8]),  .data_out(sbox_out_word[15:8]));
    aes_sbox_sbox_cfa ks3 (.data_in(sbox_in_word[7:0]),   .data_out(sbox_out_word[7:0]));

    function [31:0] get_rcon(input [5:0] word_idx);
        case(word_idx / Nk)
            6'd1:  get_rcon = 32'h01000000; 6'd2:  get_rcon = 32'h02000000;
            6'd3:  get_rcon = 32'h04000000; 6'd4:  get_rcon = 32'h08000000;
            6'd5:  get_rcon = 32'h10000000; 6'd6:  get_rcon = 32'h20000000;
            6'd7:  get_rcon = 32'h40000000; 6'd8:  get_rcon = 32'h80000000;
            6'd9:  get_rcon = 32'h1B000000; 6'd10: get_rcon = 32'h36000000;
            default: get_rcon = 32'h00000000;
        endcase
    endfunction

    reg [31:0] w0, w1, w2, w3;

    always @(*) begin
        w0 = w0_no_sbox;
        if (i0 % Nk == 0) begin
            w0 = k_f0 ^ sbox_out_word ^ get_rcon(i0);
        end
        `ifdef AES_256
        else if (i0 % 8 == 4) begin
            w0 = k_f0 ^ sbox_out_word;
        end
        `endif

        w1 = k_f1 ^ w0;
        
        w2 = k_f2 ^ w1;
        `ifdef AES_192
        if (i2 % 6 == 0) begin
            w2 = k_f2 ^ sbox_out_word ^ get_rcon(i2);
        end
        `endif
        
        w3 = k_f3 ^ w2;
    end

    wire [127:0] generated_words = {w0, w1, w2, w3};

    `ifdef AES_256
        assign next_key_reg = {key_reg[127:0], generated_words};
        assign round_key = key_reg[127:0];
    `elsif AES_192
        assign next_key_reg = {key_reg[63:0], generated_words};
        assign round_key = {key_reg[63:0], w0, w1};
    `else
        assign next_key_reg = generated_words;
        assign round_key = generated_words;
    `endif
endmodule

module aes_sbox_cfa (
    input  [7:0] data_in,
    output [7:0] data_out
);
    wire [7:0] mapped, inverted, restored;

    isomorphic_mapping_sbox_cfa map_unit      (.in(data_in),  .out(mapped));
    multiplicative_inverter_sbox_cfa inv_unit (.in(mapped),   .out(inverted));
    inverse_mapping_sbox_cfa restore_unit     (.in(inverted), .out(restored));
    affine_transformation_sbox_cfa aff_unit   (.in(restored), .out(data_out));
endmodule

module affine_transformation_sbox_cfa (
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

module isomorphic_mapping_sbox_cfa (
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

module inverse_mapping_sbox_cfa (
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

module multiplicative_inverter_sbox_cfa (
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

module gf4_multiplier_sbox_cfa (
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

module gf2_multiplier_sbox_cfa (
    input  [1:0] q, a,
    output [1:0] k
);
    assign k[1] = (q[1] & a[1]) ^ (q[0] & a[1]) ^ (q[1] & a[0]);
    assign k[0] = (q[1] & a[1]) ^ (q[0] & a[0]);
endmodule

module gf4_inverter_sbox_cfa (
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


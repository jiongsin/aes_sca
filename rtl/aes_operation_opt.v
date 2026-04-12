module aes_operation_opt #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] key_in,
    input [31:0] data_in,
    output reg valid_out,
    output reg [31:0] data_out
);

    `ifdef AES_256
        localparam Nr = 14;
    `elsif AES_192
        localparam Nr = 12;
    `else
        localparam Nr = 10;
    `endif

    localparam LOAD_CYCLES = MODE / 32;

    localparam S_LOAD = 1'b0;
    localparam S_CALC = 1'b1;

    reg state, next_state;
    reg [3:0] main_ctr, next_main_ctr;
    reg [1:0] step_count, next_step_count;
    reg [127:0] state_reg, next_state_reg;
    reg [MODE-1:0] key_reg, next_key_reg;
    
    wire [MODE-1:0] full_new_key  = {key_reg[MODE-33:0], key_in};
    wire [127:0]    full_new_data = {state_reg[95:0], data_in};

    reg [31:0] current_column;
    wire [31:0] round_word_out;
    wire [31:0] expanded_key_word;
    wire [31:0] round_key_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_LOAD;
            main_ctr      <= 4'd0;
            step_count    <= 2'd0;
            state_reg     <= 128'd0;
            key_reg       <= {MODE{1'b0}};
            valid_out     <= 1'b0;
            data_out      <= 32'd0;
        end else begin
            state         <= next_state;
            main_ctr      <= next_main_ctr;
            step_count    <= next_step_count;
            state_reg     <= next_state_reg;
            key_reg       <= next_key_reg;
            
            if (state == S_CALC && main_ctr == Nr) begin
                valid_out     <= 1'b1;
                data_out      <= round_word_out;
            end else begin
                valid_out     <= 1'b0;
                data_out      <= 32'd0;
            end
        end
    end

    always @(*) begin
        next_state      = state;
        next_main_ctr   = main_ctr;
        next_step_count = step_count;
        next_state_reg  = state_reg;
        next_key_reg    = key_reg;

        case (state)
            S_LOAD: begin
                if (valid_in) begin
                    next_key_reg   = full_new_key;
                    next_state_reg = full_new_data;

                    if (main_ctr == LOAD_CYCLES - 1) begin
                        next_state      = S_CALC;
                        next_main_ctr   = 4'd1;
                        next_step_count = 2'd0;
                        
                        next_state_reg  = full_new_data ^ full_new_key[MODE-1 -: 128];
                    end else begin
                        next_main_ctr = main_ctr + 4'd1;
                    end
                end
            end

            S_CALC: begin
                case(step_count)
                    2'd0: begin
                        next_state_reg[127:120] = round_word_out[31:24];
                        next_state_reg[87:80]   = round_word_out[23:16];
                        next_state_reg[47:40]   = round_word_out[15:8];
                        next_state_reg[7:0]     = round_word_out[7:0];
                    end
                    2'd1: begin
                        next_state_reg[95:88]   = round_word_out[31:24];
                        next_state_reg[55:48]   = round_word_out[23:16];
                        next_state_reg[15:8]    = round_word_out[15:8];
                        next_state_reg[103:96]  = round_word_out[7:0];
                    end
                    2'd2: begin
                        next_state_reg[63:56]   = round_word_out[31:24];
                        next_state_reg[23:16]   = round_word_out[23:16];
                        next_state_reg[111:104] = round_word_out[15:8];
                        next_state_reg[71:64]   = round_word_out[7:0];
                    end
                    2'd3: begin
                        next_state_reg[127:120] = state_reg[127:120];
                        next_state_reg[119:112] = state_reg[87:80];
                        next_state_reg[111:104] = state_reg[47:40];
                        next_state_reg[103:96]  = state_reg[7:0];
                        
                        next_state_reg[95:88]   = state_reg[95:88];
                        next_state_reg[87:80]   = state_reg[55:48];
                        next_state_reg[79:72]   = state_reg[15:8];
                        next_state_reg[71:64]   = state_reg[103:96];
                        
                        next_state_reg[63:56]   = state_reg[63:56];
                        next_state_reg[55:48]   = state_reg[23:16];
                        next_state_reg[47:40]   = state_reg[111:104];
                        next_state_reg[39:32]   = state_reg[71:64];
                        
                        next_state_reg[31:0]    = round_word_out;
                    end
                endcase

                next_key_reg = {key_reg[MODE-33:0], expanded_key_word};

                if (step_count == 2'd3) begin
                    next_step_count = 2'd0;
                    if (main_ctr == Nr) begin
                        next_state    = S_LOAD;
                        next_main_ctr = 4'd0;
                    end else begin
                        next_main_ctr = main_ctr + 4'd1;
                    end
                end else begin
                    next_step_count = step_count + 2'd1;
                end
            end
            
            default: next_state = S_LOAD;
        endcase
    end

    always @(*) begin
        case(step_count)
            2'd0: current_column = {state_reg[127:120], state_reg[87:80],   state_reg[47:40],   state_reg[7:0]};
            2'd1: current_column = {state_reg[95:88],   state_reg[55:48],   state_reg[15:8],    state_reg[103:96]};
            2'd2: current_column = {state_reg[63:56],   state_reg[23:16],   state_reg[111:104], state_reg[71:64]};
            2'd3: current_column = {state_reg[31:24],   state_reg[119:112], state_reg[79:72],   state_reg[39:32]};
            default: current_column = 32'd0;
        endcase
    end

    aes_key_expansion_opt #(MODE) u_key_ext (
        .round_idx(main_ctr),
        .step_idx(step_count),
        .full_key(key_reg),
        .new_word(expanded_key_word)
    );

    `ifdef AES_256
        assign round_key_word = key_reg[127:96];
    `elsif AES_192
        assign round_key_word = key_reg[63:32];
    `else
        assign round_key_word = expanded_key_word;
    `endif

    aes_round_opt u_round (
        .col_in(current_column),
        .key_in(round_key_word),
        .is_final_round(main_ctr == Nr),
        .col_out(round_word_out)
    );
endmodule

module aes_round_opt (
    input  [31:0] col_in,
    input  [31:0] key_in,
    input  is_final_round,
    output [31:0] col_out
);
    wire [31:0] sbox_out, mix_out;

    genvar i;
    generate
        for (i=0; i<4; i=i+1) begin : sbox_array
            aes_sbox_opt sb (.data_in(col_in[8*(3-i) +: 8]), .data_out(sbox_out[8*(3-i) +: 8]));
        end
    endgenerate

    aes_mix_columns_opt mix_u (
        .data_in(sbox_out),
        .data_out(mix_out)
    );

    assign col_out = is_final_round ? (sbox_out ^ key_in) : (mix_out ^ key_in);
endmodule

module aes_mix_columns_opt (
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

module aes_key_expansion_opt #(
    parameter MODE = 128
) (
    input [3:0]       round_idx,
    input [1:0]       step_idx,
    input [MODE-1:0]  full_key,
    output reg [31:0] new_word
);
    `ifdef AES_256
    localparam Nk = 8;
    `elsif AES_192
    localparam Nk = 6;
    `else
    localparam Nk = 4;
    `endif

    wire [5:0] i = ((round_idx - 4'd1) * 4) + step_idx + Nk;

    wire [31:0] first_word = full_key[MODE-1 : MODE-32]; 
    wire [31:0] last_word  = full_key[31:0];

    wire [31:0] rot_word   = {last_word[23:0], last_word[31:24]};
    
    wire [31:0] sbox_input;
    wire [31:0] sbox_output;

    `ifdef AES_256
        assign sbox_input = (i % 8 == 4) ? last_word : rot_word;
    `else
        assign sbox_input = rot_word;
    `endif

    aes_sbox_opt ks0 (.data_in(sbox_input[31:24]), .data_out(sbox_output[31:24]));
    aes_sbox_opt ks1 (.data_in(sbox_input[23:16]), .data_out(sbox_output[23:16]));
    aes_sbox_opt ks2 (.data_in(sbox_input[15:8]),  .data_out(sbox_output[15:8]));
    aes_sbox_opt ks3 (.data_in(sbox_input[7:0]),   .data_out(sbox_output[7:0]));

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

    always @(*) begin
        if (i % Nk == 0)
            new_word = first_word ^ sbox_output ^ get_rcon(i);
        `ifdef AES_256
        else if (i % 8 == 4)
            new_word = first_word ^ sbox_output;
        `endif
        else
            new_word = first_word ^ last_word;
    end
endmodule

module aes_sbox_opt (
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

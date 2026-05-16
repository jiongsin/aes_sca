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
        localparam Nk = 8;
    `elsif AES_192
        localparam Nr = 12;
        localparam Nk = 6;
    `else
        localparam Nr = 10;
        localparam Nk = 4;
    `endif

    localparam S_IDLE   = 2'd0;
    localparam S_LOAD   = 2'd1;
    localparam S_ROUND  = 2'd2;
    localparam S_OUTPUT = 2'd3;

    reg [1:0] state, next_state;
    reg [2:0] word_cnt, next_word_cnt;
    reg [3:0] round_cnt, next_round_cnt;

    reg [127:0] state_reg;
    reg [(Nk*32)-1:0] key_reg;
    reg [95:0]  next_state_buffer;

    wire [31:0] shifted_col;
    wire [31:0] subbytes_out;
    wire [31:0] mixcolumns_out;
    wire [31:0] round_data_out;
    wire [31:0] expanded_key_word;
    wire [31:0] current_round_key_word;
    wire [31:0] initial_add_rk_word;

    assign shifted_col = 
        (word_cnt[1:0] == 2'd0) ? {state_reg[127:120], state_reg[87:80],   state_reg[47:40],   state_reg[7:0]} :
        (word_cnt[1:0] == 2'd1) ? {state_reg[95:88],   state_reg[55:48],   state_reg[15:8],    state_reg[103:96]} :
        (word_cnt[1:0] == 2'd2) ? {state_reg[63:56],   state_reg[23:16],   state_reg[111:104], state_reg[71:64]} :
                                  {state_reg[31:24],   state_reg[119:112], state_reg[79:72],   state_reg[39:32]};

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sbox_gen
            aes_sbox_opt u_sbox (
                .data_in(shifted_col[(i*8) +: 8]),
                .data_out(subbytes_out[(i*8) +: 8])
            );
        end
    endgenerate

    function automatic [7:0] xtime;
        input [7:0] b;
        begin
            xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
        end
    endfunction

    wire [7:0] sb0 = subbytes_out[31:24];
    wire [7:0] sb1 = subbytes_out[23:16];
    wire [7:0] sb2 = subbytes_out[15:8];
    wire [7:0] sb3 = subbytes_out[7:0];

    wire [7:0] mc0 = xtime(sb0) ^ xtime(sb1) ^ sb1 ^ sb2 ^ sb3;
    wire [7:0] mc1 = sb0 ^ xtime(sb1) ^ xtime(sb2) ^ sb2 ^ sb3;
    wire [7:0] mc2 = sb0 ^ sb1 ^ xtime(sb2) ^ xtime(sb3) ^ sb3;
    wire [7:0] mc3 = xtime(sb0) ^ sb0 ^ sb1 ^ sb2 ^ xtime(sb3);

    assign mixcolumns_out = {mc0, mc1, mc2, mc3};

    `ifdef AES_256
        assign current_round_key_word = key_reg[127:96];
    `elsif AES_192
        assign current_round_key_word = key_reg[63:32];
    `else
        assign current_round_key_word = expanded_key_word;
    `endif

    assign initial_add_rk_word = key_in;

    assign round_data_out = (round_cnt == Nr) ? (subbytes_out ^ current_round_key_word) : (mixcolumns_out ^ current_round_key_word);

    aes_key_expansion_opt #(
        .MODE(Nk * 32)
    ) key_expand_inst (
        .round_idx(round_cnt),
        .step_idx(word_cnt[1:0]),
        .full_key(key_reg),
        .new_word(expanded_key_word)
    );

    always @(*) begin
        next_state = state;
        next_word_cnt = word_cnt;
        next_round_cnt = round_cnt;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_state = S_LOAD;
                    next_word_cnt = 3'd1;
                end
            end

            S_LOAD: begin
                if (valid_in) begin
                    if (word_cnt == Nk - 1) begin
                        next_state = S_ROUND;
                        next_round_cnt = 4'd1;
                        next_word_cnt = 3'd0;
                    end else begin
                        next_word_cnt = word_cnt + 3'd1;
                    end
                end
            end

            S_ROUND: begin
                if (word_cnt == 3'd3) begin
                    if (round_cnt == Nr) begin
                        next_state = S_OUTPUT;
                        next_word_cnt = 3'd0;
                    end else begin
                        next_round_cnt = round_cnt + 4'd1;
                        next_word_cnt = 3'd0;
                    end
                end else begin
                    next_word_cnt = word_cnt + 3'd1;
                end
            end

            S_OUTPUT: begin
                if (word_cnt == 3'd3) begin
                    next_state = S_IDLE;
                    next_word_cnt = 3'd0;
                end else begin
                    next_word_cnt = word_cnt + 3'd1;
                end
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            word_cnt <= 3'd0;
            round_cnt <= 4'd0;
        end else begin
            state <= next_state;
            word_cnt <= next_word_cnt;
            round_cnt <= next_round_cnt;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= 128'd0;
            key_reg <= 0;
            next_state_buffer <= 96'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (valid_in) begin
                        state_reg <= {state_reg[95:0], data_in ^ initial_add_rk_word};
                        key_reg <= {key_reg[(Nk*32)-33 : 0], key_in};
                    end
                end

                S_LOAD: begin
                    if (valid_in) begin
                        key_reg <= {key_reg[(Nk*32)-33 : 0], key_in};
                        if (word_cnt < 3'd4) begin
                            state_reg <= {state_reg[95:0], data_in ^ initial_add_rk_word};
                        end
                    end
                end

                S_ROUND: begin
                    key_reg <= {key_reg[(Nk*32)-33 : 0], expanded_key_word};

                    case (word_cnt[1:0])
                        2'd0: next_state_buffer[95:64] <= round_data_out;
                        2'd1: next_state_buffer[63:32] <= round_data_out;
                        2'd2: next_state_buffer[31:0]  <= round_data_out;
                        2'd3: begin
                            state_reg[127:96] <= next_state_buffer[95:64];
                            state_reg[95:64]  <= next_state_buffer[63:32];
                            state_reg[63:32]  <= next_state_buffer[31:0];
                            state_reg[31:0]   <= round_data_out;
                        end
                    endcase
                end
                
                default: begin end
            endcase
        end
    end

    always @(*) begin
        valid_out = 1'b0;
        data_out = 32'd0;
        
        if (state == S_OUTPUT) begin
            valid_out = 1'b1;
            case (word_cnt[1:0])
                2'd0: data_out = state_reg[127:96];
                2'd1: data_out = state_reg[95:64];
                2'd2: data_out = state_reg[63:32];
                2'd3: data_out = state_reg[31:0];
                default: data_out = 32'd0;
            endcase
        end
    end
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

    function automatic [31:0] get_rcon(input [5:0] word_idx);
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

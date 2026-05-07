/*****************************************************************

Design: aes_operation_sca_MODE128_10p0ns

Performance: /home/user16/aes_sca/syn/results/aes_operation_sca_MODE128_10p0ns/reports/qor.rpt
  Critical Path Clk Period : 10.0 ns
  Critical Path Slack      : 6.31 ns
  Maximum Frequency        : 271.00 MHz

Power: /home/user16/aes_sca/syn/results/aes_operation_sca_MODE128_10p0ns/reports/power.rpt
Total power                : 1841.3000 uW
  Dynamic power            : 1.4253e+03 uW (77.4%)
    Internal power         : 1236.1000 uW
    Switching power        : 189.2297 uW
  Static power             : 4.1597e+08 pW (22.6%)

Area: /home/user16/aes_sca/syn/results/aes_operation_sca_MODE128_10p0ns/reports/qor.rpt
  Design Area              : 20013.5864 (7.8749 kGE)
    Combinational Area     : 9827.240429 (49.1%)
    Noncombinational Area  : 10186.345948 (50.9%)
  Net Length               : 82878.77

*****************************************************************/
// SBOX Pipelining, Shared between aes_operation and key_expansion
module aes_operation_sca #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] key_in,
    input [31:0] data_in,
    input [287:0] random_bits,
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

    localparam S_IDLE   = 2'b00;
    localparam S_LOAD   = 2'b01;
    localparam S_ROUND  = 2'b11;
    localparam S_OUTPUT = 2'b10;

    reg [1:0] state, next_state;
    reg [3:0] cycle_cnt, next_cycle_cnt;
    reg [3:0] round_cnt, next_round_cnt;

    reg [127:0] state_reg;
    reg [MODE-1:0] key_reg;
    reg [95:0]  next_state_buffer;

    wire [31:0] shifted_col;
    wire [31:0] subbytes_out;
    wire [31:0] mixcolumns_out;
    wire [31:0] round_data_out;
    wire [31:0] expanded_key_word;
    wire [31:0] current_round_key_word;
    wire [31:0] initial_add_rk_word;

    // Shifted by 1 cycle to allow Cycle 0 for Key Expansion
    assign shifted_col = 
        (cycle_cnt == 4'd1) ? {state_reg[127:120], state_reg[87:80],   state_reg[47:40],   state_reg[7:0]} :
        (cycle_cnt == 4'd2) ? {state_reg[95:88],   state_reg[55:48],   state_reg[15:8],    state_reg[103:96]} :
        (cycle_cnt == 4'd3) ? {state_reg[63:56],   state_reg[23:16],   state_reg[111:104], state_reg[71:64]} :
                              {state_reg[31:24],   state_reg[119:112], state_reg[79:72],   state_reg[39:32]};

    // Shared Sbox connections
    wire [31:0] key_sbox_in;
    wire [31:0] key_sbox_out;
    wire [31:0] shared_sbox_in = (state == S_ROUND && cycle_cnt == 4'd0) ? key_sbox_in : shifted_col;
    wire [31:0] shared_sbox_out;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sbox_gen
            aes_sbox_sca u_sbox (
                .clk(clk),
                .data_in(shared_sbox_in[(i*8) +: 8]),
                .random_bits(random_bits[(i*36) +: 36]),
                .data_out(shared_sbox_out[(i*8) +: 8])
            );
        end
    endgenerate

    assign subbytes_out = shared_sbox_out;
    assign key_sbox_out = shared_sbox_out;

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

    // Tap points are shifted by 32 bits because the data is delayed by one cycle
    `ifdef AES_256
        assign current_round_key_word = key_reg[159:128];
        assign initial_add_rk_word = key_reg[127:96];
    `elsif AES_192
        assign current_round_key_word = key_reg[95:64];
        assign initial_add_rk_word = key_reg[63:32];
    `else
        assign current_round_key_word = key_reg[31:0];
        assign initial_add_rk_word = key_in;
    `endif

    assign round_data_out = (round_cnt == Nr) ? (subbytes_out ^ current_round_key_word) : (mixcolumns_out ^ current_round_key_word);

    // Map the key expansion step index logically
    wire [1:0] key_step_idx = (cycle_cnt < 4'd4) ? cycle_cnt[1:0] : (cycle_cnt - 4'd4);

    aes_key_expansion_sca #(
        .MODE(Nk * 32)
    ) key_expand_inst (
        .clk(clk),
        .round_idx(round_cnt),
        .step_idx(key_step_idx),
        .full_key(key_reg),
        .sbox_in(key_sbox_in),
        .sbox_out(key_sbox_out),
        .new_word(expanded_key_word)
    );

    always @(*) begin
        next_state = state;
        next_cycle_cnt = cycle_cnt;
        next_round_cnt = round_cnt;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_state = S_LOAD;
                    next_cycle_cnt = 4'd1;
                end
            end

            S_LOAD: begin
                if (valid_in) begin
                    if (cycle_cnt == Nk - 1) begin
                        next_state = S_ROUND;
                        next_round_cnt = 4'd1;
                        next_cycle_cnt = 4'd0;
                    end else begin
                        next_cycle_cnt = cycle_cnt + 4'd1;
                    end
                end
            end

            S_ROUND: begin
                if (cycle_cnt == 4'd8) begin
                    if (round_cnt == Nr) begin
                        next_state = S_OUTPUT;
                        next_cycle_cnt = 4'd0;
                    end else begin
                        next_round_cnt = round_cnt + 4'd1;
                        next_cycle_cnt = 4'd0;
                    end
                end else begin
                    next_cycle_cnt = cycle_cnt + 4'd1;
                end
            end

            S_OUTPUT: begin
                if (cycle_cnt == 4'd3) begin
                    next_state = S_IDLE;
                    next_cycle_cnt = 4'd0;
                end else begin
                    next_cycle_cnt = cycle_cnt + 4'd1;
                end
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cycle_cnt <= 4'd0;
            round_cnt <= 4'd0;
        end else begin
            state <= next_state;
            cycle_cnt <= next_cycle_cnt;
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
                        `ifndef AES_256
                        `ifndef AES_192
                        state_reg <= {state_reg[95:0], data_in ^ initial_add_rk_word};
                        `endif
                        `endif
                        key_reg <= {key_reg[(Nk*32)-33 : 0], key_in};
                    end
                end

                S_LOAD: begin
                    if (valid_in) begin
                        key_reg <= {key_reg[(Nk*32)-33 : 0], key_in};
                        if (cycle_cnt >= Nk - 4) begin
                            state_reg <= {state_reg[95:0], data_in ^ initial_add_rk_word};
                        end
                    end
                end

                S_ROUND: begin
                    if (cycle_cnt >= 4'd4 && cycle_cnt <= 4'd7) begin
                        key_reg <= {key_reg[(Nk*32)-33 : 0], expanded_key_word};
                    end
                    
                    if (cycle_cnt >= 4'd5 && cycle_cnt <= 4'd8) begin
                        case (cycle_cnt)
                            4'd5: next_state_buffer[95:64] <= round_data_out;
                            4'd6: next_state_buffer[63:32] <= round_data_out;
                            4'd7: next_state_buffer[31:0]  <= round_data_out;
                            4'd8: begin
                                state_reg[127:96] <= next_state_buffer[95:64];
                                state_reg[95:64]  <= next_state_buffer[63:32];
                                state_reg[63:32]  <= next_state_buffer[31:0];
                                state_reg[31:0]   <= round_data_out;
                            end
                        endcase
                    end
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
            case (cycle_cnt[1:0])
                2'd0: data_out = state_reg[127:96];
                2'd1: data_out = state_reg[95:64];
                2'd2: data_out = state_reg[63:32];
                2'd3: data_out = state_reg[31:0];
                default: data_out = 32'd0;
            endcase
        end
    end
endmodule

module aes_key_expansion_sca #(
    parameter MODE = 128
) (
    input clk,
    input [3:0]       round_idx,
    input [1:0]       step_idx,
    input [MODE-1:0]  full_key,
    output [31:0]     sbox_in,
    input  [31:0]     sbox_out,
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

    `ifdef AES_256
        assign sbox_in = (i % 8 == 4) ? last_word : rot_word;
    `else
        assign sbox_in = rot_word;
    `endif

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
            new_word = first_word ^ sbox_out ^ get_rcon(i);
        `ifdef AES_256
        else if (i % 8 == 4)
            new_word = first_word ^ sbox_out;
        `endif
        else
            new_word = first_word ^ last_word;
    end
endmodule

module aes_sbox_sca (
    input clk,
    input  [7:0] data_in,
    input  [35:0] random_bits, 
    output [7:0] data_out
);
    wire [7:0] data_in_0 = data_in ^ random_bits[7:0];
    wire [7:0] data_in_1 = random_bits[7:0];
    
    wire [7:0] mapped_0, mapped_1;
    wire [7:0] inverted_0, inverted_1;
    wire [7:0] restored_0, restored_1;
    wire [7:0] aff_out_0, aff_out_1;

    isomorphic_mapping_sca map_unit (
        .data_in_0(data_in_0), .data_in_1(data_in_1),
        .data_out_0(mapped_0), .data_out_1(mapped_1)
    );

    multiplicative_inverter_sca inv_unit (
        .clk(clk),
        .data_in_0(mapped_0), .data_in_1(mapped_1),
        .r(random_bits),
        .data_out_0(inverted_0), .data_out_1(inverted_1)
    );

    inverse_mapping_sca restore_unit (
        .data_in_0(inverted_0), .data_in_1(inverted_1),
        .data_out_0(restored_0), .data_out_1(restored_1)
    );

    affine_transformation_sca aff_unit (
        .data_in_0(restored_0), .data_in_1(restored_1),
        .data_out_0(aff_out_0), .data_out_1(aff_out_1)
    );

    assign data_out = aff_out_0 ^ aff_out_1;
endmodule

module dom_and_sca (
    input clk, 
    input a_0, a_1, b_0, b_1, z,
    output c_0, c_1
);
    wire inner_0 = a_0 & b_0;
    wire inner_1 = a_1 & b_1;

    wire cross_0_comb = (a_0 & b_1) ^ z;
    wire cross_1_comb = (a_1 & b_0) ^ z;

    reg cross_0_reg, cross_1_reg;
    reg inner_0_reg, inner_1_reg;

    always @(posedge clk) begin
        cross_0_reg <= cross_0_comb;
        cross_1_reg <= cross_1_comb;
        inner_0_reg <= inner_0;
        inner_1_reg <= inner_1;
    end

    assign c_0 = inner_0_reg ^ cross_0_reg;
    assign c_1 = inner_1_reg ^ cross_1_reg;
endmodule

module affine_transformation_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    assign data_out_0[0] = data_in_0[0] ^ data_in_0[4] ^ data_in_0[5] ^ data_in_0[6] ^ data_in_0[7] ^ 1'b1;
    assign data_out_0[1] = data_in_0[1] ^ data_in_0[5] ^ data_in_0[6] ^ data_in_0[7] ^ data_in_0[0] ^ 1'b1;
    assign data_out_0[2] = data_in_0[2] ^ data_in_0[6] ^ data_in_0[7] ^ data_in_0[0] ^ data_in_0[1] ^ 1'b0;
    assign data_out_0[3] = data_in_0[3] ^ data_in_0[7] ^ data_in_0[0] ^ data_in_0[1] ^ data_in_0[2] ^ 1'b0;
    assign data_out_0[4] = data_in_0[4] ^ data_in_0[0] ^ data_in_0[1] ^ data_in_0[2] ^ data_in_0[3] ^ 1'b0;
    assign data_out_0[5] = data_in_0[5] ^ data_in_0[1] ^ data_in_0[2] ^ data_in_0[3] ^ data_in_0[4] ^ 1'b1;
    assign data_out_0[6] = data_in_0[6] ^ data_in_0[2] ^ data_in_0[3] ^ data_in_0[4] ^ data_in_0[5] ^ 1'b1;
    assign data_out_0[7] = data_in_0[7] ^ data_in_0[3] ^ data_in_0[4] ^ data_in_0[5] ^ data_in_0[6] ^ 1'b0;

    assign data_out_1[0] = data_in_1[0] ^ data_in_1[4] ^ data_in_1[5] ^ data_in_1[6] ^ data_in_1[7];
    assign data_out_1[1] = data_in_1[1] ^ data_in_1[5] ^ data_in_1[6] ^ data_in_1[7] ^ data_in_1[0];
    assign data_out_1[2] = data_in_1[2] ^ data_in_1[6] ^ data_in_1[7] ^ data_in_1[0] ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[3] ^ data_in_1[7] ^ data_in_1[0] ^ data_in_1[1] ^ data_in_1[2];
    assign data_out_1[4] = data_in_1[4] ^ data_in_1[0] ^ data_in_1[1] ^ data_in_1[2] ^ data_in_1[3];
    assign data_out_1[5] = data_in_1[5] ^ data_in_1[1] ^ data_in_1[2] ^ data_in_1[3] ^ data_in_1[4];
    assign data_out_1[6] = data_in_1[6] ^ data_in_1[2] ^ data_in_1[3] ^ data_in_1[4] ^ data_in_1[5];
    assign data_out_1[7] = data_in_1[7] ^ data_in_1[3] ^ data_in_1[4] ^ data_in_1[5] ^ data_in_1[6];
endmodule

module isomorphic_mapping_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    assign data_out_0[7] = data_in_0[7] ^ data_in_0[5];
    assign data_out_0[6] = data_in_0[7] ^ data_in_0[6] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[5] = data_in_0[7] ^ data_in_0[5] ^ data_in_0[3] ^ data_in_0[2];
    assign data_out_0[4] = data_in_0[7] ^ data_in_0[5] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[3] = data_in_0[7] ^ data_in_0[6] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[2] = data_in_0[7] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[1] = data_in_0[6] ^ data_in_0[4] ^ data_in_0[1];
    assign data_out_0[0] = data_in_0[6] ^ data_in_0[1] ^ data_in_0[0];

    assign data_out_1[7] = data_in_1[7] ^ data_in_1[5];
    assign data_out_1[6] = data_in_1[7] ^ data_in_1[6] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[5] = data_in_1[7] ^ data_in_1[5] ^ data_in_1[3] ^ data_in_1[2];
    assign data_out_1[4] = data_in_1[7] ^ data_in_1[5] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[7] ^ data_in_1[6] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[2] = data_in_1[7] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[1] = data_in_1[6] ^ data_in_1[4] ^ data_in_1[1];
    assign data_out_1[0] = data_in_1[6] ^ data_in_1[1] ^ data_in_1[0];
endmodule

module inverse_mapping_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    assign data_out_0[7] = data_in_0[7] ^ data_in_0[6] ^ data_in_0[5] ^ data_in_0[1];
    assign data_out_0[6] = data_in_0[6] ^ data_in_0[2];
    assign data_out_0[5] = data_in_0[6] ^ data_in_0[5] ^ data_in_0[1];
    assign data_out_0[4] = data_in_0[6] ^ data_in_0[5] ^ data_in_0[4] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[3] = data_in_0[5] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[2] = data_in_0[7] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[1] = data_in_0[5] ^ data_in_0[4];
    assign data_out_0[0] = data_in_0[6] ^ data_in_0[5] ^ data_in_0[4] ^ data_in_0[2] ^ data_in_0[0];

    assign data_out_1[7] = data_in_1[7] ^ data_in_1[6] ^ data_in_1[5] ^ data_in_1[1];
    assign data_out_1[6] = data_in_1[6] ^ data_in_1[2];
    assign data_out_1[5] = data_in_1[6] ^ data_in_1[5] ^ data_in_1[1];
    assign data_out_1[4] = data_in_1[6] ^ data_in_1[5] ^ data_in_1[4] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[5] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[2] = data_in_1[7] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[1] = data_in_1[5] ^ data_in_1[4];
    assign data_out_1[0] = data_in_1[6] ^ data_in_1[5] ^ data_in_1[4] ^ data_in_1[2] ^ data_in_1[0];
endmodule

module multiplicative_inverter_sca (
    input clk,
    input  [7:0] data_in_0, data_in_1,
    input  [35:0] r,
    output [7:0] data_out_0, data_out_1
);
    wire [3:0] b_0 = data_in_0[7:4], c_0 = data_in_0[3:0];
    wire [3:0] b_1 = data_in_1[7:4], c_1 = data_in_1[3:0];

    wire [3:0] b_sq_0, b_sq_1;
    wire [3:0] b_sq_lambda_0, b_sq_lambda_1;
    wire [3:0] b_plus_c_0, b_plus_c_1;
    wire [3:0] c_mul_bplusc_0, c_mul_bplusc_1;
    wire [3:0] combined_inv_0, combined_inv_1;
    wire [3:0] out_h_0, out_h_1, out_l_0, out_l_1;

    assign b_sq_0[3] = b_0[3];
    assign b_sq_0[2] = b_0[3] ^ b_0[2];
    assign b_sq_0[1] = b_0[2] ^ b_0[1];
    assign b_sq_0[0] = b_0[3] ^ b_0[1] ^ b_0[0];

    assign b_sq_1[3] = b_1[3];
    assign b_sq_1[2] = b_1[3] ^ b_1[2];
    assign b_sq_1[1] = b_1[2] ^ b_1[1];
    assign b_sq_1[0] = b_1[3] ^ b_1[1] ^ b_1[0];

    assign b_sq_lambda_0[3] = b_sq_0[2] ^ b_sq_0[0];
    assign b_sq_lambda_0[2] = b_sq_0[3] ^ b_sq_0[2] ^ b_sq_0[1] ^ b_sq_0[0];
    assign b_sq_lambda_0[1] = b_sq_0[3];
    assign b_sq_lambda_0[0] = b_sq_0[2];

    assign b_sq_lambda_1[3] = b_sq_1[2] ^ b_sq_1[0];
    assign b_sq_lambda_1[2] = b_sq_1[3] ^ b_sq_1[2] ^ b_sq_1[1] ^ b_sq_1[0];
    assign b_sq_lambda_1[1] = b_sq_1[3];
    assign b_sq_lambda_1[0] = b_sq_1[2];

    assign b_plus_c_0 = b_0 ^ c_0;
    assign b_plus_c_1 = b_1 ^ c_1;

    gf4_multiplier_sca mul_inst (
        .clk(clk),
        .q_0(c_0), .q_1(c_1), .a_0(b_plus_c_0), .a_1(b_plus_c_1),
        .r(r[8:0]), .k_0(c_mul_bplusc_0), .k_1(c_mul_bplusc_1)
    );

    reg [3:0] b_sq_lambda_0_d1, b_sq_lambda_1_d1;
    reg [26:0] r_d1;
    reg [3:0] b_0_d1, b_1_d1, b_plus_c_0_d1, b_plus_c_1_d1;

    always @(posedge clk) begin
        b_sq_lambda_0_d1 <= b_sq_lambda_0; b_sq_lambda_1_d1 <= b_sq_lambda_1;
        r_d1 <= r[35:9];
        b_0_d1 <= b_0; b_1_d1 <= b_1;
        b_plus_c_0_d1 <= b_plus_c_0; b_plus_c_1_d1 <= b_plus_c_1;
    end

    wire [3:0] combined_0 = b_sq_lambda_0_d1 ^ c_mul_bplusc_0;
    wire [3:0] combined_1 = b_sq_lambda_1_d1 ^ c_mul_bplusc_1;

    gf4_inverter_sca inv4_inst (
        .clk(clk),
        .q_0(combined_0), .q_1(combined_1),
        .r(r_d1[8:0]), .q_inv_0(combined_inv_0), .q_inv_1(combined_inv_1)
    );

    reg [3:0] b_0_d2, b_1_d2, b_plus_c_0_d2, b_plus_c_1_d2;
    reg [3:0] b_0_d3, b_1_d3, b_plus_c_0_d3, b_plus_c_1_d3;
    reg [17:0] r_d2, r_d3;

    always @(posedge clk) begin
        b_0_d2 <= b_0_d1; b_1_d2 <= b_1_d1;
        b_plus_c_0_d2 <= b_plus_c_0_d1; b_plus_c_1_d2 <= b_plus_c_1_d1;
        r_d2 <= r_d1[26:9];

        b_0_d3 <= b_0_d2; b_1_d3 <= b_1_d2;
        b_plus_c_0_d3 <= b_plus_c_0_d2; b_plus_c_1_d3 <= b_plus_c_1_d2;
        r_d3 <= r_d2;
    end

    gf4_multiplier_sca mul_high (
        .clk(clk),
        .q_0(b_0_d3), .q_1(b_1_d3), .a_0(combined_inv_0), .a_1(combined_inv_1),
        .r(r_d3[8:0]), .k_0(out_h_0), .k_1(out_h_1)
    );

    gf4_multiplier_sca mul_low (
        .clk(clk),
        .q_0(b_plus_c_0_d3), .q_1(b_plus_c_1_d3), .a_0(combined_inv_0), .a_1(combined_inv_1),
        .r(r_d3[17:9]), .k_0(out_l_0), .k_1(out_l_1)
    );

    assign data_out_0 = {out_h_0, out_l_0};
    assign data_out_1 = {out_h_1, out_l_1};
endmodule

module gf4_multiplier_sca (
    input clk,
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

    gf2_multiplier_sca m1 (.clk(clk), .q_0(qh_0), .q_1(qh_1), .a_0(ah_0), .a_1(ah_1), .r(r[2:0]), .k_0(mul_hh_0), .k_1(mul_hh_1));
    gf2_multiplier_sca m2 (.clk(clk), .q_0(ql_0), .q_1(ql_1), .a_0(al_0), .a_1(al_1), .r(r[5:3]), .k_0(mul_ll_0), .k_1(mul_ll_1));
    gf2_multiplier_sca m3 (.clk(clk), .q_0(qh_0 ^ ql_0), .q_1(qh_1 ^ ql_1), .a_0(ah_0 ^ al_0), .a_1(ah_1 ^ al_1), .r(r[8:6]), .k_0(mul_hl_lh_0), .k_1(mul_hl_lh_1));

    wire [1:0] ph_phi_0, ph_phi_1;
    assign ph_phi_0[1] = mul_hh_0[1] ^ mul_hh_0[0];
    assign ph_phi_0[0] = mul_hh_0[1];
    assign ph_phi_1[1] = mul_hh_1[1] ^ mul_hh_1[0];
    assign ph_phi_1[0] = mul_hh_1[1];

    assign k_0 = {(mul_hl_lh_0 ^ mul_ll_0), (ph_phi_0 ^ mul_ll_0)};
    assign k_1 = {(mul_hl_lh_1 ^ mul_ll_1), (ph_phi_1 ^ mul_ll_1)};
endmodule

module gf2_multiplier_sca (
    input clk,
    input  [1:0] q_0, q_1, a_0, a_1,
    input  [2:0] r,
    output [1:0] k_0, k_1
);
    wire t0_0, t0_1, t1_0, t1_1, t2_0, t2_1;

    dom_and_sca and0 (
        .clk(clk),
        .a_0(q_0[0]), .a_1(q_1[0]), .b_0(a_0[0]), .b_1(a_1[0]), .z(r[0]),
        .c_0(t0_0), .c_1(t0_1)
    );

    dom_and_sca and1 (
        .clk(clk),
        .a_0(q_0[1]), .a_1(q_1[1]), .b_0(a_0[1]), .b_1(a_1[1]), .z(r[1]),
        .c_0(t1_0), .c_1(t1_1)
    );

    dom_and_sca and2 (
        .clk(clk),
        .a_0(q_0[1] ^ q_0[0]), .a_1(q_1[1] ^ q_1[0]),
        .b_0(a_0[1] ^ a_0[0]), .b_1(a_1[1] ^ a_1[0]), .z(r[2]),
        .c_0(t2_0), .c_1(t2_1)
    );

    assign k_0[1] = t2_0 ^ t0_0;
    assign k_1[1] = t2_1 ^ t0_1;

    assign k_0[0] = t1_0 ^ t0_0;
    assign k_1[0] = t1_1 ^ t0_1;
endmodule

module gf4_inverter_sca (
    input clk,
    input  [3:0] q_0, q_1,
    input  [8:0] r,
    output [3:0] q_inv_0, q_inv_1
);
    wire [1:0] qh_0 = q_0[3:2], ql_0 = q_0[1:0];
    wire [1:0] qh_1 = q_1[3:2], ql_1 = q_1[1:0];

    wire [1:0] qh_sq_phi_0 = {qh_0[0], qh_0[1]};
    wire [1:0] qh_sq_phi_1 = {qh_1[0], qh_1[1]};

    wire [1:0] ql_sq_0 = {ql_0[1], ql_0[1] ^ ql_0[0]};
    wire [1:0] ql_sq_1 = {ql_1[1], ql_1[1] ^ ql_1[0]};

    wire [1:0] qh_mul_ql_0, qh_mul_ql_1;
    gf2_multiplier_sca m_det (
        .clk(clk),
        .q_0(qh_0), .q_1(qh_1), .a_0(ql_0), .a_1(ql_1),
        .r(r[2:0]), .k_0(qh_mul_ql_0), .k_1(qh_mul_ql_1)
    );

    reg [1:0] qh_0_d1, qh_1_d1, ql_0_d1, ql_1_d1;
    reg [5:0] r_d1;
    reg [1:0] qh_sq_phi_0_d1, qh_sq_phi_1_d1;
    reg [1:0] ql_sq_0_d1, ql_sq_1_d1;

    always @(posedge clk) begin
        qh_0_d1 <= qh_0; qh_1_d1 <= qh_1;
        ql_0_d1 <= ql_0; ql_1_d1 <= ql_1;
        r_d1 <= r[8:3];
        qh_sq_phi_0_d1 <= qh_sq_phi_0; qh_sq_phi_1_d1 <= qh_sq_phi_1;
        ql_sq_0_d1 <= ql_sq_0; ql_sq_1_d1 <= ql_sq_1;
    end

    wire [1:0] det_0 = qh_sq_phi_0_d1 ^ ql_sq_0_d1 ^ qh_mul_ql_0;
    wire [1:0] det_1 = qh_sq_phi_1_d1 ^ ql_sq_1_d1 ^ qh_mul_ql_1;

    wire [1:0] inv_det_0 = {det_0[1], det_0[1] ^ det_0[0]};
    wire [1:0] inv_det_1 = {det_1[1], det_1[1] ^ det_1[0]};

    wire [1:0] q_inv_h_0, q_inv_h_1;
    gf2_multiplier_sca m_h (
        .clk(clk),
        .q_0(qh_0_d1), .q_1(qh_1_d1), .a_0(inv_det_0), .a_1(inv_det_1),
        .r(r_d1[2:0]), .k_0(q_inv_h_0), .k_1(q_inv_h_1)
    );

    wire [1:0] q_inv_l_0, q_inv_l_1;
    gf2_multiplier_sca m_l (
        .clk(clk),
        .q_0(qh_0_d1 ^ ql_0_d1), .q_1(qh_1_d1 ^ ql_1_d1), .a_0(inv_det_0), .a_1(inv_det_1),
        .r(r_d1[5:3]), .k_0(q_inv_l_0), .k_1(q_inv_l_1)
    );

    assign q_inv_0 = {q_inv_h_0, q_inv_l_0};
    assign q_inv_1 = {q_inv_h_1, q_inv_l_1};
endmodule



/*****************************************************************

Design: aes_operation_sca_MODE128_10p0ns

Performance: /home/user16/aes_sca/syn/results/aes_operation_sca_MODE128_10p0ns/reports/qor.rpt
  Critical Path Clk Period : 10.0 ns
  Critical Path Slack      : 5.98 ns
  Maximum Frequency        : 248.76 MHz

Power: /home/user16/aes_sca/syn/results/aes_operation_sca_MODE128_10p0ns/reports/power.rpt
Total power                : 2403.1000 uW
  Dynamic power            : 1.8715e+03 uW (77.9%)
    Internal power         : 1540.4000 uW
    Switching power        : 331.0826 uW
  Static power             : 5.3163e+08 pW (22.1%)

Area: /home/user16/aes_sca/syn/results/aes_operation_sca_MODE128_10p0ns/reports/qor.rpt
  Design Area              : 26128.2911 (10.2809 kGE)
    Combinational Area     : 13686.417088 (52.4%)
    Noncombinational Area  : 12441.873994 (47.6%)
  Net Length               : 151191.30

*****************************************************************/
// Full datapath DOM, Shuffling

// ============================================================================
// MAIN ACCELERATOR MODULE
// Features: Full Datapath Masking, Column Shuffling, Parallel Key Generation
// ============================================================================
module aes_operation_sca #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] key_in,
    input [31:0] data_in,
    input [178:0] random_bits,
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

    localparam S_IDLE   = 2'b00;
    localparam S_LOAD   = 2'b01;
    localparam S_ROUND  = 2'b11;
    localparam S_OUTPUT = 2'b10;

    reg [1:0] state, next_state;
    reg [3:0] cycle_cnt, next_cycle_cnt;
    reg [3:0] round_cnt, next_round_cnt;

    // Full Datapath DOM State Registers
    reg [127:0] state_reg_0;
    reg [127:0] state_reg_1;
    reg [MODE-1:0] key_reg;
    
    // Separate buffers for the two data shares
    reg [127:0] next_state_buffer_0;
    reg [127:0] next_state_buffer_1;

    // ------------------------------------------------------------------------
    // SHUFFLING LOGIC
    // ------------------------------------------------------------------------
    wire [2:0] perm_sel = random_bits[146:144];
    reg [7:0] perm_table;
    always @(*) begin
        case(perm_sel)
            3'd0: perm_table = 8'b11_10_01_00; 
            3'd1: perm_table = 8'b10_11_00_01; 
            3'd2: perm_table = 8'b01_00_11_10; 
            3'd3: perm_table = 8'b00_01_10_11; 
            3'd4: perm_table = 8'b11_01_10_00; 
            3'd5: perm_table = 8'b01_11_00_10; 
            3'd6: perm_table = 8'b10_00_11_01; 
            3'd7: perm_table = 8'b00_10_01_11; 
        endcase
    end

    wire [1:0] cur_col_idx = 
        (cycle_cnt == 4'd1) ? perm_table[1:0] :
        (cycle_cnt == 4'd2) ? perm_table[3:2] :
        (cycle_cnt == 4'd3) ? perm_table[5:4] :
        (cycle_cnt == 4'd4) ? perm_table[7:6] : 2'd0;

    reg [1:0] pipe0, pipe1, pipe2, pipe3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe0 <= 2'd0; pipe1 <= 2'd0; pipe2 <= 2'd0; pipe3 <= 2'd0;
        end else begin
            pipe0 <= cur_col_idx;
            pipe1 <= pipe0;
            pipe2 <= pipe1;
            pipe3 <= pipe2;
        end
    end
    wire [1:0] write_col_idx = pipe3;

    wire [31:0] shifted_col_0 = 
        (cur_col_idx == 2'd0) ? {state_reg_0[127:120], state_reg_0[87:80],   state_reg_0[47:40],   state_reg_0[7:0]} :
        (cur_col_idx == 2'd1) ? {state_reg_0[95:88],   state_reg_0[55:48],   state_reg_0[15:8],    state_reg_0[103:96]} :
        (cur_col_idx == 2'd2) ? {state_reg_0[63:56],   state_reg_0[23:16],   state_reg_0[111:104], state_reg_0[71:64]} :
                                {state_reg_0[31:24],   state_reg_0[119:112], state_reg_0[79:72],   state_reg_0[39:32]};

    wire [31:0] shifted_col_1 = 
        (cur_col_idx == 2'd0) ? {state_reg_1[127:120], state_reg_1[87:80],   state_reg_1[47:40],   state_reg_1[7:0]} :
        (cur_col_idx == 2'd1) ? {state_reg_1[95:88],   state_reg_1[55:48],   state_reg_1[15:8],    state_reg_1[103:96]} :
        (cur_col_idx == 2'd2) ? {state_reg_1[63:56],   state_reg_1[23:16],   state_reg_1[111:104], state_reg_1[71:64]} :
                                {state_reg_1[31:24],   state_reg_1[119:112], state_reg_1[79:72],   state_reg_1[39:32]};

    wire [31:0] key_sbox_in;
    wire [31:0] key_sbox_out;
    
    // Key Sbox safely multiplexed on Cycle 0
    wire [31:0] shared_sbox_in_0 = (state == S_ROUND && cycle_cnt == 4'd0) ? key_sbox_in : shifted_col_0;
    wire [31:0] shared_sbox_in_1 = (state == S_ROUND && cycle_cnt == 4'd0) ? 32'd0       : shifted_col_1;
    
    wire [31:0] shared_sbox_out_0;
    wire [31:0] shared_sbox_out_1;

    // ------------------------------------------------------------------------
    // SHARED DOM SBOX
    // ------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sbox_gen
            aes_sbox_sca u_sbox (
                .clk(clk),
                .data_in_0(shared_sbox_in_0[(i*8) +: 8]),
                .data_in_1(shared_sbox_in_1[(i*8) +: 8]),
                .random_bits(random_bits[(i*36) +: 36]),
                .data_out_0(shared_sbox_out_0[(i*8) +: 8]),
                .data_out_1(shared_sbox_out_1[(i*8) +: 8])
            );
        end
    endgenerate

    assign key_sbox_out = shared_sbox_out_0 ^ shared_sbox_out_1;

    function automatic [7:0] xtime;
        input [7:0] b;
        begin
            xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
        end
    endfunction

    // ------------------------------------------------------------------------
    // DUPLICATED MIXCOLUMNS FOR LINEAR MASKING
    // ------------------------------------------------------------------------
    wire [7:0] sb0_0 = shared_sbox_out_0[31:24];
    wire [7:0] sb1_0 = shared_sbox_out_0[23:16];
    wire [7:0] sb2_0 = shared_sbox_out_0[15:8];
    wire [7:0] sb3_0 = shared_sbox_out_0[7:0];

    wire [7:0] mc0_0 = xtime(sb0_0) ^ xtime(sb1_0) ^ sb1_0 ^ sb2_0 ^ sb3_0;
    wire [7:0] mc1_0 = sb0_0 ^ xtime(sb1_0) ^ xtime(sb2_0) ^ sb2_0 ^ sb3_0;
    wire [7:0] mc2_0 = sb0_0 ^ sb1_0 ^ xtime(sb2_0) ^ xtime(sb3_0) ^ sb3_0;
    wire [7:0] mc3_0 = xtime(sb0_0) ^ sb0_0 ^ sb1_0 ^ sb2_0 ^ xtime(sb3_0);
    wire [31:0] mixcolumns_out_0 = {mc0_0, mc1_0, mc2_0, mc3_0};

    wire [7:0] sb0_1 = shared_sbox_out_1[31:24];
    wire [7:0] sb1_1 = shared_sbox_out_1[23:16];
    wire [7:0] sb2_1 = shared_sbox_out_1[15:8];
    wire [7:0] sb3_1 = shared_sbox_out_1[7:0];

    wire [7:0] mc0_1 = xtime(sb0_1) ^ xtime(sb1_1) ^ sb1_1 ^ sb2_1 ^ sb3_1;
    wire [7:0] mc1_1 = sb0_1 ^ xtime(sb1_1) ^ xtime(sb2_1) ^ sb2_1 ^ sb3_1;
    wire [7:0] mc2_1 = sb0_1 ^ sb1_1 ^ xtime(sb2_1) ^ xtime(sb3_1) ^ sb3_1;
    wire [7:0] mc3_1 = xtime(sb0_1) ^ sb0_1 ^ sb1_1 ^ sb2_1 ^ xtime(sb3_1);
    wire [31:0] mixcolumns_out_1 = {mc0_1, mc1_1, mc2_1, mc3_1};

    wire [31:0] processed_data_0 = (round_cnt == Nr) ? shared_sbox_out_0 : mixcolumns_out_0;
    wire [31:0] processed_data_1 = (round_cnt == Nr) ? shared_sbox_out_1 : mixcolumns_out_1;

    // Buffer processing combinations
    wire [127:0] assembled_data_0;
    assign assembled_data_0[127:96] = (write_col_idx == 2'd0) ? processed_data_0 : next_state_buffer_0[127:96];
    assign assembled_data_0[95:64]  = (write_col_idx == 2'd1) ? processed_data_0 : next_state_buffer_0[95:64];
    assign assembled_data_0[63:32]  = (write_col_idx == 2'd2) ? processed_data_0 : next_state_buffer_0[63:32];
    assign assembled_data_0[31:0]   = (write_col_idx == 2'd3) ? processed_data_0 : next_state_buffer_0[31:0];

    wire [127:0] assembled_data_1;
    assign assembled_data_1[127:96] = (write_col_idx == 2'd0) ? processed_data_1 : next_state_buffer_1[127:96];
    assign assembled_data_1[95:64]  = (write_col_idx == 2'd1) ? processed_data_1 : next_state_buffer_1[95:64];
    assign assembled_data_1[63:32]  = (write_col_idx == 2'd2) ? processed_data_1 : next_state_buffer_1[63:32];
    assign assembled_data_1[31:0]   = (write_col_idx == 2'd3) ? processed_data_1 : next_state_buffer_1[31:0];

    // Tap the valid initial and full round keys correctly
    `ifdef AES_256
        wire [31:0] initial_add_rk_word = key_reg[127:96];
        wire [127:0] full_round_key = key_reg[255:128];
    `elsif AES_192
        wire [31:0] initial_add_rk_word = key_reg[63:32];
        wire [127:0] full_round_key = key_reg[191:64];
    `else
        wire [31:0] initial_add_rk_word = key_in;
        wire [127:0] full_round_key = key_reg[127:0];
    `endif

    wire [127:0] next_4_words;

    // Parallel schedule instantiation
    aes_key_expansion_sca #(
        .MODE(MODE)
    ) key_expand_inst (
        .round_cnt(round_cnt),
        .key_reg(key_reg),
        .sbox_in(key_sbox_in),
        .sbox_out(key_sbox_out),
        .next_4_words(next_4_words)
    );

    // ------------------------------------------------------------------------
    // STATE MACHINE
    // ------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        next_cycle_cnt = cycle_cnt;
        next_round_cnt = round_cnt;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_state = S_LOAD;
                    next_cycle_cnt = 4'd1;
                end
            end

            S_LOAD: begin
                if (valid_in) begin
                    if (cycle_cnt == Nk - 1) begin
                        next_state = S_ROUND;
                        next_round_cnt = 4'd1;
                        next_cycle_cnt = 4'd0;
                    end else begin
                        next_cycle_cnt = cycle_cnt + 4'd1;
                    end
                end
            end

            S_ROUND: begin
                if (cycle_cnt == 4'd8) begin
                    if (round_cnt == Nr) begin
                        next_state = S_OUTPUT;
                        next_cycle_cnt = 4'd0;
                    end else begin
                        next_round_cnt = round_cnt + 4'd1;
                        next_cycle_cnt = 4'd0;
                    end
                end else begin
                    next_cycle_cnt = cycle_cnt + 4'd1;
                end
            end

            S_OUTPUT: begin
                if (cycle_cnt == 4'd3) begin
                    next_state = S_IDLE;
                    next_cycle_cnt = 4'd0;
                end else begin
                    next_cycle_cnt = cycle_cnt + 4'd1;
                end
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cycle_cnt <= 4'd0;
            round_cnt <= 4'd0;
        end else begin
            state <= next_state;
            cycle_cnt <= next_cycle_cnt;
            round_cnt <= next_round_cnt;
        end
    end

    // ------------------------------------------------------------------------
    // REGISTER UPDATES
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg_0 <= 128'd0;
            state_reg_1 <= 128'd0;
            key_reg <= 0;
            next_state_buffer_0 <= 128'd0;
            next_state_buffer_1 <= 128'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (valid_in) begin
                        `ifndef AES_256
                        `ifndef AES_192
                        state_reg_0 <= {state_reg_0[95:0], data_in ^ initial_add_rk_word ^ random_bits[178:147]};
                        state_reg_1 <= {state_reg_1[95:0], random_bits[178:147]};
                        `endif
                        `endif
                        key_reg <= {key_reg[MODE-33:0], key_in};
                    end
                end

                S_LOAD: begin
                    if (valid_in) begin
                        key_reg <= {key_reg[MODE-33:0], key_in};
                        if (cycle_cnt >= Nk - 4) begin
                            state_reg_0 <= {state_reg_0[95:0], data_in ^ initial_add_rk_word ^ random_bits[178:147]};
                            state_reg_1 <= {state_reg_1[95:0], random_bits[178:147]};
                        end
                    end
                end

                S_ROUND: begin
                    if (cycle_cnt == 4'd4) begin
                        key_reg <= (MODE == 128) ? next_4_words : 
                                   (MODE == 192) ? {key_reg[63:0], next_4_words} : 
                                                   {key_reg[127:0], next_4_words};
                    end
                    
                    if (cycle_cnt == 4'd8) begin
                        state_reg_0 <= assembled_data_0 ^ full_round_key;
                        state_reg_1 <= assembled_data_1;
                    end else if (cycle_cnt >= 4'd5 && cycle_cnt <= 4'd7) begin
                        case (write_col_idx)
                            2'd0: begin next_state_buffer_0[127:96] <= processed_data_0; next_state_buffer_1[127:96] <= processed_data_1; end
                            2'd1: begin next_state_buffer_0[95:64]  <= processed_data_0; next_state_buffer_1[95:64]  <= processed_data_1; end
                            2'd2: begin next_state_buffer_0[63:32]  <= processed_data_0; next_state_buffer_1[63:32]  <= processed_data_1; end
                            2'd3: begin next_state_buffer_0[31:0]   <= processed_data_0; next_state_buffer_1[31:0]   <= processed_data_1; end
                        endcase
                    end
                end
                
                default: begin end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // OUTPUT LOGIC
    // ------------------------------------------------------------------------
    always @(*) begin
        valid_out = 1'b0;
        data_out = 32'd0;
        
        if (state == S_OUTPUT) begin
            valid_out = 1'b1;
            case (cycle_cnt[1:0])
                2'd0: data_out = state_reg_0[127:96] ^ state_reg_1[127:96];
                2'd1: data_out = state_reg_0[95:64]  ^ state_reg_1[95:64];
                2'd2: data_out = state_reg_0[63:32]  ^ state_reg_1[63:32];
                2'd3: data_out = state_reg_0[31:0]   ^ state_reg_1[31:0];
                default: data_out = 32'd0;
            endcase
        end
    end
endmodule


// ============================================================================
// PARALLEL KEY EXPANSION MODULE (SUPPORTS ALL MODES)
// ============================================================================
module aes_key_expansion_sca #(
    parameter MODE = 128
)(
    input  [3:0]      round_cnt,
    input  [MODE-1:0] key_reg,
    output [31:0]     sbox_in,
    input  [31:0]     sbox_out,
    output [127:0]    next_4_words
);

    function automatic [31:0] get_rcon(input [3:0] r_idx);
        case(r_idx)
            4'd1:  get_rcon = 32'h01000000;
            4'd2:  get_rcon = 32'h02000000;
            4'd3:  get_rcon = 32'h04000000;
            4'd4:  get_rcon = 32'h08000000;
            4'd5:  get_rcon = 32'h10000000;
            4'd6:  get_rcon = 32'h20000000;
            4'd7:  get_rcon = 32'h40000000;
            4'd8:  get_rcon = 32'h80000000;
            4'd9:  get_rcon = 32'h1B000000;
            4'd10: get_rcon = 32'h36000000;
            4'd11: get_rcon = 32'h6C000000;
            4'd12: get_rcon = 32'hD8000000;
            4'd13: get_rcon = 32'hAB000000;
            4'd14: get_rcon = 32'h4D000000;
            default: get_rcon = 32'h00000000;
        endcase
    endfunction

    generate
        if (MODE == 128) begin : gen_128
            wire [31:0] c0 = key_reg[127:96];
            wire [31:0] c1 = key_reg[95:64];
            wire [31:0] c2 = key_reg[63:32];
            wire [31:0] c3 = key_reg[31:0];

            assign sbox_in = {c3[23:0], c3[31:24]}; 

            wire [31:0] n0 = c0 ^ sbox_out ^ get_rcon(round_cnt);
            wire [31:0] n1 = c1 ^ n0;
            wire [31:0] n2 = c2 ^ n1;
            wire [31:0] n3 = c3 ^ n2;

            assign next_4_words = {n0, n1, n2, n3};

        end else if (MODE == 192) begin : gen_192
            wire [31:0] c0 = key_reg[191:160];
            wire [31:0] c1 = key_reg[159:128];
            wire [31:0] c2 = key_reg[127:96];
            wire [31:0] c3 = key_reg[95:64];
            wire [31:0] c4 = key_reg[63:32];
            wire [31:0] c5 = key_reg[31:0];

            reg [1:0] rem;
            always @(*) begin
                case (round_cnt)
                    4'd1, 4'd4, 4'd7, 4'd10, 4'd13: rem = 2'd1;
                    4'd2, 4'd5, 4'd8, 4'd11, 4'd14: rem = 2'd2;
                    4'd0, 4'd3, 4'd6, 4'd9, 4'd12:  rem = 2'd0;
                    default: rem = 2'd0;
                endcase
            end
            
            reg [3:0] rcon_idx;
            always @(*) begin
                case (round_cnt)
                    4'd1:  rcon_idx = 4'd1;
                    4'd2:  rcon_idx = 4'd2;
                    4'd4:  rcon_idx = 4'd3;
                    4'd5:  rcon_idx = 4'd4;
                    4'd7:  rcon_idx = 4'd5;
                    4'd8:  rcon_idx = 4'd6;
                    4'd10: rcon_idx = 4'd7;
                    4'd11: rcon_idx = 4'd8;
                    default: rcon_idx = 4'd0;
                endcase
            end

            wire [31:0] n1_comb = c1 ^ c0 ^ c5;
            assign sbox_in = (rem == 2'd1) ? {c5[23:0], c5[31:24]} : 
                             (rem == 2'd2) ? {n1_comb[23:0], n1_comb[31:24]} : 32'd0;

            wire [31:0] n0 = (rem == 2'd1) ? (c0 ^ sbox_out ^ get_rcon(rcon_idx)) : (c0 ^ c5);
            wire [31:0] n1 = c1 ^ n0;
            wire [31:0] n2 = (rem == 2'd1) ? (c2 ^ n1) :
                             (rem == 2'd2) ? (c2 ^ sbox_out ^ get_rcon(rcon_idx)) :
                                             (c2 ^ n1);
            wire [31:0] n3 = c3 ^ n2;

            assign next_4_words = {n0, n1, n2, n3};

        end else begin : gen_256
            wire [31:0] c0 = key_reg[255:224];
            wire [31:0] c1 = key_reg[223:192];
            wire [31:0] c2 = key_reg[191:160];
            wire [31:0] c3 = key_reg[159:128];
            wire [31:0] c4 = key_reg[127:96];
            wire [31:0] c5 = key_reg[95:64];
            wire [31:0] c6 = key_reg[63:32];
            wire [31:0] c7 = key_reg[31:0];

            wire is_rcon_round = (round_cnt[0] != 1'b0);
            wire [3:0] rcon_idx = {1'b0, round_cnt[3:1]} + 4'd1;

            assign sbox_in = is_rcon_round ? {c7[23:0], c7[31:24]} : c7;

            wire [31:0] n0 = is_rcon_round ? (c0 ^ sbox_out ^ get_rcon(rcon_idx)) : (c0 ^ sbox_out);
            wire [31:0] n1 = c1 ^ n0;
            wire [31:0] n2 = c2 ^ n1;
            wire [31:0] n3 = c3 ^ n2;

            assign next_4_words = {n0, n1, n2, n3};
        end
    endgenerate
endmodule


// ============================================================================
// DOMAIN ORIENTED MASKING (DOM) SBOX
// ============================================================================
module aes_sbox_sca (
    input clk,
    input  [7:0] data_in_0,
    input  [7:0] data_in_1,
    input  [35:0] random_bits, 
    output [7:0] data_out_0,
    output [7:0] data_out_1
);
    wire [7:0] mapped_0, mapped_1;
    wire [7:0] inverted_0, inverted_1;
    wire [7:0] restored_0, restored_1;
    wire [7:0] aff_out_0, aff_out_1;

    isomorphic_mapping_sca map_unit (
        .data_in_0(data_in_0), .data_in_1(data_in_1),
        .data_out_0(mapped_0), .data_out_1(mapped_1)
    );

    multiplicative_inverter_sca inv_unit (
        .clk(clk),
        .data_in_0(mapped_0), .data_in_1(mapped_1),
        .r(random_bits),
        .data_out_0(inverted_0), .data_out_1(inverted_1)
    );

    inverse_mapping_sca restore_unit (
        .data_in_0(inverted_0), .data_in_1(inverted_1),
        .data_out_0(restored_0), .data_out_1(restored_1)
    );

    affine_transformation_sca aff_unit (
        .data_in_0(restored_0), .data_in_1(restored_1),
        .data_out_0(aff_out_0), .data_out_1(aff_out_1)
    );

    assign data_out_0 = aff_out_0;
    assign data_out_1 = aff_out_1;
endmodule


// ============================================================================
// DOM SECURE AND GATE
// ============================================================================
module dom_and_sca (
    input clk, 
    input a_0, a_1, b_0, b_1, z,
    output c_0, c_1
);
    wire inner_0 = a_0 & b_0;
    wire inner_1 = a_1 & b_1;

    wire cross_0_comb = (a_0 & b_1) ^ z;
    wire cross_1_comb = (a_1 & b_0) ^ z;

    reg cross_0_reg, cross_1_reg;
    reg inner_0_reg, inner_1_reg;

    always @(posedge clk) begin
        cross_0_reg <= cross_0_comb;
        cross_1_reg <= cross_1_comb;
        inner_0_reg <= inner_0;
        inner_1_reg <= inner_1;
    end

    assign c_0 = inner_0_reg ^ cross_0_reg;
    assign c_1 = inner_1_reg ^ cross_1_reg;
endmodule


// ============================================================================
// AFFINE TRANSFORMATION (LINEAR)
// ============================================================================
module affine_transformation_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    assign data_out_0[0] = data_in_0[0] ^ data_in_0[4] ^ data_in_0[5] ^ data_in_0[6] ^ data_in_0[7] ^ 1'b1;
    assign data_out_0[1] = data_in_0[1] ^ data_in_0[5] ^ data_in_0[6] ^ data_in_0[7] ^ data_in_0[0] ^ 1'b1;
    assign data_out_0[2] = data_in_0[2] ^ data_in_0[6] ^ data_in_0[7] ^ data_in_0[0] ^ data_in_0[1] ^ 1'b0;
    assign data_out_0[3] = data_in_0[3] ^ data_in_0[7] ^ data_in_0[0] ^ data_in_0[1] ^ data_in_0[2] ^ 1'b0;
    assign data_out_0[4] = data_in_0[4] ^ data_in_0[0] ^ data_in_0[1] ^ data_in_0[2] ^ data_in_0[3] ^ 1'b0;
    assign data_out_0[5] = data_in_0[5] ^ data_in_0[1] ^ data_in_0[2] ^ data_in_0[3] ^ data_in_0[4] ^ 1'b1;
    assign data_out_0[6] = data_in_0[6] ^ data_in_0[2] ^ data_in_0[3] ^ data_in_0[4] ^ data_in_0[5] ^ 1'b1;
    assign data_out_0[7] = data_in_0[7] ^ data_in_0[3] ^ data_in_0[4] ^ data_in_0[5] ^ data_in_0[6] ^ 1'b0;

    assign data_out_1[0] = data_in_1[0] ^ data_in_1[4] ^ data_in_1[5] ^ data_in_1[6] ^ data_in_1[7];
    assign data_out_1[1] = data_in_1[1] ^ data_in_1[5] ^ data_in_1[6] ^ data_in_1[7] ^ data_in_1[0];
    assign data_out_1[2] = data_in_1[2] ^ data_in_1[6] ^ data_in_1[7] ^ data_in_1[0] ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[3] ^ data_in_1[7] ^ data_in_1[0] ^ data_in_1[1] ^ data_in_1[2];
    assign data_out_1[4] = data_in_1[4] ^ data_in_1[0] ^ data_in_1[1] ^ data_in_1[2] ^ data_in_1[3];
    assign data_out_1[5] = data_in_1[5] ^ data_in_1[1] ^ data_in_1[2] ^ data_in_1[3] ^ data_in_1[4];
    assign data_out_1[6] = data_in_1[6] ^ data_in_1[2] ^ data_in_1[3] ^ data_in_1[4] ^ data_in_1[5];
    assign data_out_1[7] = data_in_1[7] ^ data_in_1[3] ^ data_in_1[4] ^ data_in_1[5] ^ data_in_1[6];
endmodule


// ============================================================================
// ISOMORPHIC MAPPING
// ============================================================================
module isomorphic_mapping_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    assign data_out_0[7] = data_in_0[7] ^ data_in_0[5];
    assign data_out_0[6] = data_in_0[7] ^ data_in_0[6] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[5] = data_in_0[7] ^ data_in_0[5] ^ data_in_0[3] ^ data_in_0[2];
    assign data_out_0[4] = data_in_0[7] ^ data_in_0[5] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[3] = data_in_0[7] ^ data_in_0[6] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[2] = data_in_0[7] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[1] = data_in_0[6] ^ data_in_0[4] ^ data_in_0[1];
    assign data_out_0[0] = data_in_0[6] ^ data_in_0[1] ^ data_in_0[0];

    assign data_out_1[7] = data_in_1[7] ^ data_in_1[5];
    assign data_out_1[6] = data_in_1[7] ^ data_in_1[6] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[5] = data_in_1[7] ^ data_in_1[5] ^ data_in_1[3] ^ data_in_1[2];
    assign data_out_1[4] = data_in_1[7] ^ data_in_1[5] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[7] ^ data_in_1[6] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[2] = data_in_1[7] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[1] = data_in_1[6] ^ data_in_1[4] ^ data_in_1[1];
    assign data_out_1[0] = data_in_1[6] ^ data_in_1[1] ^ data_in_1[0];
endmodule


// ============================================================================
// INVERSE ISOMORPHIC MAPPING
// ============================================================================
module inverse_mapping_sca (
    input  [7:0] data_in_0, data_in_1,
    output [7:0] data_out_0, data_out_1
);
    assign data_out_0[7] = data_in_0[7] ^ data_in_0[6] ^ data_in_0[5] ^ data_in_0[1];
    assign data_out_0[6] = data_in_0[6] ^ data_in_0[2];
    assign data_out_0[5] = data_in_0[6] ^ data_in_0[5] ^ data_in_0[1];
    assign data_out_0[4] = data_in_0[6] ^ data_in_0[5] ^ data_in_0[4] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[3] = data_in_0[5] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[2] = data_in_0[7] ^ data_in_0[4] ^ data_in_0[3] ^ data_in_0[2] ^ data_in_0[1];
    assign data_out_0[1] = data_in_0[5] ^ data_in_0[4];
    assign data_out_0[0] = data_in_0[6] ^ data_in_0[5] ^ data_in_0[4] ^ data_in_0[2] ^ data_in_0[0];

    assign data_out_1[7] = data_in_1[7] ^ data_in_1[6] ^ data_in_1[5] ^ data_in_1[1];
    assign data_out_1[6] = data_in_1[6] ^ data_in_1[2];
    assign data_out_1[5] = data_in_1[6] ^ data_in_1[5] ^ data_in_1[1];
    assign data_out_1[4] = data_in_1[6] ^ data_in_1[5] ^ data_in_1[4] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[3] = data_in_1[5] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[2] = data_in_1[7] ^ data_in_1[4] ^ data_in_1[3] ^ data_in_1[2] ^ data_in_1[1];
    assign data_out_1[1] = data_in_1[5] ^ data_in_1[4];
    assign data_out_1[0] = data_in_1[6] ^ data_in_1[5] ^ data_in_1[4] ^ data_in_1[2] ^ data_in_1[0];
endmodule


// ============================================================================
// MULTIPLICATIVE INVERTER
// ============================================================================
module multiplicative_inverter_sca (
    input clk,
    input  [7:0] data_in_0, data_in_1,
    input  [35:0] r,
    output [7:0] data_out_0, data_out_1
);
    wire [3:0] b_0 = data_in_0[7:4], c_0 = data_in_0[3:0];
    wire [3:0] b_1 = data_in_1[7:4], c_1 = data_in_1[3:0];

    wire [3:0] b_sq_0, b_sq_1;
    wire [3:0] b_sq_lambda_0, b_sq_lambda_1;
    wire [3:0] b_plus_c_0, b_plus_c_1;
    wire [3:0] c_mul_bplusc_0, c_mul_bplusc_1;
    wire [3:0] combined_inv_0, combined_inv_1;
    wire [3:0] out_h_0, out_h_1, out_l_0, out_l_1;

    assign b_sq_0[3] = b_0[3];
    assign b_sq_0[2] = b_0[3] ^ b_0[2];
    assign b_sq_0[1] = b_0[2] ^ b_0[1];
    assign b_sq_0[0] = b_0[3] ^ b_0[1] ^ b_0[0];

    assign b_sq_1[3] = b_1[3];
    assign b_sq_1[2] = b_1[3] ^ b_1[2];
    assign b_sq_1[1] = b_1[2] ^ b_1[1];
    assign b_sq_1[0] = b_1[3] ^ b_1[1] ^ b_1[0];

    assign b_sq_lambda_0[3] = b_sq_0[2] ^ b_sq_0[0];
    assign b_sq_lambda_0[2] = b_sq_0[3] ^ b_sq_0[2] ^ b_sq_0[1] ^ b_sq_0[0];
    assign b_sq_lambda_0[1] = b_sq_0[3];
    assign b_sq_lambda_0[0] = b_sq_0[2];

    assign b_sq_lambda_1[3] = b_sq_1[2] ^ b_sq_1[0];
    assign b_sq_lambda_1[2] = b_sq_1[3] ^ b_sq_1[2] ^ b_sq_1[1] ^ b_sq_1[0];
    assign b_sq_lambda_1[1] = b_sq_1[3];
    assign b_sq_lambda_1[0] = b_sq_1[2];

    assign b_plus_c_0 = b_0 ^ c_0;
    assign b_plus_c_1 = b_1 ^ c_1;

    gf4_multiplier_sca mul_inst (
        .clk(clk),
        .q_0(c_0), .q_1(c_1), .a_0(b_plus_c_0), .a_1(b_plus_c_1),
        .r(r[8:0]), .k_0(c_mul_bplusc_0), .k_1(c_mul_bplusc_1)
    );

    reg [3:0] b_sq_lambda_0_d1, b_sq_lambda_1_d1;
    reg [26:0] r_d1;
    reg [3:0] b_0_d1, b_1_d1, b_plus_c_0_d1, b_plus_c_1_d1;

    always @(posedge clk) begin
        b_sq_lambda_0_d1 <= b_sq_lambda_0; b_sq_lambda_1_d1 <= b_sq_lambda_1;
        r_d1 <= r[35:9];
        b_0_d1 <= b_0; b_1_d1 <= b_1;
        b_plus_c_0_d1 <= b_plus_c_0; b_plus_c_1_d1 <= b_plus_c_1;
    end

    wire [3:0] combined_0 = b_sq_lambda_0_d1 ^ c_mul_bplusc_0;
    wire [3:0] combined_1 = b_sq_lambda_1_d1 ^ c_mul_bplusc_1;

    gf4_inverter_sca inv4_inst (
        .clk(clk),
        .q_0(combined_0), .q_1(combined_1),
        .r(r_d1[8:0]), .q_inv_0(combined_inv_0), .q_inv_1(combined_inv_1)
    );

    reg [3:0] b_0_d2, b_1_d2, b_plus_c_0_d2, b_plus_c_1_d2;
    reg [3:0] b_0_d3, b_1_d3, b_plus_c_0_d3, b_plus_c_1_d3;
    reg [17:0] r_d2, r_d3;

    always @(posedge clk) begin
        b_0_d2 <= b_0_d1; b_1_d2 <= b_1_d1;
        b_plus_c_0_d2 <= b_plus_c_0_d1; b_plus_c_1_d2 <= b_plus_c_1_d1;
        r_d2 <= r_d1[26:9];

        b_0_d3 <= b_0_d2; b_1_d3 <= b_1_d2;
        b_plus_c_0_d3 <= b_plus_c_0_d2; b_plus_c_1_d3 <= b_plus_c_1_d2;
        r_d3 <= r_d2;
    end

    gf4_multiplier_sca mul_high (
        .clk(clk),
        .q_0(b_0_d3), .q_1(b_1_d3), .a_0(combined_inv_0), .a_1(combined_inv_1),
        .r(r_d3[8:0]), .k_0(out_h_0), .k_1(out_h_1)
    );

    gf4_multiplier_sca mul_low (
        .clk(clk),
        .q_0(b_plus_c_0_d3), .q_1(b_plus_c_1_d3), .a_0(combined_inv_0), .a_1(combined_inv_1),
        .r(r_d3[17:9]), .k_0(out_l_0), .k_1(out_l_1)
    );

    assign data_out_0 = {out_h_0, out_l_0};
    assign data_out_1 = {out_h_1, out_l_1};
endmodule


// ============================================================================
// GF(2^4) MULTIPLIER
// ============================================================================
module gf4_multiplier_sca (
    input clk,
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

    gf2_multiplier_sca m1 (.clk(clk), .q_0(qh_0), .q_1(qh_1), .a_0(ah_0), .a_1(ah_1), .r(r[2:0]), .k_0(mul_hh_0), .k_1(mul_hh_1));
    gf2_multiplier_sca m2 (.clk(clk), .q_0(ql_0), .q_1(ql_1), .a_0(al_0), .a_1(al_1), .r(r[5:3]), .k_0(mul_ll_0), .k_1(mul_ll_1));
    gf2_multiplier_sca m3 (.clk(clk), .q_0(qh_0 ^ ql_0), .q_1(qh_1 ^ ql_1), .a_0(ah_0 ^ al_0), .a_1(ah_1 ^ al_1), .r(r[8:6]), .k_0(mul_hl_lh_0), .k_1(mul_hl_lh_1));

    wire [1:0] ph_phi_0, ph_phi_1;
    assign ph_phi_0[1] = mul_hh_0[1] ^ mul_hh_0[0];
    assign ph_phi_0[0] = mul_hh_0[1];
    assign ph_phi_1[1] = mul_hh_1[1] ^ mul_hh_1[0];
    assign ph_phi_1[0] = mul_hh_1[1];

    assign k_0 = {(mul_hl_lh_0 ^ mul_ll_0), (ph_phi_0 ^ mul_ll_0)};
    assign k_1 = {(mul_hl_lh_1 ^ mul_ll_1), (ph_phi_1 ^ mul_ll_1)};
endmodule


// ============================================================================
// GF(2^2) MULTIPLIER
// ============================================================================
module gf2_multiplier_sca (
    input clk,
    input  [1:0] q_0, q_1, a_0, a_1,
    input  [2:0] r,
    output [1:0] k_0, k_1
);
    wire t0_0, t0_1, t1_0, t1_1, t2_0, t2_1;

    dom_and_sca and0 (
        .clk(clk),
        .a_0(q_0[0]), .a_1(q_1[0]), .b_0(a_0[0]), .b_1(a_1[0]), .z(r[0]),
        .c_0(t0_0), .c_1(t0_1)
    );

    dom_and_sca and1 (
        .clk(clk),
        .a_0(q_0[1]), .a_1(q_1[1]), .b_0(a_0[1]), .b_1(a_1[1]), .z(r[1]),
        .c_0(t1_0), .c_1(t1_1)
    );

    dom_and_sca and2 (
        .clk(clk),
        .a_0(q_0[1] ^ q_0[0]), .a_1(q_1[1] ^ q_1[0]),
        .b_0(a_0[1] ^ a_0[0]), .b_1(a_1[1] ^ a_1[0]), .z(r[2]),
        .c_0(t2_0), .c_1(t2_1)
    );

    assign k_0[1] = t2_0 ^ t0_0;
    assign k_1[1] = t2_1 ^ t0_1;

    assign k_0[0] = t1_0 ^ t0_0;
    assign k_1[0] = t1_1 ^ t0_1;
endmodule


// ============================================================================
// GF(2^4) INVERTER
// ============================================================================
module gf4_inverter_sca (
    input clk,
    input  [3:0] q_0, q_1,
    input  [8:0] r,
    output [3:0] q_inv_0, q_inv_1
);
    wire [1:0] qh_0 = q_0[3:2], ql_0 = q_0[1:0];
    wire [1:0] qh_1 = q_1[3:2], ql_1 = q_1[1:0];

    wire [1:0] qh_sq_phi_0 = {qh_0[0], qh_0[1]};
    wire [1:0] qh_sq_phi_1 = {qh_1[0], qh_1[1]};

    wire [1:0] ql_sq_0 = {ql_0[1], ql_0[1] ^ ql_0[0]};
    wire [1:0] ql_sq_1 = {ql_1[1], ql_1[1] ^ ql_1[0]};

    wire [1:0] qh_mul_ql_0, qh_mul_ql_1;
    gf2_multiplier_sca m_det (
        .clk(clk),
        .q_0(qh_0), .q_1(qh_1), .a_0(ql_0), .a_1(ql_1),
        .r(r[2:0]), .k_0(qh_mul_ql_0), .k_1(qh_mul_ql_1)
    );

    reg [1:0] qh_0_d1, qh_1_d1, ql_0_d1, ql_1_d1;
    reg [5:0] r_d1;
    reg [1:0] qh_sq_phi_0_d1, qh_sq_phi_1_d1;
    reg [1:0] ql_sq_0_d1, ql_sq_1_d1;

    always @(posedge clk) begin
        qh_0_d1 <= qh_0; qh_1_d1 <= qh_1;
        ql_0_d1 <= ql_0; ql_1_d1 <= ql_1;
        r_d1 <= r[8:3];
        qh_sq_phi_0_d1 <= qh_sq_phi_0; qh_sq_phi_1_d1 <= qh_sq_phi_1;
        ql_sq_0_d1 <= ql_sq_0; ql_sq_1_d1 <= ql_sq_1;
    end

    wire [1:0] det_0 = qh_sq_phi_0_d1 ^ ql_sq_0_d1 ^ qh_mul_ql_0;
    wire [1:0] det_1 = qh_sq_phi_1_d1 ^ ql_sq_1_d1 ^ qh_mul_ql_1;

    wire [1:0] inv_det_0 = {det_0[1], det_0[1] ^ det_0[0]};
    wire [1:0] inv_det_1 = {det_1[1], det_1[1] ^ det_1[0]};

    wire [1:0] q_inv_h_0, q_inv_h_1;
    gf2_multiplier_sca m_h (
        .clk(clk),
        .q_0(qh_0_d1), .q_1(qh_1_d1), .a_0(inv_det_0), .a_1(inv_det_1),
        .r(r_d1[2:0]), .k_0(q_inv_h_0), .k_1(q_inv_h_1)
    );

    wire [1:0] q_inv_l_0, q_inv_l_1;
    gf2_multiplier_sca m_l (
        .clk(clk),
        .q_0(qh_0_d1 ^ ql_0_d1), .q_1(qh_1_d1 ^ ql_1_d1), .a_0(inv_det_0), .a_1(inv_det_1),
        .r(r_d1[5:3]), .k_0(q_inv_l_0), .k_1(q_inv_l_1)
    );

    assign q_inv_0 = {q_inv_h_0, q_inv_l_0};
    assign q_inv_1 = {q_inv_h_1, q_inv_l_1};
endmodule



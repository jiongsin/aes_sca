module aes_operation_sca #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] key_in,
    input [31:0] data_in,
    input [207:0] random_bits,
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

    reg [127:0] state_reg_0, state_reg_1;
    reg [MODE-1:0] key_reg_0, key_reg_1;
    reg [95:0]  next_state_buffer_0, next_state_buffer_1;

    wire [31:0] shifted_col_0, shifted_col_1;
    wire [31:0] subbytes_out_0, subbytes_out_1;
    wire [31:0] mixcolumns_out_0, mixcolumns_out_1;
    wire [31:0] round_data_out_0, round_data_out_1;
    wire [31:0] expanded_key_word_0, expanded_key_word_1;
    wire [31:0] current_round_key_word_0, current_round_key_word_1;
    wire [31:0] initial_add_rk_word_0, initial_add_rk_word_1;

    wire [31:0] key_mask = random_bits[63:32];
    wire [31:0] data_mask = random_bits[31:0];

    wire [31:0] masked_key_in_0 = key_in ^ key_mask;
    wire [31:0] masked_key_in_1 = key_mask;

    function automatic [31:0] shift_rows;
        input [127:0] in_state;
        input [3:0] cycle;
        begin
            shift_rows = 
                (cycle == 4'd1) ? {in_state[127:120], in_state[87:80],   in_state[47:40],   in_state[7:0]} :
                (cycle == 4'd2) ? {in_state[95:88],   in_state[55:48],   in_state[15:8],    in_state[103:96]} :
                (cycle == 4'd3) ? {in_state[63:56],   in_state[23:16],   in_state[111:104], in_state[71:64]} :
                                  {in_state[31:24],   in_state[119:112], in_state[79:72],   in_state[39:32]};
        end
    endfunction

    assign shifted_col_0 = shift_rows(state_reg_0, cycle_cnt);
    assign shifted_col_1 = shift_rows(state_reg_1, cycle_cnt);

    wire [31:0] key_sbox_in_0, key_sbox_in_1;
    wire [31:0] key_sbox_out_0, key_sbox_out_1;
    
    wire [31:0] shared_sbox_in_0 = (state == S_ROUND && cycle_cnt == 4'd0) ? key_sbox_in_0 : shifted_col_0;
    wire [31:0] shared_sbox_in_1 = (state == S_ROUND && cycle_cnt == 4'd0) ? key_sbox_in_1 : shifted_col_1;
    wire [31:0] shared_sbox_out_0, shared_sbox_out_1;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sbox_gen
            aes_sbox_sca u_sbox (
                .clk(clk),
                .data_in_0(shared_sbox_in_0[(i*8) +: 8]),
                .data_in_1(shared_sbox_in_1[(i*8) +: 8]),
                .random_bits(random_bits[64 + (i*36) +: 36]),
                .data_out_0(shared_sbox_out_0[(i*8) +: 8]),
                .data_out_1(shared_sbox_out_1[(i*8) +: 8])
            );
        end
    endgenerate

    assign subbytes_out_0 = shared_sbox_out_0;
    assign subbytes_out_1 = shared_sbox_out_1;
    assign key_sbox_out_0 = shared_sbox_out_0;
    assign key_sbox_out_1 = shared_sbox_out_1;

    wire [31:0] actual_key_sbox_out_0;
    wire [31:0] actual_key_sbox_out_1;

    `ifdef AES_192
        reg [31:0] sbox_buffer_0, sbox_buffer_1;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                sbox_buffer_0 <= 32'd0;
                sbox_buffer_1 <= 32'd0;
            end else if (state == S_ROUND && cycle_cnt == 4'd4) begin
                sbox_buffer_0 <= key_sbox_out_0;
                sbox_buffer_1 <= key_sbox_out_1;
            end
        end

        assign actual_key_sbox_out_0 = (cycle_cnt > 4'd4) ? sbox_buffer_0 : key_sbox_out_0;
        assign actual_key_sbox_out_1 = (cycle_cnt > 4'd4) ? sbox_buffer_1 : key_sbox_out_1;
    `else
        assign actual_key_sbox_out_0 = key_sbox_out_0;
        assign actual_key_sbox_out_1 = key_sbox_out_1;
    `endif

    function automatic [7:0] xtime;
        input [7:0] b;
        begin
            xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
        end
    endfunction

    function automatic [31:0] mix_col;
        input [31:0] sb;
        reg [7:0] sb0, sb1, sb2, sb3;
        reg [7:0] mc0, mc1, mc2, mc3;
        begin
            sb0 = sb[31:24]; sb1 = sb[23:16]; sb2 = sb[15:8]; sb3 = sb[7:0];
            mc0 = xtime(sb0) ^ xtime(sb1) ^ sb1 ^ sb2 ^ sb3;
            mc1 = sb0 ^ xtime(sb1) ^ xtime(sb2) ^ sb2 ^ sb3;
            mc2 = sb0 ^ sb1 ^ xtime(sb2) ^ xtime(sb3) ^ sb3;
            mc3 = xtime(sb0) ^ sb0 ^ sb1 ^ sb2 ^ xtime(sb3);
            mix_col = {mc0, mc1, mc2, mc3};
        end
    endfunction

    assign mixcolumns_out_0 = mix_col(subbytes_out_0);
    assign mixcolumns_out_1 = mix_col(subbytes_out_1);

    `ifdef AES_256
        assign current_round_key_word_0 = key_reg_0[159:128];
        assign current_round_key_word_1 = key_reg_1[159:128];
        assign initial_add_rk_word_0 = key_reg_0[127:96];
        assign initial_add_rk_word_1 = key_reg_1[127:96];
    `elsif AES_192
        assign current_round_key_word_0 = key_reg_0[95:64];
        assign current_round_key_word_1 = key_reg_1[95:64];
        assign initial_add_rk_word_0 = key_reg_0[63:32];
        assign initial_add_rk_word_1 = key_reg_1[63:32];
    `else
        assign current_round_key_word_0 = key_reg_0[31:0];
        assign current_round_key_word_1 = key_reg_1[31:0];
        assign initial_add_rk_word_0 = masked_key_in_0;
        assign initial_add_rk_word_1 = masked_key_in_1;
    `endif

    assign round_data_out_0 = (round_cnt == Nr) ? (subbytes_out_0 ^ current_round_key_word_0) : (mixcolumns_out_0 ^ current_round_key_word_0);
    assign round_data_out_1 = (round_cnt == Nr) ? (subbytes_out_1 ^ current_round_key_word_1) : (mixcolumns_out_1 ^ current_round_key_word_1);

    wire [1:0] key_step_idx = (cycle_cnt < 4'd4) ? cycle_cnt[1:0] : (cycle_cnt - 4'd4);

    aes_key_expansion_sca #(
        .MODE(Nk * 32)
    ) key_expand_inst (
        .clk(clk),
        .round_idx(round_cnt),
        .step_idx(key_step_idx),
        .full_key_0(key_reg_0),
        .full_key_1(key_reg_1),
        .sbox_in_0(key_sbox_in_0),
        .sbox_in_1(key_sbox_in_1),
        .sbox_out_0(actual_key_sbox_out_0),
        .sbox_out_1(actual_key_sbox_out_1),
        .new_word_0(expanded_key_word_0),
        .new_word_1(expanded_key_word_1)
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
            state_reg_0 <= 128'd0;
            state_reg_1 <= 128'd0;
            key_reg_0 <= 0;
            key_reg_1 <= 0;
            next_state_buffer_0 <= 96'd0;
            next_state_buffer_1 <= 96'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (valid_in) begin
                        `ifndef AES_256
                        `ifndef AES_192
                        state_reg_0 <= {state_reg_0[95:0], data_in ^ data_mask ^ initial_add_rk_word_0};
                        state_reg_1 <= {state_reg_1[95:0], data_mask ^ initial_add_rk_word_1};
                        `endif
                        `endif
                        key_reg_0 <= {key_reg_0[(Nk*32)-33 : 0], masked_key_in_0};
                        key_reg_1 <= {key_reg_1[(Nk*32)-33 : 0], masked_key_in_1};
                    end
                end

                S_LOAD: begin
                    if (valid_in) begin
                        key_reg_0 <= {key_reg_0[(Nk*32)-33 : 0], masked_key_in_0};
                        key_reg_1 <= {key_reg_1[(Nk*32)-33 : 0], masked_key_in_1};
                        if (cycle_cnt >= Nk - 4) begin
                            state_reg_0 <= {state_reg_0[95:0], data_in ^ data_mask ^ initial_add_rk_word_0};
                            state_reg_1 <= {state_reg_1[95:0], data_mask ^ initial_add_rk_word_1};
                        end
                    end
                end

                S_ROUND: begin
                    if (cycle_cnt >= 4'd4 && cycle_cnt <= 4'd7) begin
                        key_reg_0 <= {key_reg_0[(Nk*32)-33 : 0], expanded_key_word_0};
                        key_reg_1 <= {key_reg_1[(Nk*32)-33 : 0], expanded_key_word_1};
                    end
                    
                    if (cycle_cnt >= 4'd5 && cycle_cnt <= 4'd8) begin
                        case (cycle_cnt)
                            4'd5: begin 
                                next_state_buffer_0[95:64] <= round_data_out_0; 
                                next_state_buffer_1[95:64] <= round_data_out_1; 
                            end
                            4'd6: begin 
                                next_state_buffer_0[63:32] <= round_data_out_0; 
                                next_state_buffer_1[63:32] <= round_data_out_1; 
                            end
                            4'd7: begin 
                                next_state_buffer_0[31:0]  <= round_data_out_0; 
                                next_state_buffer_1[31:0]  <= round_data_out_1; 
                            end
                            4'd8: begin
                                state_reg_0[127:96] <= next_state_buffer_0[95:64];
                                state_reg_0[95:64]  <= next_state_buffer_0[63:32];
                                state_reg_0[63:32]  <= next_state_buffer_0[31:0];
                                state_reg_0[31:0]   <= round_data_out_0;
                                
                                state_reg_1[127:96] <= next_state_buffer_1[95:64];
                                state_reg_1[95:64]  <= next_state_buffer_1[63:32];
                                state_reg_1[63:32]  <= next_state_buffer_1[31:0];
                                state_reg_1[31:0]   <= round_data_out_1;
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
                2'd0: data_out = state_reg_0[127:96] ^ state_reg_1[127:96];
                2'd1: data_out = state_reg_0[95:64]  ^ state_reg_1[95:64];
                2'd2: data_out = state_reg_0[63:32]  ^ state_reg_1[63:32];
                2'd3: data_out = state_reg_0[31:0]   ^ state_reg_1[31:0];
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
    input [MODE-1:0]  full_key_0,
    input [MODE-1:0]  full_key_1,
    output [31:0]     sbox_in_0,
    output [31:0]     sbox_in_1,
    input  [31:0]     sbox_out_0,
    input  [31:0]     sbox_out_1,
    output reg [31:0] new_word_0,
    output reg [31:0] new_word_1
);
    `ifdef AES_256
    localparam Nk = 8;
    `elsif AES_192
    localparam Nk = 6;
    `else
    localparam Nk = 4;
    `endif

    wire [5:0] i = ((round_idx - 4'd1) * 4) + step_idx + Nk;

    wire [31:0] first_word_0 = full_key_0[MODE-1 : MODE-32];
    wire [31:0] last_word_0  = full_key_0[31:0];
    wire [31:0] first_word_1 = full_key_1[MODE-1 : MODE-32];
    wire [31:0] last_word_1  = full_key_1[31:0];
    
    `ifdef AES_192
        wire [31:0] lookahead_w_0 = full_key_0[159:128] ^ full_key_0[191:160] ^ full_key_0[31:0];
        wire [31:0] lookahead_w_1 = full_key_1[159:128] ^ full_key_1[191:160] ^ full_key_1[31:0];
        
        wire [31:0] sbox_word_0 = (round_idx % 3 == 2) ? lookahead_w_0 : last_word_0;
        wire [31:0] sbox_word_1 = (round_idx % 3 == 2) ? lookahead_w_1 : last_word_1;
        
        assign sbox_in_0 = {sbox_word_0[23:0], sbox_word_0[31:24]};
        assign sbox_in_1 = {sbox_word_1[23:0], sbox_word_1[31:24]};
    `else
        wire [31:0] rot_word_0 = {last_word_0[23:0], last_word_0[31:24]};
        wire [31:0] rot_word_1 = {last_word_1[23:0], last_word_1[31:24]};
        
        `ifdef AES_256
            assign sbox_in_0 = (i % 8 == 4) ? last_word_0 : rot_word_0;
            assign sbox_in_1 = (i % 8 == 4) ? last_word_1 : rot_word_1;
        `else
            assign sbox_in_0 = rot_word_0;
            assign sbox_in_1 = rot_word_1;
        `endif
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
        if (i % Nk == 0) begin
            new_word_0 = first_word_0 ^ sbox_out_0 ^ get_rcon(i);
            new_word_1 = first_word_1 ^ sbox_out_1;
        end
        `ifdef AES_256
        else if (i % 8 == 4) begin
            new_word_0 = first_word_0 ^ sbox_out_0;
            new_word_1 = first_word_1 ^ sbox_out_1;
        end
        `endif
        else begin
            new_word_0 = first_word_0 ^ last_word_0;
            new_word_1 = first_word_1 ^ last_word_1;
        end
    end
endmodule

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
        .data_out_0(data_out_0), .data_out_1(data_out_1)
    );
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

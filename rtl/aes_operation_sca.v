module aes_operation_sca #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] key_in,
    input [31:0] data_in,
    input [143:0] random_bits,
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

    reg [127:0] state_reg_A_0, state_reg_A_1;
    reg [127:0] state_reg_B_0, state_reg_B_1;
    
    reg [(MODE)-1:0] key_reg_0, key_reg_1;
    
    reg [127:0] round_key_reg_0, round_key_reg_1;

    wire [31:0] shifted_col_A_0, shifted_col_A_1;
    wire [31:0] shifted_col_B_0, shifted_col_B_1;
    wire [31:0] subbytes_out_0, subbytes_out_1;
    wire [31:0] mixcolumns_out_0, mixcolumns_out_1;
    wire [31:0] round_data_out_0, round_data_out_1;
    wire [31:0] expanded_key_word_0, expanded_key_word_1;

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
                (cycle == 4'd2) ? {in_state[31:24],   in_state[119:112], in_state[79:72],   in_state[39:32]} :
                (cycle == 4'd3) ? {in_state[63:56],   in_state[23:16],   in_state[111:104], in_state[71:64]} :
                                  {in_state[95:88],   in_state[55:48],   in_state[15:8],    in_state[103:96]};
        end
    endfunction

    wire [3:0] shift_cycle = (cycle_cnt >= 4'd5) ? (cycle_cnt - 4'd4) : cycle_cnt;

    assign shifted_col_A_0 = shift_rows(state_reg_A_0, shift_cycle);
    assign shifted_col_A_1 = shift_rows(state_reg_A_1, shift_cycle);
    assign shifted_col_B_0 = shift_rows(state_reg_B_0, shift_cycle);
    assign shifted_col_B_1 = shift_rows(state_reg_B_1, shift_cycle);

    wire [31:0] key_sbox_in_0, key_sbox_in_1;
    wire [31:0] key_sbox_out_0, key_sbox_out_1;
    
    wire [31:0] shared_sbox_in_0 = 
        (cycle_cnt == 4'd0) ? key_sbox_in_0 :
        (cycle_cnt >= 4'd1 && cycle_cnt <= 4'd4) ? shifted_col_A_0 : shifted_col_B_0;
        
    wire [31:0] shared_sbox_in_1 = 
        (cycle_cnt == 4'd0) ? key_sbox_in_1 :
        (cycle_cnt >= 4'd1 && cycle_cnt <= 4'd4) ? shifted_col_A_1 : shifted_col_B_1;

    wire [31:0] shared_sbox_out_0, shared_sbox_out_1;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : sbox_gen
            aes_sbox_sca u_sbox (
                .clk(clk),
		.rst_n(rst_n),
                .data_in_0(shared_sbox_in_0[(i*8) +: 8]),
                .data_in_1(shared_sbox_in_1[(i*8) +: 8]),
                .random_bits(random_bits[(i*36) +: 36]),
                .data_out_0(shared_sbox_out_0[(i*8) +: 8]),
                .data_out_1(shared_sbox_out_1[(i*8) +: 8])
            );
        end
    endgenerate

    assign subbytes_out_0 = shared_sbox_out_0;
    assign subbytes_out_1 = shared_sbox_out_1;

    reg [31:0] sbox_buffer_0, sbox_buffer_1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sbox_buffer_0 <= 32'd0;
            sbox_buffer_1 <= 32'd0;
        end else if (state == S_ROUND && cycle_cnt == 4'd4) begin
            sbox_buffer_0 <= shared_sbox_out_0;
            sbox_buffer_1 <= shared_sbox_out_1;
        end
    end

    wire [31:0] actual_key_sbox_out_0 = (cycle_cnt > 4'd4) ? sbox_buffer_0 : shared_sbox_out_0;
    wire [31:0] actual_key_sbox_out_1 = (cycle_cnt > 4'd4) ? sbox_buffer_1 : shared_sbox_out_1;

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
            sb0 = sb[7:0]; sb1 = sb[15:8]; sb2 = sb[23:16]; sb3 = sb[31:24];
            mc0 = xtime(sb0) ^ xtime(sb1) ^ sb1 ^ sb2 ^ sb3;
            mc1 = sb0 ^ xtime(sb1) ^ xtime(sb2) ^ sb2 ^ sb3;
            mc2 = sb0 ^ sb1 ^ xtime(sb2) ^ xtime(sb3) ^ sb3;
            mc3 = xtime(sb0) ^ sb0 ^ sb1 ^ sb2 ^ xtime(sb3);
            mix_col = {mc3, mc2, mc1, mc0};
        end
    endfunction

    assign mixcolumns_out_0 = mix_col(subbytes_out_0);
    assign mixcolumns_out_1 = mix_col(subbytes_out_1);

    wire is_emerging_A = (cycle_cnt >= 4'd5 && cycle_cnt <= 4'd8);

    wire [31:0] current_round_key_word_0 =
        (state == S_LOAD) ? (
            (cycle_cnt == 4'd4) ? round_key_reg_0[31:0] :
            (cycle_cnt == 4'd5) ? round_key_reg_0[63:32]  :
            (cycle_cnt == 4'd6) ? round_key_reg_0[95:64]  : round_key_reg_0[127:96]
        ) : (is_emerging_A) ? round_key_reg_0[127:96] :
            (cycle_cnt == 4'd0) ? round_key_reg_0[31:0] :
            (cycle_cnt == 4'd1) ? round_key_reg_0[63:32]  :
            (cycle_cnt == 4'd2) ? round_key_reg_0[95:64]  : round_key_reg_0[127:96];

    wire [31:0] current_round_key_word_1 =
        (state == S_LOAD) ? (
            (cycle_cnt == 4'd4) ? round_key_reg_1[31:0] :
            (cycle_cnt == 4'd5) ? round_key_reg_1[63:32]  :
            (cycle_cnt == 4'd6) ? round_key_reg_1[95:64]  : round_key_reg_1[127:96]
        ) : (is_emerging_A) ? round_key_reg_1[127:96] :
            (cycle_cnt == 4'd0) ? round_key_reg_1[31:0] :
            (cycle_cnt == 4'd1) ? round_key_reg_1[63:32]  :
            (cycle_cnt == 4'd2) ? round_key_reg_1[95:64]  : round_key_reg_1[127:96];

    wire bypass_mixcol = is_emerging_A ? (round_cnt == Nr) : ((state == S_OUTPUT) ? 1'b1 : (round_cnt - 4'd1 == Nr));

    assign round_data_out_0 = bypass_mixcol ? (subbytes_out_0 ^ current_round_key_word_0) : (mixcolumns_out_0 ^ current_round_key_word_0);
    assign round_data_out_1 = bypass_mixcol ? (subbytes_out_1 ^ current_round_key_word_1) : (mixcolumns_out_1 ^ current_round_key_word_1);

    wire [1:0] key_step_idx = (cycle_cnt >= 4'd4 && cycle_cnt <= 4'd7) ? (cycle_cnt - 4'd4) : 2'd0;

    aes_key_expansion_sca #(
        .MODE(MODE)
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
            state_reg_A_0 <= 128'd0; state_reg_A_1 <= 128'd0;
            state_reg_B_0 <= 128'd0; state_reg_B_1 <= 128'd0;
            key_reg_0 <= 0; key_reg_1 <= 0;
            round_key_reg_0 <= 128'd0; round_key_reg_1 <= 128'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (valid_in) begin
                        key_reg_0 <= {masked_key_in_0, key_reg_0[(MODE)-1 : 32]};
                        key_reg_1 <= {masked_key_in_1, key_reg_1[(MODE)-1 : 32]};
                        round_key_reg_0 <= {masked_key_in_0, round_key_reg_0[127:32]};
                        round_key_reg_1 <= {masked_key_in_1, round_key_reg_1[127:32]};
                        
                        state_reg_A_0 <= {data_in ^ data_mask ^ masked_key_in_0, state_reg_A_0[127:32]};
                        state_reg_A_1 <= {data_mask ^ masked_key_in_1, state_reg_A_1[127:32]};
                    end
                end

                S_LOAD: begin
                    if (valid_in) begin
                        if (cycle_cnt < Nk) begin
                            key_reg_0 <= {masked_key_in_0, key_reg_0[(MODE)-1 : 32]};
                            key_reg_1 <= {masked_key_in_1, key_reg_1[(MODE)-1 : 32]};
                        end
                        
                        if (cycle_cnt < 4'd4) begin
                            round_key_reg_0 <= {masked_key_in_0, round_key_reg_0[127:32]};
                            round_key_reg_1 <= {masked_key_in_1, round_key_reg_1[127:32]};
                            
                            state_reg_A_0 <= {data_in ^ data_mask ^ masked_key_in_0, state_reg_A_0[127:32]};
                            state_reg_A_1 <= {data_mask ^ masked_key_in_1, state_reg_A_1[127:32]};
                        end
                    end
                end

                S_ROUND: begin
                    if (cycle_cnt >= 4'd4 && cycle_cnt <= 4'd7) begin
                        key_reg_0 <= {expanded_key_word_0, key_reg_0[(MODE)-1 : 32]};
                        key_reg_1 <= {expanded_key_word_1, key_reg_1[(MODE)-1 : 32]};
                        
                        `ifdef AES_256
                            round_key_reg_0 <= {key_reg_0[159:128], round_key_reg_0[127:32]};
                            round_key_reg_1 <= {key_reg_1[159:128], round_key_reg_1[127:32]};
                        `elsif AES_192
                            round_key_reg_0 <= {key_reg_0[159:128], round_key_reg_0[127:32]};
                            round_key_reg_1 <= {key_reg_1[159:128], round_key_reg_1[127:32]};
                        `else
                            round_key_reg_0 <= {expanded_key_word_0, round_key_reg_0[127:32]};
                            round_key_reg_1 <= {expanded_key_word_1, round_key_reg_1[127:32]};
                        `endif
                    end
                    
                    if (cycle_cnt >= 4'd5 && cycle_cnt <= 4'd8) begin
                        state_reg_A_0 <= {round_data_out_0 ^ random_bits[31:0], state_reg_A_0[127:32]};
                        state_reg_A_1 <= {round_data_out_1 ^ random_bits[31:0], state_reg_A_1[127:32]};
                    end
                    
                    if (cycle_cnt >= 4'd0 && cycle_cnt <= 4'd3) begin
                        if (round_cnt > 4'd1) begin
                            state_reg_B_0 <= {round_data_out_0 ^ random_bits[31:0], state_reg_B_0[127:32]};
                            state_reg_B_1 <= {round_data_out_1 ^ random_bits[31:0], state_reg_B_1[127:32]};
                        end else if (valid_in) begin
                            state_reg_B_0 <= {data_in ^ data_mask ^ current_round_key_word_0, state_reg_B_0[127:32]};
                            state_reg_B_1 <= {data_mask ^ current_round_key_word_1, state_reg_B_1[127:32]};
                        end
                    end
                end
                
                S_OUTPUT: begin
                    if (cycle_cnt >= 4'd0 && cycle_cnt <= 4'd3) begin
                        state_reg_B_0 <= {round_data_out_0 ^ random_bits[31:0], state_reg_B_0[127:32]};
                        state_reg_B_1 <= {round_data_out_1 ^ random_bits[31:0], state_reg_B_1[127:32]};
                        
                        state_reg_A_0 <= {32'd0, state_reg_A_0[127:32]};
                        state_reg_A_1 <= {32'd0, state_reg_A_1[127:32]};
                    end
                end
                
                default: begin end
            endcase
        end
    end

    always @(*) begin
        valid_out = 1'b0;
        data_out = 32'd0;
        
        if (state == S_ROUND && round_cnt == Nr && cycle_cnt >= 4'd5 && cycle_cnt <= 4'd8) begin
            valid_out = 1'b1;
            data_out = round_data_out_0 ^ round_data_out_1;
        end
        else if (state == S_OUTPUT && cycle_cnt < 4'd4) begin
            valid_out = 1'b1;
            data_out = round_data_out_0 ^ round_data_out_1;
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

    wire [31:0] first_word_0 = full_key_0[31:0];
    wire [31:0] last_word_0  = full_key_0[MODE-1 : MODE-32];
    wire [31:0] first_word_1 = full_key_1[31:0];
    wire [31:0] last_word_1  = full_key_1[MODE-1 : MODE-32];
    
    `ifdef AES_192
        wire [31:0] lookahead_w_0 = full_key_0[63:32] ^ full_key_0[31:0] ^ full_key_0[191:160];
        wire [31:0] lookahead_w_1 = full_key_1[63:32] ^ full_key_1[31:0] ^ full_key_1[191:160];
        
        wire [31:0] sbox_word_0 = (round_idx % 3 == 2) ? lookahead_w_0 : last_word_0;
        wire [31:0] sbox_word_1 = (round_idx % 3 == 2) ? lookahead_w_1 : last_word_1;
        
        assign sbox_in_0 = {sbox_word_0[7:0], sbox_word_0[31:8]};
        assign sbox_in_1 = {sbox_word_1[7:0], sbox_word_1[31:8]};
    `else
        wire [31:0] rot_word_0 = {last_word_0[7:0], last_word_0[31:8]};
        wire [31:0] rot_word_1 = {last_word_1[7:0], last_word_1[31:8]};
        
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
            6'd1:  get_rcon = 32'h00000001; 6'd2:  get_rcon = 32'h00000002;
            6'd3:  get_rcon = 32'h00000004; 6'd4:  get_rcon = 32'h00000008;
            6'd5:  get_rcon = 32'h00000010; 6'd6:  get_rcon = 32'h00000020;
            6'd7:  get_rcon = 32'h00000040; 6'd8:  get_rcon = 32'h00000080;
            6'd9:  get_rcon = 32'h0000001B; 6'd10: get_rcon = 32'h00000036;
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

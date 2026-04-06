module aes_operation_datapath32 #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [MODE-1:0] key_in,
    input [127:0]  data_in,
    output reg     valid_out,
    output [127:0] data_out
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
    reg [1:0] step_count, next_step_count;
    reg [127:0] state_reg, next_state_reg;
    reg [MODE-1:0] key_reg, next_key_reg;
    reg next_valid_out;
    
    reg [31:0] current_column;
    wire [31:0] round_word_out;
    wire [31:0] expanded_key_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            round_ctr  <= 4'd0;
            step_count <= 2'd0;
            state_reg  <= 128'd0;
            key_reg    <= {MODE{1'b0}};
            valid_out  <= 1'b0;
        end else begin
            state      <= next_state;
            round_ctr  <= next_round_ctr;
            step_count <= next_step_count;
            state_reg  <= next_state_reg;
            key_reg    <= next_key_reg;
            valid_out  <= next_valid_out;
        end
    end

    always @(*) begin
        next_state      = state;
        next_round_ctr  = round_ctr;
        next_step_count = step_count;
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
                    next_step_count = 2'd0;
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
                    
                    if (round_ctr == Nr) begin
                        next_valid_out = 1'b1;
                        next_state     = S_IDLE;
                    end else begin
                        next_round_ctr = round_ctr + 4'd1;
                    end
                end else begin
                    next_step_count = step_count + 2'd1;
                end
            end
            
            default: next_state = S_IDLE;
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
        .round_idx(round_ctr),
        .step_idx(step_count),
        .full_key(key_reg),
        .new_word(expanded_key_word)
    );

    wire [31:0] round_key_word;
    `ifdef AES_256
        assign round_key_word = key_reg[127:96];   // Use Wi-4 (already in reg)
    `elsif AES_192
        assign round_key_word = key_reg[63:32];    // Use Wi-4 (already in reg)
    `else
        assign round_key_word = expanded_key_word; // Use Wi (generated now)
    `endif

    aes_round_opt u_round (
        .col_in(current_column),
        .key_in(round_key_word),
        .is_final_round(round_ctr == Nr),
        .col_out(round_word_out)
    );

    assign data_out = (valid_out) ? state_reg : 128'd0;

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
            aes_sbox_base sb (.data_in(col_in[8*(3-i) +: 8]), .data_out(sbox_out[8*(3-i) +: 8]));
        end
    endgenerate

    aes_mix_columns_opt mix_u (
        .data_in(sbox_out),
        .data_out(mix_out)
    );

    assign col_out = is_final_round ? (sbox_out ^ key_in) : (mix_out ^ key_in);
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
    wire [31:0] sub_word;

    aes_sbox_base ks0 (.data_in(rot_word[31:24]), .data_out(sub_word[31:24]));
    aes_sbox_base ks1 (.data_in(rot_word[23:16]), .data_out(sub_word[23:16]));
    aes_sbox_base ks2 (.data_in(rot_word[15:8]),  .data_out(sub_word[15:8]));
    aes_sbox_base ks3 (.data_in(rot_word[7:0]),   .data_out(sub_word[7:0]));

    `ifdef AES_256
    wire [31:0] sub_only_word;
    aes_sbox_base ks4 (.data_in(last_word[31:24]), .data_out(sub_only_word[31:24]));
    aes_sbox_base ks5 (.data_in(last_word[23:16]), .data_out(sub_only_word[23:16]));
    aes_sbox_base ks6 (.data_in(last_word[15:8]),  .data_out(sub_only_word[15:8]));
    aes_sbox_base ks7 (.data_in(last_word[7:0]),   .data_out(sub_only_word[7:0]));
    `endif

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
            new_word = first_word ^ sub_word ^ get_rcon(i);
        `ifdef AES_256
        else if (i % 8 == 4)
            new_word = first_word ^ sub_only_word;
        `endif
        else
            new_word = first_word ^ last_word;
    end
endmodule

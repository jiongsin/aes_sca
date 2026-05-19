module aes_operation_base #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] key_in,
    input [31:0] data_in,
    output reg       valid_out,
    output reg [31:0] data_out
);

    `ifdef AES_256
        localparam Nr = 14;
        localparam KEY_WORDS = 8;
    `elsif AES_192
        localparam Nr = 12;
        localparam KEY_WORDS = 6;
    `else
        localparam Nr = 10;
        localparam KEY_WORDS = 4;
    `endif

    localparam S_IDLE   = 2'd0;
    localparam S_LOAD   = 2'd1;
    localparam S_ROUND  = 2'd2;
    localparam S_OUTPUT = 2'd3;

    reg [1:0] state, next_state;
    reg [3:0] round_ctr, next_round_ctr;
    reg [3:0] word_ctr, next_word_ctr;
    reg [127:0] state_reg, next_state_reg;
    reg [MODE-1:0] key_reg, next_key_reg;
    reg next_valid_out;
    reg [31:0] next_data_out;

    wire [127:0] round_key;
    wire [MODE-1:0] generated_next_key_reg;
    wire [127:0] round_state_out;

    aes_key_expansion_base #(MODE) u_key_ext (
        .round_ctr(round_ctr == 4'd0 ? 4'd1 : round_ctr),
        .key_reg(key_reg),
        .round_key(round_key),
        .next_key_reg(generated_next_key_reg)
    );

    aes_round_base u_round (
        .state_in(state_reg),
        .key_in(round_key),
        .is_final_round(round_ctr == Nr),
        .state_out(round_state_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            round_ctr  <= 4'd0;
            word_ctr   <= 4'd0;
            state_reg  <= 128'd0;
            key_reg    <= {MODE{1'b0}};
            valid_out  <= 1'b0;
            data_out   <= 32'd0;
        end else begin
            state      <= next_state;
            round_ctr  <= next_round_ctr;
            word_ctr   <= next_word_ctr;
            state_reg  <= next_state_reg;
            key_reg    <= next_key_reg;
            valid_out  <= next_valid_out;
            data_out   <= next_data_out;
        end
    end

    always @(*) begin
        next_state      = state;
        next_round_ctr  = round_ctr;
        next_word_ctr   = word_ctr;
        next_state_reg  = state_reg;
        next_key_reg    = key_reg;
        next_valid_out  = 1'b0;
        next_data_out   = 32'd0;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_state     = S_LOAD;
                    next_word_ctr  = 4'd1;
                    next_state_reg = {state_reg[95:0], data_in};
                    next_key_reg   = {key_reg[MODE-33:0], key_in};
                end
            end

            S_LOAD: begin
                if (valid_in) begin
                    next_word_ctr = word_ctr + 4'd1;
                    
                    if (word_ctr < 4) begin
                        next_state_reg = {state_reg[95:0], data_in};
                    end
                    
                    if (word_ctr < KEY_WORDS) begin
                        next_key_reg = {key_reg[MODE-33:0], key_in};
                    end

                    if (word_ctr == KEY_WORDS - 1) begin
                        next_state = S_ROUND;
                        next_round_ctr = 4'd0;
                    end
                end
            end

            S_ROUND: begin
                if (round_ctr == 4'd0) begin
                    next_state_reg = state_reg ^ key_reg[MODE-1 -: 128];
                    next_round_ctr = 4'd1;
                end else begin
                    next_state_reg = round_state_out;
                    next_key_reg   = generated_next_key_reg;

                    if (round_ctr == Nr) begin
                        next_state = S_OUTPUT;
                        next_word_ctr = 4'd0;
                    end else begin
                        next_round_ctr = round_ctr + 4'd1;
                    end
                end
            end

            S_OUTPUT: begin
                next_valid_out = 1'b1;
                next_data_out  = state_reg[127 -: 32];
                next_state_reg = {state_reg[95:0], 32'd0};
                next_word_ctr  = word_ctr + 4'd1;
                
                if (word_ctr == 4'd3) begin
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end
endmodule

module aes_round_base (
    input  [127:0] state_in,
    input  [127:0] key_in,
    input  is_final_round,
    output [127:0] state_out
);

    wire [127:0] sub_out;
    
    genvar i;
    generate
        for (i=0; i<16; i=i+1) begin : sbox_array
            aes_sbox_base sb (
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
    
    aes_mix_columns_base mix0 (.data_in(shift_out[127:96]), .data_out(mix_out[127:96]));
    aes_mix_columns_base mix1 (.data_in(shift_out[95:64]),  .data_out(mix_out[95:64]));
    aes_mix_columns_base mix2 (.data_in(shift_out[63:32]),  .data_out(mix_out[63:32]));
    aes_mix_columns_base mix3 (.data_in(shift_out[31:0]),   .data_out(mix_out[31:0]));

    assign state_out = is_final_round ? (shift_out ^ key_in) : (mix_out ^ key_in);
endmodule

module aes_mix_columns_base (
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

module aes_key_expansion_base #(
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

    aes_sbox_base ks0 (.data_in(sbox_in_word[31:24]), .data_out(sbox_out_word[31:24]));
    aes_sbox_base ks1 (.data_in(sbox_in_word[23:16]), .data_out(sbox_out_word[23:16]));
    aes_sbox_base ks2 (.data_in(sbox_in_word[15:8]),  .data_out(sbox_out_word[15:8]));
    aes_sbox_base ks3 (.data_in(sbox_in_word[7:0]),   .data_out(sbox_out_word[7:0]));

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

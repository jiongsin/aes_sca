module aes_operation_base #(
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

    localparam S_IDLE   = 2'b00;
    localparam S_LOAD   = 2'b01;
    localparam S_CALC   = 2'b11;
    localparam S_OUTPUT = 2'b10;

    reg [1:0] state, next_state;
    reg [3:0] cycle_cnt, next_cycle_cnt;
    reg [3:0] round_ctr, next_round_ctr;

    reg [127:0] state_reg, next_state_reg;
    reg [MODE-1:0] key_reg, next_key_reg;

    wire [127:0] round_key;
    wire [MODE-1:0] generated_next_key_reg;
    wire [127:0] round_state_out;

    aes_key_expansion_128_base #(MODE) u_key_ext (
        .round_ctr(round_ctr),
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

    always @(*) begin
        next_state     = state;
        next_cycle_cnt = cycle_cnt;
        next_round_ctr = round_ctr;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_state     = S_LOAD;
                    next_cycle_cnt = 4'd1;
                    next_round_ctr = 4'd0;
                end
            end

            S_LOAD: begin
                if (valid_in) begin
                    if (cycle_cnt == Nk - 1) begin
                        next_state     = S_CALC;
                        next_cycle_cnt = 4'd0;
                        next_round_ctr = 4'd1;
                    end else begin
                        next_cycle_cnt = cycle_cnt + 4'd1;
                    end
                end
            end

            S_CALC: begin
                if (round_ctr == Nr) begin
                    next_state     = S_OUTPUT;
                    next_cycle_cnt = 4'd0;
                end else begin
                    next_round_ctr = round_ctr + 4'd1;
                end
            end

            S_OUTPUT: begin
                if (cycle_cnt == 4'd3) begin
                    next_state     = S_IDLE;
                    next_cycle_cnt = 4'd0;
                    next_round_ctr = 4'd0;
                end else begin
                    next_cycle_cnt = cycle_cnt + 4'd1;
                end
            end

            default: begin
                next_state     = S_IDLE;
                next_cycle_cnt = 4'd0;
                next_round_ctr = 4'd0;
            end
        endcase
    end

    always @(*) begin
        next_state_reg = state_reg;
        next_key_reg   = key_reg;

        case (state)
            S_IDLE: begin
                if (valid_in) begin
                    next_key_reg   = {key_in, key_reg[MODE-1:32]};
                    next_state_reg = {data_in ^ key_in, state_reg[127:32]};
                end
            end

            S_LOAD: begin
                if (valid_in) begin
                    if (cycle_cnt < Nk) begin
                        next_key_reg = {key_in, key_reg[MODE-1:32]};
                    end

                    if (cycle_cnt < 4'd4) begin
                        next_state_reg = {data_in ^ key_in, state_reg[127:32]};
                    end
                end
            end

            S_CALC: begin
                next_state_reg = round_state_out;
                next_key_reg   = generated_next_key_reg;
            end

            S_OUTPUT: begin
                next_state_reg = {32'd0, state_reg[127:32]};
            end

            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cycle_cnt <= 4'd0;
            round_ctr <= 4'd0;
            state_reg <= 128'd0;
            key_reg   <= {MODE{1'b0}};
        end else begin
            state     <= next_state;
            cycle_cnt <= next_cycle_cnt;
            round_ctr <= next_round_ctr;
            state_reg <= next_state_reg;
            key_reg   <= next_key_reg;
        end
    end

    always @(*) begin
        valid_out = 1'b0;
        data_out  = 32'd0;

        if (state == S_OUTPUT) begin
            valid_out = 1'b1;
            data_out  = state_reg[31:0];
        end
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
        for (i = 0; i < 16; i = i + 1) begin : sbox_array
            aes_sbox_base sb (
                .data_in(state_in[(i*8) +: 8]),
                .data_out(sub_out[(i*8) +: 8])
            );
        end
    endgenerate

    wire [127:0] shift_out;

    assign shift_out = {
        sub_out[95:88],   sub_out[55:48],   sub_out[15:8],    sub_out[103:96],
        sub_out[63:56],   sub_out[23:16],   sub_out[111:104], sub_out[71:64],
        sub_out[31:24],   sub_out[119:112], sub_out[79:72],   sub_out[39:32],
        sub_out[127:120], sub_out[87:80],   sub_out[47:40],   sub_out[7:0]
    };

    wire [127:0] mix_out;

    aes_mix_columns_base mix0 (.data_in(shift_out[31:0]),   .data_out(mix_out[31:0]));
    aes_mix_columns_base mix1 (.data_in(shift_out[63:32]),  .data_out(mix_out[63:32]));
    aes_mix_columns_base mix2 (.data_in(shift_out[95:64]),  .data_out(mix_out[95:64]));
    aes_mix_columns_base mix3 (.data_in(shift_out[127:96]), .data_out(mix_out[127:96]));

    assign state_out = is_final_round ? (shift_out ^ key_in) : (mix_out ^ key_in);

endmodule


module aes_mix_columns_base (
    input  [31:0] data_in,
    output [31:0] data_out
);

    wire [7:0] s0, s1, s2, s3;
    wire [7:0] mc0, mc1, mc2, mc3;

    assign s0 = data_in[7:0];
    assign s1 = data_in[15:8];
    assign s2 = data_in[23:16];
    assign s3 = data_in[31:24];

    function [7:0] xtime(input [7:0] x);
        begin
            xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
        end
    endfunction

    assign mc0 = xtime(s0) ^ xtime(s1) ^ s1 ^ s2 ^ s3;
    assign mc1 = s0 ^ xtime(s1) ^ xtime(s2) ^ s2 ^ s3;
    assign mc2 = s0 ^ s1 ^ xtime(s2) ^ xtime(s3) ^ s3;
    assign mc3 = xtime(s0) ^ s0 ^ s1 ^ s2 ^ xtime(s3);

    assign data_out = {mc3, mc2, mc1, mc0};

endmodule


module aes_key_expansion_128_base #(
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
    wire [5:0] i1 = ((round_ctr - 4'd1) * 4) + 1 + Nk;
    wire [5:0] i2 = ((round_ctr - 4'd1) * 4) + 2 + Nk;
    wire [5:0] i3 = ((round_ctr - 4'd1) * 4) + 3 + Nk;

    wire [31:0] w0_out, w1_out, w2_out, w3_out;

    aes_single_word_gen_base #(MODE) gen0 (
        .i(i0), .w_first(key_reg[31:0]),   .w_last(key_reg[MODE-1 -: 32]), .w_out(w0_out)
    );
    aes_single_word_gen_base #(MODE) gen1 (
        .i(i1), .w_first(key_reg[63:32]),  .w_last(w0_out),                .w_out(w1_out)
    );
    aes_single_word_gen_base #(MODE) gen2 (
        .i(i2), .w_first(key_reg[95:64]),  .w_last(w1_out),                .w_out(w2_out)
    );
    aes_single_word_gen_base #(MODE) gen3 (
        .i(i3), .w_first(key_reg[127:96]), .w_last(w2_out),                .w_out(w3_out)
    );

    wire [127:0] generated_words = {w3_out, w2_out, w1_out, w0_out};

    `ifdef AES_256
        assign next_key_reg = {generated_words, key_reg[MODE-1:128]};
        assign round_key    = key_reg[MODE-1:MODE-128];
    `elsif AES_192
        assign next_key_reg = {generated_words, key_reg[MODE-1:128]};
        assign round_key    = {w1_out, w0_out, key_reg[MODE-1:128]};
    `else
        assign next_key_reg = generated_words;
        assign round_key    = generated_words;
    `endif

endmodule


module aes_single_word_gen_base #(
    parameter MODE = 128
) (
    input [5:0] i,
    input [31:0] w_first,
    input [31:0] w_last,
    output reg [31:0] w_out
);

    `ifdef AES_256
        localparam Nk = 8;
    `elsif AES_192
        localparam Nk = 6;
    `else
        localparam Nk = 4;
    `endif

    wire [31:0] rot_word = {w_last[7:0], w_last[31:8]};
    wire [31:0] sub_word;

    aes_sbox_base ks0 (.data_in(rot_word[7:0]),   .data_out(sub_word[7:0]));
    aes_sbox_base ks1 (.data_in(rot_word[15:8]),  .data_out(sub_word[15:8]));
    aes_sbox_base ks2 (.data_in(rot_word[23:16]), .data_out(sub_word[23:16]));
    aes_sbox_base ks3 (.data_in(rot_word[31:24]), .data_out(sub_word[31:24]));

    `ifdef AES_256
        wire [31:0] sub_only_word;
        aes_sbox_base ks4 (.data_in(w_last[7:0]),   .data_out(sub_only_word[7:0]));
        aes_sbox_base ks5 (.data_in(w_last[15:8]),  .data_out(sub_only_word[15:8]));
        aes_sbox_base ks6 (.data_in(w_last[23:16]), .data_out(sub_only_word[23:16]));
        aes_sbox_base ks7 (.data_in(w_last[31:24]), .data_out(sub_only_word[31:24]));
    `endif

    function [31:0] get_rcon(input [5:0] word_idx);
        case(word_idx / Nk)
            6'd1:  get_rcon = 32'h00000001;
            6'd2:  get_rcon = 32'h00000002;
            6'd3:  get_rcon = 32'h00000004;
            6'd4:  get_rcon = 32'h00000008;
            6'd5:  get_rcon = 32'h00000010;
            6'd6:  get_rcon = 32'h00000020;
            6'd7:  get_rcon = 32'h00000040;
            6'd8:  get_rcon = 32'h00000080;
            6'd9:  get_rcon = 32'h0000001B;
            6'd10: get_rcon = 32'h00000036;
            default: get_rcon = 32'h00000000;
        endcase
    endfunction

    always @(*) begin
        if (i % Nk == 0) begin
            w_out = w_first ^ sub_word ^ get_rcon(i);
        end
        `ifdef AES_256
        else if (i % 8 == 4) begin
            w_out = w_first ^ sub_only_word;
        end
        `endif
        else begin
            w_out = w_first ^ w_last;
        end
    end

endmodule

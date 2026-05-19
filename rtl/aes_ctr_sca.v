module aes_ctr_sca #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input start,
    input valid_in,
    input [31:0] trng_in,
    input [31:0] key_in,
    input [31:0] nonce_in,
    input [31:0] pt_in,
    input stop,
    output reg valid_out,
    output reg [31:0] ct_out
);

    localparam S_IDLE       = 4'd0;
    localparam S_LOAD_TRNG  = 4'd1;
    localparam S_LOAD_KEY   = 4'd2;
    localparam S_LOAD_NONCE = 4'd3;
    localparam S_AES_FEED   = 4'd4;
    localparam S_LOAD_PT    = 4'd5;
    localparam S_AES_WAIT   = 4'd6;
    localparam S_AES_OUT    = 4'd7;

    reg [3:0] state, next_state;
    reg [3:0] count, next_count;

    wire [143:0] random_bits;
    wire prng_valid;

    `ifdef AES_256
        reg [255:0] key_reg, next_key_reg;
    `elsif AES_192
        reg [191:0] key_reg, next_key_reg;
    `else
        reg [127:0] key_reg, next_key_reg;
    `endif

    reg [127:0] nonce_reg, next_nonce_reg;
    reg [255:0] pt_reg, next_pt_reg;

    reg aes_valid_in;
    reg [31:0] aes_key_in;
    reg [31:0] aes_data_in;
    wire aes_valid_out;
    wire [31:0] aes_data_out;

    assign prng_valid = (state == S_LOAD_TRNG) && valid_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            count <= 4'd0;
        `ifdef AES_256
            key_reg <= 256'd0;
        `elsif AES_192
            key_reg <= 192'd0;
        `else
            key_reg <= 128'd0;
        `endif
            nonce_reg <= 128'd0;
            pt_reg <= 256'd0;
        end else begin
            state <= next_state;
            count <= next_count;
            key_reg <= next_key_reg;
            nonce_reg <= next_nonce_reg;
            pt_reg <= next_pt_reg;
        end
    end

    always @(*) begin
        next_state = state;
        next_count = count;
        next_key_reg = key_reg;
        next_nonce_reg = nonce_reg;
        next_pt_reg = pt_reg;

        case (state)
            S_IDLE: begin
                if (start) begin
                    next_state = S_LOAD_TRNG;
                    next_count = 4'd0;
                end
            end

            S_LOAD_TRNG: begin
                if (valid_in) begin
                    if (count == 4'd4) begin
                        next_state = S_LOAD_KEY;
                        next_count = 4'd0;
                    end else begin
                        next_count = count + 4'd1;
                    end
                end
            end

            S_LOAD_KEY: begin
                if (valid_in) begin
                `ifdef AES_256
                    next_key_reg = {key_in, key_reg[255:32]};
                    if (count == 4'd7) begin
                `elsif AES_192
                    next_key_reg = {key_in, key_reg[191:32]};
                    if (count == 4'd5) begin
                `else
                    next_key_reg = {key_in, key_reg[127:32]};
                    if (count == 4'd3) begin
                `endif
                        next_state = S_LOAD_NONCE;
                        next_count = 4'd0;
                    end else begin
                        next_count = count + 4'd1;
                    end
                end
            end

            S_LOAD_NONCE: begin
                if (valid_in) begin
                    next_nonce_reg = {nonce_in, nonce_reg[127:32]};
                    if (count == 4'd3) begin
                        next_state = S_AES_FEED;
                        next_count = 4'd0;
                    end else begin
                        next_count = count + 4'd1;
                    end
                end
            end

            S_AES_FEED: begin
            `ifdef AES_256
                if (count == 4'd11) begin
            `elsif AES_192
                if (count == 4'd9) begin
            `else
                if (count == 4'd7) begin
            `endif
                    next_state = S_LOAD_PT;
                    next_count = 4'd0;
                end else begin
                    next_count = count + 4'd1;
                end
            end

            S_LOAD_PT: begin
                if (valid_in) begin
                    next_pt_reg = {pt_in, pt_reg[255:32]};
                    if (count == 4'd7) begin
                        next_state = S_AES_WAIT;
                        next_count = 4'd0;
                    end else begin
                        next_count = count + 4'd1;
                    end
                end
            end

            S_AES_WAIT: begin
                if (aes_valid_out) begin
                    next_state = S_AES_OUT;
                    next_count = 4'd1;
                    next_pt_reg = {32'd0, pt_reg[255:32]};
                end
            end

            S_AES_OUT: begin
                if (aes_valid_out) begin
                    next_pt_reg = {32'd0, pt_reg[255:32]};
                    if (count == 4'd7) begin
                        if (stop) begin
                            next_state = S_IDLE;
                        end else begin
                            next_state = S_AES_FEED;
                            next_nonce_reg[127:96] = nonce_reg[127:96] + 32'd2;
                        end
                        next_count = 4'd0;
                    end else begin
                        next_count = count + 4'd1;
                    end
                end
            end
            
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    always @(*) begin
        aes_valid_in = 1'b0;
        aes_key_in = 32'd0;
        aes_data_in = 32'd0;
        valid_out = 1'b0;
        ct_out = 32'd0;

        if (state == S_AES_FEED) begin
            aes_valid_in = 1'b1;
            
        `ifdef AES_256
            case (count)
                4'd0: aes_key_in = key_reg[31:0];
                4'd1: aes_key_in = key_reg[63:32];
                4'd2: aes_key_in = key_reg[95:64];
                4'd3: aes_key_in = key_reg[127:96];
                4'd4: aes_key_in = key_reg[159:128];
                4'd5: aes_key_in = key_reg[191:160];
                4'd6: aes_key_in = key_reg[223:192];
                4'd7: aes_key_in = key_reg[255:224];
                default: aes_key_in = 32'd0;
            endcase

            case (count)
                4'd0, 4'd8:  aes_data_in = nonce_reg[31:0];
                4'd1, 4'd9:  aes_data_in = nonce_reg[63:32];
                4'd2, 4'd10: aes_data_in = nonce_reg[95:64];
                4'd3:        aes_data_in = nonce_reg[127:96];
                4'd11:       aes_data_in = nonce_reg[127:96] + 32'd1;
                default:     aes_data_in = 32'd0;
            endcase
        `elsif AES_192
            case (count)
                4'd0: aes_key_in = key_reg[31:0];
                4'd1: aes_key_in = key_reg[63:32];
                4'd2: aes_key_in = key_reg[95:64];
                4'd3: aes_key_in = key_reg[127:96];
                4'd4: aes_key_in = key_reg[159:128];
                4'd5: aes_key_in = key_reg[191:160];
                default: aes_key_in = 32'd0;
            endcase

            case (count)
                4'd0, 4'd6:  aes_data_in = nonce_reg[31:0];
                4'd1, 4'd7:  aes_data_in = nonce_reg[63:32];
                4'd2, 4'd8:  aes_data_in = nonce_reg[95:64];
                4'd3:        aes_data_in = nonce_reg[127:96];
                4'd9:        aes_data_in = nonce_reg[127:96] + 32'd1;
                default:     aes_data_in = 32'd0;
            endcase
        `else
            case (count)
                4'd0, 4'd4: aes_key_in = key_reg[31:0];
                4'd1, 4'd5: aes_key_in = key_reg[63:32];
                4'd2, 4'd6: aes_key_in = key_reg[95:64];
                4'd3, 4'd7: aes_key_in = key_reg[127:96];
                default: aes_key_in = 32'd0;
            endcase

            case (count)
                4'd0, 4'd4:  aes_data_in = nonce_reg[31:0];
                4'd1, 4'd5:  aes_data_in = nonce_reg[63:32];
                4'd2, 4'd6:  aes_data_in = nonce_reg[95:64];
                4'd3:        aes_data_in = nonce_reg[127:96];
                4'd7:        aes_data_in = nonce_reg[127:96] + 32'd1;
                default:     aes_data_in = 32'd0;
            endcase
        `endif
        end

        if (state == S_AES_WAIT && aes_valid_out) begin
            valid_out = 1'b1;
            ct_out = aes_data_out ^ pt_reg[31:0];
        end
        else if (state == S_AES_OUT && aes_valid_out) begin
            valid_out = 1'b1;
            ct_out = aes_data_out ^ pt_reg[31:0];
        end
    end

    aes_prng_sca u_aes_prng (
        .clk(clk),
        .rst_n(rst_n),
        .trng_in(trng_in),
        .trng_valid(prng_valid),
        .random_out(random_bits)
    );

    aes_operation_sca #(
        .MODE(MODE)
    ) u_aes_operation (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(aes_valid_in),
        .key_in(aes_key_in),
        .data_in(aes_data_in),
        .random_bits(random_bits),
        .valid_out(aes_valid_out),
        .data_out(aes_data_out)
    );

endmodule


module aes_prng_sca (
    input clk,
    input rst_n,
    input [31:0] trng_in,
    input trng_valid,
    output [143:0] random_out
);

    reg [31:0] b1, b2, b3, b4, b5;
    wire [31:0] next_b1, next_b2, next_b3, next_b4, next_b5;

    // Xorshift32 math function
    function [31:0] xs32;
        input [31:0] in_val;
        reg [31:0] temp1, temp2;
        begin
            temp1 = in_val ^ (in_val << 13);
            temp2 = temp1 ^ (temp1 >> 17);
            xs32  = temp2 ^ (temp2 << 5);
        end
    endfunction

    // Connect blocks and inject TRNG when valid
    assign next_b1 = trng_valid ? (xs32(b5) ^ trng_in) : xs32(b5);
    assign next_b2 = xs32(b1);
    assign next_b3 = xs32(b2);
    assign next_b4 = xs32(b3);
    assign next_b5 = xs32(b4);

    // Update memory every clock cycle
    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            // Values must not be zero
            b1 <= 32'd1;
            b2 <= 32'd2;
            b3 <= 32'd3;
            b4 <= 32'd4;
            b5 <= 32'd5;
        end else begin
            b1 <= next_b1;
            b2 <= next_b2;
            b3 <= next_b3;
            b4 <= next_b4;
            b5 <= next_b5;
        end
    end

    // Take exactly 144 bits for the AES mask
    assign random_out = {b5[15:0], b4, b3, b2, b1};
endmodule

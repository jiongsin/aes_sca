module aes_ctr_base #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input start,
    input valid_in,
    input [31:0] key_in,
    input [31:0] nonce_in,
    input [31:0] pt_in,
    input stop,
    output reg valid_out,
    output reg [31:0] ct_out
);

    localparam S_IDLE       = 3'd0;
    localparam S_LOAD_KEY   = 3'd1;
    localparam S_LOAD_NONCE = 3'd2;
    localparam S_AES_FEED   = 3'd3;
    localparam S_LOAD_PT    = 3'd4;
    localparam S_AES_WAIT   = 3'd5;
    localparam S_AES_OUT    = 3'd6;

    reg [2:0] state, next_state;
    reg [3:0] count, next_count;

    `ifdef AES_256
        reg [255:0] key_reg, next_key_reg;
    `elsif AES_192
        reg [191:0] key_reg, next_key_reg;
    `else
        reg [127:0] key_reg, next_key_reg;
    `endif

    reg [127:0] nonce_reg, next_nonce_reg;
    reg [127:0] pt_reg, next_pt_reg;

    reg aes_valid_in;
    reg [31:0] aes_key_in;
    reg [31:0] aes_data_in;
    wire aes_valid_out;
    wire [31:0] aes_data_out;

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
            pt_reg <= 128'd0;
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
                    next_state = S_LOAD_KEY;
                    next_count = 4'd0;
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
                if (count == 4'd7) begin // 8 cycles for AES-256 key loading
            `elsif AES_192
                if (count == 4'd5) begin // 6 cycles for AES-192 key loading
            `else
                if (count == 4'd3) begin // 4 cycles for AES-128 key loading
            `endif
                    next_state = S_LOAD_PT;
                    next_count = 4'd0;
                end else begin
                    next_count = count + 4'd1;
                end
            end

            S_LOAD_PT: begin
                if (valid_in) begin
                    next_pt_reg = {pt_in, pt_reg[127:32]};
                    if (count == 4'd3) begin
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
                    next_pt_reg = {32'd0, pt_reg[127:32]};
                end
            end

            S_AES_OUT: begin
                if (aes_valid_out) begin
                    next_pt_reg = {32'd0, pt_reg[127:32]};
                    if (count == 4'd3) begin
                        if (stop) begin
                            next_state = S_IDLE;
                        end else begin
                            next_state = S_AES_FEED;
                            next_nonce_reg[31:0] = nonce_reg[31:0] + 32'd1; 
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
                4'd0: aes_data_in = nonce_reg[31:0];
                4'd1: aes_data_in = nonce_reg[63:32];
                4'd2: aes_data_in = nonce_reg[95:64];
                4'd3: aes_data_in = nonce_reg[127:96];
                default: aes_data_in = 32'd0;
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
                4'd0: aes_data_in = nonce_reg[31:0];
                4'd1: aes_data_in = nonce_reg[63:32];
                4'd2: aes_data_in = nonce_reg[95:64];
                4'd3: aes_data_in = nonce_reg[127:96];
                default: aes_data_in = 32'd0;
            endcase
        `else
            case (count)
                4'd0: aes_key_in = key_reg[31:0];
                4'd1: aes_key_in = key_reg[63:32];
                4'd2: aes_key_in = key_reg[95:64];
                4'd3: aes_key_in = key_reg[127:96];
                default: aes_key_in = 32'd0;
            endcase

            case (count)
                4'd0: aes_data_in = nonce_reg[31:0];
                4'd1: aes_data_in = nonce_reg[63:32];
                4'd2: aes_data_in = nonce_reg[95:64];
                4'd3: aes_data_in = nonce_reg[127:96];
                default: aes_data_in = 32'd0;
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

    aes_operation_base #(
        .MODE(MODE)
    ) u_aes_operation (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(aes_valid_in),
        .key_in(aes_key_in),
        .data_in(aes_data_in),
        .valid_out(aes_valid_out),
        .data_out(aes_data_out)
    );

endmodule

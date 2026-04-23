module aes_gcm_base #(
    parameter MODE = 128
) (
    input clk,
    input rst_n,
    input start,
    input [MODE-1:0] key_in,
    input [95:0] iv_in,
    input [127:0] data_in,
    input data_valid,
    output reg [127:0] data_out,
    output reg data_out_valid,
    output reg [127:0] tag_out,
    output reg tag_out_valid
);

    localparam S_IDLE      = 3'd0;
    localparam S_WAIT_H    = 3'd1;
    localparam S_WAIT_J0   = 3'd2;
    localparam S_PROCESS   = 3'd3;
    localparam S_WAIT_DATA = 3'd4;
    localparam S_FINISH    = 3'd5;

    reg [2:0] state, next_state;
    
    reg aes_valid_in;
    reg [127:0] aes_data_in;
    wire aes_valid_out;
    wire [127:0] aes_data_out;

    reg [127:0] hash_key_h, next_hash_key_h;
    reg [127:0] j0_enc, next_j0_enc;
    reg [127:0] counter, next_counter;
    reg [127:0] ghash_state, next_ghash_state;
    reg [63:0]  len_c, next_len_c;

    wire [127:0] ghash_mult_out;
    wire [127:0] mult_a;
    
    aes_operation_base #(MODE) u_aes_core (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(aes_valid_in),
        .key_in(key_in),
        .data_in(aes_data_in),
        .valid_out(aes_valid_out),
        .data_out(aes_data_out)
    );

    assign mult_a = ((state == S_PROCESS) && !start) ? (ghash_state ^ {64'd0, len_c}) : (ghash_state ^ (data_out_valid ? data_out : 128'd0));

    gf_128_multiplier u_gf_mult (
        .a(mult_a), 
        .b(hash_key_h),
        .c(ghash_mult_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            hash_key_h  <= 128'd0;
            j0_enc      <= 128'd0;
            counter     <= 128'd0;
            ghash_state <= 128'd0;
            len_c       <= 64'd0;
        end else begin
            state       <= next_state;
            hash_key_h  <= next_hash_key_h;
            j0_enc      <= next_j0_enc;
            counter     <= next_counter;
            ghash_state <= next_ghash_state;
            len_c       <= next_len_c;
        end
    end

    always @(*) begin
        next_state       = state;
        next_hash_key_h  = hash_key_h;
        next_j0_enc      = j0_enc;
        next_counter     = counter;
        next_ghash_state = ghash_state;
        next_len_c       = len_c;
        
        aes_valid_in     = 1'b0;
        aes_data_in      = 128'd0;
        
        data_out         = 128'd0;
        data_out_valid   = 1'b0;
        tag_out          = 128'd0;
        tag_out_valid    = 1'b0;

        case (state)
            S_IDLE: begin
                next_ghash_state = 128'd0;
                next_len_c       = 64'd0;
                if (start) begin
                    aes_valid_in = 1'b1;
                    aes_data_in  = 128'd0; 
                    next_state   = S_WAIT_H;
                end
            end

            S_WAIT_H: begin
                if (aes_valid_out) begin
                    next_hash_key_h = aes_data_out;
                    aes_valid_in    = 1'b1;
                    next_counter    = {iv_in, 32'd1}; 
                    aes_data_in     = {iv_in, 32'd1};
                    next_state      = S_WAIT_J0;
                end
            end

            S_WAIT_J0: begin
                if (aes_valid_out) begin
                    next_j0_enc  = aes_data_out;
                    next_counter = counter + 128'd1;
                    next_state   = S_PROCESS;
                end
            end

            S_PROCESS: begin
                if (data_valid) begin
                    aes_valid_in = 1'b1;
                    aes_data_in  = counter;
                    next_state   = S_WAIT_DATA;
                end else if (!start) begin
                    next_ghash_state = ghash_mult_out;
                    next_state       = S_FINISH;
                end
            end

            S_WAIT_DATA: begin
                if (aes_valid_out) begin
                    data_out         = data_in ^ aes_data_out;
                    data_out_valid   = 1'b1;
                    next_ghash_state = ghash_mult_out;
                    next_counter     = counter + 128'd1;
                    next_len_c       = len_c + 64'd128;
                    next_state       = S_PROCESS;
                end
            end
            
            S_FINISH: begin
                tag_out       = ghash_state ^ j0_enc;
                tag_out_valid = 1'b1;
                next_state    = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end
endmodule

module gf_128_multiplier (
    input  [127:0] a,
    input  [127:0] b,
    output [127:0] c
);
    wire [127:0] v [0:128];
    wire [127:0] z [0:128];
    
    assign v[0] = b;
    assign z[0] = 128'd0;
    
    genvar i;
    generate
        for (i = 0; i < 128; i = i + 1) begin : gf_loop
            assign z[i+1] = a[127-i] ? (z[i] ^ v[i]) : z[i];
            assign v[i+1] = v[i][0] ? ({1'b0, v[i][127:1]} ^ 128'hE1000000000000000000000000000000) : {1'b0, v[i][127:1]};
        end
    endgenerate
    
    assign c = z[128];
endmodule

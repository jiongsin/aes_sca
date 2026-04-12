module aes_operation_datapath32 #(
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
    `elsif AES_192
        localparam Nr = 12;
    `else
        localparam Nr = 10;
    `endif

    localparam LOAD_CYCLES = MODE / 32;

    localparam S_LOAD = 1'b0;
    localparam S_CALC = 1'b1;

    reg state, next_state;
    reg [3:0] main_ctr, next_main_ctr;
    reg [1:0] step_count, next_step_count;
    reg [127:0] state_reg, next_state_reg;
    reg [MODE-1:0] key_reg, next_key_reg;
    
    wire [MODE-1:0] full_new_key  = {key_reg[MODE-33:0], key_in};
    wire [127:0]    full_new_data = {state_reg[95:0], data_in};

    reg [31:0] current_column;
    wire [31:0] round_word_out;
    wire [31:0] expanded_key_word;
    wire [31:0] round_key_word;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_LOAD;
            main_ctr      <= 4'd0;
            step_count    <= 2'd0;
            state_reg     <= 128'd0;
            key_reg       <= {MODE{1'b0}};
            valid_out     <= 1'b0;
            data_out      <= 32'd0;
        end else begin
            state         <= next_state;
            main_ctr      <= next_main_ctr;
            step_count    <= next_step_count;
            state_reg     <= next_state_reg;
            key_reg       <= next_key_reg;
            
            if (state == S_CALC && main_ctr == Nr) begin
                valid_out     <= 1'b1;
                data_out      <= round_word_out;
            end else begin
                valid_out     <= 1'b0;
                data_out      <= 32'd0;
            end
        end
    end

    always @(*) begin
        next_state      = state;
        next_main_ctr   = main_ctr;
        next_step_count = step_count;
        next_state_reg  = state_reg;
        next_key_reg    = key_reg;

        case (state)
            S_LOAD: begin
                if (valid_in) begin
                    next_key_reg   = full_new_key;
                    next_state_reg = full_new_data;

                    if (main_ctr == LOAD_CYCLES - 1) begin
                        next_state      = S_CALC;
                        next_main_ctr   = 4'd1;
                        next_step_count = 2'd0;
                        
                        next_state_reg  = full_new_data ^ full_new_key[MODE-1 -: 128];
                    end else begin
                        next_main_ctr = main_ctr + 4'd1;
                    end
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
                    if (main_ctr == Nr) begin
                        next_state    = S_LOAD;
                        next_main_ctr = 4'd0;
                    end else begin
                        next_main_ctr = main_ctr + 4'd1;
                    end
                end else begin
                    next_step_count = step_count + 2'd1;
                end
            end
            
            default: next_state = S_LOAD;
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

    aes_key_expansion_datapath32 #(MODE) u_key_ext (
        .round_idx(main_ctr),
        .step_idx(step_count),
        .full_key(key_reg),
        .new_word(expanded_key_word)
    );

    `ifdef AES_256
        assign round_key_word = key_reg[127:96];
    `elsif AES_192
        assign round_key_word = key_reg[63:32];
    `else
        assign round_key_word = expanded_key_word;
    `endif

    aes_round_datapath32 u_round (
        .col_in(current_column),
        .key_in(round_key_word),
        .is_final_round(main_ctr == Nr),
        .col_out(round_word_out)
    );
endmodule

module aes_round_datapath32 (
    input  [31:0] col_in,
    input  [31:0] key_in,
    input  is_final_round,
    output [31:0] col_out
);
    wire [31:0] sbox_out, mix_out;

    genvar i;
    generate
        for (i=0; i<4; i=i+1) begin : sbox_array
            aes_sbox_datapath32 sb (.data_in(col_in[8*(3-i) +: 8]), .data_out(sbox_out[8*(3-i) +: 8]));
        end
    endgenerate

    aes_mix_columns_datapath32 mix_u (
        .data_in(sbox_out),
        .data_out(mix_out)
    );

    assign col_out = is_final_round ? (sbox_out ^ key_in) : (mix_out ^ key_in);
endmodule

module aes_mix_columns_datapath32 (
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

module aes_key_expansion_datapath32 #(
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

    aes_sbox_datapath32 ks0 (.data_in(sbox_input[31:24]), .data_out(sbox_output[31:24]));
    aes_sbox_datapath32 ks1 (.data_in(sbox_input[23:16]), .data_out(sbox_output[23:16]));
    aes_sbox_datapath32 ks2 (.data_in(sbox_input[15:8]),  .data_out(sbox_output[15:8]));
    aes_sbox_datapath32 ks3 (.data_in(sbox_input[7:0]),   .data_out(sbox_output[7:0]));

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
            new_word = first_word ^ sbox_output ^ get_rcon(i);
        `ifdef AES_256
        else if (i % 8 == 4)
            new_word = first_word ^ sbox_output;
        `endif
        else
            new_word = first_word ^ last_word;
    end
endmodule

module aes_sbox_datapath32 (
    input [7:0] data_in,
    output reg [7:0] data_out
);
    always @(*) begin
        case (data_in)
            8'h00: data_out = 8'h63; 8'h01: data_out = 8'h7c; 8'h02: data_out = 8'h77; 8'h03: data_out = 8'h7b;
            8'h04: data_out = 8'hf2; 8'h05: data_out = 8'h6b; 8'h06: data_out = 8'h6f; 8'h07: data_out = 8'hc5;
            8'h08: data_out = 8'h30; 8'h09: data_out = 8'h01; 8'h0a: data_out = 8'h67; 8'h0b: data_out = 8'h2b;
            8'h0c: data_out = 8'hfe; 8'h0d: data_out = 8'hd7; 8'h0e: data_out = 8'hab; 8'h0f: data_out = 8'h76;
            8'h10: data_out = 8'hca; 8'h11: data_out = 8'h82; 8'h12: data_out = 8'hc9; 8'h13: data_out = 8'h7d;
            8'h14: data_out = 8'hfa; 8'h15: data_out = 8'h59; 8'h16: data_out = 8'h47; 8'h17: data_out = 8'hf0;
            8'h18: data_out = 8'had; 8'h19: data_out = 8'hd4; 8'h1a: data_out = 8'ha2; 8'h1b: data_out = 8'haf;
            8'h1c: data_out = 8'h9c; 8'h1d: data_out = 8'ha4; 8'h1e: data_out = 8'h72; 8'h1f: data_out = 8'hc0;
            8'h20: data_out = 8'hb7; 8'h21: data_out = 8'hfd; 8'h22: data_out = 8'h93; 8'h23: data_out = 8'h26;
            8'h24: data_out = 8'h36; 8'h25: data_out = 8'h3f; 8'h26: data_out = 8'hf7; 8'h27: data_out = 8'hcc;
            8'h28: data_out = 8'h34; 8'h29: data_out = 8'ha5; 8'h2a: data_out = 8'he5; 8'h2b: data_out = 8'hf1;
            8'h2c: data_out = 8'h71; 8'h2d: data_out = 8'hd8; 8'h2e: data_out = 8'h31; 8'h2f: data_out = 8'h15;
            8'h30: data_out = 8'h04; 8'h31: data_out = 8'hc7; 8'h32: data_out = 8'h23; 8'h33: data_out = 8'hc3;
            8'h34: data_out = 8'h18; 8'h35: data_out = 8'h96; 8'h36: data_out = 8'h05; 8'h37: data_out = 8'h9a;
            8'h38: data_out = 8'h07; 8'h39: data_out = 8'h12; 8'h3a: data_out = 8'h80; 8'h3b: data_out = 8'he2;
            8'h3c: data_out = 8'heb; 8'h3d: data_out = 8'h27; 8'h3e: data_out = 8'hb2; 8'h3f: data_out = 8'h75;
            8'h40: data_out = 8'h09; 8'h41: data_out = 8'h83; 8'h42: data_out = 8'h2c; 8'h43: data_out = 8'h1a;
            8'h44: data_out = 8'h1b; 8'h45: data_out = 8'h6e; 8'h46: data_out = 8'h5a; 8'h47: data_out = 8'ha0;
            8'h48: data_out = 8'h52; 8'h49: data_out = 8'h3b; 8'h4a: data_out = 8'hd6; 8'h4b: data_out = 8'hb3;
            8'h4c: data_out = 8'h29; 8'h4d: data_out = 8'he3; 8'h4e: data_out = 8'h2f; 8'h4f: data_out = 8'h84;
            8'h50: data_out = 8'h53; 8'h51: data_out = 8'hd1; 8'h52: data_out = 8'h00; 8'h53: data_out = 8'hed;
            8'h54: data_out = 8'h20; 8'h55: data_out = 8'hfc; 8'h56: data_out = 8'hb1; 8'h57: data_out = 8'h5b;
            8'h58: data_out = 8'h6a; 8'h59: data_out = 8'hcb; 8'h5a: data_out = 8'hbe; 8'h5b: data_out = 8'h39;
            8'h5c: data_out = 8'h4a; 8'h5d: data_out = 8'h4c; 8'h5e: data_out = 8'h58; 8'h5f: data_out = 8'hcf;
            8'h60: data_out = 8'hd0; 8'h61: data_out = 8'hef; 8'h62: data_out = 8'haa; 8'h63: data_out = 8'hfb;
            8'h64: data_out = 8'h43; 8'h65: data_out = 8'h4d; 8'h66: data_out = 8'h33; 8'h67: data_out = 8'h85;
            8'h68: data_out = 8'h45; 8'h69: data_out = 8'hf9; 8'h6a: data_out = 8'h02; 8'h6b: data_out = 8'h7f;
            8'h6c: data_out = 8'h50; 8'h6d: data_out = 8'h3c; 8'h6e: data_out = 8'h9f; 8'h6f: data_out = 8'ha8;
            8'h70: data_out = 8'h51; 8'h71: data_out = 8'ha3; 8'h72: data_out = 8'h40; 8'h73: data_out = 8'h8f;
            8'h74: data_out = 8'h92; 8'h75: data_out = 8'h9d; 8'h76: data_out = 8'h38; 8'h77: data_out = 8'hf5;
            8'h78: data_out = 8'hbc; 8'h79: data_out = 8'hb6; 8'h7a: data_out = 8'hda; 8'h7b: data_out = 8'h21;
            8'h7c: data_out = 8'h10; 8'h7d: data_out = 8'hff; 8'h7e: data_out = 8'hf3; 8'h7f: data_out = 8'hd2;
            8'h80: data_out = 8'hcd; 8'h81: data_out = 8'h0c; 8'h82: data_out = 8'h13; 8'h83: data_out = 8'hec;
            8'h84: data_out = 8'h5f; 8'h85: data_out = 8'h97; 8'h86: data_out = 8'h44; 8'h87: data_out = 8'h17;
            8'h88: data_out = 8'hc4; 8'h89: data_out = 8'ha7; 8'h8a: data_out = 8'h7e; 8'h8b: data_out = 8'h3d;
            8'h8c: data_out = 8'h64; 8'h8d: data_out = 8'h5d; 8'h8e: data_out = 8'h19; 8'h8f: data_out = 8'h73;
            8'h90: data_out = 8'h60; 8'h91: data_out = 8'h81; 8'h92: data_out = 8'h4f; 8'h93: data_out = 8'hdc;
            8'h94: data_out = 8'h22; 8'h95: data_out = 8'h2a; 8'h96: data_out = 8'h90; 8'h97: data_out = 8'h88;
            8'h98: data_out = 8'h46; 8'h99: data_out = 8'hee; 8'h9a: data_out = 8'hb8; 8'h9b: data_out = 8'h14;
            8'h9c: data_out = 8'hde; 8'h9d: data_out = 8'h5e; 8'h9e: data_out = 8'h0b; 8'h9f: data_out = 8'hdb;
            8'ha0: data_out = 8'he0; 8'ha1: data_out = 8'h32; 8'ha2: data_out = 8'h3a; 8'ha3: data_out = 8'h0a;
            8'ha4: data_out = 8'h49; 8'ha5: data_out = 8'h06; 8'ha6: data_out = 8'h24; 8'ha7: data_out = 8'h5c;
            8'ha8: data_out = 8'hc2; 8'ha9: data_out = 8'hd3; 8'haa: data_out = 8'hac; 8'hab: data_out = 8'h62;
            8'hac: data_out = 8'h91; 8'had: data_out = 8'h95; 8'hae: data_out = 8'he4; 8'haf: data_out = 8'h79;
            8'hb0: data_out = 8'he7; 8'hb1: data_out = 8'hc8; 8'hb2: data_out = 8'h37; 8'hb3: data_out = 8'h6d;
            8'hb4: data_out = 8'h8d; 8'hb5: data_out = 8'hd5; 8'hb6: data_out = 8'h4e; 8'hb7: data_out = 8'ha9;
            8'hb8: data_out = 8'h6c; 8'hb9: data_out = 8'h56; 8'hba: data_out = 8'hf4; 8'hbb: data_out = 8'hea;
            8'hbc: data_out = 8'h65; 8'hbd: data_out = 8'h7a; 8'hbe: data_out = 8'hae; 8'hbf: data_out = 8'h08;
            8'hc0: data_out = 8'hba; 8'hc1: data_out = 8'h78; 8'hc2: data_out = 8'h25; 8'hc3: data_out = 8'h2e;
            8'hc4: data_out = 8'h1c; 8'hc5: data_out = 8'ha6; 8'hc6: data_out = 8'hb4; 8'hc7: data_out = 8'hc6;
            8'hc8: data_out = 8'he8; 8'hc9: data_out = 8'hdd; 8'hca: data_out = 8'h74; 8'hcb: data_out = 8'h1f;
            8'hcc: data_out = 8'h4b; 8'hcd: data_out = 8'hbd; 8'hce: data_out = 8'h8b; 8'hcf: data_out = 8'h8a;
            8'hd0: data_out = 8'h70; 8'hd1: data_out = 8'h3e; 8'hd2: data_out = 8'hb5; 8'hd3: data_out = 8'h66;
            8'hd4: data_out = 8'h48; 8'hd5: data_out = 8'h03; 8'hd6: data_out = 8'hf6; 8'hd7: data_out = 8'h0e;
            8'hd8: data_out = 8'h61; 8'hd9: data_out = 8'h35; 8'hda: data_out = 8'h57; 8'hdb: data_out = 8'hb9;
            8'hdc: data_out = 8'h86; 8'hdd: data_out = 8'hc1; 8'hde: data_out = 8'h1d; 8'hdf: data_out = 8'h9e;
            8'he0: data_out = 8'he1; 8'he1: data_out = 8'hf8; 8'he2: data_out = 8'h98; 8'he3: data_out = 8'h11;
            8'he4: data_out = 8'h69; 8'he5: data_out = 8'hd9; 8'he6: data_out = 8'h8e; 8'he7: data_out = 8'h94;
            8'he8: data_out = 8'h9b; 8'he9: data_out = 8'h1e; 8'hea: data_out = 8'h87; 8'heb: data_out = 8'he9;
            8'hec: data_out = 8'hce; 8'hed: data_out = 8'h55; 8'hee: data_out = 8'h28; 8'hef: data_out = 8'hdf;
            8'hf0: data_out = 8'h8c; 8'hf1: data_out = 8'ha1; 8'hf2: data_out = 8'h89; 8'hf3: data_out = 8'h0d;
            8'hf4: data_out = 8'hbf; 8'hf5: data_out = 8'he6; 8'hf6: data_out = 8'h42; 8'hf7: data_out = 8'h68;
            8'hf8: data_out = 8'h41; 8'hf9: data_out = 8'h99; 8'hfa: data_out = 8'h2d; 8'hfb: data_out = 8'h0f;
            8'hfc: data_out = 8'hb0; 8'hfd: data_out = 8'h54; 8'hfe: data_out = 8'hbb; 8'hff: data_out = 8'h16;
            default: data_out = 8'h00;
        endcase
    end
endmodule

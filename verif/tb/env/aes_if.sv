interface aes_sbox_if(input logic clk);
    logic [7:0] data_in;
    logic [7:0] data_out;
    
    clocking drv_cb @(posedge clk);
        output data_in;
    endclocking
    
    clocking mon_cb @(posedge clk);
        input data_in;
        input data_out;
    endclocking
endinterface

interface aes_operation_if #(parameter MODE = 128) (input logic clk);
    logic rst_n;
    logic valid_in;
	
    `ifdef AES_BASE
        `define IS_128BIT
    `elsif AES_CFA
        `define IS_128BIT
	`endif

    `ifdef IS_128BIT
        logic [MODE-1:0] key_in;
        logic [127:0] data_in;
        logic [127:0] data_out;
    `else
        logic [31:0] key_in;
        logic [31:0] data_in;
        logic [31:0] data_out;
    `endif

    logic valid_out;

    // Clocking block for synchronous driving
    clocking drv_cb @(posedge clk);
        default input #3ns output #2ns;
        output valid_in, key_in, data_in;
        input  valid_out, data_out;
    endclocking

    // Clocking block for monitoring
    clocking mon_cb @(posedge clk);
        default input #5ns output #0;
        input valid_in, key_in, data_in;
        input valid_out, data_out;
    endclocking
endinterface

interface aes_gcm_if #(parameter MODE = 128) (input logic clk);
    logic rst_n;
    logic start;
    logic [MODE-1:0] key_in;
    logic [95:0] iv_in;
    logic [127:0] data_in;
    logic data_valid;

    logic [127:0] data_out;
    logic data_out_valid;
    logic [127:0] tag_out;
    logic tag_out_valid;

    clocking drv_cb @(posedge clk);
        default input #0 output #0;
        output start, key_in, iv_in, data_in, data_valid;
        input  data_out, data_out_valid, tag_out, tag_out_valid;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #0 output #0;
        input start, key_in, iv_in, data_in, data_valid;
        input data_out, data_out_valid, tag_out, tag_out_valid;
    endclocking
endinterface


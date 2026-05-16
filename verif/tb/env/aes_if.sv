interface aes_sbox_if(input logic clk);
    `ifdef AES_SCA
        logic [7:0] data_in_0;
        logic [7:0] data_in_1;
        logic [35:0] random_bits;
        logic [7:0] data_out_0;
        logic [7:0] data_out_1;
    `else
        logic [7:0] data_in;
        logic [7:0] data_out;
    `endif
    
    clocking drv_cb @(posedge clk);
        default output #2ns;
        `ifdef AES_SCA
            output data_in_0;
            output data_in_1;
            output random_bits;
        `else
            output data_in;
        `endif
    endclocking
    
    clocking mon_cb @(posedge clk);
        default input #2ns;
        `ifdef AES_SCA
            input data_in_0;
            input data_in_1;
            input random_bits;
            input data_out_0;
            input data_out_1;
        `else
            input data_in;
            input data_out;
        `endif
    endclocking
endinterface


interface aes_operation_if #(parameter MODE = 128) (input logic clk);
    logic rst_n;
    logic valid_in;
    logic [31:0] key_in;
    logic [31:0] data_in;
    logic [31:0] data_out;
    `ifdef AES_SCA
    logic [143:0] random_bits;
    `endif
    logic valid_out;

    clocking drv_cb @(posedge clk);
        default input #3ns output #2ns;
        output valid_in, key_in, data_in `ifdef AES_SCA , random_bits `endif;
        input  valid_out, data_out;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #5ns output #0;
        input valid_in, key_in, data_in `ifdef AES_SCA , random_bits `endif;
        input valid_out, data_out;
    endclocking
endinterface

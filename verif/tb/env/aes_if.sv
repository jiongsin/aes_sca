interface aes_if #(parameter MODE = 128) (input logic clk);
    logic rst_n;
    logic valid_in;
    logic [MODE-1:0] key_in;
    logic [127:0] data_in;
    logic valid_out;
    logic [127:0] data_out;

    // Clocking block for synchronous driving
    clocking drv_cb @(posedge clk);
        default input #0 output #0;
        output valid_in, key_in, data_in;
        input  valid_out, data_out;
    endclocking

    // Clocking block for monitoring
    clocking mon_cb @(posedge clk);
        default input #0 output #0;
        input valid_in, key_in, data_in;
        input valid_out, data_out;
    endclocking
endinterface

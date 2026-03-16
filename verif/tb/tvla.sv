`timescale 1ns / 1ps

module aes_tvla_tb;

    // Parameters
    parameter CLK_PERIOD = 10;
    `ifdef AES_256
        parameter MODE = 256;
    `elsif AES_192
        parameter MODE = 192;
    `else
        parameter MODE = 128;
    `endif

    // DUT Signals
    reg clk;
    reg rst_n;
    reg valid_in;
    reg [MODE-1:0] key;
    reg [127:0] data_in;
    wire valid_out;
    wire [127:0] data_out;

    // Fixed TVLA constants
    const reg [127:0] FIXED_PT  = 128'hDA_39_A3_EE_5E_6B_4B_0D_32_55_BF_EF_95_60_18_90;
    const reg [MODE-1:0] FIXED_KEY = { (MODE/128){128'h01_23_45_67_89_AB_CD_EF_FE_DC_BA_98_76_54_32_10} };

    // TVLA Variables
    integer i;
    integer file_ptr;
    reg is_random;

    // Instantiate DUT
    aes_operation #(MODE) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .key(key),
        .data_in(data_in),
        .valid_out(valid_out),
        .data_out(data_out)
    );

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        // Open file to log trace labels (0 for fixed, 1 for random)
        file_ptr = $fopen("tvla_labels.txt", "w");
        
        // Initialize
        rst_n = 0;
        valid_in = 0;
        key = FIXED_KEY;
        data_in = 0;

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        $display("Starting TVLA Trace Generation (1000 iterations)...");

        for (i = 0; i < 1000; i = i + 1) begin
            // Decide Fixed vs Random
            is_random = $urandom % 2;
            $fdisplay(file_ptr, "%b", is_random);

            @(negedge clk);
            valid_in = 1;
            key = FIXED_KEY; // Key usually stays fixed in standard TVLA

            if (is_random) begin
                data_in = {$urandom, $urandom, $urandom, $urandom};
            end else begin
                data_in = FIXED_PT;
            end

            @(negedge clk);
            valid_in = 0;

            // Wait for operation to complete
            wait(valid_out);
            @(negedge clk); // Hold one cycle after completion
        end

        $fclose(file_ptr);
        $display("TVLA Trace Generation Complete.");
        $finish;
    end

    // Optional: Monitor for debugging
    /*
    always @(posedge valid_out) begin
        $display("Iteration completed. Result: %h", data_out);
    end
    */

endmodule

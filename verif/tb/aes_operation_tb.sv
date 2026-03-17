module aes_operation_tb;
    import aes_pkg::*;
    
	`ifdef AES_256
    parameter MODE = 256;
    `elsif AES_192
    parameter MODE = 192;
    `else
    parameter MODE = 128;
    `endif

    bit clk;
    bit rst_n;

    int test_count;

    always #5ns clk = ~clk;

    aes_if#(MODE) intf(clk);
    assign intf.rst_n = rst_n;
    
	`ifdef GLS_SIM 
	    `ifdef AES_256
        aes_operation_MODE256 dut (
	    `elsif AES_192
        aes_operation_MODE192 dut (
	    `else 
        aes_operation_MODE128 dut (
		`endif
    `else
    aes_operation #(MODE) dut (
    `endif
        .clk        (intf.clk),
        .rst_n      (intf.rst_n),
        .valid_in   (intf.valid_in),
        .key_in     (intf.key_in),
        .data_in    (intf.data_in),
        .valid_out  (intf.valid_out),
        .data_out   (intf.data_out)
    );

    initial begin
        event e_sync;
        mailbox gen2drv = new(1); 
        mailbox mon2scb = new();

        aes_driver#(MODE)    drv = new(intf, gen2drv, e_sync);
        aes_monitor#(MODE)   mon = new(intf, mon2scb, e_sync);
        aes_scoreboard#(MODE) scb = new(mon2scb);

	    if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 1000;
        end

        $display("[%0t] [TOP] Starting AES-%0d Simulation", $time, MODE);
        rst_n = 0;
        intf.valid_in = 0; 
        repeat(5) @(negedge clk);
		rst_n = 1;      
        repeat(5) @(posedge clk); 

        fork
            drv.run();
            mon.run();
            scb.run();
        join_none

        `ifdef TVLA_STATIC
            // Static Test Case
            begin
                aes_transaction#(MODE) tr_static = new();
                tr_static.data_in = 128'h3243f6a8_885a308d_313198a2_e0370734;
                tr_static.key_in  = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
                
                $display("[%0t] [TVLA] Running Static Vector Simulation", $time);
                gen2drv.put(tr_static);
                
                // Wait for the specific output
                wait(scb.transaction_count == 1);
                
                if (intf.data_out == 128'h3925841d_02dc09fb_dc118597_196a0b32)
                    $display("[%0t] [TVLA] SUCCESS: Data matches expected result", $time);
                else
                    $error("[%0t] [TVLA] FAILURE: Data mismatch!", $time);
            end
        `else
            // Random Simulation
            begin
                if (!$value$plusargs("COUNT=%d", test_count)) test_count = 1000;
                $display("[%0t] [TOP] Starting AES-%0d Random Simulation", $time, MODE);
                
                for (int i = 0; i < test_count; i++) begin
                    aes_transaction#(MODE) tr = new(); 
                    if(!tr.randomize()) $fatal("Randomization failed");
                    gen2drv.put(tr); 
                    @(e_sync);
                end
                wait(scb.transaction_count == test_count);
            end
        `endif

        scb.report(); 
        $finish;
    end
    
	initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("./sim/aes_operation.vcd");
            $dumpvars(0, aes_operation_tb.dut);
        end
    end
endmodule

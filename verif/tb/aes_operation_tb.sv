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

    always #5 clk = ~clk;

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
        #25 rst_n = 1;      
        repeat(5) @(posedge clk); 

        fork
            drv.run();
            mon.run();
            scb.run();
        join_none

        // Random testing loop
        for (int i = 0; i < test_count; i++) begin
            aes_transaction#(MODE) tr = new(); 
            if(!tr.randomize()) $fatal("Randomization failed");
            gen2drv.put(tr); 
            @(e_sync);
        end

        wait(scb.transaction_count == test_count);
        scb.report(); 
        $finish;
    end

endmodule

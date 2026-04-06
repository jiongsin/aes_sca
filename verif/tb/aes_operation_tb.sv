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
   
    `ifdef AES_BASE
        `define VER base
    `else
        `define VER opt
    `endif

    `ifdef AES_256
        `define MODE 256
    `elsif AES_192
        `define MODE 192
    `else
        `define MODE 128
    `endif

    `ifdef GLS_SIM
        `define DUT_TARGET aes_operation_```VER``_MODE```MODE
    `else
        `define DUT_TARGET aes_operation_```VER``#(```MODE)
    `endif

    `DUT_TARGET dut (
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

        begin
            if (!$value$plusargs("COUNT=%d", test_count)) test_count = 1000;
            $display("[%0t] [TOP] Starting AES-%0d Random Simulation", $time, MODE);
                
            for (int i = 0; i < test_count; i++) begin
                aes_transaction#(MODE) tr = new(); 
				`ifdef TVLA_STATIC
			        tr.plain_text = 128'h3243f6a8_885a308d_313198a2_e0370734;
                    tr.key        = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
				`else
                    if(!tr.randomize()) $fatal("Randomization failed");
				`endif

                gen2drv.put(tr); 
                @(e_sync);
            end
            wait(scb.transaction_count == test_count);
        end

        scb.report(); 
        $finish;
    end
    
	initial begin
        if ($test$plusargs("DUMP_VCD")) begin
		    `ifdef TVLA_STATIC
                $dumpfile("./sim_static/aes_operation.vcd");
			`else
                $dumpfile("./sim/aes_operation.vcd");
			`endif
            $dumpvars(0, aes_operation_tb.dut);
        end
    end
endmodule

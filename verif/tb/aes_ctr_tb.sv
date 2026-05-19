module aes_ctr_tb;
    import aes_ctr_pkg::*;
    
    `ifdef AES_256
        parameter MODE = 256;
        `define MODE 256
    `elsif AES_192
        parameter MODE = 192;
        `define MODE 192
    `else
        parameter MODE = 128;
        `define MODE 128
    `endif
    
    `ifdef AES_BASE
        `define VER base
    `elsif AES_OPT
        `define VER opt
    `elsif AES_SCA
        `define VER sca
    `endif

    bit clk;
    bit rst_n;
    int test_count;

    always #5ns clk = ~clk;

    aes_ctr_if#(MODE) intf(clk);
    assign intf.rst_n = rst_n;

    `ifdef GLS_SIM
        `define DUT_TARGET aes_ctr_```VER``_MODE```MODE
    `else
        `define DUT_TARGET aes_ctr_```VER``#(```MODE)
    `endif

    `DUT_TARGET dut (
        .clk        (intf.clk),
        .rst_n      (intf.rst_n),
        .start      (intf.start),
        .valid_in   (intf.valid_in),
        .trng_in    (intf.trng_in),
        .key_in     (intf.key_in),
        .nonce_in   (intf.nonce_in),
        .pt_in      (intf.pt_in),
        .stop       (intf.stop),
        .valid_out  (intf.valid_out),
        .ct_out     (intf.ct_out)
    );

    initial begin
        mailbox gen2drv = new(10); 
        mailbox mon2scb = new();

        aes_ctr_driver#(MODE)     drv = new(intf, gen2drv);
        aes_ctr_monitor#(MODE)    mon = new(intf, mon2scb);
        aes_ctr_scoreboard#(MODE) scb = new(mon2scb);

        if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 1000;
        end

        $display("[%0t] [TOP] Starting AES CTR Simulation", $time);

        intf.start = 1'b0;
        intf.valid_in = 1'b0;
        intf.stop = 1'b0;

        rst_n = 0;
        repeat(5) @(negedge clk);
        rst_n = 1;      
        repeat(5) @(posedge clk); 

        fork
            drv.run();
            mon.run();
            scb.run();
        join_none


        begin
            for (int i = 0; i < test_count; i++) begin
                aes_ctr_transaction#(MODE) tr = new(); 
                if(!tr.randomize()) $fatal("Randomization failed");
                gen2drv.put(tr); 
            end
            wait(scb.transaction_count >= test_count * 2);
            repeat(10) @(posedge clk);
        end

        scb.report(); 
        $finish;
    end
    
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("./sim/aes_ctr.vcd");
            $dumpvars(0, aes_ctr_tb.dut);
        end
    end
endmodule

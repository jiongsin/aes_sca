module aes_gcm_tb;
    import aes_pkg::*;
    
    `ifdef AES_256
    parameter MODE = 256;
    `elsif AES_192
    parameter MODE = 192;
    `else
    parameter MODE = 128;
    `endif
    
    `ifdef AES_BASE
        `define VER base
        `define IS_128BIT
    `elsif AES_CFA
        `define VER cfa
        `define IS_128BIT
    `elsif AES_DATAPATH32
        `define VER datapath32
    `elsif AES_OPT
        `define VER opt
    `elsif AES_DOM
        `define VER dom
    `endif

    `ifdef AES_256
        `define MODE 256
    `elsif AES_192
        `define MODE 192
    `else
        `define MODE 128
    `endif

    bit clk;
    bit rst_n;
    int test_count;

    always #5ns clk = ~clk;

    aes_gcm_if#(MODE) intf(clk);
    assign intf.rst_n = rst_n;
 
    `ifdef GLS_SIM
        `define DUT_TARGET aes_gcm_```VER``_MODE```MODE
    `else
        `define DUT_TARGET aes_gcm_```VER``#(```MODE)
    `endif

    `DUT_TARGET dut (
        .clk            (intf.clk),
        .rst_n          (intf.rst_n),
        .start          (intf.start),
        .key_in         (intf.key_in),
        .iv_in          (intf.iv_in),
        .data_in        (intf.data_in),
        .data_valid     (intf.data_valid),
        .data_out       (intf.data_out),
        .data_out_valid (intf.data_out_valid),
        .tag_out        (intf.tag_out),
        .tag_out_valid  (intf.tag_out_valid)
    );

    initial begin
        event e_sync;
        mailbox gen2drv = new(1); 
        mailbox mon2scb = new();

        aes_gcm_driver#(MODE)     drv = new(intf, gen2drv, e_sync);
        aes_gcm_monitor#(MODE)    mon = new(intf, mon2scb, e_sync);
        aes_gcm_scoreboard#(MODE) scb = new(mon2scb);

        if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 1000;
        end

        $display("[%0t] [TOP] Starting AES GCM Simulation", $time);
        
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
                aes_gcm_transaction#(MODE) tr = new(); 
                if(!tr.randomize()) $fatal("Randomization failed");

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
            $dumpfile("aes_gcm.vcd");
            $dumpvars(0, aes_gcm_tb.dut);
        end
    end
endmodule

module aes_sbox_tb;
    import aes_pkg::*;
   
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

    bit clk;
    
    always #5ns clk = ~clk;
    
    aes_sbox_if intf(clk);
    
	`ifdef GLS_SIM
        `define DUTS_TARGET aes_sbox_```VER``
    `else
        `define DUTS_TARGET aes_sbox_```VER``
    `endif

    `DUTS_TARGET dut (
        .data_in (intf.data_in),
        .data_out(intf.data_out)
    );
    
    initial begin
        mailbox gen2drv = new(1);
        mailbox mon2scb = new();
        
        aes_sbox_driver     drv = new(intf, gen2drv);
        aes_sbox_monitor    mon = new(intf, mon2scb);
        aes_sbox_scoreboard scb = new(mon2scb);
        
        $display("[%0t] [TOP] Starting AES SBOX Simulation", $time);
        
        clk = 0;
        
        fork
            drv.run();
            mon.run();
            scb.run();
        join_none
        
        for (int i = 0; i < 256; i++) begin
            aes_sbox_transaction tr = new();
            tr.data_in = i;
            gen2drv.put(tr);
            @(posedge clk);
        end
        
        scb.report();
        $finish;
    end
endmodule

`ifdef AES_SBOX

module aes_sbox_tb;
    import aes_sbox_pkg::*;
    
    bit clk;
    
    always #5ns clk = ~clk;
    
    aes_sbox_if intf(clk);
    
    `ifdef AES_SCA
        aes_sbox_sca dut (
            .clk         (clk),
            .data_in_0   (intf.data_in_0),
            .data_in_1   (intf.data_in_1),
            .random_bits (intf.random_bits),
            .data_out_0  (intf.data_out_0),
            .data_out_1  (intf.data_out_1)
        );
    `else
        aes_sbox_base dut (
            .data_in  (intf.data_in),
            .data_out (intf.data_out)
        );
    `endif
    
    initial begin
        event e_sync;
        mailbox gen2drv = new(1);
        mailbox mon2scb = new();
        
        aes_sbox_driver  drv = new(intf, gen2drv, e_sync);
        aes_sbox_monitor mon = new(intf, mon2scb, e_sync);
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
            
            `ifdef TVLA_STATIC
                tr.data_in = 0;
            `else
                tr.data_in = i;
            `endif

            gen2drv.put(tr);
            @(e_sync);
        end
    end

    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            `ifdef TVLA_STATIC
                $dumpfile("./sim_static/aes_sbox.vcd");
            `elsif TVLA_DYNAMIC
                $dumpfile("./sim_dynamic/aes_sbox.vcd");
            `else
                $dumpfile("./sim/aes_sbox.vcd");
            `endif
            $dumpvars(0, aes_sbox_tb.dut);
        end
    end
endmodule

`endif

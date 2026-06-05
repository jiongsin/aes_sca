`ifdef AES_OPERATION

module aes_operation_tb;
    import aes_operation_pkg::*;
    
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

    aes_operation_if#(MODE) intf(clk);
    assign intf.rst_n = rst_n;

    `ifdef AES_SCA
    logic [143:0] rand_bits_local;

    always @(posedge clk) begin
        if (rst_n) begin
            if (!std::randomize(rand_bits_local)) begin
                $display("Randomization failed");
            end
            intf.drv_cb.random_bits <= rand_bits_local;
        end
    end
    `endif

    `ifdef GLS_SIM
        `define DUT_TARGET aes_operation_```VER``_MODE```MODE
    `else
        `define DUT_TARGET aes_operation_```VER``#(```MODE)
    `endif

    `DUT_TARGET dut (
        .clk         (intf.clk),
        .rst_n       (intf.rst_n),
        .valid_in    (intf.valid_in),
        .key_in      (intf.key_in),
        .data_in     (intf.data_in),
        `ifdef AES_SCA
        .random_bits (intf.random_bits),
        `endif
        .valid_out   (intf.valid_out),
        .data_out    (intf.data_out)
    );

    initial begin
        event e_sync;
        mailbox gen2drv = new(10); 
        mailbox mon2scb = new();

        aes_operation_driver#(MODE)   drv = new(intf, gen2drv, e_sync);
        aes_operation_monitor#(MODE)  mon = new(intf, mon2scb, e_sync);
        aes_operation_scoreboard#(MODE) scb = new(mon2scb);

        if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 1000;
        end

        $display("[%0t] [TOP] Starting AES %0d Simulation", $time, MODE);
        rst_n = 0;
        intf.valid_in = 0;
        intf.key_in    = 32'd0;
        intf.data_in   = 32'd0;
        `ifdef AES_SCA
        intf.random_bits = 144'd0;
        `endif
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
            $display("[%0t] [TOP] Starting AES %0d Random Simulation", $time, MODE);
                
            `ifdef AES_SCA
                for (int i = 0; i < test_count; i++) begin
                    aes_operation_transaction#(MODE) tr_A = new(); 
                    aes_operation_transaction#(MODE) tr_B = new(); 

                    `ifdef TVLA_STATIC
                        tr_A.plain_text = 128'h3243f6a8_885a308d_313198a2_e0370734;
                        tr_A.key        = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
                        tr_B.plain_text = 128'h3243f6a8_885a308d_313198a2_e0370734;
                    `elsif TVLA_DYNAMIC
                        if(!std::randomize(tr_A.plain_text)) $fatal("Randomization failed");
                        tr_A.key        = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
                        if(!std::randomize(tr_B.plain_text)) $fatal("Randomization failed");
                    `else
                        if(!tr_A.randomize()) $fatal("Randomization failed");
                        if(!tr_B.randomize()) $fatal("Randomization failed");
                    `endif
                    
                    tr_B.key = tr_A.key; 
        
                    gen2drv.put(tr_A); 
                    gen2drv.put(tr_B); 
                end
                wait(scb.transaction_count == test_count * 2);
            `else
                for (int i = 0; i < test_count; i++) begin
                    aes_operation_transaction#(MODE) tr = new(); 
                    `ifdef TVLA_STATIC
                        tr.plain_text = 128'h3243f6a8_885a308d_313198a2_e0370734;
                        tr.key        = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
                    `elsif TVLA_DYNAMIC
                        if(!std::randomize(tr.plain_text)) $fatal("Randomization failed");
                        tr.key        = 128'h2b7e1516_28aed2a6_abf71588_09cf4f3c;
                    `else
                        if(!tr.randomize()) $fatal("Randomization failed");
                    `endif
        
                    gen2drv.put(tr); 
                    @(e_sync);
                end
                wait(scb.transaction_count == test_count);
            `endif
            
            repeat(5) @(posedge clk);
        end

        scb.report(); 
        $finish;
    end
    
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            `ifdef TVLA_STATIC
                $dumpfile("./sim_static/aes_operation.vcd");
            `elsif TVLA_DYNAMIC
                $dumpfile("./sim_dynamic/aes_operation.vcd");
            `else
                $dumpfile("./sim/aes_operation.vcd");
            `endif
            $dumpvars(0, aes_operation_tb.dut);
        end
    end
endmodule

`endif

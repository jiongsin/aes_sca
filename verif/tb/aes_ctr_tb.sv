`ifdef AES_CTR

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
`else
    `define VER base
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

    `ifdef AES_SCA
        .trng_in    (intf.trng_in),
    `endif

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

        aes_ctr_driver#(MODE)     drv;
        aes_ctr_monitor#(MODE)    mon;
        aes_ctr_scoreboard#(MODE) scb;

        int expected_scoreboard_count;

        drv = new(intf, gen2drv);
        mon = new(intf, mon2scb);
        scb = new(mon2scb);

        if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 1000;
        end

    `ifdef AES_SCA
        expected_scoreboard_count = test_count * 2;
    `else
        expected_scoreboard_count = test_count;
    `endif

        $display("[%0t] [TOP] Starting AES CTR Simulation", $time);
        $display("[%0t] [TOP] MODE = %0d", $time, MODE);
        $display("[%0t] [TOP] Requested core cycles = %0d", $time, test_count);
        $display("[%0t] [TOP] Expected scoreboard transactions = %0d",
                 $time, expected_scoreboard_count);

        intf.start    = 1'b0;
        intf.valid_in = 1'b0;
        intf.stop     = 1'b0;
        intf.key_in   = '0;
        intf.nonce_in = '0;
        intf.pt_in    = 32'd0;

    `ifdef AES_SCA
        intf.trng_in = '0;
    `endif

        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        fork
            drv.run();
            mon.run();
            scb.run();
        join_none

        for (int i = 0; i < test_count; i++) begin
            aes_ctr_transaction#(MODE) tr;
            tr = new();

            if (!tr.randomize()) begin
                $fatal(1, "Randomization failed at item %0d", i);
            end

            gen2drv.put(tr);
        end

        wait (scb.transaction_count >= expected_scoreboard_count);

        repeat (10) @(posedge clk);

        scb.report();

        $finish;
    end

endmodule

`endif

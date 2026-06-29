//------------------------------------------------------------------------------
// File        : aes_prng_tb.sv
// Description : Top-level SystemVerilog testbench for the AES SCA PRNG block.
//               Instantiates the PRNG interface and DUT, applies randomized TRNG-valid stimulus, and checks generated random output with the package scoreboard.
//------------------------------------------------------------------------------

`ifdef AES_PRNG

module aes_prng_tb;
    bit clk;
    int test_count;

    always #5ns clk = ~clk;

    aes_prng_if intf(clk);

    aes_prng_sca dut (
        .clk         (intf.clk),
        .rst_n       (intf.rst_n),
        .trng_in     (intf.trng_in),
        .trng_valid  (intf.trng_valid),
        .random_out  (intf.random_out)
    );

    initial begin
        mailbox gen2drv = new(10);
        mailbox mon2scb = new();

        aes_prng_pkg::aes_prng_driver     drv = new(intf, gen2drv);
        aes_prng_pkg::aes_prng_monitor    mon = new(intf, mon2scb);
        aes_prng_pkg::aes_prng_scoreboard scb = new(mon2scb);

        if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 1000;
        end

        $display("[%0t] [TOP] Starting PRNG Verification Suite", $time);

        fork
            drv.run();
            mon.run();
            scb.run();
        join_none

        intf.rst_n = 0;
        intf.trng_valid = 0;
        intf.trng_in = 0;
        repeat(5) @(negedge clk);
        intf.rst_n = 1;
        repeat(1) @(posedge clk);

        for (int i = 0; i < test_count; i++) begin
            aes_prng_pkg::aes_prng_transaction tr = new();
            if (!tr.randomize()) $fatal("Randomization failed");
            gen2drv.put(tr);
        end

        wait(scb.transaction_count == test_count);
        repeat(2) @(posedge clk);

        scb.report();
        $finish;
    end
endmodule

`endif


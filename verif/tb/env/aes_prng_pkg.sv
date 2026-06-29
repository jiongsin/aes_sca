//------------------------------------------------------------------------------
// File        : aes_prng_pkg.sv
// Description : SystemVerilog verification package for the AES PRNG testbench.
//               Defines PRNG transactions, driver and monitor components, cycle-accurate xorshift reference behavior, scoreboard checking, and reporting.
//------------------------------------------------------------------------------

package aes_prng_pkg;

    class aes_prng_transaction;
        bit rst_n;
        rand bit [31:0] trng_in;
        rand bit trng_valid;
        bit [143:0] random_out;

        constraint trng_valid_distribution {
            trng_valid dist {1'b1 := 40, 1'b0 := 60};
        }
    endclass

    class aes_prng_driver;
        virtual aes_prng_if vif;
        mailbox gen2drv;

        function new(virtual aes_prng_if vif, mailbox gen2drv);
            this.vif = vif;
            this.gen2drv = gen2drv;
        endfunction

        task run();
            forever begin
                aes_prng_transaction trans;
                gen2drv.get(trans);
                @(vif.drv_cb);
                vif.drv_cb.trng_valid <= trans.trng_valid;
                vif.drv_cb.trng_in   <= trans.trng_in;
            end
        endtask
    endclass

    class aes_prng_monitor;
        virtual aes_prng_if vif;
        mailbox mon2scb;

        function new(virtual aes_prng_if vif, mailbox mon2scb);
            this.vif = vif;
            this.mon2scb = mon2scb;
        endfunction

        task run();
            forever begin
                aes_prng_transaction trans = new();
                @(vif.mon_cb);
                trans.rst_n      = vif.mon_cb.rst_n;
                trans.trng_in    = vif.mon_cb.trng_in;
                trans.trng_valid = vif.mon_cb.trng_valid;
                trans.random_out = vif.mon_cb.random_out;
                mon2scb.put(trans);
            end
        endtask
    endclass

    class aes_prng_scoreboard;
        mailbox mon2scb;
        int transaction_count = 0;
        int mismatch_count = 0;

        bit [31:0] b1 = 32'd1;
        bit [31:0] b2 = 32'd2;
        bit [31:0] b3 = 32'd3;
        bit [31:0] b4 = 32'd4;
        bit [31:0] b5 = 32'd5;
        bit is_first_cycle = 1;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        // Golden Reference Function for Xorshift32
        function automatic [31:0] xs32_ref(input [31:0] in_val);
            logic [31:0] temp1, temp2;
            temp1 = in_val ^ (in_val << 13);
            temp2 = temp1 ^ (temp1 >> 17);
            return temp2 ^ (temp2 << 5);
        endfunction

        task run();
            aes_prng_transaction trans;
            bit [143:0] expected_out;

            forever begin
                mon2scb.get(trans);

                if (trans.rst_n) begin
                    b1 = 32'd1;
                    b2 = 32'd2;
                    b3 = 32'd3;
                    b4 = 32'd4;
                    b5 = 32'd5;
                    is_first_cycle = 0;
                end else if (!is_first_cycle) begin
                    transaction_count++;
                    expected_out = {b5[15:0], b4, b3, b2, b1};

                    if (trans.random_out !== expected_out) begin
                        mismatch_count++;
                        $error("[%0t] [FAIL] Trans #%0d Mismatch! Expected: %h | Got: %h",
                               $time, transaction_count, expected_out, trans.random_out);
                    end else begin
                        $display("[%0t] [PASS] Trans #%0d Match! Output: %h",
                                 $time, transaction_count, trans.random_out);
                    end

                    begin
                        bit [31:0] next_b1, next_b2, next_b3, next_b4, next_b5;
                        next_b1 = trans.trng_valid ? (xs32_ref(b5) ^ trans.trng_in) : xs32_ref(b5);
                        next_b2 = xs32_ref(b1);
                        next_b3 = xs32_ref(b2);
                        next_b4 = xs32_ref(b3);
                        next_b5 = xs32_ref(b4);

                        b1 = next_b1;
                        b2 = next_b2;
                        b3 = next_b3;
                        b4 = next_b4;
                        b5 = next_b5;
                    end
                end
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("     AES PRNG VERIFICATION REPORT");
            $display("========================================");
            $display(" Total Checked Cycles : %0d", transaction_count);
            $display(" Mismatches           : %0d", mismatch_count);
            $display(" TEST STATUS          : %s",
                    (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED");
            $display("========================================\n");
        endfunction
    endclass

endpackage


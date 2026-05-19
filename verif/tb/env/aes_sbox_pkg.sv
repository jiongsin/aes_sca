package aes_sbox_pkg;

    import "DPI-C" function bit [7:0] aes_sbox_ref_model(
        input byte unsigned data_in
    );

    class aes_sbox_transaction;
        rand bit [7:0] data_in;
        bit [7:0] data_out;
        
        `ifdef AES_SCA
        bit [7:0] mask;
        bit [35:0] random_bits;
        `endif
        
        function new();
        endfunction
    endclass

    class aes_sbox_driver;
        virtual aes_sbox_if vif;
        mailbox gen2drv;
        event next_item;

        function new(virtual aes_sbox_if vif, mailbox gen2drv, event next_item);
            this.vif = vif;
            this.gen2drv = gen2drv;
            this.next_item = next_item;
        endfunction

        task run();
            forever begin
                aes_sbox_transaction trans;
                gen2drv.get(trans);

                @(vif.drv_cb);
                `ifdef AES_SCA
                    if (!std::randomize(trans.mask)) $display("Randomization failed");
                    if (!std::randomize(trans.random_bits)) $display("Randomization failed");
                    
                    vif.drv_cb.data_in_0 <= trans.data_in ^ trans.mask;
                    vif.drv_cb.data_in_1 <= trans.mask;
                    vif.drv_cb.random_bits <= trans.random_bits;
                `else
                    vif.drv_cb.data_in <= trans.data_in;
                `endif
                
                ->next_item;
            end
        endtask
    endclass

    class aes_sbox_monitor;
        virtual aes_sbox_if vif;
        mailbox mon2scb;
        event next_item;

        function new(virtual aes_sbox_if vif, mailbox mon2scb, event next_item);
            this.vif = vif;
            this.mon2scb = mon2scb;
            this.next_item = next_item;
        endfunction

        task run();
            @(vif.mon_cb);
            forever begin
                @(vif.mon_cb);
                begin
                    automatic aes_sbox_transaction trans = new();
                    
                    `ifdef AES_SCA
                        trans.data_in = vif.mon_cb.data_in_0 ^ vif.mon_cb.data_in_1;
                        trans.random_bits = vif.mon_cb.random_bits;
                        
                        fork
                            begin
                                automatic aes_sbox_transaction t_local = trans;
                                repeat(4) @(vif.mon_cb);
                                t_local.data_out = vif.mon_cb.data_out_0 ^ vif.mon_cb.data_out_1;
                                mon2scb.put(t_local);
                            end
                        join_none
                    `else
                        trans.data_in = vif.mon_cb.data_in;
                        trans.data_out = vif.mon_cb.data_out;
                        mon2scb.put(trans);
                    `endif
                end
            end
        endtask
    endclass

    class aes_sbox_scoreboard;
        mailbox mon2scb;
        int transaction_count = 0;
        int mismatch_count = 0;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_sbox_transaction trans;
            bit [7:0] expected_out;

            forever begin
                mon2scb.get(trans);
                transaction_count++;

                expected_out = aes_sbox_ref_model(trans.data_in);

                if (trans.data_out === expected_out) begin
                    $display("[%0t] [PASS] Trans #%0d | In: %h | Out: %h", 
                             $time, transaction_count, trans.data_in, trans.data_out);
                end else begin
                    mismatch_count++;
                    $error("[%0t] [FAIL] Trans #%0d Mismatch! | In: %h | Out: %h | Expected: %h", 
                           $time, transaction_count, trans.data_in, trans.data_out, expected_out);
                end

                if (transaction_count == 256) begin
                    report();
                    $finish;
                end
            end
        endtask

        function void report();
            $display("\n=============================================");
            $display("        AES SBOX VERIFICATION REPORT");
            $display("=============================================");
            $display(" Total Transactions : %0d", transaction_count);
            $display(" Mismatches         : %0d", mismatch_count);
            $display(" TEST STATUS        : %s", 
                    (mismatch_count == 0 && transaction_count == 256) ? "PASSED" : "FAILED");
            $display("=============================================\n");
        endfunction
    endclass

endpackage

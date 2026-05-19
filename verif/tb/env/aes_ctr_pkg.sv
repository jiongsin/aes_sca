package aes_ctr_pkg;

    import "DPI-C" function void aes_ctr_ref_model(
        input int mode,
        input bit [255:0] key,
        input bit [127:0] nonce,
        input bit [255:0] pt,
        output bit [255:0] ct
    );

    class aes_ctr_transaction #(parameter MODE = 128);
        rand bit [MODE-1:0] key;
        rand bit [127:0]    nonce;
        rand bit [255:0]    plain_text;
        rand bit [159:0]    trng;
        bit [255:0]         cipher_text;
    endclass

    class aes_ctr_driver #(parameter MODE = 128);
        virtual aes_ctr_if#(MODE) vif;
        mailbox gen2drv;

        function new(virtual aes_ctr_if#(MODE) vif, mailbox gen2drv);
            this.vif = vif;
            this.gen2drv = gen2drv;
        endfunction

        task run();
            vif.drv_cb.start <= 0;
            vif.drv_cb.valid_in <= 0;
            vif.drv_cb.stop <= 0;
            forever begin
                aes_ctr_transaction#(MODE) trans;
                gen2drv.get(trans);
                
                @ (vif.drv_cb);
                vif.drv_cb.start <= 1'b1;
                @ (vif.drv_cb);
                vif.drv_cb.start <= 1'b0;
                vif.drv_cb.valid_in <= 1'b1;
                
                for (int i = 0; i < 5; i++) begin
                    vif.drv_cb.trng_in <= trans.trng[(i*32) +: 32];
                    @ (vif.drv_cb);
                end
                
                for (int i = 0; i < (MODE/32); i++) begin
                    vif.drv_cb.key_in <= trans.key[(i*32) +: 32];
                    @ (vif.drv_cb);
                end
                
                for (int i = 0; i < 4; i++) begin
                    vif.drv_cb.nonce_in <= trans.nonce[(i*32) +: 32];
                    @ (vif.drv_cb);
                end
                
                vif.drv_cb.valid_in <= 1'b0;
                
                if (MODE == 256) begin
                    repeat(12) @ (vif.drv_cb);
                end else if (MODE == 192) begin
                    repeat(10) @ (vif.drv_cb);
                end else begin
                    repeat(8) @ (vif.drv_cb);
                end
                
                vif.drv_cb.valid_in <= 1'b1;
                for (int i = 0; i < 8; i++) begin
                    vif.drv_cb.pt_in <= trans.plain_text[(i*32) +: 32];
                    @ (vif.drv_cb);
                end
                vif.drv_cb.valid_in <= 1'b0;
                
                forever begin
                    @ (vif.drv_cb);
                    if (vif.drv_cb.valid_out === 1'b1) break;
                end
                vif.drv_cb.stop <= 1'b1;
                
                @ (vif.drv_cb);

                forever begin
                    @ (vif.drv_cb);
                    if (vif.drv_cb.valid_out === 1'b0) break;
                end
                vif.drv_cb.stop <= 1'b0;
                
                @ (vif.drv_cb);
            end
        endtask
    endclass

    class aes_ctr_monitor #(parameter MODE = 128);
        virtual aes_ctr_if#(MODE) vif;
        mailbox mon2scb;

        function new(virtual aes_ctr_if#(MODE) vif, mailbox mon2scb);
            this.vif = vif;
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_ctr_transaction#(MODE) trans;
            forever begin
                @ (vif.mon_cb);
                if (vif.mon_cb.start === 1'b1) begin
                    trans = new();
                    @ (vif.mon_cb);
                    
                    for (int i = 0; i < 5; i++) begin
                        trans.trng[(i*32) +: 32] = vif.mon_cb.trng_in;
                        @ (vif.mon_cb);
                    end
                    
                    for (int i = 0; i < (MODE/32); i++) begin
                        trans.key[(i*32) +: 32] = vif.mon_cb.key_in;
                        @ (vif.mon_cb);
                    end
                    
                    for (int i = 0; i < 4; i++) begin
                        trans.nonce[(i*32) +: 32] = vif.mon_cb.nonce_in;
                        if (i < 3) @ (vif.mon_cb);
                    end
                    
                    forever begin
                        @ (vif.mon_cb);
                        if (vif.mon_cb.valid_in === 1'b1) break;
                    end
                    
                    for (int i = 0; i < 8; i++) begin
                        trans.plain_text[(i*32) +: 32] = vif.mon_cb.pt_in;
                        if (i < 7) @ (vif.mon_cb);
                    end
                    
                    forever begin
                        @ (vif.mon_cb);
                        if (vif.mon_cb.valid_out === 1'b1) break;
                    end
                    
                    for (int i = 0; i < 8; i++) begin
                        trans.cipher_text[(i*32) +: 32] = vif.mon_cb.ct_out;
                        if (i < 7) @ (vif.mon_cb);
                    end
                    
                    mon2scb.put(trans);
                end
            end
        endtask
    endclass

    class aes_ctr_scoreboard #(parameter MODE = 128);
        mailbox mon2scb;
        int transaction_count = 0;
        int mismatch_count = 0;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_ctr_transaction#(MODE) trans;
            bit [255:0] expected_cipher;
            bit [255:0] wide_key;
            
            forever begin
                mon2scb.get(trans);
                transaction_count++;
                
                wide_key = 0;
                wide_key[MODE-1:0] = trans.key;
                
                aes_ctr_ref_model(MODE, wide_key, trans.nonce, trans.plain_text, expected_cipher);
                
                if (trans.cipher_text === expected_cipher) begin
                    $display("[%0t] [PASS] Trans %0d | PT: %h | CT: %h", $time, transaction_count, trans.plain_text, trans.cipher_text);
                end else begin
                    mismatch_count++;
                    $error("[%0t] [FAIL] Trans %0d Mismatch | PT: %h | CT: %h | Expected: %h", $time, transaction_count, trans.plain_text, trans.cipher_text, expected_cipher);
                end
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("      AES %0d CTR VERIFICATION REPORT", MODE);
            $display("========================================");
            $display(" Total Transactions : %0d", transaction_count);
            $display(" Mismatches         : %0d", mismatch_count);
            $display(" TEST STATUS        : %s", (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED");
            $display("========================================\n");
            if (mismatch_count > 0) begin
                $fatal(1, "Test failed!");
            end
        endfunction
    endclass

endpackage

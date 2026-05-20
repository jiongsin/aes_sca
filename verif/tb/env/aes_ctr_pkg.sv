package aes_ctr_pkg;

    import "DPI-C" function void aes_ctr_ref_model(
        input int mode,
        input int num_blocks,
        input bit [255:0] key,
        input bit [127:0] nonce,
        input bit [255:0] pt,
        output bit [255:0] ct
    );

    class aes_ctr_transaction #(parameter MODE = 128);
        rand bit [MODE-1:0] key;
        rand bit [127:0]    nonce;
        `ifdef AES_SCA
            rand bit [255:0]    plain_text;
            rand bit [159:0]    trng;
            bit [255:0]         cipher_text;
        `else
            rand bit [127:0]    plain_text;
            bit [127:0]         cipher_text;
        `endif
    endclass

    class aes_ctr_driver #(parameter MODE = 128);
        virtual aes_ctr_if#(MODE) vif;
        mailbox gen2drv;

        function new(virtual aes_ctr_if#(MODE) vif, mailbox gen2drv);
            this.vif = vif;
            this.gen2drv = gen2drv;
        endfunction

        task run();
            bit is_continuous = 0;
            int cycle_count = 0;
            vif.drv_cb.start <= 0;
            vif.drv_cb.valid_in <= 0;
            vif.drv_cb.stop <= 0;
            
            forever begin
                aes_ctr_transaction#(MODE) trans;
                gen2drv.get(trans);
                
                if (!is_continuous) begin
                    @ (vif.drv_cb);
                    vif.drv_cb.start <= 1'b1;
                    @ (vif.drv_cb);
                    vif.drv_cb.start <= 1'b0;
                    vif.drv_cb.valid_in <= 1'b1;
                    
                    `ifdef AES_SCA
                        for (int i = 0; i < 5; i++) begin
                            vif.drv_cb.trng_in <= trans.trng[(i*32) +: 32];
                            @ (vif.drv_cb);
                        end
                    `endif
                    
                    for (int i = 0; i < (MODE/32); i++) begin
                        vif.drv_cb.key_in <= trans.key[(i*32) +: 32];
                        @ (vif.drv_cb);
                    end
                    
                    for (int i = 0; i < 4; i++) begin
                        vif.drv_cb.nonce_in <= trans.nonce[(i*32) +: 32];
                        @ (vif.drv_cb);
                    end
                    vif.drv_cb.valid_in <= 1'b0;
                    
                    `ifdef AES_SCA
                        if (MODE == 256) repeat(12) @ (vif.drv_cb);
                        else if (MODE == 192) repeat(10) @ (vif.drv_cb);
                        else repeat(8) @ (vif.drv_cb);
                    `else
                        if (MODE == 256) repeat(8) @ (vif.drv_cb);
                        else if (MODE == 192) repeat(6) @ (vif.drv_cb);
                        else repeat(4) @ (vif.drv_cb);
                    `endif
                    
                end else begin
                    vif.drv_cb.valid_in <= 1'b0;
                    `ifdef AES_SCA
                        if (MODE == 256) repeat(11) @ (vif.drv_cb);
                        else if (MODE == 192) repeat(9) @ (vif.drv_cb);
                        else repeat(7) @ (vif.drv_cb);
                    `else
                        if (MODE == 256) repeat(7) @ (vif.drv_cb);
                        else if (MODE == 192) repeat(5) @ (vif.drv_cb);
                        else repeat(3) @ (vif.drv_cb);
                    `endif
                end
                
                vif.drv_cb.valid_in <= 1'b1;
                
                `ifdef AES_SCA
                    for (int i = 0; i < 8; i++) begin
                `else
                    for (int i = 0; i < 4; i++) begin
                `endif
                    vif.drv_cb.pt_in <= trans.plain_text[(i*32) +: 32];
                    @ (vif.drv_cb);
                end
                vif.drv_cb.valid_in <= 1'b0;
                
                forever begin
                    @ (vif.drv_cb);
                    if (vif.drv_cb.valid_out === 1'b1) break;
                end
                
                cycle_count++;
                if (cycle_count == 3) begin
                    vif.drv_cb.stop <= 1'b1;
                    is_continuous = 0;
                    cycle_count = 0;
                end else begin
                    vif.drv_cb.stop <= 1'b0;
                    is_continuous = 1;
                end
                
                @ (vif.drv_cb);

                forever begin
                    @ (vif.drv_cb);
                    if (vif.drv_cb.valid_out === 1'b0) break;
                end
                vif.drv_cb.stop <= 1'b0;
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
            bit is_continuous = 0;
            bit [255:0] saved_key;
            bit [127:0] saved_nonce;
            
            `ifdef AES_SCA
                bit [159:0] saved_trng;
            `endif
            
            forever begin
                trans = new();
                
                if (!is_continuous) begin
                    forever begin
                        @ (vif.mon_cb);
                        if (vif.mon_cb.start === 1'b1) break;
                    end
                    @ (vif.mon_cb); 
                    
                    `ifdef AES_SCA
                        for (int i = 0; i < 5; i++) begin
                            trans.trng[(i*32) +: 32] = vif.mon_cb.trng_in;
                            @ (vif.mon_cb);
                        end
                    `endif
                    
                    for (int i = 0; i < (MODE/32); i++) begin
                        trans.key[(i*32) +: 32] = vif.mon_cb.key_in;
                        @ (vif.mon_cb);
                    end
                    
                    for (int i = 0; i < 4; i++) begin
                        trans.nonce[(i*32) +: 32] = vif.mon_cb.nonce_in;
                        if (i < 3) @ (vif.mon_cb);
                    end
                    
                    saved_key = trans.key;
                    saved_nonce = trans.nonce;
                    `ifdef AES_SCA
                        saved_trng = trans.trng;
                    `endif
                end else begin
                    `ifdef AES_SCA
                        saved_nonce[31:0] = saved_nonce[31:0] + 32'd2;
                        trans.trng = saved_trng;
                    `else
                        saved_nonce[31:0] = saved_nonce[31:0] + 32'd1;
                    `endif
                    trans.key = saved_key;
                    trans.nonce = saved_nonce;
                end
                
                forever begin
                    @ (vif.mon_cb);
                    if (vif.mon_cb.valid_in === 1'b1) break;
                end
                
                `ifdef AES_SCA
                    for (int i = 0; i < 8; i++) begin
                        trans.plain_text[(i*32) +: 32] = vif.mon_cb.pt_in;
                        if (i < 7) @ (vif.mon_cb);
                    end
                `else
                    for (int i = 0; i < 4; i++) begin
                        trans.plain_text[(i*32) +: 32] = vif.mon_cb.pt_in;
                        if (i < 3) @ (vif.mon_cb);
                    end
                `endif
                
                forever begin
                    @ (vif.mon_cb);
                    if (vif.mon_cb.valid_out === 1'b1) break;
                end
                
                `ifdef AES_SCA
                    for (int i = 0; i < 8; i++) begin
                        trans.cipher_text[(i*32) +: 32] = vif.mon_cb.ct_out;
                        if (i < 7) @ (vif.mon_cb);
                    end
                `else
                    for (int i = 0; i < 4; i++) begin
                        trans.cipher_text[(i*32) +: 32] = vif.mon_cb.ct_out;
                        if (i < 3) @ (vif.mon_cb);
                    end
                `endif
                
                mon2scb.put(trans);
                
                if (vif.mon_cb.stop === 1'b0) begin
                    is_continuous = 1;
                end else begin
                    is_continuous = 0;
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
            bit [255:0] expected_cipher_wide;
            bit [255:0] wide_key;
            bit [255:0] wide_pt;
            bit [127:0] wide_nonce;
            bit [127:0] display_nonce; 
            
            bit [127:0] pt_block[2];
            bit [127:0] ct_block[2];
            bit [127:0] exp_block[2];

            int cycle_num;
            string block_id;
            int blocks_per_trans;

            forever begin
                mon2scb.get(trans);

                wide_key = 0;
                wide_pt = 0;
                wide_nonce = 0;

                for (int i = 0; i < (MODE/32); i++) begin
                    wide_key[i*32 +: 32] = trans.key[i*32 +: 32];
                end

                for (int i = 0; i < 4; i++) begin
                    wide_nonce[i*32 +: 32] = trans.nonce[i*32 +: 32];
                end

                `ifdef AES_SCA
                    for (int i = 0; i < 8; i++) begin
                        wide_pt[i*32 +: 32] = trans.plain_text[i*32 +: 32];
                    end
                    blocks_per_trans = 2;
                `else
                    for (int i = 0; i < 4; i++) begin
                        wide_pt[i*32 +: 32] = trans.plain_text[i*32 +: 32];
                    end
                    blocks_per_trans = 1;
                `endif

                aes_ctr_ref_model(MODE, blocks_per_trans, wide_key, wide_nonce, wide_pt, expected_cipher_wide);

                `ifdef AES_SCA
                    pt_block[0]  = trans.plain_text[127:0];
                    pt_block[1]  = trans.plain_text[255:128];
                    
                    ct_block[0]  = trans.cipher_text[127:0];
                    ct_block[1]  = trans.cipher_text[255:128];
                    
                    exp_block[0] = expected_cipher_wide[127:0];   
                    exp_block[1] = expected_cipher_wide[255:128]; 
                `else
                    pt_block[0]  = trans.plain_text;
                    ct_block[0]  = trans.cipher_text;
                    exp_block[0] = expected_cipher_wide[127:0];
                `endif

                for (int b = 0; b < blocks_per_trans; b++) begin
                    transaction_count++;
                    
                    display_nonce = trans.nonce;
                    if (b == 1) begin
                        display_nonce[31:0] = display_nonce[31:0] + 32'd1;
                    end
                    
                    `ifdef AES_SCA
                        cycle_num = ((transaction_count - 1) / 2) + 1;
                        block_id  = (transaction_count % 2 != 0) ? "A" : "B";

                        if (ct_block[b] === exp_block[b]) begin
                            $display("[%0t] [PASS] Cycle %0d Block %s Trans %0d | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h", 
                                     $time, cycle_num, block_id, transaction_count, pt_block[b], trans.key, display_nonce, ct_block[b]);
                        end else begin
                            mismatch_count++;
                            $error("[%0t] [FAIL] Cycle %0d Block %s Trans %0d Mismatch | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h | Expected Ciphertext: %h", 
                                   $time, cycle_num, block_id, transaction_count, pt_block[b], trans.key, display_nonce, ct_block[b], exp_block[b]);
                        end
                    `else
                        if (ct_block[b] === exp_block[b]) begin
                            $display("[%0t] [PASS] Trans %0d | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h", 
                                     $time, transaction_count, pt_block[b], trans.key, display_nonce, ct_block[b]);
                        end else begin
                            mismatch_count++;
                            $error("[%0t] [FAIL] Trans %0d Mismatch | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h | Expected Ciphertext: %h", 
                                   $time, transaction_count, pt_block[b], trans.key, display_nonce, ct_block[b], exp_block[b]);
                        end
                    `endif
                end
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("      AES CTR %0d VERIFICATION REPORT", MODE);
            $display("========================================");
            `ifdef AES_SCA
                $display(" Total Transactions : %0d", transaction_count);
                $display(" Total Core Cycles  : %0d", transaction_count / 2);
            `else
                $display(" Total Transactions : %0d", transaction_count);
            `endif
            $display(" Mismatches         : %0d", mismatch_count);
            $display(" TEST STATUS        : %s", 
                    (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED");
            $display("========================================\n");
            if (mismatch_count > 0) begin
                $fatal(1, "Test failed!");
            end
        endfunction
    endclass
endpackage

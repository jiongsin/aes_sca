package aes_pkg;

    import "DPI-C" function void aes_operation_ref_model(
        input int mode,
        input bit [255:0] key,
        input bit [127:0] data_in,
        output bit [127:0] data_out
    );

    import "DPI-C" function void aes_gcm_ref_model(
        input int mode,
        input bit [255:0] key,
        input bit [95:0] iv,
        input bit [127:0] pt_in,
        input int num_blocks,
        output bit [127:0] ct_out,
        output bit [127:0] tag_out
    );

    import "DPI-C" function bit [7:0] aes_sbox_ref_model(
        input byte unsigned data_in
    );

    class aes_sbox_transaction;
        rand bit [7:0] data_in;
        `ifdef AES_SCA
        rand bit [35:0] random_bits;
        `endif
        bit [7:0] data_out;
        
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
                vif.drv_cb.data_in <= trans.data_in;
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
            aes_sbox_transaction trans;
            @(vif.mon_cb);
            forever begin
                @(vif.mon_cb);
                trans = new();
                
                trans.data_in = vif.mon_cb.data_in;
                `ifdef AES_SCA
                trans.random_bits = vif.mon_cb.random_bits;
                repeat(4) @(vif.mon_cb);
                `endif
                trans.data_out = vif.mon_cb.data_out;
                mon2scb.put(trans);
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
            $display("\n========================================");
            $display("        AES SBOX VERIFICATION REPORT");
            $display("========================================");
            $display(" Total Transactions : %0d", transaction_count);
            $display(" Mismatches         : %0d", mismatch_count);
            $display(" TEST STATUS        : %s", 
                    (mismatch_count == 0 && transaction_count == 256) ? "PASSED" : "FAILED");
            $display("========================================\n");
        endfunction
    endclass

    class aes_operation_transaction #(parameter MODE = 128);
        rand bit [MODE-1:0] key;
        rand bit [127:0]    plain_text;
        `ifdef AES_SCA
        rand bit [351:0]    random_bits;
        `endif
        bit [127:0]         cipher_text;

        constraint key_dist {
            key dist {
                {MODE{1'b1}} :/ 3,
                0            :/ 3,
                [1 : {(MODE-1){1'b1}}-1]    :/ 4,
                [{(MODE-1){1'b1}} : {MODE{1'b1}}-1] :/ 90
            };
        }

        covergroup aes_cg;
            cp_key: coverpoint key {
                bins zero_key  = {0};
                bins small_val = {[1 : 16'hFFFF]};
                bins large_val = {[{MODE{1'b1}} - 16'hFFFF : {MODE{1'b1}}]};
                bins others    = default;
            }
            cp_data: coverpoint plain_text {
                bins special_cases = {128'h0, {128{1'b1}}};
                bins ranges[10]    = {[0:$]};
            }
        endgroup

        function new();
            aes_cg = new();
        endfunction

        function void sample();
            aes_cg.sample();
        endfunction
    endclass

    class aes_operation_driver #(parameter MODE = 128);
        virtual aes_operation_if#(MODE) vif;
        mailbox gen2drv;
        event next_item; 

        function new(virtual aes_operation_if#(MODE) vif, mailbox gen2drv, event next_item);
            this.vif = vif;
            this.gen2drv = gen2drv;
            this.next_item = next_item;
        endfunction

        task run();
            vif.drv_cb.valid_in <= 0;
            forever begin
                `ifdef AES_SCA
                aes_operation_transaction#(MODE) trans_A, trans_B;
                gen2drv.get(trans_A);
                gen2drv.get(trans_B);
                
                @(vif.drv_cb);
                vif.drv_cb.valid_in <= 1'b1;
                
                for (int i = 0; i < (MODE/32); i++) begin
                    vif.drv_cb.key_in <= trans_A.key[MODE - 1 - (i*32) -: 32];
                    vif.drv_cb.data_in <= trans_A.plain_text[127 - (i*32) -: 32];
                    if (i < (MODE/32) - 1) @(vif.drv_cb);
                end
                @(vif.drv_cb);
                
                for (int i = 0; i < (MODE/32); i++) begin
                    vif.drv_cb.key_in <= trans_B.key[MODE - 1 - (i*32) -: 32];
                    vif.drv_cb.data_in <= trans_B.plain_text[127 - (i*32) -: 32];
                    if (i < (MODE/32) - 1) @(vif.drv_cb);
                end
                @(vif.drv_cb);
                
                vif.drv_cb.valid_in <= 1'b0;
                
                wait(vif.mon_cb.valid_out == 1'b1);
                wait(vif.mon_cb.valid_out == 1'b0);
                
                `else
                aes_operation_transaction#(MODE) trans;
                gen2drv.get(trans);
            
                @(vif.drv_cb);
                
                `ifdef IS_128BIT
                    vif.drv_cb.key_in   <= trans.key;
                    vif.drv_cb.data_in  <= trans.plain_text;
                    vif.drv_cb.valid_in <= 1'b1;
                
                    @(vif.drv_cb);
                    vif.drv_cb.valid_in <= 1'b0;
                `else
                    vif.drv_cb.valid_in <= 1'b1;
                    
                    for (int i = 0; i < (MODE/32); i++) begin
                        vif.drv_cb.key_in <= trans.key[MODE - 1 - (i*32) -: 32];
                        if (i >= (MODE/32) - 4) begin
                            vif.drv_cb.data_in <= trans.plain_text[127 - ((i - ((MODE/32) - 4)) * 32) -: 32];
                        end else begin
                            vif.drv_cb.data_in <= 32'd0;
                        end
                        if (i < (MODE/32) - 1) @(vif.drv_cb);
                    end
                    @(vif.drv_cb);
                    vif.drv_cb.valid_in <= 1'b0;
                `endif
                
                wait(vif.mon_cb.valid_out == 1'b1);
                @(vif.mon_cb);
                `endif
            end
        endtask
    endclass

    class aes_operation_monitor #(parameter MODE = 128);
        virtual aes_operation_if#(MODE) vif;
        mailbox mon2scb;
        event next_item;

        typedef enum {IDLE, CAPTURE_INPUT, WAIT_OUTPUT, CLEANUP} state_t;
        state_t state = IDLE;
        
        `ifdef AES_SCA
        aes_operation_transaction#(MODE) trans_q[$];
        `endif

        function new(virtual aes_operation_if#(MODE) vif, mailbox mon2scb, event next_item);
            this.vif = vif;
            this.mon2scb = mon2scb;
            this.next_item = next_item;
        endfunction

        task run();
            `ifdef AES_SCA
            fork
                forever begin
                    @(vif.mon_cb);
                    if (vif.mon_cb.valid_in === 1'b1) begin
                        aes_operation_transaction#(MODE) trans = new();
                        trans.key = 0;
                        trans.plain_text = 0;
                        for (int i = 0; i < (MODE/32); i++) begin
                            trans.key[MODE - 1 - (i*32) -: 32] = vif.mon_cb.key_in;
                            trans.plain_text[127 - (i*32) -: 32] = vif.mon_cb.data_in;
                            trans.random_bits = vif.mon_cb.random_bits;
                            if (i < (MODE/32) - 1) @(vif.mon_cb);
                        end
                        trans_q.push_back(trans);
                    end
                end
                
                forever begin
                    @(vif.mon_cb);
                    if (vif.mon_cb.valid_out === 1'b1) begin
                        aes_operation_transaction#(MODE) trans;
                        wait(trans_q.size() > 0);
                        trans = trans_q.pop_front();
                        
                        for (int i = 0; i < 4; i++) begin
                            trans.cipher_text[127 - (i*32) -: 32] = vif.mon_cb.data_out;
                            if (i < 3) @(vif.mon_cb);
                        end
                        
                        mon2scb.put(trans);
                        ->next_item;
                    end
                end
            join_none
            `else
            aes_operation_transaction#(MODE) trans;
            forever begin
                @(vif.mon_cb);
                case (state)
                    IDLE: begin
                        if (vif.mon_cb.valid_in === 1'b1) begin
                            trans = new();
                            `ifdef IS_128BIT
                                trans.key = vif.mon_cb.key_in;
                                trans.plain_text = vif.mon_cb.data_in;
                            `else
                                for (int i = 0; i < (MODE/32); i++) begin
                                    trans.key[MODE - 1 - (i*32) -: 32] = vif.mon_cb.key_in;
                                    if (i >= (MODE/32) - 4) begin
                                        trans.plain_text[127 - ((i - ((MODE/32) - 4)) * 32) -: 32] = vif.mon_cb.data_in;
                                    end
                                    if (i < (MODE/32) - 1) @(vif.mon_cb);
                                end
                            `endif
                            state = WAIT_OUTPUT;
                        end
                    end

                    WAIT_OUTPUT: begin
                        if (vif.mon_cb.valid_out === 1'b1) begin
                            `ifdef IS_128BIT
                                trans.cipher_text = vif.mon_cb.data_out;
                            `else
                                for (int i = 0; i < 4; i++) begin
                                    trans.cipher_text[127 - (i*32) -: 32] = vif.mon_cb.data_out;
                                    if (i < 3) @(vif.mon_cb);
                                end
                            `endif
                            mon2scb.put(trans);
                            ->next_item;
                            state = CLEANUP;
                        end
                    end

                    CLEANUP: begin
                        if (vif.mon_cb.valid_in === 1'b0 && 
                            vif.mon_cb.valid_out === 1'b0) begin
                            state = IDLE;
                        end
                    end
                endcase
            end
            `endif
        endtask
    endclass

    class aes_operation_scoreboard #(parameter MODE = 128);
        mailbox mon2scb;
        int transaction_count = 0;
        int mismatch_count = 0;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_operation_transaction#(MODE) trans;
            bit [127:0] expected_cipher;
            bit [255:0] wide_key;
            
            int cycle_num;
            string block_id;

            forever begin
                mon2scb.get(trans);
                transaction_count++;
                trans.sample();

                wide_key = 0;
                wide_key[MODE-1:0] = trans.key;
                aes_operation_ref_model(MODE, wide_key, trans.plain_text, expected_cipher);

                `ifdef AES_SCA
                    // Calculate which cycle and which block (A or B) this is
                    cycle_num = ((transaction_count - 1) / 2) + 1;
                    block_id  = (transaction_count % 2 != 0) ? "A" : "B";

                    if (trans.cipher_text === expected_cipher) begin
                        $display("[%0t] [PASS] Cycle #%0d Block %s (Trans #%0d) | Plaintext: %h | Key: %h | Ciphertext: %h", 
                                 $time, cycle_num, block_id, transaction_count, trans.plain_text, trans.key, trans.cipher_text);
                    end else begin
                        mismatch_count++;
                        $error("[%0t] [FAIL] Cycle #%0d Block %s (Trans #%0d) Mismatch! | Plaintext: %h | Key: %h | Ciphertext: %h | Expected Ciphertext: %h", 
                               $time, cycle_num, block_id, transaction_count, trans.plain_text, trans.key, trans.cipher_text, expected_cipher);
                    end
                `else
                    if (trans.cipher_text === expected_cipher) begin
                        $display("[%0t] [PASS] Trans #%0d | Plaintext: %h | Key: %h | Ciphertext: %h", 
                                 $time, transaction_count, trans.plain_text, trans.key, trans.cipher_text);
                    end else begin
                        mismatch_count++;
                        $error("[%0t] [FAIL] Trans #%0d Mismatch! | Plaintext: %h | Key: %h | Ciphertext: %h | Expected Ciphertext: %h", 
                               $time, transaction_count, trans.plain_text, trans.key, trans.cipher_text, expected_cipher);
                    end
                `endif
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("      AES-%0d VERIFICATION REPORT", MODE);
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
        endfunction
    endclass

    class aes_gcm_transaction #(parameter MODE = 128);
        rand bit [MODE-1:0] key;
        rand bit [95:0]     iv;
        rand bit [127:0]    plain_text;
        
        bit [127:0] cipher_text;
        bit [127:0] tag;

        constraint key_dist {
            key dist {
                {MODE{1'b1}} :/ 3,
                0            :/ 3,
                [1 : {(MODE-1){1'b1}}-1]    :/ 4,
                [{(MODE-1){1'b1}} : {MODE{1'b1}}-1] :/ 90
            };
        }

        function new();
        endfunction
        
        function void sample();
        endfunction
    endclass

    class aes_gcm_driver #(parameter MODE = 128);
        virtual aes_gcm_if#(MODE) vif;
        mailbox gen2drv;
        event next_item; 

        function new(virtual aes_gcm_if#(MODE) vif, mailbox gen2drv, event next_item);
            this.vif = vif;
            this.gen2drv = gen2drv;
            this.next_item = next_item;
        endfunction

        task run();
            vif.drv_cb.start <= 0;
            vif.drv_cb.data_valid <= 0;
            
            forever begin
                aes_gcm_transaction#(MODE) trans;
                gen2drv.get(trans);
            
                @(vif.drv_cb);
                
                vif.drv_cb.start  <= 1'b1;
                vif.drv_cb.key_in <= trans.key;
                vif.drv_cb.iv_in  <= trans.iv;
                
                repeat(40) @(vif.drv_cb);
                
                vif.drv_cb.data_in    <= trans.plain_text;
                vif.drv_cb.data_valid <= 1'b1;
                
                @(vif.drv_cb);
                vif.drv_cb.data_valid <= 1'b0;
                
                wait(vif.mon_cb.data_out_valid == 1'b1);
                @(vif.drv_cb);
                
                vif.drv_cb.start <= 1'b0;
                
                wait(vif.mon_cb.tag_out_valid == 1'b1);
                @(vif.drv_cb);
            end
        endtask
    endclass

    class aes_gcm_monitor #(parameter MODE = 128);
        virtual aes_gcm_if#(MODE) vif;
        mailbox mon2scb;
        event next_item;

        function new(virtual aes_gcm_if#(MODE) vif, mailbox mon2scb, event next_item);
            this.vif = vif;
            this.mon2scb = mon2scb;
            this.next_item = next_item;
        endfunction

        task run();
            aes_gcm_transaction#(MODE) trans;
            
            forever begin
                @(vif.mon_cb);
                
                if (vif.mon_cb.start === 1'b1 && vif.mon_cb.data_valid === 1'b1) begin
                    trans = new();
                    trans.key        = vif.mon_cb.key_in;
                    trans.iv         = vif.mon_cb.iv_in;
                    trans.plain_text = vif.mon_cb.data_in;

                    wait(vif.mon_cb.data_out_valid === 1'b1);
                    trans.cipher_text = vif.mon_cb.data_out;

                    wait(vif.mon_cb.tag_out_valid === 1'b1);
                    trans.tag = vif.mon_cb.tag_out;

                    mon2scb.put(trans);
                    ->next_item;
                end
            end
        endtask
    endclass

    class aes_gcm_scoreboard #(parameter MODE = 128);
        mailbox mon2scb;
        int transaction_count = 0;
        int mismatch_count = 0;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_gcm_transaction#(MODE) trans;
            bit [127:0] expected_cipher;
            bit [127:0] expected_tag;
            bit [255:0] wide_key;

            forever begin
                mon2scb.get(trans);
                transaction_count++;
                trans.sample();

                wide_key = 0;
                wide_key[MODE-1:0] = trans.key;
                
                aes_gcm_ref_model(MODE, wide_key, trans.iv, trans.plain_text, 1, expected_cipher, expected_tag);

                if (trans.cipher_text === expected_cipher && trans.tag === expected_tag) begin
                    $display("[%0t] [PASS] Trans #%0d | Plaintext: %h | Key: %h | Vector: %h | Ciphertext: %h | Tag : %h", 
                             $time, transaction_count, trans.plain_text, trans.key, trans.iv, trans.cipher_text, trans.tag);
                end else begin
                    mismatch_count++;
                    $error("[%0t] [FAIL] Trans #%0d Mismatch! | Plaintext: %h | Key: %h | Vector: %h | Ciphertext: %h |  Expected Ciphertext : %h | Tag : %h | Expected Tag: %h", 
                           $time, transaction_count, trans.plain_text, trans.key, trans.iv, trans.cipher_text, expected_cipher, trans.tag, expected_tag);
                end
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("    AES-%0d-GCM VERIFICATION REPORT", MODE);
            $display("========================================");
            $display(" Total Transactions : %0d", transaction_count);
            $display(" Mismatches         : %0d", mismatch_count);
            $display(" TEST STATUS        : %s", 
                    (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED");
            $display("========================================\n");
        endfunction
    endclass

endpackage

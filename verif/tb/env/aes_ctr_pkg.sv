//------------------------------------------------------------------------------
// File        : aes_ctr_pkg.sv
// Description : SystemVerilog verification package for the AES CTR testbench.
//               Defines CTR transactions, driver and monitor behavior, DPI reference-model comparison, scoreboard reporting, and coverage sampling.
//------------------------------------------------------------------------------

package aes_ctr_pkg;

    import "DPI-C" function void aes_ctr_ref_model(
        input  int         mode,
        input  int         num_blocks,
        input  bit [255:0] key,
        input  bit [127:0] nonce,
        input  bit [255:0] pt,
        output bit [255:0] ct
    );

    class aes_ctr_transaction #(parameter MODE = 128);

        rand bit [MODE-1:0] key;
        rand bit [127:0]    nonce;

    `ifdef AES_SCA
        rand bit [159:0] trng;
        rand bit [255:0] plain_text;
             bit [255:0] cipher_text;
    `else
        rand bit [127:0] plain_text;
             bit [127:0] cipher_text;
    `endif

        constraint key_dist {
            key dist {
                {MODE{1'b1}} :/ 3,
                0            :/ 3,
                [1 : {(MODE-1){1'b1}}-1] :/ 4,
                [{(MODE-1){1'b1}} : {MODE{1'b1}}-1] :/ 90
            };
        }

        covergroup aes_ctr_cg;
            cp_key: coverpoint key {
                bins zero_key  = {0};
                bins small_val = {[1 : 16'hFFFF]};
                bins large_val = {[{MODE{1'b1}} - 16'hFFFF : {MODE{1'b1}}]};
                bins others    = default;
            }

            cp_nonce: coverpoint nonce {
                bins zero_nonce = {0};
                bins max_nonce  = {{128{1'b1}}};
                bins others     = default;
            }

        `ifdef AES_SCA
            cp_pt_low: coverpoint plain_text[127:0] {
                bins special_cases = {128'h0, {128{1'b1}}};
                bins ranges[10]    = {[0:$]};
            }

            cp_pt_high: coverpoint plain_text[255:128] {
                bins special_cases = {128'h0, {128{1'b1}}};
                bins ranges[10]    = {[0:$]};
            }
        `else
            cp_pt: coverpoint plain_text {
                bins special_cases = {128'h0, {128{1'b1}}};
                bins ranges[10]    = {[0:$]};
            }
        `endif
        endgroup

        function new();
            aes_ctr_cg = new();
        endfunction

        function void sample();
            aes_ctr_cg.sample();
        endfunction

    endclass

    class aes_ctr_driver #(parameter MODE = 128);

        virtual aes_ctr_if#(MODE) vif;
        mailbox gen2drv;

        function new(
            virtual aes_ctr_if#(MODE) vif,
            mailbox gen2drv
        );
            this.vif     = vif;
            this.gen2drv = gen2drv;
        endfunction

        task automatic drive_plaintext_and_wait_output(
            input aes_ctr_transaction#(MODE) trans,
            input bit stop_on_this_transaction
        );
            int word_idx;
            int total_words;

        `ifdef AES_SCA
            total_words = 8;
        `else
            total_words = 4;
        `endif

            word_idx = 0;

            vif.drv_cb.valid_in <= 1'b1;
            vif.drv_cb.pt_in    <= trans.plain_text[31:0];

            if ((total_words == 1) && stop_on_this_transaction) begin
                vif.drv_cb.stop <= 1'b1;
            end else begin
                vif.drv_cb.stop <= 1'b0;
            end

            forever begin
                @(vif.drv_cb);

                if (vif.drv_cb.valid_out === 1'b1) begin
                    word_idx++;

                    if (word_idx == total_words) begin
                        break;
                    end else begin
                        vif.drv_cb.pt_in <= trans.plain_text[(word_idx*32) +: 32];

                        if ((word_idx == total_words - 1) &&
                            stop_on_this_transaction) begin
                            vif.drv_cb.stop <= 1'b1;
                        end else begin
                            vif.drv_cb.stop <= 1'b0;
                        end
                    end
                end
            end

            vif.drv_cb.valid_in <= 1'b0;
            vif.drv_cb.pt_in    <= 32'd0;
            vif.drv_cb.stop     <= 1'b0;
        endtask

        task run();
            bit is_continuous;
            int cycle_count;
            bit stop_this_transaction;

            is_continuous = 1'b0;
            cycle_count   = 0;

            vif.drv_cb.start    <= 1'b0;
            vif.drv_cb.valid_in <= 1'b0;
            vif.drv_cb.stop     <= 1'b0;
            vif.drv_cb.pt_in    <= 32'd0;
            vif.drv_cb.key_in   <= '0;
            vif.drv_cb.nonce_in <= '0;

        `ifdef AES_SCA
            vif.drv_cb.trng_in <= '0;
        `endif

            forever begin
                aes_ctr_transaction#(MODE) trans;

                gen2drv.get(trans);

                if (!is_continuous) begin
                    @(vif.drv_cb);

                    vif.drv_cb.key_in   <= trans.key;
                    vif.drv_cb.nonce_in <= trans.nonce;

                `ifdef AES_SCA
                    vif.drv_cb.trng_in <= trans.trng;
                `endif

                    vif.drv_cb.start <= 1'b1;
                    @(vif.drv_cb);
                    vif.drv_cb.start <= 1'b0;
                end

                stop_this_transaction = (cycle_count == 2);

                drive_plaintext_and_wait_output(
                    trans,
                    stop_this_transaction
                );

                if (stop_this_transaction) begin
                    is_continuous = 1'b0;
                    cycle_count   = 0;
                end else begin
                    is_continuous = 1'b1;
                    cycle_count++;
                end

                @(vif.drv_cb);
            end
        endtask

    endclass

    class aes_ctr_monitor #(parameter MODE = 128);

        virtual aes_ctr_if#(MODE) vif;
        mailbox mon2scb;

        function new(
            virtual aes_ctr_if#(MODE) vif,
            mailbox mon2scb
        );
            this.vif     = vif;
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_ctr_transaction#(MODE) trans;

            bit is_continuous;
            bit stop_seen;

            bit [255:0] saved_key;
            bit [127:0] saved_nonce;

        `ifdef AES_SCA
            bit [159:0] saved_trng;
        `endif

            int word_idx;
            int total_words;

        `ifdef AES_SCA
            total_words = 8;
        `else
            total_words = 4;
        `endif

            is_continuous = 1'b0;

            forever begin
                trans = new();

                if (!is_continuous) begin
                    forever begin
                        @(vif.mon_cb);
                        if (vif.mon_cb.start === 1'b1) begin
                            break;
                        end
                    end

                    trans.key   = vif.mon_cb.key_in;
                    trans.nonce = vif.mon_cb.nonce_in;

                `ifdef AES_SCA
                    trans.trng = vif.mon_cb.trng_in;
                    saved_trng = trans.trng;
                `endif

                    saved_key   = trans.key;
                    saved_nonce = trans.nonce;
                end else begin
                    trans.key = saved_key;

                `ifdef AES_SCA
                    saved_nonce[31:0] = saved_nonce[31:0] + 32'd2;
                    trans.trng = saved_trng;
                `else
                    saved_nonce[31:0] = saved_nonce[31:0] + 32'd1;
                `endif

                    trans.nonce = saved_nonce;
                end

                word_idx  = 0;
                stop_seen = 1'b0;

                forever begin
                    @(vif.mon_cb);

                    if (vif.mon_cb.valid_out === 1'b1) begin
                        trans.plain_text[(word_idx*32) +: 32]  = vif.mon_cb.pt_in;
                        trans.cipher_text[(word_idx*32) +: 32] = vif.mon_cb.ct_out;

                        if (word_idx == total_words - 1) begin
                            stop_seen = vif.mon_cb.stop;
                        end

                        word_idx++;

                        if (word_idx == total_words) begin
                            break;
                        end
                    end
                end

                mon2scb.put(trans);

                if (stop_seen) begin
                    is_continuous = 1'b0;
                end else begin
                    is_continuous = 1'b1;
                end
            end
        endtask

    endclass

    class aes_ctr_scoreboard #(parameter MODE = 128);

        mailbox mon2scb;

        int transaction_count = 0;
        int mismatch_count    = 0;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_ctr_transaction#(MODE) trans;

            bit [255:0] expected_cipher_wide;
            bit [255:0] wide_key;
            bit [255:0] wide_pt;
            bit [127:0] wide_nonce;

            bit [127:0] pt_block[2];
            bit [127:0] ct_block[2];
            bit [127:0] exp_block[2];

            bit [127:0] display_nonce;

            int blocks_per_trans;
            int cycle_num;
            string block_id;

            forever begin
                mon2scb.get(trans);

                trans.sample();

                wide_key   = '0;
                wide_pt    = '0;
                wide_nonce = '0;

                wide_key[MODE-1:0] = trans.key;
                wide_nonce         = trans.nonce;

            `ifdef AES_SCA
                wide_pt = trans.plain_text;
                blocks_per_trans = 2;
            `else
                wide_pt[127:0] = trans.plain_text;
                blocks_per_trans = 1;
            `endif

                aes_ctr_ref_model(
                    MODE,
                    blocks_per_trans,
                    wide_key,
                    wide_nonce,
                    wide_pt,
                    expected_cipher_wide
                );

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
                        $display(
                            "[%0t] [PASS] Cycle %0d Block %s Trans %0d | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h",
                            $time,
                            cycle_num,
                            block_id,
                            transaction_count,
                            pt_block[b],
                            trans.key,
                            display_nonce,
                            ct_block[b]
                        );
                    end else begin
                        mismatch_count++;
                        $error(
                            "[%0t] [FAIL] Cycle %0d Block %s Trans %0d Mismatch | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h | Expected Ciphertext: %h",
                            $time,
                            cycle_num,
                            block_id,
                            transaction_count,
                            pt_block[b],
                            trans.key,
                            display_nonce,
                            ct_block[b],
                            exp_block[b]
                        );
                    end
                `else
                    if (ct_block[b] === exp_block[b]) begin
                        $display(
                            "[%0t] [PASS] Trans %0d | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h",
                            $time,
                            transaction_count,
                            pt_block[b],
                            trans.key,
                            display_nonce,
                            ct_block[b]
                        );
                    end else begin
                        mismatch_count++;
                        $error(
                            "[%0t] [FAIL] Trans %0d Mismatch | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h | Expected Ciphertext: %h",
                            $time,
                            transaction_count,
                            pt_block[b],
                            trans.key,
                            display_nonce,
                            ct_block[b],
                            exp_block[b]
                        );
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
            $display(
                " TEST STATUS        : %s",
                (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED"
            );
            $display("========================================\n");

            if (mismatch_count > 0) begin
                $fatal(1, "Test failed!");
            end
        endfunction

    endclass

endpackage

//------------------------------------------------------------------------------
// File        : aes_operation_pkg.sv
// Description : SystemVerilog verification package for the AES operation testbench.
//               Defines operation transactions, constrained stimulus, driver sequencing, monitor capture, DPI reference comparison, scoreboard reporting, and coverage.
//------------------------------------------------------------------------------

package aes_operation_pkg;

    import "DPI-C" function void aes_operation_ref_model(
        input int mode,
        input bit [255:0] key,
        input bit [127:0] data_in,
        output bit [127:0] data_out
    );

    class aes_operation_transaction #(parameter MODE = 128);
        rand bit [MODE-1:0] key;
        rand bit [127:0]    plain_text;
        `ifdef AES_SCA
        bit [351:0]         random_bits;
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

                @ (vif.drv_cb);
                vif.drv_cb.valid_in <= 1'b1;

                // Little Endian Drive (Word 0 to Word Nk-1)
                for (int i = 0; i < (MODE/32); i++) begin
                    vif.drv_cb.key_in <= trans_A.key[(i*32) +: 32];
                    if (i < 4) begin
                        vif.drv_cb.data_in <= trans_A.plain_text[(i*32) +: 32];
                    end else begin
                        vif.drv_cb.data_in <= 32'd0;
                    end
                    if (i < (MODE/32) - 1) @ (vif.drv_cb);
                end
                @ (vif.drv_cb);

                for (int i = 0; i < 4; i++) begin
                    vif.drv_cb.key_in <= 32'd0;
                    vif.drv_cb.data_in <= trans_B.plain_text[(i*32) +: 32];
                    if (i < 3) @ (vif.drv_cb);
                end
                @ (vif.drv_cb);

                vif.drv_cb.valid_in <= 1'b0;

                wait(vif.mon_cb.valid_out == 1'b1);
                wait(vif.mon_cb.valid_out == 1'b0);

                `else

                aes_operation_transaction#(MODE) trans;
                gen2drv.get(trans);

                @ (vif.drv_cb);
                vif.drv_cb.valid_in <= 1'b1;

                for (int i = 0; i < (MODE/32); i++) begin
                    vif.drv_cb.key_in <= trans.key[(i*32) +: 32];
                    vif.drv_cb.data_in <= (i < 4) ? trans.plain_text[(i*32) +: 32] : 32'd0;

                    if (i < (MODE/32) - 1) begin
                        @ (vif.drv_cb);
                    end
                end

                @ (vif.drv_cb);
                vif.drv_cb.valid_in <= 1'b0;
                vif.drv_cb.key_in   <= 32'd0;
                vif.drv_cb.data_in  <= 32'd0;

                // Wait for the 4-cycle 32-bit output stream to complete.
                wait(vif.mon_cb.valid_out == 1'b1);
                repeat (4) @ (vif.mon_cb);
                wait(vif.mon_cb.valid_out == 1'b0);
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
            // DO NOT MODIFY AES_SCA PATH
            bit is_block_b = 0;
            bit [MODE-1:0] saved_key;

            fork
                forever begin
                    @ (vif.mon_cb);
                    if (vif.mon_cb.valid_in === 1'b1) begin
                        aes_operation_transaction#(MODE) trans = new();
                        trans.key = 0;
                        trans.plain_text = 0;

                        if (!is_block_b) begin
                            for (int i = 0; i < (MODE/32); i++) begin
                                trans.key[(i*32) +: 32] = vif.mon_cb.key_in;
                                if (i < 4) begin
                                    trans.plain_text[(i*32) +: 32] = vif.mon_cb.data_in;
                                end
                                trans.random_bits = vif.mon_cb.random_bits;
                                if (i < (MODE/32) - 1) @ (vif.mon_cb);
                            end
                            saved_key = trans.key;
                            is_block_b = 1;
                        end else begin
                            trans.key = saved_key;
                            for (int i = 0; i < 4; i++) begin
                                trans.plain_text[(i*32) +: 32] = vif.mon_cb.data_in;
                                trans.random_bits = vif.mon_cb.random_bits;
                                if (i < 3) @ (vif.mon_cb);
                            end
                            is_block_b = 0;
                        end
                        trans_q.push_back(trans);
                    end
                end

                forever begin
                    @ (vif.mon_cb);
                    if (vif.mon_cb.valid_out === 1'b1) begin
                        aes_operation_transaction#(MODE) trans;
                        wait(trans_q.size() > 0);
                        trans = trans_q.pop_front();

                        for (int i = 0; i < 4; i++) begin
                            trans.cipher_text[(i*32) +: 32] = vif.mon_cb.data_out;
                            if (i < 3) @ (vif.mon_cb);
                        end

                        mon2scb.put(trans);
                        -> next_item;
                    end
                end
            join_none
            `else
            // Revised non-AES_SCA path only.
            // Captures one MODE/32-cycle little-endian input stream and one
            // 4-cycle little-endian 32-bit output stream.
            aes_operation_transaction#(MODE) trans;

            forever begin
                @ (vif.mon_cb);
                case (state)
                    IDLE: begin
                        if (vif.mon_cb.valid_in === 1'b1) begin
                            trans = new();
                            trans.key = '0;
                            trans.plain_text = '0;
                            trans.cipher_text = '0;

                            for (int i = 0; i < (MODE/32); i++) begin
                                trans.key[(i*32) +: 32] = vif.mon_cb.key_in;
                                if (i < 4) begin
                                    trans.plain_text[(i*32) +: 32] = vif.mon_cb.data_in;
                                end
                                if (i < (MODE/32) - 1) @ (vif.mon_cb);
                            end

                            state = WAIT_OUTPUT;
                        end
                    end

                    WAIT_OUTPUT: begin
                        if (vif.mon_cb.valid_out === 1'b1) begin
                            for (int i = 0; i < 4; i++) begin
                                trans.cipher_text[(i*32) +: 32] = vif.mon_cb.data_out;
                                if (i < 3) @ (vif.mon_cb);
                            end

                            mon2scb.put(trans);
                            -> next_item;
                            state = CLEANUP;
                        end
                    end

                    CLEANUP: begin
                        if (vif.mon_cb.valid_in === 1'b0 &&
                            vif.mon_cb.valid_out === 1'b0) begin
                            state = IDLE;
                        end
                    end

                    default: begin
                        state = IDLE;
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

                    cycle_num = ((transaction_count - 1) / 2) + 1;
                    block_id  = (transaction_count % 2 != 0) ? "A" : "B";

                    if (trans.cipher_text === expected_cipher) begin
                        $display("[%0t] [PASS] Cycle %0d Block %s Trans %0d | Plaintext: %h | Key: %h | Ciphertext: %h",
                                 $time, cycle_num, block_id, transaction_count, trans.plain_text, trans.key, trans.cipher_text);
                    end else begin
                        mismatch_count++;
                        $error("[%0t] [FAIL] Cycle %0d Block %s Trans %0d Mismatch | Plaintext: %h | Key: %h | Ciphertext: %h | Expected Ciphertext: %h",
                               $time, cycle_num, block_id, transaction_count, trans.plain_text, trans.key, trans.cipher_text, expected_cipher);
                    end
                `else
                    if (trans.cipher_text === expected_cipher) begin
                        $display("[%0t] [PASS] Trans %0d | Plaintext: %h | Key: %h | Ciphertext: %h",
                                 $time, transaction_count, trans.plain_text, trans.key, trans.cipher_text);
                    end else begin
                        mismatch_count++;
                        $error("[%0t] [FAIL] Trans %0d Mismatch | Plaintext: %h | Key: %h | Ciphertext: %h | Expected Ciphertext: %h",
                               $time, transaction_count, trans.plain_text, trans.key, trans.cipher_text, expected_cipher);
                    end
                `endif
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("      AES Operation %0d VERIFICATION REPORT", MODE);
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


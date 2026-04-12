package aes_pkg;

    import "DPI-C" function void aes_ref_model(
        input int mode,
        input bit [255:0] key,
        input bit [127:0] data_in,
        output bit [127:0] data_out
    );

    class aes_transaction #(parameter MODE = 128);
        rand bit [MODE-1:0] key;
        rand bit [127:0]    plain_text;
        bit [127:0]         cipher_text;

        constraint key_dist {
            key dist {
                {MODE{1'b1}} :/ 20,
                0            :/ 10,
                [1 : 100]    :/ 10,
                [101 : {MODE{1'b1}}-1] :/ 60
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

    class aes_driver #(parameter MODE = 128);
        virtual aes_if#(MODE) vif;
        mailbox gen2drv;
        event next_item; 

        function new(virtual aes_if#(MODE) vif, mailbox gen2drv, event next_item);
            this.vif = vif;
            this.gen2drv = gen2drv;
            this.next_item = next_item;
        endfunction

        task run();
            vif.drv_cb.valid_in <= 0;
            forever begin
                aes_transaction#(MODE) trans;
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
            end
        endtask
    endclass

    class aes_monitor #(parameter MODE = 128);
        virtual aes_if#(MODE) vif;
        mailbox mon2scb;
        event next_item;

        typedef enum {IDLE, CAPTURE_INPUT, WAIT_OUTPUT, CLEANUP} state_t;
        state_t state = IDLE;

        function new(virtual aes_if#(MODE) vif, mailbox mon2scb, event next_item);
            this.vif = vif;
            this.mon2scb = mon2scb;
            this.next_item = next_item;
        endfunction

        task run();
            aes_transaction#(MODE) trans;
            
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
        endtask
    endclass

    class aes_scoreboard #(parameter MODE = 128);
        mailbox mon2scb;
        int transaction_count = 0;
        int mismatch_count = 0;

        function new(mailbox mon2scb);
            this.mon2scb = mon2scb;
        endfunction

        task run();
            aes_transaction#(MODE) trans;
            bit [127:0] expected_cipher;
            bit [255:0] wide_key;

            forever begin
                mon2scb.get(trans);
                transaction_count++;
                trans.sample();

                wide_key = 0;
                wide_key[MODE-1:0] = trans.key;
                aes_ref_model(MODE, wide_key, trans.plain_text, expected_cipher);

                if (trans.cipher_text === expected_cipher) begin
                    $display("[%0t] [PASS] Trans #%0d | Plaintext: %h | Key: %h | Ciphertext: %h", 
                             $time, transaction_count, trans.plain_text, trans.key, trans.cipher_text);
                end else begin
                    mismatch_count++;
                    $error("[%0t] [FAIL] Trans #%0d Mismatch! | Plaintext: %h | Key: %h | Ciphertext: %h | Expected Ciphertext: %h", $time, transaction_count, trans.plain_text, trans.key, trans.cipher_text, expected_cipher);
                end
            end
        endtask

        function void report();
            $display("\n========================================");
            $display("        AES VERIFICATION REPORT");
            $display("========================================");
            $display(" Total Transactions : %0d", transaction_count);
            $display(" Mismatches         : %0d", mismatch_count);
            $display(" TEST STATUS        : %s", 
                    (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED");
            $display("========================================\n");
        endfunction
    endclass

endpackage

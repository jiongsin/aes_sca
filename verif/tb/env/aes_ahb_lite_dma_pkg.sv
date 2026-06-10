package aes_ahb_lite_dma_pkg;

    import "DPI-C" function void aes_ctr_ref_model(
        input  int         mode,
        input  int         num_blocks,
        input  bit [255:0] key,
        input  bit [127:0] nonce,
        input  bit [255:0] pt,
        output bit [255:0] ct
    );

    localparam bit [1:0] HTRANS_IDLE   = 2'b00;
    localparam bit [1:0] HTRANS_BUSY   = 2'b01;
    localparam bit [1:0] HTRANS_NONSEQ = 2'b10;
    localparam bit [1:0] HTRANS_SEQ    = 2'b11;

    localparam bit [2:0] HSIZE_WORD    = 3'b010;
    localparam bit [2:0] HBURST_SINGLE = 3'b000;
    localparam bit [3:0] HPROT_DATA    = 4'b0011;

    localparam int A_CTRL        = 'h00;
    localparam int A_STATUS      = 'h04;
    localparam int A_PTDATA      = 'h08;
    localparam int A_CTDATA      = 'h0C;
    localparam int A_PT_LEVEL    = 'h10;
    localparam int A_CT_LEVEL    = 'h14;

    localparam int A_KEY0        = 'h18;
    localparam int A_NONCE0      = 'h40;
    localparam int A_TRNG0       = 'h50;

    localparam int A_IRQ_STATUS  = 'h70;
    localparam int A_BURST_COUNT = 'h74;
    localparam int A_BURST_DONE  = 'h78;

    localparam bit [31:0] CTRL_START      = 32'h0000_0001;
    localparam bit [31:0] CTRL_ENABLE     = 32'h0000_0002;
    localparam bit [31:0] CTRL_AUTO_START = 32'h0000_0004;
    localparam bit [31:0] CTRL_DEC_MODE   = 32'h0000_0008;
    localparam bit [31:0] CTRL_IRQ_EN     = 32'h0000_0010;
    localparam bit [31:0] CTRL_CLEAR      = 32'h0000_0100;

    localparam int ST_CORE_ACTIVE      = 0;
    localparam int ST_DONE             = 1;
    localparam int ST_PT_EMPTY         = 2;
    localparam int ST_PT_FULL          = 3;
    localparam int ST_CT_EMPTY         = 4;
    localparam int ST_CT_FULL          = 5;
    localparam int ST_IRQ              = 6;
    localparam int ST_PT_OVERFLOW      = 7;
    localparam int ST_CT_UNDERFLOW     = 8;
    localparam int ST_DEC_MODE         = 9;
    localparam int ST_JOB_ACTIVE       = 10;
    localparam int ST_BURST_ZERO       = 11;
    localparam int ST_COUNTER_OVERFLOW = 12;
    localparam int ST_ILLEGAL_ACCESS   = 13;


    class aes_ahb_lite_dma_transaction #(parameter MODE = 128);

        rand bit [MODE-1:0] key;
        rand bit [127:0]    nonce;
        rand bit [159:0]    trng;
        rand bit [255:0]    plain_text;

             bit [255:0]    cipher_text;

        constraint key_dist {
            key dist {
                {MODE{1'b0}}       :/ 3,
                {MODE{1'b1}}       :/ 3,
                [1:{MODE{1'b1}}-1] :/ 94
            };
        }

        covergroup aes_ahb_lite_dma_cg;
            cp_key_zero: coverpoint (key == '0);
            cp_key_ones: coverpoint (key == {MODE{1'b1}});

            cp_nonce_low: coverpoint nonce[31:0] {
                bins zero        = {32'h0000_0000};
                bins near_wrap[] = {32'hFFFF_FFFE, 32'hFFFF_FFFF};
                bins others      = default;
            }

            cp_pt_low: coverpoint plain_text[31:0] {
                bins zero   = {32'h0000_0000};
                bins ones   = {32'hFFFF_FFFF};
                bins others = default;
            }
        endgroup

        function new();
            aes_ahb_lite_dma_cg = new();
        endfunction

        function void sample();
            aes_ahb_lite_dma_cg.sample();
        endfunction

    endclass


    class aes_ahb_lite_dma_driver #(parameter MODE = 128);

        virtual aes_ahb_lite_dma_if vif;
        mailbox gen2drv;
        mailbox drv2scb;

        function new(
            virtual aes_ahb_lite_dma_if vif,
            mailbox gen2drv,
            mailbox drv2scb
        );
            this.vif     = vif;
            this.gen2drv = gen2drv;
            this.drv2scb = drv2scb;
        endfunction


        task automatic idle_bus();
            vif.HSEL      = 1'b0;
            vif.HADDR     = 32'd0;
            vif.HTRANS    = HTRANS_IDLE;
            vif.HWRITE    = 1'b0;
            vif.HSIZE     = HSIZE_WORD;
            vif.HBURST    = HBURST_SINGLE;
            vif.HPROT     = HPROT_DATA;
            vif.HMASTLOCK = 1'b0;
            vif.HWDATA    = 32'd0;
            vif.HREADY    = 1'b1;
        endtask


        task automatic wait_ready_posedge();
            do begin
                @(posedge vif.HCLK);
            end while (vif.HREADYOUT !== 1'b1);
        endtask


        task automatic drive_idle_direct();
            vif.HSEL      = 1'b0;
            vif.HADDR     = 32'd0;
            vif.HTRANS    = HTRANS_IDLE;
            vif.HWRITE    = 1'b0;
            vif.HSIZE     = HSIZE_WORD;
            vif.HBURST    = HBURST_SINGLE;
            vif.HPROT     = HPROT_DATA;
            vif.HMASTLOCK = 1'b0;
            vif.HWDATA    = 32'd0;
            vif.HREADY    = 1'b1;
        endtask


        task automatic drive_write_direct(
            input bit [31:0] addr,
            input bit [31:0] data_phase
        );
            vif.HSEL      = 1'b1;
            vif.HADDR     = addr;
            vif.HTRANS    = HTRANS_NONSEQ;
            vif.HWRITE    = 1'b1;
            vif.HSIZE     = HSIZE_WORD;
            vif.HBURST    = HBURST_SINGLE;
            vif.HPROT     = HPROT_DATA;
            vif.HMASTLOCK = 1'b0;
            vif.HWDATA    = data_phase;
            vif.HREADY    = 1'b1;
        endtask


        task automatic drive_read_direct(input bit [31:0] addr);
            vif.HSEL      = 1'b1;
            vif.HADDR     = addr;
            vif.HTRANS    = HTRANS_NONSEQ;
            vif.HWRITE    = 1'b0;
            vif.HSIZE     = HSIZE_WORD;
            vif.HBURST    = HBURST_SINGLE;
            vif.HPROT     = HPROT_DATA;
            vif.HMASTLOCK = 1'b0;
            vif.HWDATA    = 32'd0;
            vif.HREADY    = 1'b1;
        endtask


        task automatic drive_final_wdata_direct(input bit [31:0] data_phase);
            vif.HSEL      = 1'b0;
            vif.HADDR     = 32'd0;
            vif.HTRANS    = HTRANS_IDLE;
            vif.HWRITE    = 1'b0;
            vif.HSIZE     = HSIZE_WORD;
            vif.HBURST    = HBURST_SINGLE;
            vif.HPROT     = HPROT_DATA;
            vif.HMASTLOCK = 1'b0;
            vif.HWDATA    = data_phase;
            vif.HREADY    = 1'b1;
        endtask


        task automatic ahb_write_stream(
            input bit [31:0] addr_q[$],
            input bit [31:0] data_q[$]
        );
            int n;

            n = addr_q.size();

            if (n == 0) begin
                return;
            end

            if (data_q.size() != n) begin
                $fatal(1, "AHB write stream queue size mismatch");
            end

            @(negedge vif.HCLK);

            drive_write_direct(addr_q[0], 32'd0);

            for (int i = 0; i < n; i++) begin
                wait_ready_posedge();

                @(negedge vif.HCLK);

                if (i + 1 < n) begin
                    drive_write_direct(addr_q[i+1], data_q[i]);
                end else begin
                    drive_final_wdata_direct(data_q[i]);
                end
            end

            wait_ready_posedge();

            @(negedge vif.HCLK);
            drive_idle_direct();
        endtask


        task automatic ahb_write(
            input bit [31:0] addr,
            input bit [31:0] data
        );
            bit [31:0] addr_q[$];
            bit [31:0] data_q[$];

            addr_q.delete();
            data_q.delete();

            addr_q.push_back(addr);
            data_q.push_back(data);

            ahb_write_stream(addr_q, data_q);
        endtask


        task automatic ahb_read(
            input  bit [31:0] addr,
            output bit [31:0] data
        );
            @(negedge vif.HCLK);

            drive_read_direct(addr);

            wait_ready_posedge();

            @(negedge vif.HCLK);
            drive_idle_direct();

            wait_ready_posedge();

            #1ns;
            data = vif.HRDATA;

            @(negedge vif.HCLK);
            drive_idle_direct();
        endtask


        task automatic ahb_read_stream_same_addr(
            input  bit [31:0] addr,
            input  int        count,
            output bit [31:0] data_q[$]
        );
            data_q.delete();

            if (count <= 0) begin
                return;
            end

            @(negedge vif.HCLK);

            drive_read_direct(addr);

            wait_ready_posedge();

            for (int i = 0; i < count; i++) begin
                @(negedge vif.HCLK);

                if (i + 1 < count) begin
                    drive_read_direct(addr);
                end else begin
                    drive_idle_direct();
                end

                wait_ready_posedge();

                #1ns;
                data_q.push_back(vif.HRDATA);
            end

            @(negedge vif.HCLK);
            drive_idle_direct();
        endtask


        task automatic wait_pt_space(input int timeout_cycles = 20000);
            for (int i = 0; i < timeout_cycles; i++) begin
                @(posedge vif.HCLK);

                if (vif.dma_pt_req === 1'b1) begin
                    return;
                end
            end

            $fatal(1, "[%0t] Timeout waiting for dma_pt_req/PT FIFO space", $time);
        endtask


        task automatic wait_ct_data(input int timeout_cycles = 20000);
            for (int i = 0; i < timeout_cycles; i++) begin
                @(posedge vif.HCLK);

                if (vif.dma_ct_req === 1'b1) begin
                    return;
                end
            end

            $fatal(1, "[%0t] Timeout waiting for dma_ct_req/CT FIFO data", $time);
        endtask


        task automatic build_setup_stream(
            input  aes_ahb_lite_dma_transaction#(MODE) trans,
            output bit [31:0] addr_q[$],
            output bit [31:0] data_q[$]
        );
            bit [255:0] wide_key;
            bit [255:0] wide_trng;

            addr_q.delete();
            data_q.delete();

            wide_key = '0;
            wide_key[MODE-1:0] = trans.key;

            wide_trng = '0;
            wide_trng[159:0] = trans.trng;

            addr_q.push_back(A_CTRL);
            data_q.push_back(CTRL_CLEAR);

            addr_q.push_back(A_IRQ_STATUS);
            data_q.push_back(32'h0000_3FFF);

            for (int i = 0; i < 8; i++) begin
                addr_q.push_back(A_KEY0 + (i * 4));
                data_q.push_back(wide_key[(i*32) +: 32]);
            end

            for (int i = 0; i < 4; i++) begin
                addr_q.push_back(A_NONCE0 + (i * 4));
                data_q.push_back(trans.nonce[(i*32) +: 32]);
            end

            for (int i = 0; i < 5; i++) begin
                addr_q.push_back(A_TRNG0 + (i * 4));
                data_q.push_back(wide_trng[(i*32) +: 32]);
            end

            addr_q.push_back(A_BURST_COUNT);
            data_q.push_back(32'd1);

            for (int i = 0; i < 8; i++) begin
                addr_q.push_back(A_PTDATA);
                data_q.push_back(trans.plain_text[(i*32) +: 32]);
            end

            addr_q.push_back(A_CTRL);
            data_q.push_back(CTRL_START | CTRL_ENABLE | CTRL_IRQ_EN);
        endtask


        task automatic read_cipher_text(output bit [255:0] ct);
            bit [31:0] rd_q[$];

            ct = '0;

            wait_ct_data();

            ahb_read_stream_same_addr(A_CTDATA, 8, rd_q);

            if (rd_q.size() != 8) begin
                $fatal(1,
                       "[%0t] CT read stream returned %0d words, expected 8",
                       $time,
                       rd_q.size());
            end

            for (int i = 0; i < 8; i++) begin
                ct[(i*32) +: 32] = rd_q[i];
            end
        endtask


        task automatic run_one(input aes_ahb_lite_dma_transaction#(MODE) trans);
            bit [31:0] addr_q[$];
            bit [31:0] data_q[$];
            bit [31:0] burst_done;

            build_setup_stream(trans, addr_q, data_q);
            ahb_write_stream(addr_q, data_q);

            read_cipher_text(trans.cipher_text);

            ahb_read(A_BURST_DONE, burst_done);

            if (burst_done[15:0] != 16'd1) begin
                $fatal(1,
                       "[%0t] BURST_DONE mismatch. Got %0d expected 1",
                       $time,
                       burst_done[15:0]);
            end

            drv2scb.put(trans);
        endtask


        task automatic write_pt_chunk(
            input aes_ahb_lite_dma_transaction#(MODE) tr_q[$],
            ref   int tx_word_idx,
            input int total_words
        );
            bit [31:0] pt_level_word;
            bit [31:0] addr_q[$];
            bit [31:0] data_q[$];

            int pt_level;
            int pt_space;
            int chunk_words;
            int burst_idx;
            int word_in_burst;

            if (tx_word_idx >= total_words) begin
                return;
            end

            wait_pt_space();

            // Check level only once before this continuous PTDATA chunk.
            ahb_read(A_PT_LEVEL, pt_level_word);

            pt_level = pt_level_word[7:0];
            pt_space = 8 - pt_level;

            if (pt_space <= 0) begin
                return;
            end

            chunk_words = total_words - tx_word_idx;

            if (chunk_words > pt_space) begin
                chunk_words = pt_space;
            end

            addr_q.delete();
            data_q.delete();

            for (int i = 0; i < chunk_words; i++) begin
                burst_idx     = (tx_word_idx + i) / 8;
                word_in_burst = (tx_word_idx + i) % 8;

                addr_q.push_back(A_PTDATA);
                data_q.push_back(tr_q[burst_idx].plain_text[(word_in_burst*32) +: 32]);
            end

            // Continuous pipelined PTDATA write stream.
            ahb_write_stream(addr_q, data_q);

            for (int i = 0; i < chunk_words; i++) begin
                burst_idx     = (tx_word_idx + i) / 8;
                word_in_burst = (tx_word_idx + i) % 8;

            //    $display("[%0t] [DMA_STREAM_WR_PT_PIPE] burst[%0d] word[%0d] = %08h",
            //             $time,
            //             burst_idx,
            //             word_in_burst,
            //             tr_q[burst_idx].plain_text[(word_in_burst*32) +: 32]);
            end

            tx_word_idx += chunk_words;
        endtask


        task automatic read_ct_chunk(
            input aes_ahb_lite_dma_transaction#(MODE) tr_q[$],
            ref   int rx_word_idx,
            input int total_words
        );
            bit [31:0] ct_level_word;
            bit [31:0] rd_q[$];

            int ct_level;
            int chunk_words;
            int burst_idx;
            int word_in_burst;

            if (rx_word_idx >= total_words) begin
                return;
            end

            wait_ct_data();

            // Check level only once before this continuous CTDATA chunk.
            ahb_read(A_CT_LEVEL, ct_level_word);

            ct_level = ct_level_word[7:0];

            if (ct_level <= 0) begin
                return;
            end

            chunk_words = total_words - rx_word_idx;

            if (chunk_words > ct_level) begin
                chunk_words = ct_level;
            end

            rd_q.delete();

            // Continuous pipelined CTDATA read stream.
            ahb_read_stream_same_addr(A_CTDATA, chunk_words, rd_q);

            if (rd_q.size() != chunk_words) begin
                $fatal(1,
                       "[%0t] CT read stream returned %0d words, expected %0d",
                       $time,
                       rd_q.size(),
                       chunk_words);
            end

            for (int i = 0; i < chunk_words; i++) begin
                burst_idx     = (rx_word_idx + i) / 8;
                word_in_burst = (rx_word_idx + i) % 8;

                tr_q[burst_idx].cipher_text[(word_in_burst*32) +: 32] = rd_q[i];

                //$display("[%0t] [DMA_STREAM_RD_CT_PIPE] burst[%0d] word[%0d] = %08h",
                //         $time,
                //         burst_idx,
                //         word_in_burst,
                //         rd_q[i]);

                if (word_in_burst == 7) begin
                    drv2scb.put(tr_q[burst_idx]);
                end
            end

            rx_word_idx += chunk_words;
        endtask


        task automatic run_stream(input aes_ahb_lite_dma_transaction#(MODE) tr_q[$]);
            bit [31:0] addr_q[$];
            bit [31:0] data_q[$];
            bit [31:0] burst_done;

            bit [MODE-1:0] base_key;
            bit [127:0]    base_nonce;
            bit [159:0]    base_trng;

            int burst_count;
            int total_words;
            int tx_word_idx;
            int rx_word_idx;
            int idle_cycles;

            burst_count = tr_q.size();

            if (burst_count <= 0) begin
                return;
            end

            if (burst_count > 16'hFFFF) begin
                $fatal(1,
                       "[%0t] run_stream burst_count=%0d exceeds 16-bit BURST_COUNT",
                       $time,
                       burst_count);
            end

            total_words = burst_count * 8;

            base_key   = tr_q[0].key;
            base_nonce = tr_q[0].nonce;
            base_trng  = tr_q[0].trng;

            for (int b = 0; b < burst_count; b++) begin
                tr_q[b].key         = base_key;
                tr_q[b].trng        = base_trng;
                tr_q[b].nonce       = base_nonce;
                tr_q[b].nonce[31:0] = base_nonce[31:0] + (32'd2 * b);
                tr_q[b].cipher_text = '0;
            end

            addr_q.delete();
            data_q.delete();

            // Setup stream only. Plaintext is streamed later.
            addr_q.push_back(A_CTRL);
            data_q.push_back(CTRL_CLEAR);

            addr_q.push_back(A_IRQ_STATUS);
            data_q.push_back(32'h0000_3FFF);

            begin
                bit [255:0] wide_key;

                wide_key = '0;
                wide_key[MODE-1:0] = base_key;

                for (int i = 0; i < 8; i++) begin
                    addr_q.push_back(A_KEY0 + (i * 4));
                    data_q.push_back(wide_key[(i*32) +: 32]);
                end
            end

            for (int i = 0; i < 4; i++) begin
                addr_q.push_back(A_NONCE0 + (i * 4));
                data_q.push_back(base_nonce[(i*32) +: 32]);
            end

            begin
                bit [255:0] wide_trng;

                wide_trng = '0;
                wide_trng[159:0] = base_trng;

                for (int i = 0; i < 5; i++) begin
                    addr_q.push_back(A_TRNG0 + (i * 4));
                    data_q.push_back(wide_trng[(i*32) +: 32]);
                end
            end

            addr_q.push_back(A_BURST_COUNT);
            data_q.push_back(burst_count[31:0]);

            addr_q.push_back(A_CTRL);
            data_q.push_back(CTRL_START | CTRL_ENABLE | CTRL_IRQ_EN);

            ahb_write_stream(addr_q, data_q);

            tx_word_idx = 0;
            rx_word_idx = 0;
            idle_cycles = 0;

            while (rx_word_idx < total_words) begin
                bit progressed;

                progressed = 1'b0;

                // Prefer draining ciphertext if data exists.
                if ((rx_word_idx < total_words) && (vif.dma_ct_req === 1'b1)) begin
                    read_ct_chunk(tr_q, rx_word_idx, total_words);
                    progressed = 1'b1;
                end

                // Then feed plaintext if space exists.
                if ((tx_word_idx < total_words) && (vif.dma_pt_req === 1'b1)) begin
                    write_pt_chunk(tr_q, tx_word_idx, total_words);
                    progressed = 1'b1;
                end

                if (progressed) begin
                    idle_cycles = 0;
                end else begin
                    idle_cycles++;

                    if (idle_cycles > 20000) begin
                        $fatal(1,
                               "[%0t] Stream timeout: tx_word_idx=%0d/%0d rx_word_idx=%0d/%0d dma_pt_req=%0b dma_ct_req=%0b irq=%0b",
                               $time,
                               tx_word_idx,
                               total_words,
                               rx_word_idx,
                               total_words,
                               vif.dma_pt_req,
                               vif.dma_ct_req,
                               vif.irq);
                    end

                    @(posedge vif.HCLK);
                end
            end

            ahb_read(A_BURST_DONE, burst_done);

            if (burst_done[15:0] != burst_count[15:0]) begin
                $fatal(1,
                       "[%0t] BURST_DONE mismatch. Got %0d expected %0d",
                       $time,
                       burst_done[15:0],
                       burst_count);
            end
        endtask


        task run();
            idle_bus();

            forever begin
                aes_ahb_lite_dma_transaction#(MODE) trans;

                gen2drv.get(trans);
                run_one(trans);
            end
        endtask

    endclass


    class aes_ahb_lite_dma_monitor;

        virtual aes_ahb_lite_dma_if vif;

        int legal_access_count;
        int error_response_count;

        function new(virtual aes_ahb_lite_dma_if vif);
            this.vif = vif;
        endfunction

        task run();
            forever begin
                @(vif.mon_cb);

                if (vif.mon_cb.HSEL &&
                    vif.mon_cb.HTRANS[1] &&
                    vif.mon_cb.HREADY &&
                    vif.mon_cb.HREADYOUT) begin
                    legal_access_count++;
                end

                if (vif.mon_cb.HRESP) begin
                    error_response_count++;
                end
            end
        endtask

    endclass


    class aes_ahb_lite_dma_scoreboard #(parameter MODE = 128);

        mailbox drv2scb;

        int transaction_count = 0;
        int block_count       = 0;
        int mismatch_count    = 0;

        function new(mailbox drv2scb);
            this.drv2scb = drv2scb;
        endfunction

        task run();
            aes_ahb_lite_dma_transaction#(MODE) trans;

            bit [255:0] expected_cipher_wide;
            bit [255:0] wide_key;
            bit [255:0] wide_pt;
            bit [127:0] wide_nonce;

            bit [127:0] pt_block[2];
            bit [127:0] ct_block[2];
            bit [127:0] exp_block[2];

            bit [127:0] display_nonce;

            int dma_cycle_num;
            string block_id;

            forever begin
                drv2scb.get(trans);

                trans.sample();

                wide_key   = '0;
                wide_pt    = '0;
                wide_nonce = '0;

                wide_key[MODE-1:0] = trans.key;
                wide_pt            = trans.plain_text;
                wide_nonce         = trans.nonce;

                aes_ctr_ref_model(
                    MODE,
                    2,
                    wide_key,
                    wide_nonce,
                    wide_pt,
                    expected_cipher_wide
                );

                pt_block[0]  = trans.plain_text[127:0];
                pt_block[1]  = trans.plain_text[255:128];

                ct_block[0]  = trans.cipher_text[127:0];
                ct_block[1]  = trans.cipher_text[255:128];

                exp_block[0] = expected_cipher_wide[127:0];
                exp_block[1] = expected_cipher_wide[255:128];

                transaction_count++;
                dma_cycle_num = transaction_count;

                for (int b = 0; b < 2; b++) begin
                    block_count++;

                    display_nonce = trans.nonce;

                    if (b == 1) begin
                        display_nonce[31:0] = display_nonce[31:0] + 32'd1;
                    end

                    block_id = (b == 0) ? "A" : "B";

                    if (ct_block[b] === exp_block[b]) begin
                        $display(
                            "[%0t] [PASS] DMA Cycle %0d Block %s | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h",
                            $time,
                            dma_cycle_num,
                            block_id,
                            pt_block[b],
                            trans.key,
                            display_nonce,
                            ct_block[b]
                        );
                    end else begin
                        mismatch_count++;

                        $error(
                            "[%0t] [FAIL] DMA Cycle %0d Block %s Mismatch | Plaintext: %h | Key: %h | Nonce: %h | Ciphertext: %h | Expected Ciphertext: %h",
                            $time,
                            dma_cycle_num,
                            block_id,
                            pt_block[b],
                            trans.key,
                            display_nonce,
                            ct_block[b],
                            exp_block[b]
                        );
                    end
                end
            end
        endtask

        function void report();
            $display("\n========================================");
            $display(" AES AHB-LITE DMA SCA %0d VERIFICATION REPORT", MODE);
            $display("========================================");
            $display(" Total DMA Transactions : %0d", transaction_count);
            $display(" Total AES Blocks       : %0d", block_count);
            $display(" Mismatches             : %0d", mismatch_count);
            $display(
                " TEST STATUS            : %s",
                (mismatch_count == 0 && transaction_count > 0) ? "PASSED" : "FAILED"
            );
            $display("========================================\n");

            if (mismatch_count > 0 || transaction_count == 0) begin
                $fatal(1, "AES AHB-Lite DMA SCA test failed!");
            end
        endfunction

    endclass

endpackage

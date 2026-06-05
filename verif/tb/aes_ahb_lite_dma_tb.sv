`ifdef AES_AHB_LITE_DMA

module aes_ahb_lite_dma_tb;
    import aes_ahb_lite_dma_pkg::*;

`ifdef AES_256
    parameter MODE = 256;
    `define MODE 256
`elsif AES_192
    parameter MODE = 192;
    `define MODE 192
`else
    parameter MODE = 128;
    `define MODE 128
`endif

`define FIFO_DEPTH 8
`define BURST_CNT_W 32

`ifdef AES_SCA
    `define VER sca
`else
    `define VER sca
`endif

    bit HCLK;
    bit HRESETn;
    int test_count;

    always #5ns HCLK = ~HCLK;

    aes_ahb_lite_dma_if intf(HCLK);

    assign intf.HRESETn = HRESETn;

`ifdef GLS_SIM
    `define DUT_TARGET aes_ahb_lite_dma_```VER``_MODE```MODE``_FIFO_DEPTH```FIFO_DEPTH``_BURST_CNT_W```BURST_CNT_W
`else
    `define DUT_TARGET aes_ahb_lite_dma_```VER``#(```MODE, 8, 32)
`endif

    `DUT_TARGET dut (
        .HCLK       (HCLK),
        .HRESETn    (intf.HRESETn),

        .HSEL       (intf.HSEL),
        .HADDR      (intf.HADDR),
        .HTRANS     (intf.HTRANS),
        .HWRITE     (intf.HWRITE),
        .HSIZE      (intf.HSIZE),
        .HBURST     (intf.HBURST),
        .HPROT      (intf.HPROT),
        .HMASTLOCK  (intf.HMASTLOCK),
        .HWDATA     (intf.HWDATA),
        .HREADY     (intf.HREADY),

        .HRDATA     (intf.HRDATA),
        .HREADYOUT  (intf.HREADYOUT),
        .HRESP      (intf.HRESP),

        .dma_pt_req (intf.dma_pt_req),
        .dma_ct_req (intf.dma_ct_req),
        .irq        (intf.irq)
    );

`ifdef AES_DMA_INTERNAL_DBG
    initial begin
        forever begin
            @(posedge HCLK);

            if (HRESETn) begin
                if (dut.core_start === 1'b1) begin
                    $display("[%0t] [DUT_DBG] core_start pulse observed", $time);
                end

                if (dut.u_aes_ctr_sca.start === 1'b1) begin
                    $display("[%0t] [DUT_DBG] aes_ctr_sca.start observed", $time);
                end
            end
        end
    end
`endif

    initial begin
        mailbox gen2drv = new(10);
        mailbox drv2scb = new();

        aes_ahb_lite_dma_driver#(MODE)     drv;
        aes_ahb_lite_dma_monitor           mon;
        aes_ahb_lite_dma_scoreboard#(MODE) scb;

        aes_ahb_lite_dma_transaction#(MODE) tr_q[$];

        int expected_scoreboard_count;

        drv = new(intf, gen2drv, drv2scb);
        mon = new(intf);
        scb = new(drv2scb);

        if (!$value$plusargs("COUNT=%d", test_count)) begin
            test_count = 100;
        end

        expected_scoreboard_count = test_count;

        $display("[%0t] [DMA_TB_VERSION] continuous-stream AHB-Lite DMA TB", $time);
        $display("[%0t] [TOP] Starting AES AHB-Lite DMA SCA simulation", $time);
        $display("[%0t] [TOP] MODE = %0d", $time, MODE);
        $display("[%0t] [TOP] Continuous DMA bursts = %0d", $time, test_count);
        $display("[%0t] [TOP] Expected scoreboard transactions = %0d",
                 $time, expected_scoreboard_count);
        $display("[%0t] [TOP] Expected AES blocks = %0d",
                 $time, test_count * 2);

        intf.HSEL      = 1'b0;
        intf.HADDR     = 32'd0;
        intf.HTRANS    = HTRANS_IDLE;
        intf.HWRITE    = 1'b0;
        intf.HSIZE     = HSIZE_WORD;
        intf.HBURST    = HBURST_SINGLE;
        intf.HPROT     = HPROT_DATA;
        intf.HMASTLOCK = 1'b0;
        intf.HWDATA    = 32'd0;
        intf.HREADY    = 1'b1;

        HRESETn = 1'b0;
        repeat (5) @(negedge HCLK);
        HRESETn = 1'b1;
        repeat (5) @(posedge HCLK);

        fork
            mon.run();
            scb.run();
        join_none

        for (int i = 0; i < test_count; i++) begin
            aes_ahb_lite_dma_transaction#(MODE) tr;
            tr = new();

            if (!tr.randomize()) begin
                $fatal(1, "Randomization failed at item %0d", i);
            end

            tr_q.push_back(tr);
        end

        drv.run_stream(tr_q);

        wait (scb.transaction_count >= expected_scoreboard_count);

        repeat (10) @(posedge HCLK);

        scb.report();

        $display("[%0t] [TOP] AHB accepted accesses      = %0d",
                 $time, mon.legal_access_count);
        $display("[%0t] [TOP] AHB error-response cycles = %0d",
                 $time, mon.error_response_count);

        $finish;
    end

endmodule

`endif

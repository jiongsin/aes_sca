module aes_ahb_lite_dma_sca #(
    parameter MODE        = 128,
    parameter FIFO_DEPTH  = 8,
    parameter BURST_CNT_W = 32
) (
    input             HCLK,
    input             HRESETn,

    input             HSEL,
    input      [31:0] HADDR,
    input      [1:0]  HTRANS,
    input             HWRITE,
    input      [2:0]  HSIZE,
    input      [2:0]  HBURST,
    input      [3:0]  HPROT,
    input             HMASTLOCK,
    input      [31:0] HWDATA,
    input             HREADY,

    output reg [31:0] HRDATA,
    output            HREADYOUT,
    output            HRESP,

    output            dma_pt_req,
    output            dma_ct_req,
    output            irq
);

    localparam FIFO_AW = $clog2(FIFO_DEPTH);
    localparam KEY_WORDS = MODE / 32;

    // ------------------------------------------------------------
    // Address constants
    // ------------------------------------------------------------
    localparam [7:0] A_CTRL        = 8'h00;
    localparam [7:0] A_STATUS      = 8'h04;
    localparam [7:0] A_PTDATA      = 8'h08;
    localparam [7:0] A_CTDATA      = 8'h0C;
    localparam [7:0] A_PT_LEVEL    = 8'h10;
    localparam [7:0] A_CT_LEVEL    = 8'h14;

    localparam [7:0] A_KEY0        = 8'h18;
    localparam [7:0] A_KEY1        = 8'h1C;
    localparam [7:0] A_KEY2        = 8'h20;
    localparam [7:0] A_KEY3        = 8'h24;
    localparam [7:0] A_KEY4        = 8'h28;
    localparam [7:0] A_KEY5        = 8'h2C;
    localparam [7:0] A_KEY6        = 8'h30;
    localparam [7:0] A_KEY7        = 8'h34;

    localparam [7:0] A_NONCE0      = 8'h40;
    localparam [7:0] A_NONCE1      = 8'h44;
    localparam [7:0] A_NONCE2      = 8'h48;
    localparam [7:0] A_NONCE3      = 8'h4C;

    localparam [7:0] A_TRNG0       = 8'h50;
    localparam [7:0] A_TRNG1       = 8'h54;
    localparam [7:0] A_TRNG2       = 8'h58;
    localparam [7:0] A_TRNG3       = 8'h5C;
    localparam [7:0] A_TRNG4       = 8'h60;

    localparam [7:0] A_IRQ_STATUS  = 8'h70;
    localparam [7:0] A_BURST_COUNT = 8'h74;
    localparam [7:0] A_BURST_DONE  = 8'h78;

    localparam [FIFO_AW:0] FIFO_DEPTH_COUNT = FIFO_DEPTH;
    localparam [FIFO_AW:0] BURST_WORDS      = 8;

    // ------------------------------------------------------------
    // Sticky status bit indexes
    // ------------------------------------------------------------
    localparam ST_DONE             = 1;
    localparam ST_PT_OVERFLOW      = 7;
    localparam ST_CT_UNDERFLOW     = 8;
    localparam ST_BURST_ZERO       = 11;
    localparam ST_COUNTER_OVERFLOW = 12;
    localparam ST_ILLEGAL_ACCESS   = 13;

    // ------------------------------------------------------------
    // AHB-Lite response generation
    // ------------------------------------------------------------
    localparam [1:0] ERR_NONE   = 2'd0;
    localparam [1:0] ERR_FIRST  = 2'd1;
    localparam [1:0] ERR_SECOND = 2'd2;

    reg [1:0] err_state;

    assign HREADYOUT = (err_state != ERR_FIRST);
    assign HRESP     = (err_state != ERR_NONE);

    wire hready_accept = HREADY & HREADYOUT;
    wire ahb_addr_phase = HSEL & hready_accept & HTRANS[1];

    // HMASTLOCK, HBURST, and HPROT are accepted as AHB-Lite signals.
    // This slave does not need locked-transfer or protection behavior internally.

    // ------------------------------------------------------------
    // Legal access decode in address phase
    // ------------------------------------------------------------
    wire addr_word_aligned = (HADDR[1:0] == 2'b00);
    wire size_word         = (HSIZE == 3'b010);

    wire [7:0] addr8 = HADDR[7:0];

    wire is_key_addr =
        (addr8 == A_KEY0) || (addr8 == A_KEY1) ||
        (addr8 == A_KEY2) || (addr8 == A_KEY3) ||
        (addr8 == A_KEY4) || (addr8 == A_KEY5) ||
        (addr8 == A_KEY6) || (addr8 == A_KEY7);

    wire is_nonce_addr =
        (addr8 == A_NONCE0) || (addr8 == A_NONCE1) ||
        (addr8 == A_NONCE2) || (addr8 == A_NONCE3);

    wire is_trng_addr =
        (addr8 == A_TRNG0) || (addr8 == A_TRNG1) ||
        (addr8 == A_TRNG2) || (addr8 == A_TRNG3) ||
        (addr8 == A_TRNG4);

    wire readable_addr =
        (addr8 == A_CTRL)        ||
        (addr8 == A_STATUS)      ||
        (addr8 == A_CTDATA)      ||
        (addr8 == A_PT_LEVEL)    ||
        (addr8 == A_CT_LEVEL)    ||
        is_key_addr              ||
        is_nonce_addr            ||
        is_trng_addr             ||
        (addr8 == A_IRQ_STATUS)  ||
        (addr8 == A_BURST_COUNT) ||
        (addr8 == A_BURST_DONE);

    wire writable_addr =
        (addr8 == A_CTRL)        ||
        (addr8 == A_PTDATA)      ||
        is_key_addr              ||
        is_nonce_addr            ||
        is_trng_addr             ||
        (addr8 == A_IRQ_STATUS)  ||
        (addr8 == A_BURST_COUNT);

    wire direction_legal = HWRITE ? writable_addr : readable_addr;

    wire ahb_addr_legal =
        size_word &&
        addr_word_aligned &&
        direction_legal;

    // ------------------------------------------------------------
    // AHB-Lite address/control phase capture
    //
    // Correct AHB-Lite write pairing:
    //   ahb_addr_d / ahb_write_d = previous accepted address/control phase
    //   ahb_wdata_phase          = current HWDATA data phase
    // ------------------------------------------------------------
    reg       ahb_write_d;
    reg       ahb_valid_d;
    reg       ahb_legal_d;
    reg [7:0] ahb_addr_d;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ahb_write_d <= 1'b0;
            ahb_valid_d <= 1'b0;
            ahb_legal_d <= 1'b0;
            ahb_addr_d  <= 8'd0;
        end else begin
            ahb_valid_d <= 1'b0;

            if (ahb_addr_phase) begin
                ahb_write_d <= HWRITE;
                ahb_addr_d  <= HADDR[7:0];
                ahb_legal_d <= ahb_addr_legal;
                ahb_valid_d <= 1'b1;
            end
        end
    end

    wire ahb_wr = ahb_valid_d &  ahb_write_d & ahb_legal_d & (err_state == ERR_NONE);
    wire ahb_rd = ahb_valid_d & ~ahb_write_d & ahb_legal_d & (err_state == ERR_NONE);

    wire [31:0] ahb_wdata_phase = HWDATA;

    // ------------------------------------------------------------
    // ERROR response FSM
    // ------------------------------------------------------------
    wire illegal_data_phase = ahb_valid_d & ~ahb_legal_d & (err_state == ERR_NONE);

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            err_state <= ERR_NONE;
        end else begin
            case (err_state)
                ERR_NONE: begin
                    if (illegal_data_phase) begin
                        err_state <= ERR_FIRST;
                    end
                end

                ERR_FIRST: begin
                    err_state <= ERR_SECOND;
                end

                ERR_SECOND: begin
                    err_state <= ERR_NONE;
                end

                default: begin
                    err_state <= ERR_NONE;
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Configuration registers
    // ------------------------------------------------------------
    reg        ctrl_enable;
    reg        ctrl_auto_start;
    reg        ctrl_dec_mode;
    reg        ctrl_irq_en;

    reg [31:0] key_word [0:KEY_WORDS-1];

    reg [127:0] nonce_reg;
    reg [159:0] trng_reg;

    reg [BURST_CNT_W-1:0] burst_count_reg;
    reg [BURST_CNT_W-1:0] burst_done_count;

    reg [127:0] nonce_work_reg;
    reg [159:0] trng_work_reg;

    wire [MODE-1:0] key_to_core;

    genvar key_g;
    generate
        for (key_g = 0; key_g < KEY_WORDS; key_g = key_g + 1) begin : g_key_pack
            assign key_to_core[(key_g*32) +: 32] = key_word[key_g];
        end
    endgenerate

    wire [2:0] key_word_idx = (ahb_addr_d - A_KEY0) >> 2;

    wire is_key_addr_d =
        (ahb_addr_d == A_KEY0) || (ahb_addr_d == A_KEY1) ||
        (ahb_addr_d == A_KEY2) || (ahb_addr_d == A_KEY3) ||
        (ahb_addr_d == A_KEY4) || (ahb_addr_d == A_KEY5) ||
        (ahb_addr_d == A_KEY6) || (ahb_addr_d == A_KEY7);

    // ------------------------------------------------------------
    // Xorshift helper for working TRNG seed evolution
    // ------------------------------------------------------------
    function [31:0] xs32;
        input [31:0] in_val;
        reg [31:0] t1;
        reg [31:0] t2;
        begin
            t1   = in_val ^ (in_val << 13);
            t2   = t1     ^ (t1 >> 17);
            xs32 = t2     ^ (t2 << 5);
        end
    endfunction

    function [159:0] evolve_trng_seed;
        input [159:0] s;
        begin
            evolve_trng_seed = {
                xs32(s[159:128] ^ 32'hA5A5_0004),
                xs32(s[127:96]  ^ 32'hA5A5_0003),
                xs32(s[95:64]   ^ 32'hA5A5_0002),
                xs32(s[63:32]   ^ 32'hA5A5_0001),
                xs32(s[31:0]    ^ 32'hA5A5_0000)
            };
        end
    endfunction

    // ------------------------------------------------------------
    // FIFOs
    // ------------------------------------------------------------
    wire [31:0] pt_dout;
    wire [31:0] ct_dout;

    wire pt_empty;
    wire pt_full;
    wire ct_empty;
    wire ct_full;

    wire [FIFO_AW:0] pt_level;
    wire [FIFO_AW:0] ct_level;
    wire [FIFO_AW:0] ct_free = FIFO_DEPTH_COUNT - ct_level;

    wire fifo_clear_write = ahb_wr & (ahb_addr_d == A_CTRL) & ahb_wdata_phase[8];
    wire fifo_clear       = fifo_clear_write;

    wire pt_wr_from_ahb   = ahb_wr & (ahb_addr_d == A_PTDATA) & ~pt_full;
    wire pt_wr_overflow   = ahb_wr & (ahb_addr_d == A_PTDATA) &  pt_full;

    wire ct_rd_from_ahb   = ahb_rd & (ahb_addr_d == A_CTDATA) & ~ct_empty;
    wire ct_rd_underflow  = ahb_rd & (ahb_addr_d == A_CTDATA) &  ct_empty;

    wire core_valid_out;
    wire [31:0] core_ct_out;

    wire pt_rd_to_core    = core_valid_out;
    wire ct_wr_from_core  = core_valid_out & ~ct_full;

    sync_fifo_fwft_dma #(
        .WIDTH(32),
        .DEPTH(FIFO_DEPTH)
    ) u_pt_fifo (
        .clk   (HCLK),
        .rst_n (HRESETn),
        .clear (fifo_clear),
        .push  (pt_wr_from_ahb),
        .din   (ahb_wdata_phase),
        .pop   (pt_rd_to_core),
        .dout  (pt_dout),
        .empty (pt_empty),
        .full  (pt_full),
        .level (pt_level)
    );

    sync_fifo_fwft_dma #(
        .WIDTH(32),
        .DEPTH(FIFO_DEPTH)
    ) u_ct_fifo (
        .clk   (HCLK),
        .rst_n (HRESETn),
        .clear (fifo_clear),
        .push  (ct_wr_from_core),
        .din   (core_ct_out),
        .pop   (ct_rd_from_ahb),
        .dout  (ct_dout),
        .empty (ct_empty),
        .full  (ct_full),
        .level (ct_level)
    );

    assign dma_pt_req = ~pt_full;
    assign dma_ct_req = ~ct_empty;

    // ------------------------------------------------------------
    // Job/core control
    // ------------------------------------------------------------
    reg job_active;
    reg core_active;
    reg [2:0] out_word_count;

    reg core_start_q;

    wire burst_count_zero = (burst_count_reg == {BURST_CNT_W{1'b0}});

    wire can_launch_burst =
        ctrl_enable &&
        job_active &&
        !core_active &&
        !core_start_q &&
        !burst_count_zero &&
        (burst_done_count < burst_count_reg) &&
        (pt_level >= BURST_WORDS) &&
        (ct_free  >= BURST_WORDS);

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            core_start_q <= 1'b0;
        end else begin
            core_start_q <= can_launch_burst;
        end
    end

    wire core_start    = core_start_q;
    wire core_valid_in = core_active & ~pt_empty & ~ct_full;
    wire core_stop     = 1'b1;

    aes_ctr_sca #(
        .MODE(MODE)
    ) u_aes_ctr_sca (
        .clk       (HCLK),
        .rst_n     (HRESETn),
        .start     (core_start),
        .valid_in  (core_valid_in),
        .trng_in   (trng_work_reg),
        .key_in    (key_to_core),
        .nonce_in  (nonce_work_reg),
        .pt_in     (pt_dout),
        .stop      (core_stop),
        .valid_out (core_valid_out),
        .ct_out    (core_ct_out)
    );

    wire burst_last_word =
        core_active & core_valid_out & (out_word_count == 3'd7);

    wire [BURST_CNT_W-1:0] burst_count_minus_one =
        burst_count_reg - {{(BURST_CNT_W-1){1'b0}}, 1'b1};

    wire final_burst = (burst_done_count == burst_count_minus_one);

    wire counter_overflow_event =
        burst_last_word &&
        ((nonce_work_reg[31:0] == 32'hFFFF_FFFF) ||
         (nonce_work_reg[31:0] == 32'hFFFF_FFFE));

    // ------------------------------------------------------------
    // Sticky status / IRQ
    // ------------------------------------------------------------
    reg [13:0] sticky_status;

    assign irq = ctrl_irq_en &
                 (sticky_status[ST_DONE]             |
                  sticky_status[ST_PT_OVERFLOW]      |
                  sticky_status[ST_CT_UNDERFLOW]     |
                  sticky_status[ST_COUNTER_OVERFLOW] |
                  sticky_status[ST_BURST_ZERO]       |
                  sticky_status[ST_ILLEGAL_ACCESS]);

    // ------------------------------------------------------------
    // Main register/control update
    // ------------------------------------------------------------
    integer rst_i;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ctrl_enable      <= 1'b0;
            ctrl_auto_start  <= 1'b0;
            ctrl_dec_mode    <= 1'b0;
            ctrl_irq_en      <= 1'b0;

            for (rst_i = 0; rst_i < KEY_WORDS; rst_i = rst_i + 1) begin
                key_word[rst_i] <= 32'd0;
            end

            nonce_reg        <= 128'd0;
            trng_reg         <= 160'd0;

            burst_count_reg  <= {{(BURST_CNT_W-1){1'b0}}, 1'b1};
            burst_done_count <= {BURST_CNT_W{1'b0}};

            nonce_work_reg   <= 128'd0;
            trng_work_reg    <= 160'd0;

            job_active       <= 1'b0;
            core_active      <= 1'b0;
            out_word_count   <= 3'd0;

            sticky_status    <= 14'd0;
        end else begin
            if (pt_wr_overflow) begin
                sticky_status[ST_PT_OVERFLOW] <= 1'b1;
            end

            if (ct_rd_underflow) begin
                sticky_status[ST_CT_UNDERFLOW] <= 1'b1;
            end

            if (counter_overflow_event) begin
                sticky_status[ST_COUNTER_OVERFLOW] <= 1'b1;
            end

            if (illegal_data_phase) begin
                sticky_status[ST_ILLEGAL_ACCESS] <= 1'b1;
            end

            if (ahb_wr) begin
                if (is_key_addr_d) begin
                    if (key_word_idx < KEY_WORDS) begin
                        key_word[key_word_idx] <= ahb_wdata_phase;
                    end
                end else begin
                    case (ahb_addr_d)
                        A_CTRL: begin
                            ctrl_enable     <= ahb_wdata_phase[1];
                            ctrl_auto_start <= ahb_wdata_phase[2];
                            ctrl_dec_mode   <= ahb_wdata_phase[3];
                            ctrl_irq_en     <= ahb_wdata_phase[4];

                            if (ahb_wdata_phase[0]) begin
                                sticky_status[ST_DONE] <= 1'b0;
                                burst_done_count       <= {BURST_CNT_W{1'b0}};

                                nonce_work_reg <= nonce_reg;
                                trng_work_reg  <= trng_reg;

                                if (burst_count_zero) begin
                                    job_active                    <= 1'b0;
                                    core_active                   <= 1'b0;
                                    sticky_status[ST_BURST_ZERO] <= 1'b1;
                                end else begin
                                    job_active     <= 1'b1;
                                    core_active    <= 1'b0;
                                    out_word_count <= 3'd0;
                                end
                            end

                            if (ahb_wdata_phase[8]) begin
                                job_active       <= 1'b0;
                                core_active      <= 1'b0;
                                out_word_count   <= 3'd0;
                                burst_done_count <= {BURST_CNT_W{1'b0}};
                                sticky_status    <= 14'd0;
                            end
                        end

                        A_NONCE0: nonce_reg[31:0]    <= ahb_wdata_phase;
                        A_NONCE1: nonce_reg[63:32]   <= ahb_wdata_phase;
                        A_NONCE2: nonce_reg[95:64]   <= ahb_wdata_phase;
                        A_NONCE3: nonce_reg[127:96]  <= ahb_wdata_phase;

                        A_TRNG0:  trng_reg[31:0]     <= ahb_wdata_phase;
                        A_TRNG1:  trng_reg[63:32]    <= ahb_wdata_phase;
                        A_TRNG2:  trng_reg[95:64]    <= ahb_wdata_phase;
                        A_TRNG3:  trng_reg[127:96]   <= ahb_wdata_phase;
                        A_TRNG4:  trng_reg[159:128]  <= ahb_wdata_phase;

                        A_IRQ_STATUS: begin
                            if (ahb_wdata_phase[ST_DONE])
                                sticky_status[ST_DONE] <= 1'b0;
                            if (ahb_wdata_phase[ST_PT_OVERFLOW])
                                sticky_status[ST_PT_OVERFLOW] <= 1'b0;
                            if (ahb_wdata_phase[ST_CT_UNDERFLOW])
                                sticky_status[ST_CT_UNDERFLOW] <= 1'b0;
                            if (ahb_wdata_phase[ST_BURST_ZERO])
                                sticky_status[ST_BURST_ZERO] <= 1'b0;
                            if (ahb_wdata_phase[ST_COUNTER_OVERFLOW])
                                sticky_status[ST_COUNTER_OVERFLOW] <= 1'b0;
                            if (ahb_wdata_phase[ST_ILLEGAL_ACCESS])
                                sticky_status[ST_ILLEGAL_ACCESS] <= 1'b0;
                        end

                        A_BURST_COUNT: begin
                            burst_count_reg <= ahb_wdata_phase[BURST_CNT_W-1:0];
                        end

                        default: begin end
                    endcase
                end
            end

            if (core_start) begin
                core_active    <= 1'b1;
                out_word_count <= 3'd0;
            end

            if (core_valid_out) begin
                if (out_word_count == 3'd7) begin
                    out_word_count <= 3'd0;
                    core_active    <= 1'b0;

                    burst_done_count <= burst_done_count +
                                        {{(BURST_CNT_W-1){1'b0}}, 1'b1};

                    if (final_burst) begin
                        job_active             <= 1'b0;
                        sticky_status[ST_DONE] <= 1'b1;
                    end else begin
                        nonce_work_reg[31:0] <= nonce_work_reg[31:0] + 32'd2;
                        trng_work_reg        <= evolve_trng_seed(trng_work_reg);
                    end
                end else begin
                    out_word_count <= out_word_count + 3'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Read data
    // ------------------------------------------------------------
    wire [31:0] ctrl_word = {
        23'd0,
        1'b0,
        3'd0,
        ctrl_irq_en,
        ctrl_dec_mode,
        ctrl_auto_start,
        ctrl_enable,
        1'b0
    };

    wire [31:0] status_word = {
        18'd0,
        sticky_status[ST_ILLEGAL_ACCESS],
        sticky_status[ST_COUNTER_OVERFLOW],
        sticky_status[ST_BURST_ZERO],
        job_active,
        ctrl_dec_mode,
        sticky_status[ST_CT_UNDERFLOW],
        sticky_status[ST_PT_OVERFLOW],
        irq,
        ct_full,
        ct_empty,
        pt_full,
        pt_empty,
        sticky_status[ST_DONE],
        core_active
    };

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HRDATA <= 32'd0;
        end else begin
            if (err_state != ERR_NONE) begin
                HRDATA <= 32'd0;
            end else if (ahb_rd) begin
                if (is_key_addr_d) begin
                    if (key_word_idx < KEY_WORDS) begin
                        HRDATA <= key_word[key_word_idx];
                    end else begin
                        HRDATA <= 32'd0;
                    end
                end else begin
                    case (ahb_addr_d)
                        A_CTRL:        HRDATA <= ctrl_word;
                        A_STATUS:      HRDATA <= status_word;
                        A_CTDATA:      HRDATA <= ct_empty ? 32'd0 : ct_dout;
                        A_PT_LEVEL:    HRDATA <= {{(32-(FIFO_AW+1)){1'b0}}, pt_level};
                        A_CT_LEVEL:    HRDATA <= {{(32-(FIFO_AW+1)){1'b0}}, ct_level};

                        A_NONCE0:      HRDATA <= nonce_reg[31:0];
                        A_NONCE1:      HRDATA <= nonce_reg[63:32];
                        A_NONCE2:      HRDATA <= nonce_reg[95:64];
                        A_NONCE3:      HRDATA <= nonce_reg[127:96];

                        A_TRNG0:       HRDATA <= trng_reg[31:0];
                        A_TRNG1:       HRDATA <= trng_reg[63:32];
                        A_TRNG2:       HRDATA <= trng_reg[95:64];
                        A_TRNG3:       HRDATA <= trng_reg[127:96];
                        A_TRNG4:       HRDATA <= trng_reg[159:128];

                        A_IRQ_STATUS:  HRDATA <= status_word;
                        A_BURST_COUNT: HRDATA <= {{(32-BURST_CNT_W){1'b0}}, burst_count_reg};
                        A_BURST_DONE:  HRDATA <= {{(32-BURST_CNT_W){1'b0}}, burst_done_count};

                        default:       HRDATA <= 32'd0;
                    endcase
                end
            end
        end
    end

endmodule


module sync_fifo_fwft_dma #(
    parameter WIDTH = 32,
    parameter DEPTH = 8
) (
    input                  clk,
    input                  rst_n,
    input                  clear,
    input                  push,
    input      [WIDTH-1:0] din,
    input                  pop,
    output     [WIDTH-1:0] dout,
    output                 empty,
    output                 full,
    output reg [$clog2(DEPTH):0] level
);

    localparam AW = $clog2(DEPTH);

    localparam [AW:0] DEPTH_COUNT = DEPTH;

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr;
    reg [AW-1:0] rd_ptr;

    wire do_push = push & ~full;
    wire do_pop  = pop  & ~empty;

    wire [AW-1:0] wr_ptr_next =
        (wr_ptr == DEPTH-1) ? {AW{1'b0}} :
        (wr_ptr + {{(AW-1){1'b0}}, 1'b1});

    wire [AW-1:0] rd_ptr_next =
        (rd_ptr == DEPTH-1) ? {AW{1'b0}} :
        (rd_ptr + {{(AW-1){1'b0}}, 1'b1});

    assign empty = (level == {AW+1{1'b0}});
    assign full  = (level == DEPTH_COUNT);
    assign dout  = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            level  <= {AW+1{1'b0}};
        end else if (clear) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            level  <= {AW+1{1'b0}};
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr_next;
            end

            if (do_pop) begin
                rd_ptr <= rd_ptr_next;
            end

            case ({do_push, do_pop})
                2'b10:   level <= level + {{AW{1'b0}}, 1'b1};
                2'b01:   level <= level - {{AW{1'b0}}, 1'b1};
                default: level <= level;
            endcase
        end
    end

endmodule

interface aes_sbox_if(input logic clk);
    `ifdef AES_SCA
        logic [7:0] data_in_0;
        logic [7:0] data_in_1;
        logic [35:0] random_bits;
        logic [7:0] data_out_0;
        logic [7:0] data_out_1;
    `else
        logic [7:0] data_in;
        logic [7:0] data_out;
    `endif
    
    clocking drv_cb @(posedge clk);
        default output #2ns;
        `ifdef AES_SCA
            output data_in_0;
            output data_in_1;
            output random_bits;
        `else
            output data_in;
        `endif
    endclocking
    
    clocking mon_cb @(posedge clk);
        default input #2ns;
        `ifdef AES_SCA
            input data_in_0;
            input data_in_1;
            input random_bits;
            input data_out_0;
            input data_out_1;
        `else
            input data_in;
            input data_out;
        `endif
    endclocking
endinterface


interface aes_operation_if #(parameter MODE = 128) (input logic clk);
    logic rst_n;
    logic valid_in;
    logic [31:0] key_in;
    logic [31:0] data_in;
    logic [31:0] data_out;
    `ifdef AES_SCA
    logic [143:0] random_bits;
    `endif
    logic valid_out;

    clocking drv_cb @(posedge clk);
        default input #3ns output #2ns;
        output valid_in, key_in, data_in `ifdef AES_SCA , random_bits `endif;
        input  valid_out, data_out;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #5ns output #0;
        input valid_in, key_in, data_in `ifdef AES_SCA , random_bits `endif;
        input valid_out, data_out;
    endclocking
endinterface


interface aes_prng_if (input logic clk);
    logic rst_n;

    // revised: full TRNG seed
    logic [159:0] trng_in;
    logic trng_valid;
    logic [143:0] random_out;

    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output trng_in, trng_valid;
        input random_out;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1ns output #0;
        input rst_n, trng_in, trng_valid, random_out;
    endclocking
endinterface


interface aes_ctr_if #(parameter MODE = 128) (input logic clk);
    logic rst_n;
    logic start;
    logic valid_in;
`ifdef AES_SCA
    logic [159:0] trng_in;
`endif
    logic [MODE-1:0] key_in;
    logic [127:0] nonce_in;
    logic [31:0] pt_in;
    logic stop;
    logic valid_out;
    logic [31:0] ct_out;

    clocking drv_cb @(posedge clk);
        output start, valid_in, `ifdef AES_SCA trng_in, `endif key_in, nonce_in, pt_in, stop;
        input valid_out, ct_out;
    endclocking

    clocking mon_cb @(posedge clk);
        input start, valid_in, `ifdef AES_SCA trng_in, `endif key_in, nonce_in, pt_in, stop, valid_out, ct_out;
    endclocking
endinterface


interface aes_ahb_lite_dma_if(input logic HCLK);
    logic        HRESETn;

    logic        HSEL;
    logic [31:0] HADDR;
    logic [1:0]  HTRANS;
    logic        HWRITE;
    logic [2:0]  HSIZE;
    logic [2:0]  HBURST;
    logic [3:0]  HPROT;
    logic        HMASTLOCK;
    logic [31:0] HWDATA;
    logic        HREADY;

    logic [31:0] HRDATA;
    logic        HREADYOUT;
    logic        HRESP;

    logic        dma_pt_req;
    logic        dma_ct_req;
    logic        irq;

    clocking drv_cb @(posedge HCLK);
        default input #3ns output #2ns;
        output HSEL, HADDR, HTRANS, HWRITE, HSIZE, HBURST, HPROT, HMASTLOCK, HWDATA, HREADY;
        input HRDATA, HREADYOUT, HRESP;
        input dma_pt_req, dma_ct_req, irq;
    endclocking

    clocking mon_cb @(posedge HCLK);
        default input #5ns output #0;
        input HSEL, HADDR, HTRANS, HWRITE, HSIZE, HBURST, HPROT, HMASTLOCK, HWDATA, HREADY;
        input HRDATA, HREADYOUT, HRESP;
        input dma_pt_req, dma_ct_req, irq;
    endclocking
endinterface

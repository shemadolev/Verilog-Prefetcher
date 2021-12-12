`resetall
`timescale 1ns / 1ps

`include "print.svh"
`include "utils.svh"

module prefetcherTop_aw_flush();

localparam ADDR_SIZE_ENCODE = 4;
localparam ADDR_WIDTH = 1<<ADDR_SIZE_ENCODE; 
localparam QUEUE_WIDTH = 3'd3; 
localparam WATCHDOG_SIZE = 10'd10; 
localparam BURST_LEN_WIDTH = 4'd8; 
localparam ID_WIDTH = 4'd8; 
localparam DATA_SIZE_ENCODE = 3'd0;
localparam DATA_WIDTH = (1<<DATA_SIZE_ENCODE)<<3;
localparam STRB_WIDTH = (DATA_WIDTH/8);
localparam PROMISE_WIDTH = 3'd3; 
localparam PIPELINE_OUTPUT = 0;
localparam PRFETCH_FRQ_WIDTH = 3'd6;

//########### prefetcherTop ###########//
    // + axi signals (prefetcher<->DDR)
logic                       clk;
logic                       en; 
logic                       resetN;
logic                       s_ar_valid;
logic                       s_ar_ready;
logic [0:BURST_LEN_WIDTH-1] s_ar_len;
logic [0:ADDR_WIDTH-1]       s_ar_addr; 
logic [0:ID_WIDTH-1]       s_ar_id;
logic                       m_ar_valid;
logic                       m_ar_ready;
logic [0:BURST_LEN_WIDTH-1] m_ar_len;
logic [0:ADDR_WIDTH-1]       m_ar_addr;
logic [0:ID_WIDTH-1]       m_ar_id;
logic                       s_r_valid;
logic                       s_r_ready;
logic                       s_r_last;
logic [0:DATA_WIDTH-1]      s_r_data;
logic [0:ID_WIDTH-1]       s_r_id;
logic                       m_r_valid;
logic                       m_r_ready;
logic                       m_r_last;
logic [0:DATA_WIDTH-1]      m_r_data;
logic [0:ID_WIDTH-1]       m_r_id;
logic                       s_aw_valid;
logic                       s_aw_ready;
logic [0:ADDR_WIDTH-1]       s_aw_addr;
logic [0:ID_WIDTH-1]       s_aw_id;
logic                       m_aw_valid;
logic                       m_aw_ready;
logic [0:ADDR_WIDTH-1]       bar;
logic [0:ADDR_WIDTH-1]       limit;
logic [0:QUEUE_WIDTH]       windowSize;
logic [0:WATCHDOG_SIZE-1]   watchdogCnt; 
logic [0:PRFETCH_FRQ_WIDTH-1] crs_prefetch_freq;
logic [0:QUEUE_WIDTH-1]     crs_almostFullSpacer;
logic [0:2]                 errorCode;

//########### axi-dram ###########//
logic                   rst;

//These are not checked, assign some contants for valid/ready
logic [ADDR_WIDTH-1:0]  s_axi_awaddr;
logic [7:0]             s_axi_awlen;
logic [DATA_WIDTH-1:0]  s_axi_wdata;
logic [STRB_WIDTH-1:0]  s_axi_wstrb;
logic                   s_axi_wlast;
logic                   s_axi_wvalid;
logic                   s_axi_wready;

logic [ID_WIDTH-1:0]    s_axi_bid;
logic [1:0]             s_axi_bresp; //dram's output - always 2'b00, no error can be sent
logic                   s_axi_bvalid;
logic                   s_axi_bready;


logic [1:0]             s_axi_rresp;

prefetcherTop #(
.ADDR_BITS(ADDR_WIDTH),
.LOG_QUEUE_SIZE(QUEUE_WIDTH),
.WATCHDOG_SIZE(WATCHDOG_SIZE),
.BURST_LEN_WIDTH(BURST_LEN_WIDTH),
.TID_WIDTH(ID_WIDTH),
.LOG_BLOCK_DATA_BYTES(DATA_SIZE_ENCODE),
.PROMISE_WIDTH(PROMISE_WIDTH),
.PRFETCH_FRQ_WIDTH(PRFETCH_FRQ_WIDTH)
) prefetcherTop_dut (
    .clk(clk),
    .en(en), 
    .resetN(resetN),
    .s_ar_valid(s_ar_valid),
    .s_ar_ready(s_ar_ready),
    .s_ar_len(s_ar_len),
    .s_ar_addr(s_ar_addr), 
    .s_ar_id(s_ar_id),
    .m_ar_valid(m_ar_valid),
    .m_ar_ready(m_ar_ready),
    .m_ar_len(m_ar_len),
    .m_ar_addr(m_ar_addr),
    .m_ar_id(m_ar_id),
    .s_r_valid(s_r_valid),
    .s_r_ready(s_r_ready),
    .s_r_last(s_r_last),
    .s_r_data(s_r_data),
    .s_r_id(s_r_id),
    .m_r_valid(m_r_valid),
    .m_r_ready(m_r_ready),
    .m_r_last(m_r_last),
    .m_r_data(m_r_data),
    .m_r_id(m_r_id),
    .s_aw_valid(s_aw_valid),
    .s_aw_ready(s_aw_ready),
    .s_aw_addr(s_aw_addr),
    .s_aw_id(s_aw_id),
    .m_aw_valid(m_aw_valid),
    .m_aw_ready(m_aw_ready),
    .bar(bar),
    .limit(limit),
    .windowSize(windowSize),
    .watchdogCnt(watchdogCnt), 
    .crs_almostFullSpacer(crs_almostFullSpacer),
    .crs_prefetch_freq(crs_prefetch_freq),
    .errorCode(errorCode)
);

axi_ram #
(
    // Width of data bus in bits
    .DATA_WIDTH(DATA_WIDTH),
    // Width of address bus in bits
    .ADDR_WIDTH(ADDR_WIDTH),
    // Width of ID signal
    .ID_WIDTH(ID_WIDTH),
    // Extra pipeline register on output
    .PIPELINE_OUTPUT(PIPELINE_OUTPUT)
) axi_ram_inst (
    .clk(clk),
    .rst(rst),
    .s_axi_awid(s_aw_id),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awlen(s_axi_awlen),
    .s_axi_awsize(DATA_SIZE_ENCODE),
    .s_axi_awburst(2'b01),
    .s_axi_awlock(1'b0), //Irrelevant when accessing a single port
    .s_axi_awcache(4'b0000),
    .s_axi_awprot(3'b000),
    .s_axi_awvalid(m_aw_valid),
    .s_axi_awready(m_aw_ready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wlast(s_axi_wlast),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bid(s_axi_bid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_arid(m_ar_id),// read request
    .s_axi_araddr(m_ar_addr),
    .s_axi_arlen(m_ar_len),
    .s_axi_arsize(DATA_SIZE_ENCODE),
    .s_axi_arburst(2'b01), //INC burst type, the only type supported by NVDLA
    .s_axi_arlock(1'b0), //Irrelevant when accessing a single port
    .s_axi_arcache(4'b0000), // Irrelevant, used for caching attributes
    .s_axi_arprot(3'b000), // Irrelevant, used for access premissions 
    .s_axi_arvalid(m_ar_valid),
    .s_axi_arready(m_ar_ready),
    .s_axi_rid(m_r_id), //read data
    .s_axi_rdata(m_r_data),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rlast(m_r_last),
    .s_axi_rvalid(m_r_valid),
    .s_axi_rready(m_r_ready)
);

assign rst = ~resetN;

assign s_axi_awaddr = s_aw_addr;
assign s_axi_wstrb = {STRB_WIDTH{1'b1}};
assign s_axi_bready = 1'b1;


localparam clock_period=20;
initial begin
    clk <= '0;
    forever begin
        #(clock_period/2) clk = ~clk;
    end
end

localparam timeout=100000;
initial begin
    #(timeout) $finish;
end

initial begin
    localparam BASE_ADDR = 16'h0eef;
    localparam REQ_NUM = 3;
    localparam RD_LEN = 0;
    localparam STRIDE = 3;
    localparam TRANS_ID = 5; 
    localparam WR_LEN = 99;
    resetN = 1'b0;
    en = 1'b1;

//CR Space
        // Ctrl
    watchdogCnt = 10'd1000;
    bar = 0;
    limit = BASE_ADDR * 2;
    windowSize = {{(QUEUE_WIDTH-2){1'b0}}, 2'd3};
    crs_prefetch_freq = 10;
        // Data
    crs_almostFullSpacer={{(QUEUE_WIDTH-2){1'b0}}, 2'd2};

    s_aw_valid = 1'b0;
    s_axi_wvalid = 1'b0;
    s_ar_valid = 1'b0;
    s_r_ready = 1'b0;

    #clock_period;
    resetN=1'b1;

    //AW of initial data (sequential of 0->(WR_LEN-1))
    s_aw_addr = BASE_ADDR; // +i increment
    s_aw_id = TRANS_ID;
    s_axi_awlen = WR_LEN; 

    `TRANSACTION(s_aw_valid,s_aw_ready)

    //Write data
    s_axi_wlast = 1'b0;
	for(int i=0;i<s_axi_awlen;i++) begin
	    s_axi_wdata = i;
        `TRANSACTION(s_axi_wvalid,s_axi_wready)
	end

	s_axi_wdata = s_axi_awlen;
	s_axi_wlast = 1'b1;
	`TRANSACTION(s_axi_wvalid,s_axi_wready)

    //Write response (B) should be returned, but not caught

    for (int i=0; i<REQ_NUM; i++) begin
        //Read req of BASE_ADDR
        s_ar_addr = BASE_ADDR + i * STRIDE;
        s_ar_len = RD_LEN;
        s_ar_id = TRANS_ID;

        `TRANSACTION(s_ar_valid,s_ar_ready)

        #(clock_period*6);
    end
    
    s_r_ready = 1'b1;

    #(clock_period*100);

    //Write req to move the prefetcher to st_cleanup
    s_aw_addr = BASE_ADDR;
    s_aw_id = {{(ID_WIDTH-3){1'b0}}, 3'd5};
    s_axi_awlen = RD_LEN; //BURST=1
 
    `TRANSACTION(s_aw_valid,s_aw_ready)

    //Write data
    s_axi_wdata = 0;
    s_axi_wlast = 1'b0;
	
    `TRANSACTION(s_axi_wvalid,s_axi_wready)
      
    while(prefetcherTop_dut.pr_r_valid) begin
        #clock_period;
    end 
      
    $finish;
end

endmodule
`resetall

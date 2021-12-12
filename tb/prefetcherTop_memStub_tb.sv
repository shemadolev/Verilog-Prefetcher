`resetall
`timescale 1ns / 1ps

`define printTop(MOD) \
    $display("------- BEGIN Top --------"); \
    $display("  sel_ar_pr %b",MOD.sel_ar_pr); \
    $display("  sel_r_pr %b",MOD.sel_r_pr); \
    $display("  ctrlFlush %b",MOD.ctrlFlush); \
    $display("------- END Top --------")

`define printData(MOD)  \
    $display("------- BEGIN Data --------"); \
    $display("  opCode %d",MOD.reqOpcode); \
    $display("  almostFull %b",MOD.almostFull); \
    $display("  errorCode %d",MOD.errorCode); \
    $display("  prefetchReqCnt %d",MOD.prefetchReqCnt); \
    $display("  head:%d tail:%d validCnt:%d isEmpty:%d isFull:%d",MOD.headPtr, MOD.tailPtr, MOD.validCnt, MOD.isEmpty, MOD.isFull); \
    $display("  hasOutstanding:%b burstOffset:%d readDataPtr:%d",MOD.hasOutstanding, MOD.burstOffset, MOD.readDataPtr); \
    $display(" ** Requset signal **"); \
    $display("   addrHit:%d addrIdx:%d", MOD.addrHit, MOD.addrIdx); \
    for(int i=0;i<MOD.QUEUE_SIZE;i++) begin \
        $display("--Block           %d ",i); \
        if(MOD.headPtr == i) \
            $display(" ^^^ HEAD ^^^"); \
        if(MOD.tailPtr == i) \
            $display(" ^^^ TAIL ^^^"); \
        $display("  valid           %d",MOD.validVec[i]); \
        if(MOD.validVec[i]) begin \
            $display("  addrValid       %b",MOD.addrValid[i]); \
            if(MOD.addrValid[i]) begin \
                $display("  address         0x%h",MOD.blockAddrMat[i]); \
                $display("  prefetchReq     %b",MOD.prefetchReqVec[i]); \
                $display("  promiseCnt      %d",MOD.promiseCnt[i]); \
            end \
            $display("  data valid      %d",MOD.dataValidVec[i]); \
            if(MOD.dataValidVec[i]) begin \
                $display("  data            0x%h",MOD.dataMat[i]); \
                $display("  last            0x%h",MOD.lastVec[i]); \
            end \
        end \
    end \
    $display(" ** Resp data **"); \
    $display(" pr_r_valid:%b respData:0x%h respLast:%b", MOD.pr_r_valid, MOD.respData, MOD.respLast); \
    $display("------- END Data --------")

`define printCtrl(MOD)  \
    $display("------- BEGIN Control --------"); \
    $display("  en %b",MOD.en); \
    $display("  st_pr_cur \t%s",MOD.st_pr_cur.name); \
    $display("  st_exec_cur \t%s",MOD.st_exec_cur.name); \
    $display("  pr_opCode %d",MOD.pr_opCode); \
    $display("  pr_context_valid %b",MOD.pr_context_valid); \
    $display("  stride_sampled 0x%h",MOD.stride_sampled); \
    $display("  valid_burst %b",MOD.valid_burst); \
    if(MOD.stride_learned) \
        $display("  stride_reg 0x%h",MOD.stride_reg); \
        $display("  bar 0x%h, limit 0x%h",MOD.bar, MOD.limit); \
    if(MOD.pr_context_valid == 1) begin \
        $display("  pr_m_ar_len %d",MOD.pr_m_ar_len); \
        $display("  pr_m_ar_id %d",MOD.pr_m_ar_id); \
    end \
    $display("  prefetchAddr_valid %b",MOD.prefetchAddr_valid); \
    if(MOD.prefetchAddr_valid) \
        $display("  prefetchAddr_reg 0x%h",MOD.prefetchAddr_reg); \
    $display("------- END Control --------")

// `define printMem(MOD) \
// for (i = 0; i < 2**VALID_ADDR_WIDTH; i = i + 2**(VALID_ADDR_WIDTH/2)) begin \
//     for (j = i; j < i + 2**(VALID_ADDR_WIDTH/2); j = j + 1) begin \
//         $display("0x%h : 0x%h",j,MOD.mem[j]); \
//     end \
// end 

`define TRANSACTION(valid,ready) \
    valid = 1'b1; \
    while(~(valid & ready)) begin \
        #clock_period; \
    end \
    #clock_period; \
    valid = 1'b0;

module prefetcherTop_memStub_tb();

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

// localparam VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
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
// logic [2:0]             s_axi_awsize;
// logic [1:0]             s_axi_awburst;
// logic                   s_axi_awlock;
// logic [3:0]             s_axi_awcache;
// logic [2:0]             s_axi_awprot;
logic [DATA_WIDTH-1:0]  s_axi_wdata;
logic [STRB_WIDTH-1:0]  s_axi_wstrb;
logic                   s_axi_wlast;
logic                   s_axi_wvalid;
logic                   s_axi_wready;

logic [ID_WIDTH-1:0]    s_axi_bid;
logic [1:0]             s_axi_bresp; //dram's output - always 2'b00, no error can be sent
logic                   s_axi_bvalid;
logic                   s_axi_bready;

//todo Assign constant values:
// logic [2:0]             s_axi_arsize;
// logic [1:0]             s_axi_arburst;
// logic                   s_axi_arlock;
// logic [3:0]             s_axi_arcache;
// logic [2:0]             s_axi_arprot;

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

// commented logics - assign on tests

assign s_axi_awaddr = s_aw_addr;
// assign s_axi_awlen = ;
assign s_axi_wstrb = {STRB_WIDTH{1'b1}};
// assign s_axi_wdata = ;
// assign s_axi_wlast = ;
// assign s_axi_wvalid = ; 
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
    localparam LEN = 0;
    resetN = 1'b0;
    en = 1'b1;

    $display("axi_ram_inst.VALID_ADDR_WIDTH=%d",axi_ram_inst.VALID_ADDR_WIDTH);
    $display("axi_ram_inst.STRB_WIDTH=%d",axi_ram_inst.STRB_WIDTH);

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

    for (int i=0; i<REQ_NUM; i++) begin
        //Write req to BASE_ADDR+i
        s_aw_addr = BASE_ADDR + i; // +i increment
        s_aw_id = {{(ID_WIDTH-3){1'b0}}, 3'd5};
        s_axi_awlen = LEN+2; 

        `TRANSACTION(s_aw_valid,s_aw_ready)

        //Write data
	s_axi_wlast = 1'b0;
	
	for(int j=0;j<s_axi_awlen;j++) begin
	    s_axi_wdata = i * (s_axi_awlen+1) + j;
            `TRANSACTION(s_axi_wvalid,s_axi_wready)
	end

	s_axi_wdata = i * (s_axi_awlen+1) + s_axi_awlen;
	s_axi_wlast = 1'b1;
	`TRANSACTION(s_axi_wvalid,s_axi_wready)

        //Write response (B) should be returned, but not caught
        // #clock_period;
    end

    for (int i=0; i<REQ_NUM; i++) begin
        //Read req of BASE_ADDR
        s_ar_addr = BASE_ADDR + i;
        s_ar_len = LEN;
        s_ar_id={{(ID_WIDTH-3){1'b0}}, 3'd5};

        `TRANSACTION(s_ar_valid,s_ar_ready)

        #(clock_period*6);
    end
    
    s_r_ready = 1'b1;

    #(clock_period*100);

    //Write req to move the prefetcher to st_cleanup
    s_aw_addr = BASE_ADDR;
    s_aw_id = {{(ID_WIDTH-3){1'b0}}, 3'd5};
    s_axi_awlen = LEN; //BURST=1
 
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

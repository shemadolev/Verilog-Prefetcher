    `define tick(clk) \
    clk=0; \
    #1; \
    clk=1; \
    #1

    `define printTop(MOD) #1; \
    $display("------- BEGIN Top --------"); \
    $display("  sel_ar_pr %b",MOD.sel_ar_pr); \
    $display("  sel_r_pr %b",MOD.sel_r_pr); \
    $display("  ctrlFlush %b",MOD.ctrlFlush); \
    $display("------- END Top --------")

    `define printData(MOD) #1; \
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

    `define printCtrl(MOD) #1; \
    $display("------- BEGIN Control --------"); \
    $display("  en %b",MOD.en); \
    $display("  st_pr_cur \t%s",MOD.st_pr_cur.name); \
    $display("  st_pr_next \t%s",MOD.st_pr_next.name); \
    $display("  st_exec_cur \t%s",MOD.st_exec_cur.name); \
    $display("  st_exec_next \t%s",MOD.st_exec_next.name); \
    $display("  pr_opCode_next %d",MOD.pr_opCode_next); \
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

    module prefetcherTop__memStub_tb();

    localparam ADDR_SIZE_ENCODE = 6; 
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
    logic [0:QUEUE_WIDTH-1]     crs_almostFullSpacer;
    logic [0:2]                 errorCode;

    //########### axi-dram ###########//
    wire                   rst;
    
    //These are not checked, assign some contants for valid/ready
    wire [ADDR_WIDTH-1:0]  s_axi_awaddr;
    wire [7:0]             s_axi_awlen;
    // wire [2:0]             s_axi_awsize;
    // wire [1:0]             s_axi_awburst;
    // wire                   s_axi_awlock;
    // wire [3:0]             s_axi_awcache;
    // wire [2:0]             s_axi_awprot;
    wire [DATA_WIDTH-1:0]  s_axi_wdata;
    wire [STRB_WIDTH-1:0]  s_axi_wstrb;
    wire                   s_axi_wlast;
    wire                   s_axi_wvalid;
    wire                   s_axi_wready;
    
    wire [ID_WIDTH-1:0]    s_axi_bid;
    wire [1:0]             s_axi_bresp; //dram's output - always 2'b00, no error can be sent
    wire                   s_axi_bvalid;
    wire                   s_axi_bready;

    //todo Assign constant values:
    // wire [2:0]             s_axi_arsize;
    // wire [1:0]             s_axi_arburst;
    // wire                   s_axi_arlock;
    // wire [3:0]             s_axi_arcache;
    // wire [2:0]             s_axi_arprot;

    wire [1:0]             s_axi_rresp;

    prefetcherTop #(
    .ADDR_BITS(ADDR_WIDTH),
    .LOG_QUEUE_SIZE(QUEUE_WIDTH),
    .WATCHDOG_SIZE(WATCHDOG_SIZE),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH),
    .TID_WIDTH(ID_WIDTH),
    .LOG_BLOCK_DATA_BYTES(DATA_SIZE_ENCODE),
    .PROMISE_WIDTH(PROMISE_WIDTH)
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

// commented wires - assign on tests

// assign s_axi_awaddr = ;
// assign s_axi_awlen = ;
assign s_axi_wstrb = {STRB_WIDTH{1'b1}};
// assign s_axi_wdata = ;
// assign s_axi_wlast = ;
// assign s_axi_wvalid = ; 
assign s_axi_bready = 1'b1;


    initial begin
        localparam BASE_ADDR = 64'hdeadbeef;
        resetN=0;
        en = 1;
        // watchdogCnt = 10'd1000;

        `tick(clk);
        resetN=1;
    //CR Space
            // Ctrl
        bar = 0;
        limit = BASE_ADDR * 2;
        windowSize= 3;
        watchdogCnt= 10'd1000;
            // Data
        crs_almostFullSpacer=2;

        s_ar_valid = 0;
        s_r_ready  = 0;
        s_aw_valid = 0;

        // for (int i=0; i<10; i++) begin
            // s_ar_addr = BASE_ADDR + i*64;
        `tick(clk);

        s_ar_valid = 1'b1;
        s_ar_addr = BASE_ADDR;
        s_ar_len=3;
        s_ar_id=5;

        `tick(clk);
        while(~(s_ar_valid & s_ar_ready))
            `tick(clk);

        $display("\n~~~~~~~   1. After read req of addr 0x%h",s_ar_addr);
        `printTop(prefetcherTop_dut);
        `printCtrl(prefetcherTop_dut.prCtrlPath);
        `printData(prefetcherTop_dut.prDataPath);
        
        while(~s_r_valid)
            `tick(clk);

        `tick(clk);
        $display("\n~~~~~~~   2. s_r_valid == 1");
        `printTop(prefetcherTop_dut);
        `printCtrl(prefetcherTop_dut.prCtrlPath);
        `printData(prefetcherTop_dut.prDataPath);

        // //DDR R check 
        // s_ar_valid = 0;
        // m_ar_ready = 1;
        // s_r_ready = 0;
        // m_r_valid = 0;
        // s_aw_valid =0;
        // m_aw_ready = 0;

        // while(~(m_r_ready & m_r_valid)) begin
        //     m_r_valid = 1;
        //     m_r_id = 5;
        //     m_r_last = 1'b1;
        //     m_r_data = 42;
        //     $display("\n~~~~ Data read cycle");
        //     `printTop(prefetcherTop_dut);
        //     `printCtrl(prefetcherTop_dut.prCtrlPath);
        //     `printData(prefetcherTop_dut.prDataPath);
        //     `tick(clk);
        // end
        // $display("\n~~~~ m_r_ready == 1");
        // `printTop(prefetcherTop_dut);
        // `printCtrl(prefetcherTop_dut.prCtrlPath);
        // `printData(prefetcherTop_dut.prDataPath);
        // `tick(clk);
        // m_r_valid = 0;
        // $display("\n~~~~ opCode == 3");
        // `printTop(prefetcherTop_dut);
        // `printCtrl(prefetcherTop_dut.prCtrlPath);
        // `printData(prefetcherTop_dut.prDataPath);
        // `tick(clk);
        // $display("\n~~~~ SUCCESS in data read");
        // `printTop(prefetcherTop_dut);
        // `printCtrl(prefetcherTop_dut.prCtrlPath);
        // `printData(prefetcherTop_dut.prDataPath);
        
        $stop;
    end

    endmodule

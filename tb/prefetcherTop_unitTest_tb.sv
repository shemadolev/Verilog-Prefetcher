`resetall
`timescale 1ns / 1ps

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

module prefetcherTop_tb();

localparam ADDR_BITS = 64; 
localparam LOG_QUEUE_SIZE = 3'd3; 
localparam WATCHDOG_SIZE = 10'd10; 
localparam BURST_LEN_WIDTH = 4'd8; 
localparam TID_WIDTH = 4'd8; 
localparam LOG_BLOCK_DATA_BYTES = 3'd0;
localparam PROMISE_WIDTH = 3'd3; 
localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3; 

logic     clk;
logic     en; 
logic     resetN;
logic s_ar_valid;
logic s_ar_ready;
logic [0:BURST_LEN_WIDTH-1] s_ar_len;
logic [0:ADDR_BITS-1] s_ar_addr; 
logic [0:TID_WIDTH-1] s_ar_id;
logic m_ar_valid;
logic m_ar_ready;
logic [0:BURST_LEN_WIDTH-1] m_ar_len;
logic [0:ADDR_BITS-1] m_ar_addr;
logic [0:TID_WIDTH-1] m_ar_id;
logic s_r_valid;
logic s_r_ready;
logic s_r_last;
logic [0:BLOCK_DATA_SIZE_BITS-1] s_r_data;
logic [0:TID_WIDTH-1] s_r_id;
logic m_r_valid;
logic m_r_ready;
logic m_r_last;
logic [0:BLOCK_DATA_SIZE_BITS-1]  m_r_data;
logic [0:TID_WIDTH-1] m_r_id;
logic s_aw_valid;
logic s_aw_ready;
logic [0:ADDR_BITS-1] s_aw_addr;
logic [0:TID_WIDTH-1] s_aw_id;
logic m_aw_valid;
logic m_aw_ready;
logic     [0:ADDR_BITS-1] bar;
logic     [0:ADDR_BITS-1] limit;
logic     [0:LOG_QUEUE_SIZE] windowSize;
logic     [0:WATCHDOG_SIZE-1] watchdogCnt; 
logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer;
logic    [0:2] errorCode;

prefetcherTop #(
.ADDR_BITS(ADDR_BITS),
.LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
.WATCHDOG_SIZE(WATCHDOG_SIZE),
.BURST_LEN_WIDTH(BURST_LEN_WIDTH),
.TID_WIDTH(TID_WIDTH),
.LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
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

    m_r_valid=0;

    s_ar_len=3;
    s_ar_id=5;

    //NVDLA AR check

    s_ar_valid = 1'b1;
    m_ar_ready = 0;
    s_r_ready = 0;
    m_r_valid = 0;
    s_aw_valid =0;
    m_aw_ready = 0;

    for (int i=0; i<10; i++) begin
        m_ar_ready = 1;
        // s_ar_addr = BASE_ADDR + i*64;
        s_ar_addr = BASE_ADDR;
        `tick(clk);
        $display("\n\n~~~~~~~    Cycle %d",i);
        `printTop(prefetcherTop_dut);
        `printCtrl(prefetcherTop_dut.prCtrlPath);
        `printData(prefetcherTop_dut.prDataPath);
    end
    
    //DDR R check 
    s_ar_valid = 0;
    m_ar_ready = 1;
    s_r_ready = 0;
    m_r_valid = 0;
    s_aw_valid =0;
    m_aw_ready = 0;

    while(~(m_r_ready & m_r_valid)) begin
        m_r_valid = 1;
        m_r_id = 5;
        m_r_last = 1'b1;
        m_r_data = 42;
        $display("\n~~~~ Data read cycle");
        `printTop(prefetcherTop_dut);
        `printCtrl(prefetcherTop_dut.prCtrlPath);
        `printData(prefetcherTop_dut.prDataPath);
        `tick(clk);
    end
    $display("\n~~~~ m_r_ready == 1");
    `printTop(prefetcherTop_dut);
    `printCtrl(prefetcherTop_dut.prCtrlPath);
    `printData(prefetcherTop_dut.prDataPath);
    `tick(clk);
    m_r_valid = 0;
    $display("\n~~~~ opCode == 3");
    `printTop(prefetcherTop_dut);
    `printCtrl(prefetcherTop_dut.prCtrlPath);
    `printData(prefetcherTop_dut.prDataPath);
    `tick(clk);
    $display("\n~~~~ SUCCESS in data read");
    `printTop(prefetcherTop_dut);
    `printCtrl(prefetcherTop_dut.prCtrlPath);
    `printData(prefetcherTop_dut.prDataPath);
    
    $stop;
end

endmodule
`resetall

`define tick(clk) \
clk=0; \
#1; \
clk=1; \
#1

`define printState(MOD) \
$display("------- BEGIN Prefetcher State --------"); \
$display("  almostFull %b",MOD.almostFull); \
$display("  errorCode %d",MOD.errorCode); \
$display("  prefetchReqCnt %d",MOD.prefetchReqCnt); \
$display("  head:%d tail:%d validCnt:%d isEmpty:%d isFull:%d",MOD.headPtr, MOD.tailPtr, MOD.validCnt, MOD.isEmpty, MOD.isFull); \
$display("  hasOutstanding:%b burstOffset:%d readDataPtr:%d",MOD.hasOutstanding, MOD.burstOffset, MOD.readDataPtr); \
$display(" ** Requset signal **"); \
$display("   addrHit:%d addrIdx:%d", MOD.addrHit, MOD.addrIdx); \
for(int i=0;i<MOD.QUEUE_SIZE;i++) begin \
    $display("--Block           %d ",i); \
    $display("  valid           %d",MOD.validVec[i]); \
    $display("  addrValid       %b",MOD.addrValid[i]); \
    $display("  address         0x%h",MOD.blockAddrMat[i]); \
    $display("  data valid      %d",MOD.dataValidVec[i]); \
    $display("  data            0x%h",MOD.dataMat[i]); \
    $display("  last            0x%h",MOD.lastVec[i]); \
    $display("  prefetchReqVec  %b",MOD.prefetchReqVec[i]); \
    $display("  promiseCnt      %d",MOD.promiseCnt[i]); \
end \
$display(" ** Resp data **"); \
$display(" pr_r_valid:%b respData:0x%h respLast:%b", MOD.pr_r_valid, MOD.respData, MOD.respLast); \
$display("------- END Prefetcher State --------")


module prefetcherCtrl();
    localparam ADDR_BITS = 64; //64bit address 2^64
    localparam LOG_QUEUE_SIZE = 3'd6; // the size of the queue [2^x] 
    localparam WATCHDOG_SIZE = 10'd10; // number of bits for the watchdog counter
    localparam LOG_BLOCK_DATA_BYTES = 3'd6; //[Bytes]
    localparam BURST_LEN_WIDTH = 4'd8; //NVDLA max is 3; AXI4 supports up to 8 bits
    localparam TID_WIDTH = 4'd8 //NVDLA max is 3; AXI4 supports up to 8 bits

    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3; //shift left by 3 to convert Bytes->bits

    logic     clk;
    logic     en;
    logic     resetN;
    logic     ctrlFlush;

    // Prefetch Data Path
        // Control bits
    logic    pr_flush; //control bit to flush the queue
    logic    [0:2] pr_opCode;
    logic     pr_addrHit;
    logic     pr_hasOutstanding;
    logic     [0:LOG_QUEUE_SIZE] pr_reqCnt;
    logic     pr_almostFull;
    logic    pr_isCleanup; // indicates that the prefecher is in cleaning
    logic    pr_context_valid; // burst & tag were learned
       // Read channel
     logic     pr_r_valid;
     logic     pr_r_in_last;
     logic     [0:BLOCK_DATA_SIZE_BITS-1] pr_r_in_data;
        //Read Req Channel
     logic    [0:ADDR_BITS-1] pr_m_ar_addr;
     logic    [0:BURST_LEN_WIDTH-1] pr_m_ar_len;
     logic    [0:TID_WIDTH-1] pr_m_ar_id;

    // Slave AXI ports (PR <-> NVDLA)
        //AR (Read Request)
     logic s_ar_valid;
     logic s_ar_ready;
     logic [0:BURST_LEN_WIDTH-1]s_ar_len;
     logic [0:ADDR_BITS-1] s_ar_addr; 
     logic [0:TID_WIDTH-1] s_ar_id;
        //R (Read data)
     logic s_r_valid;
     logic s_r_ready;
     logic s_r_last;
     logic [0:BLOCK_DATA_SIZE_BITS-1] s_r_data;
     logic [0:TID_WIDTH-1] s_r_id;

    // Master AXI ports (PR <-> DDR)
        //AR (Read Request)
     logic m_ar_valid;
     logic m_ar_ready;
     logic [0:BURST_LEN_WIDTH-1] m_ar_len;
     logic [0:ADDR_BITS-1] m_ar_addr;
     logic [0:TID_WIDTH-1] m_ar_id;
        //R (Read data)
     logic m_r_valid;
     logic m_r_ready;
     logic [0:TID_WIDTH-1] m_r_id;

    //CR Space
     logic     [0:ADDR_BITS-1] bar;
     logic     [0:ADDR_BITS-1] limit;
     logic     [0:LOG_QUEUE_SIZE] windowSize;
     logic     [0:WATCHDOG_SIZE-1] watchdogCnt //the size of the counter that is used to divide the clk freq for the watchdog


    prefetcherCtrl #(
        .ADDR_BITS(ADDR_BITS),
        .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
        .WATCHDOG_SIZE(WATCHDOG_SIZE),
        .LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
        .BURST_LEN_WIDTH(BURST_LEN_WIDTH),
        .TID_WIDTH(TID_WIDTH)
    ) prefetcherCtrl_dut (
        .clk(clk),
        .en(en),
        .resetN(resetN),
        .ctrlFlush(ctrlFlush),
        .pr_flush(pr_flush), //control bit to flush the queue
        .pr_opCode(pr_opCode),
        .pr_addrHit(pr_addrHit),
        .pr_hasOutstanding(pr_hasOutstanding),
        .pr_reqCnt(pr_reqCnt),
        .pr_almostFull(pr_almostFull),
        .pr_isCleanup(pr_isCleanup), // indicates that the prefecher is in cleaning
        .pr_context_valid(pr_context_valid), // burst & tag were learned
        .pr_r_valid(pr_r_valid),
        .pr_r_in_last(pr_r_in_last),
        .pr_r_in_data(pr_r_in_data),
        .pr_m_ar_addr(pr_m_ar_addr),
        .pr_m_ar_len(pr_m_ar_len),
        .pr_m_ar_id(pr_m_ar_id),
        .s_ar_valid(s_ar_valid),
        .s_ar_ready(s_ar_ready),
        .s_ar_len(s_ar_len),
        .s_ar_addr(s_ar_addr), 
        .s_ar_id(s_ar_id),
        .s_r_valid(s_r_valid),
        .s_r_ready(s_r_ready),
        .s_r_last(s_r_last),
        .s_r_data(s_r_data),
        .s_r_id(s_r_id),
        .m_ar_valid(m_ar_valid),
        .m_ar_ready(m_ar_ready),
        .m_ar_len(m_ar_len),
        .m_ar_addr(m_ar_addr),
        .m_ar_id(m_ar_id),
        .m_r_valid(m_r_valid),
        .m_r_ready(m_r_ready),
        .m_r_id(m_r_id),
        .bar(bar),
        .limit(limit),
        .windowSize(windowSize),
        .watchdogCnt(watchdogCnt) //the size of the counter that is used to divide the clk freq for the watchdog
    );

    initial begin
        resetN=0;
        crs_almostFullSpacer=2;

        `tick(clk);
        $display("###### Reseted prefetcher");
        resetN=1;
        `printPrefetcher(prefetcherData_dut);
        reqBurstLen=1; 
    $display("**** All tests passed ****");
    
        $stop;
    end

endmodule

`define tick(clk) \
clk=0; \
#1; \
clk=1; \
#1

`define printPrefetcher(MOD) \
$display("------- BEGIN Prefetcher State --------"); \
$display("  almostFull %b",MOD.almostFull); \
$display("  errorCode %d",MOD.errorCode); \
$display("  prefetchReqCnt %d",MOD.prefetchReqCnt); \
$display("  head:%d tail:%d validCnt:%d isEmpty:%d isFull:%d",MOD.headPtr, MOD.tailPtr, MOD.validCnt, MOD.isEmpty, MOD.isFull); \
$display("  hasOutstanding:%b pr_r_valid:%b burstOffset:%d readDataPtr:%d",MOD.hasOutstanding, MOD.pr_r_valid, MOD.burstOffset, MOD.readDataPtr); \
$display(" ** Requset signal **"); \
$display("   reqDataValid:%d addrHit:%d addrIdx:%d",MOD.reqDataValid, MOD.addrHit, MOD.addrIdx); \
for(int i=0;i<MOD.QUEUE_SIZE;i++) begin \
    $display("--Block %d ",i); \
    $display("  valid       %d",MOD.validVec[i]); \
    $display("  data valid  %d",MOD.dataValidVec[i]); \
    $display("  address     0x%h",MOD.blockAddrMat[i]); \
    $display("  data        0x%h",MOD.dataMat[i]); \
    $display("  last        0x%h",MOD.lastVec[i]); \
    $display("  outstanding %b",MOD.outstandingReqVec[i]); \
end \
$display(" ** Resp data **"); \
$display(" pr_r_valid:%b respData:0x%h",MOD.pr_r_valid,MOD.respData); \
$display("------- END Prefetcher State --------")

    localparam LOG_QUEUE_SIZE = 3'd3; // the size of the queue [2^x] 
    localparam QUEUE_SIZE = 1<<LOG_QUEUE_SIZE;
    localparam LOG_BLOCK_DATA_BYTES = 3'd3; //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3; //shift left by 3 to convert Bytes->bits
    localparam ADDR_BITS = 7'd64; // the size of the address [bits]
    localparam PROMISE_WIDTH = 3'd3; // the log size of the promise's counter
    localparam BURST_LEN_WIDTH = 4'd8; //NVDLA max is 3, AXI4 supports up to 8 bits

    logic   clk;
    logic   resetN;
    logic   [0:ADDR_BITS-1] reqAddr;
    logic   [0:BURST_LEN_WIDTH-1] reqBurstLen;
    logic   [0:BLOCK_DATA_SIZE_BITS-1] reqData;
    logic   reqLast;
    logic   [0:2] reqOpcode;

    //CRS
    logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer; 
    //TODO input the actual requested size of block

    //local
    logic   pr_r_valid;
    logic	[0:BLOCK_DATA_SIZE_BITS-1] respData;
    logic	respLast;
    logic	addrHit;
    
    //global
    logic	[0:LOG_QUEUE_SIZE] prefetchReqCnt;
    logic	almostFull; //If queue is {crs_almostFullSpacer} blocks from being full
    logic   [0:2] errorCode;
    logic   hasOutstanding;

prefetcherData #(
    .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
    .LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
    .ADDR_BITS(ADDR_BITS),
    .PROMISE_WIDTH(PROMISE_WIDTH),
    .BURST_LEN_WIDTH(BURST_LEN_WIDTH)
) prefetcherData_dut (
    .clk(clk),
    .resetN(resetN),
    .reqAddr(reqAddr),
    .reqBurstLen(reqBurstLen),
    .reqData(reqData),
    .reqOpcode(reqOpcode),
    .crs_almostFullSpacer(crs_almostFullSpacer), 
    .respData(respData),
    .respLast(respLast),
    .addrHit(addrHit),
    .pr_r_valid(pr_r_valid),
    .prefetchReqCnt(prefetchReqCnt),
    .almostFull(almostFull), //If queue is {crs_almostFullSpacer} blocks from being full
    .errorCode(errorCode),
    .hasOutstanding(hasOutstanding)
);

initial begin
    resetN=0;
    crs_almostFullSpacer=2;

    `tick(clk);
    $display("###### Reseted prefetcher");
    `printPrefetcher(prefetcherData_dut);
    resetN=1;

//writeReq
    reqAddr=64'hdeadbeef;
    reqOpcode=3; //WRITE_REQ
    for (int i=0; i<5;i++) begin
        reqAddr+=1;
        `tick(clk);
    end

    $display("###### After WriteReq");
    `printPrefetcher(prefetcherData_dut);

//WriteResp
    reqAddr=64'hdeadbeef;
    reqData=64'h0;
    reqOpcode=4; //WRITE_RESP
    for (int i=0; i<6;i++) begin //One extra write response
        reqAddr+=1;
        reqData+=64'h10;
        `tick(clk);
        $display("###### After WriteResp (%d/5) addr: %h", i, reqAddr);
        `printPrefetcher(prefetcherData_dut);
    end

//readReq
        reqOpcode=2; //READ
    //read twice existing address - hoq
        reqAddr=64'hdeadbeef+1;
        `tick(clk);
        `tick(clk);
        assert(pr_r_valid == 1'b1 && respData == 64'h10);
        $display("###### After read HOQ");
        `printPrefetcher(prefetcherData_dut);
    //read existing address - HOQ+1
    ef+2;
        `tick(clk);
        assert(pr_r_valid == 1'b1 && respData == 64'h20);
        $display("###### After read HOQ+1");
        `printPrefetcher(prefetcherData_dut);
    //read from HOQ-1
    ef+1;
        `tick(clk);
        assert(pr_r_valid == 1'b0);
        $display("###### After read HOQ-1");
        `printPrefetcher(prefetcherData_dut);
    //read from MOQ
    ef+4;
        `tick(clk);
        assert(pr_r_valid == 1'b0);
        $display("###### After read MOQ");
        `printPrefetcher(prefetcherData_dut);
    //read non-existing
    
        `tick(clk);
        assert(pr_r_valid == 1'b0);
        $display("###### After read non-existent");
        `printPrefetcher(prefetcherData_dut);
//invalidate
        reqOpcodeALIDATE
    //normal invalidate
        reqAddr=64'hdeadbeef+3;
        `tick(clk);
        assert(prefetcherData_dut.dataValidVec[2] == 1'b0);
        $display("###### After invalidate existent");
        `printPrefetcher(prefetcherData_dut);
    //invalidate non-exsiting
        reqAddr=64'h1234;
        `tick(clk);
        $display("###### After invalidate non-existent");
        `printPrefetcher(prefetcherData_dut);
//NOP
        reqOpcode=0; //NOP
        `tick(clk);
        `tick(clk);
        `tick(clk);
        $display("###### After NOP * 3");
        `printPrefetcher(prefetcherData_dut);
//read
    //read after invalidate + POP
        reqOpcode=2; //READ
        reqAddr=64'hdeadbeef+3;
        `tick(clk);
        assert(pr_r_valid == 1'b0);
        assert(prefetcherData_dut.headPtr == 3'd2);
        $display("###### After read invalidated + POP");
        
//writeReq
        reqOpcode=3; //WRITE_REQ
    //Write till full
        // valid blocks=3, capacity=8 => 2*not almostFull, 2*almostFull, 1*full
        reqAddr=64'hdeadbeff;
        for (int i=0; i<2;i++) begin
            reqAddr+=1;
            `tick(clk);
            assert(prefetcherData_dut.isFull == 1'b0 && prefetcherData_dut.almostFull == 1'b0);
        end
        for (int i=0; i<2;i++) begin
            reqAddr+=1;
            `tick(clk);
            assert(prefetcherData_dut.isFull == 1'b0 && prefetcherData_dut.almostFull == 1'b1);
        end
        reqAddr+=1;
        `tick(clk);
        assert(prefetcherData_dut.isFull == 1'b1 && prefetcherData_dut.almostFull == 1'b1);

        $display("###### After WriteReq till full");
        `printPrefetcher(prefetcherData_dut);
    //Write when full        
        reqAddr+=1;
        `tick(clk);
        assert(prefetcherData_dut.isFull == 1'b1 && prefetcherData_dut.almostFull == 1'b1 && prefetcherData_dut.errorCode == 2'd2);
        $display("###### After WriteReq when full");
        `printPrefetcher(prefetcherData_dut);
    //NOP - make sure error cleared
        reqOpcode=0; //NOP
        `tick(clk);
        assert(prefetcherData_dut.errorCode == 2'd0);
   $display("**** All tests passed ****");
  
    $stop;
end

endmodule

//todo add: WriteReq & check almostFull, and error when full
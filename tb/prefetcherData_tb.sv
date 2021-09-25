`define tick() clk=0; #1; clk=1; #1

`define printPrefetcher(MOD) \
$display("------- BEGIN Prefetcher State --------") \
for(int i=0;i<MOD.QUEUE_SIZE;i++){ \
    $display(" Block %d ",i); \
    $display("  valid       %d",MOD.validVec[i]); \
    $display("  data valid  %d",MOD.dataValidVec[i]); \
    $display("  address     %h",MOD.); \
    $display("  data        %h",MOD.dataMat[i]); \
 \
} \
$display("------- END Prefetcher State --------") \

module prefetcherDataTb ();

    parameter LOG_QUEUE_SIZE = 3; // the size of the queue [2^x] 
    localparam QUEUE_SIZE = 1<<LOG_QUEUE_SIZE;
    parameter LOG_BLOCK_DATA_BYTES = 6; //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3; //shift left by 3 to convert Bytes->bits
    parameter BA_ADDR_SIZE = 64; // the size of the address [bits]
    parameter WATCHDOG_SIZE = 10; // number of bits for the watchdog counter

    logic	  clk;
    logic     resetN;
    logic     [0:BA_ADDR_SIZE-1] inAddr;
    logic	  [0:BLOCK_DATA_SIZE_BITS-1] inData;
    logic     [0:1] inOpcode
    logic     [0:WATCHDOG_SIZE-1] watchdogCnt;
    logic     [0:LOG_QUEUE_SIZE-1] almostFullSpacer; 
    logic	  [0:BLOCK_DATA_SIZE_BITS-1] dataOut;
    logic     valid;
    logic     dataValid; 
    logic	  [0:LOG_QUEUE_SIZE] outstandingReqCnt;
    logic	  almostFull;

module	prefetcherData #(
    .LOG_QUEUE_SIZE(LOG_QUEUE_SIZE),
    .LOG_BLOCK_DATA_BYTES(LOG_BLOCK_DATA_BYTES),
    .BA_ADDR_SIZE(BA_ADDR_SIZE),
    .WATCHDOG_SIZE(WATCHDOG_SIZE)
)(
    .clk(clk),
    .resetN(resetN),
    .inAddr(inAddr),
    .inData(inData),
    .inOpcode(inOpcode),
    .watchdogCnt(watchdogCnt),
    .almostFullSpacer(almostFullSpacer), 
    .dataOut(dataOut),
    .valid(valid),
    .dataValid(dataValid), 
    .outstandingReqCnt(outstandingReqCnt),
    .almostFull(almostFull)
);

function automatic void tick(ref logic clk);
    clk=0;
    #1;
    clk=1;
    #1;    
endfunction

initial begin

    resetN=0;
    watchdogCnt=1000;
    almostFullSpacer=2;
    tick(clk);
    resetN=1;

    //writeReq
    inAddr=64'hdeadbeef;
    inOpcode=2; //WRITE_REQ
    for (int i=0; i<5;i++) begin
        inAddr+=1;
        tick();
    end

// print dump ======================================

    //WriteResp
    inAddr=64'hdeadbeef;
    inData=64'h10;
    inOpcode=3; //WRITE_RESP
    for (int i=0; i<6;i++) begin
        inAddr+=1;
        inData+=64'h10;
        tick();
    end

// print dump ======================================

    //readReq
        inOpcode=1; //READ
        //read existing address - hoq
        inAddr=64'hdeadbeef+1;
        tick()
        //add assert
// print dump ======================================
        //read existing address - moq
        inAddr=64'hdeadbeef+3;
        tick()
        //add assert
// print dump ======================================
        //read non-existing address
        inAddr=64'h1;
        tick()
        //add assert
// print dump ======================================

    //invalidate
        inOpcode=0; //INVALIDATE
        //invalidate non-exsiting
        inAddr=64'h0;
        tick()
        //invalidate exsiting
        inAddr=
        tick()

   $display("**** All tests passed ****");
  
    $stop;
end

endmodule
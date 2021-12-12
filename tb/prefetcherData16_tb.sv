`resetall
`timescale 1ns / 1ps

`include "print.svh"
`include "utils.svh"

module prefetcherData16Tb ();

    localparam LOG_QUEUE_SIZE = 4; // the size of the queue [2^x] 
    localparam QUEUE_SIZE = 1<<LOG_QUEUE_SIZE;
    localparam LOG_BLOCK_DATA_BYTES = 3; //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3; //shift left by 3 to convert Bytes->bits
    localparam ADDR_BITS = 64; // the size of the address [bits]
    localparam PROMISE_WIDTH = 3; // the log size of the promise's counter
    localparam BURST_LEN_WIDTH = 4; //NVDLA max is 3, AXI4 supports up to 8 bits

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
    ) prefetcherData16_dut (
        .clk(clk),
        .resetN(resetN),
        .reqAddr(reqAddr),
        .reqBurstLen(reqBurstLen),
        .reqData(reqData),
        .reqLast(reqLast),
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
        resetN=1;
        `printData(prefetcherData_dut);
        reqBurstLen=2; //==3

    //readReqMaster
        reqAddr=64'hdeadbeef;
        for (int i=0; i<3;i++) begin
            reqOpcode=2; 
            reqAddr+=1;
            #1;
            assert(addrHit == 1'b0);
            `tick(clk);
        end

        $display("###### After read_req_NVDLA burst");
        `printData(prefetcherData_dut);
        assert(pr_r_valid == 1'b0); //verify that no data was inserted to the prefetcher
        assert(hasOutstanding == 1'b1);

        // check error opcode of readDataPromise when there is no data in the queue
        reqOpcode=4;
        `tick(clk);
        assert(errorCode == 3'd3);


    //readReqPref
        reqAddr=64'hdeadbeef + 64'h5;
        reqOpcode=1; 
        for (int i=3; i<5;i++) begin
            reqAddr+=1;
            #1;
            `tick(clk);
        end
        $display("###### After prefetching 2 addresses");
        `printData(prefetcherData_dut);
        assert(hasOutstanding == 1'b1);
        assert(almostFull == 1'b1);


    //readDataSlave
        reqData=64'h0;
        reqOpcode=3; 
        for (int i=0; i<4;i++) begin //One extra write response
            for(int j=0; j<reqBurstLen-1;j++) begin
                reqLast=1'b0;
                reqData+=64'h10;
                `tick(clk);
            end
            reqData+=64'h10;
            reqLast=1'b1;
            `tick(clk);
            $display("###### After read_data_DDR (%d/4)", i+1);
            `printData(prefetcherData_dut);
            assert(pr_r_valid == 1'b1); //verify that the data path inform the controller that there is data that can be sent to NVDLA
        end
        assert(hasOutstanding == 1'b1);


    //readDataPromise
        while (pr_r_valid == 1'b1) begin
            reqOpcode=4; 
            `tick(clk);
            $display("###### After read_data_NVDLA");
            `printData(prefetcherData_dut);
        end
        assert(prefetchReqCnt == 2);

    //readReqMaster - request the prefetched addresses
        reqAddr=64'hdeadbeef + 64'h5;
        reqOpcode=2;
        for (int i=3; i<5;i++) begin
            reqAddr+=1;
            #1;
            `tick(clk);
            assert(addrHit == 1'b1);
            `tick(clk); //Request twice
            assert(addrHit == 1'b1);
        end
        $display("###### After requesting the prefetched addresses (twice for each)");
        `printData(prefetcherData_dut);
        assert(prefetchReqCnt == 0); //no unrequested addresses at this point

    //readDataPromise - with promiseCnt>1
        while (pr_r_valid == 1'b1) begin
            reqOpcode=4; 
            `tick(clk);
            $display("###### After read_data_NVDLA");
            `printData(prefetcherData_dut);
        end

    //readReqPref
        reqAddr=64'hdeadbef6;
        reqOpcode=1;
        for (int i=0; i<2;i++) begin
            reqAddr+=1;
            #1;
            `tick(clk);
        end
        $display("###### After prefetching 2 addresses");
        `printData(prefetcherData_dut);
        assert(hasOutstanding == 1'b1);


    $display("Phase 2");

    //readReqMaster - request the prefetched addresses + new one
        reqAddr=64'hdeadbef6;
        reqOpcode=2;
        for (int i=0; i<3;i++) begin
            reqAddr+=1;
            #1;
            if(i < 2)
                assert(addrHit == 1'b1);
            else
                assert(addrHit == 1'b0);
            #1;
            `tick(clk);
            $display("###### After requesting address 0x%h", reqAddr);
            `printData(prefetcherData_dut);
        end
        $display("###### After requesting the prefetched addresses + new one");
        `printData(prefetcherData_dut);
        assert(prefetchReqCnt == 0); //no unrequested addresses at this point


    //readDataSlave
        reqData=64'h500;
        reqOpcode=3; 
        for (int i=0; i<3;i++) begin //One extra write response
            for(int j=0; j<reqBurstLen-1;j++) begin
                reqLast=1'b0;
                reqData+=64'h10;
                `tick(clk);
            end
            reqData+=64'h10;
            reqLast=1'b1;
            `tick(clk);
            $display("###### After read_data_DDR (%d/3)", i+1);
            `printData(prefetcherData_dut);
            assert(pr_r_valid == 1'b1); //verify that the data path inform the controller that there is data that can be sent to NVDLA
        end
        assert(hasOutstanding == 1'b1);


    //readDataPromise - with promiseCnt>1
        while (pr_r_valid == 1'b1) begin
            reqOpcode=4; 
            `tick(clk);
        end
        $display("###### After read_data_NVDLA");
        `printData(prefetcherData_dut);


    //Flush & different burst
        resetN=0;
        crs_almostFullSpacer=2;

        `tick(clk);
        $display("###### Reseted prefetcher");
        resetN=1;
        `printData(prefetcherData_dut);

    $display("**** All tests passed ****");
    
        $stop;
    end
endmodule
`resetall

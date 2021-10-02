/* Module name: prefetcherQueue
 * Description: prefetchQueue is the base module (queue) of a prefetcher. main capabilities:
 *              * Stores outstanding requests and data responses from DRAM
 *              * Supports 4 opreations, for each block in the queue, according to 5 opcodes: 
                    0 - NOP ,1 - readReqPref,  2 - readReqMaster(AXI AR/Read Request), 3 - readDataSlave(AXI R/Read Data), 4 - readDataPromise
                * errorCode:
                    0 - no error, 1 - Invalid opcode, 2 - WriteReq to full queue, 3 - Requesting data read when not ready
 */
module	prefetcherData #(
    parameter LOG_QUEUE_SIZE = 3'd6, // the size of the queue [2^x] 
    localparam QUEUE_SIZE = 1<<LOG_QUEUE_SIZE,
    parameter LOG_BLOCK_DATA_BYTES = 3'd6, //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3, //shift left by 3 to convert Bytes->bits
    parameter ADDR_BITS = 7'd64, // the size of the address [bits]
    parameter PROMISE_WIDTH = 3'd3 // the log size of the promise's counter
)(
    input logic	    clk,
    input logic     resetN,
    input logic     [0:ADDR_BITS-1] reqAddr,
    input logic	    [0:BLOCK_DATA_SIZE_BITS-1] reqData,
    input logic     [0:2] reqOpcode,

    //CRS
    input logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer, 
    //TODO input the actual requested size of block

    //local
    output logic    respValid,
    output logic	[0:BLOCK_DATA_SIZE_BITS-1] respData,
    output logic	[0:ADDR_BITS-1] respAddr,
    
    //global
    output logic	dataReady,
    output logic	[0:LOG_QUEUE_SIZE] outstandingReqCnt,
    output logic	almostFull, //If queue is {crs_almostFullSpacer} blocks from being full
    output logic    [0:1] errorCode
);

//queue data
logic [0:BLOCK_DATA_SIZE_BITS-1] dataMat [0:QUEUE_SIZE-1];
//block metadata
logic [0:QUEUE_SIZE-1] validVec, dataValidVec, outstandingReqVec;
logic [0:PROMISE_WIDTH-1] promiseCnt [0:QUEUE_SIZE-1];
logic [0:ADDR_BITS-1] blockAddrMat [0:QUEUE_SIZE-1]; //should be inserted block aligned
//queue helpers
logic [0:LOG_QUEUE_SIZE-1] headPtr, tailPtr, addrIdx;
logic [0:LOG_QUEUE_SIZE] validCnt;
logic addrHit, isEmpty, isFull, dataReady_head, dataReady_nxtHead;

//find the valid address index
findValueIdx #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE), .TAG_SIZE(ADDR_BITS)) findAddrIdx 
                (.inTag(reqAddr), .inMat(blockAddrMat), .valid(validVec),
                 .hit(addrHit), .matchIdx(addrIdx)
                 );

//count the number of outstanding requests
onesCnt #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE)) outstandingReqs 
                (.A(outstandingReqVec), 
                 .ones(outstandingReqCnt)
                );

//count the number of valid blocks
onesCnt #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE)) numOfValidBlocks 
                (.A(validVec), 
                 .ones(validCnt)
                );

always_comb begin
    respData = dataMat[headPtr];
    respAddr = blockAddrMat[headPtr];
    isFull = (tailPtr == headPtr) && !isEmpty;
    isEmpty = ~|validVec;
    almostFull = validCnt + crs_almostFullSpacer >= QUEUE_SIZE;
    dataReady_head = (validVec[headPtr] && dataValidVec[headPtr] == 1'b1 && promiseCnt[headPtr] > {(PROMISE_WIDTH){1'b0}});
    dataReady_nxtHead = (validVec[headPtr + 1] && dataValidVec[headPtr + 1] == 1'b1 && promiseCnt[headPtr + 1] > {(PROMISE_WIDTH){1'b0}});
    dataReady = dataReady_head || ((promiseCnt[headPtr] == {(PROMISE_WIDTH){1'b0}}) && dataReady_nxtHead);
end

// 0 - NOP ,1 - readReqPref,  2 - readReqMaster(AXI AR/Read Request), 3 - readDataSlave(AXI R/Read Data), 4 - readDataPromise

always_ff @(posedge clk or negedge resetN)
begin
    // TODO update the miss machine according to the new opcodes
	if(!resetN)	begin 
        validVec <= {QUEUE_SIZE{1'b0}};
        // dataValidVec <= {QUEUE_SIZE{1'b0}};
        outstandingReqVec <= {QUEUE_SIZE{1'b0}};
        headPtr <= 1'b0;
        tailPtr <= 1'b0;
        respValid <= 1'b0;
        errorCode <= 2'b0;
	end
	    
    else begin
        errorCode <= 2'd0;
        respValid <= 1'b0;

        // readReqPref (Read requests which were initiated by transactions from the prefetching mechanism)
        // Assupmtion: Prefetcher will not demand an existing readReq
        else if(reqOpcode==3'd1) begin
            if(!isFull) begin
                validVec[tailPtr] <= 1'b1;
                dataValidVec[tailPtr] <= 1'b0;
                outstandingReqVec[tailPtr] <= 1'b1;
                promiseCnt[addrIdx] <= {(PROMISE_WIDTH){1'b0}};
                blockAddrMat[tailPtr] <= reqAddr;
                tailPtr <= tailPtr + 1;
            end else begin 
                //Queue full!
                errorCode <= 2'd2;
            end
        end

        // readReqMaster (Read requests which were initiated by transactions from the MASTER)
        else if(reqOpcode==3'd2) begin
            if(addrHit) begin
                promiseCnt[addrIdx] <= promiseCnt[addrIdx] + 1'd1;
            end
            if(!isFull) begin
                validVec[tailPtr] <= 1'b1;
                dataValidVec[tailPtr] <= 1'b0;
                outstandingReqVec[tailPtr] <= 1'b1;
                promiseCnt[addrIdx] <= {{(PROMISE_WIDTH-1){1'b0}},1'b1};
                blockAddrMat[tailPtr] <= reqAddr;
                tailPtr <= tailPtr + 1;
            end else begin 
                //Queue full!
                errorCode <= 2'd2;
            end
        end

        // readDataSlave (Receiving read data from SLAVE)
        else if(reqOpcode==3'd3) begin
            if(addrHit) begin
                dataValidVec[addrIdx] <= 1'b1;
                outstandingReqVec[addrIdx] <= 1'b0;
                dataMat[addrIdx] <= reqData;
            end
        end 

        // readDataPromise (Return data block that MASTER requested and is valid).
            // Pops head if fulfilled all head promises, and nextHead is valid & his promise > 0.
        if((reqOpcode==3'd4)) begin
            if(!dataReady) begin
                errorCode <= 2'd3; //Requesting data read when not ready
            end else begin
                if(!dataReady_head) begin //Head's promise == 0, nextHead is ready
                    //Pop (even if data is invalid)
                    validVec[headPtr] = 1'b0;
                    headPtr = headPtr + 1'b1;
                end 
                //Current head's data is ready
                respValid <= 1'b1;
                promiseCnt[headPtr] = promiseCnt[headPtr] - 1'b1;
            end
        end

        //Invalid opcode
        else if(!reqOpcode == 3'd0) begin 
            errorCode <= 2'd1; 
        end
	end
end

endmodule

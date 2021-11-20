/* Module name: prefetcher data path
 * Description: prefetch data path is the base module (queue) of a prefetcher. main capabilities:
 *              * Stores outstanding requests and data responses from DRAM
 *              * Supports 4 opreations, for each block in the queue, according to 5 opcodes: 
                    0 - NOP ,1 - readReqPref,  2 - readReqMaster(AXI AR/Read Request), 3 - readDataSlave(AXI R/Read Data), 4 - readDataPromise
                * errorCode:
                    0 - no error, 1 - Invalid opcode, 2 - ReadReq to full queue, 3 - Requesting data read when not ready, 4 - Read data overflow
 */
module	prefetcherData #(
    parameter LOG_QUEUE_SIZE = 4'd8, // the size of the queue [2^x] 
    localparam QUEUE_SIZE = 1<<LOG_QUEUE_SIZE,
    parameter LOG_BLOCK_DATA_BYTES = 3'd6, //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3, //shift left by 3 to convert Bytes->bits
    parameter ADDR_BITS = 7'd64, // the size of the address [bits]
    parameter PROMISE_WIDTH = 3'd3, // the log size of the promise's counter
    parameter BURST_LEN_WIDTH = 4'd8 //NVDLA max is 3, AXI4 supports up to 8 bits
)(
    input logic	    clk,
    input logic     resetN,
    input logic     [0:ADDR_BITS-1] reqAddr,
    input logic	    [0:BURST_LEN_WIDTH-1] reqBurstLen, //Must not change during work
    input logic	    [0:BLOCK_DATA_SIZE_BITS-1] reqData,
    input logic     reqLast,
    input logic     [0:2] reqOpcode,

    //CRS
    input logic     [0:LOG_QUEUE_SIZE-1] crs_almostFullSpacer, //Spacer is crs_almostFullSpacer * reqBurstLen

    //local
    output logic	[0:BLOCK_DATA_SIZE_BITS-1] respData,
    output logic	respLast,
    output logic	addrHit,
    
    output logic	pr_r_valid,
    //global
    output logic	[0:LOG_QUEUE_SIZE] prefetchReqCnt,
    output logic	almostFull, //If queue is {crs_almostFullSpacer} blocks from being full
    output logic    [0:2] errorCode,
    output logic    hasOutstanding
);

//queue data
logic [0:BLOCK_DATA_SIZE_BITS-1] dataMat [0:QUEUE_SIZE-1];
//block metadata
logic [0:QUEUE_SIZE-1] validVec, dataValidVec, prefetchReqVec, lastVec, curBurstMask, tailBurstMask;
logic [0:QUEUE_SIZE-1] addrValid; //'1' IFF is head of burst IFF corresponding blockAddrMat is valid
logic [0:PROMISE_WIDTH-1] promiseCnt [0:QUEUE_SIZE-1];
logic [0:ADDR_BITS-1] blockAddrMat [0:QUEUE_SIZE-1]; //should be inserted block aligned
//queue helpers
logic [0:LOG_QUEUE_SIZE-1] headPtr, tailPtr, addrIdx;
logic [0:LOG_QUEUE_SIZE-1] readDataPtr; //Points to next block that readDataSlave writes to 
logic [0:LOG_QUEUE_SIZE] validCnt;
logic isEmpty, isFull, dataReady_curBurst, dataReady_nxtBurst, active;
logic [0:BURST_LEN_WIDTH-1] burstOffset; //For readDataPromise: Offset inside a burst

//find the valid address index
findValueIdx #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE), .TAG_SIZE(ADDR_BITS)) findAddrIdx 
                (.inTag(reqAddr), .inMat(blockAddrMat), .valid(validVec & addrValid),
                 .hit(addrHit), .matchIdx(addrIdx)
                 );

//count the number of outstanding requests
onesCnt #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE)) outstandingReqs 
                (.A(prefetchReqVec), 
                 .ones(prefetchReqCnt)
                );

//count the number of valid blocks
onesCnt #(.LOG_VEC_SIZE(LOG_QUEUE_SIZE)) numOfValidBlocks 
                (.A(validVec), 
                 .ones(validCnt)
                );

//vector of 1's for the current burst indices
vectorMask #(.LOG_WIDTH(LOG_QUEUE_SIZE)) headBurst_mask
                (.headIdx(headPtr), .tailIdx(headPtr + reqBurstLen),
                 .outMask(curBurstMask)
                );

//vector of 1's for the current tail burst
vectorMask #(.LOG_WIDTH(LOG_QUEUE_SIZE)) tailBurst_mask
                (.headIdx(tailPtr), .tailIdx(tailPtr + reqBurstLen),
                 .outMask(tailBurstMask)
                );

always_comb begin
    active = |validVec; //at least one block is valid
    respData = dataReady_curBurst ? dataMat[headPtr + burstOffset] : dataMat[headPtr + reqBurstLen + burstOffset]; //Pass data in head/head+1, based on promise&dataValid of head
    respLast = lastVec[headPtr + burstOffset];
    isFull = (QUEUE_SIZE - validCnt) < reqBurstLen;
    isEmpty = ~|validVec;
    almostFull = (validCnt + (crs_almostFullSpacer * reqBurstLen)  >= QUEUE_SIZE) & active;
    dataReady_curBurst = (validVec[headPtr + burstOffset] && dataValidVec[headPtr + burstOffset] == 1'b1 && promiseCnt[headPtr] > {(PROMISE_WIDTH){1'b0}});
    dataReady_nxtBurst = (validVec[headPtr + reqBurstLen] && dataValidVec[headPtr + reqBurstLen] == 1'b1 && promiseCnt[headPtr + reqBurstLen] > {(PROMISE_WIDTH){1'b0}});
    pr_r_valid = (dataReady_curBurst || ((promiseCnt[headPtr] == {(PROMISE_WIDTH){1'b0}}) && dataReady_nxtBurst)) & active;
    hasOutstanding = |((dataValidVec & validVec) ^ validVec);
end

// 0 - NOP ,1 - readReqPref,  2 - readReqMaster(AXI AR/Read Request), 3 - readDataSlave(AXI R/Read Data), 4 - readDataPromise

always_ff @(posedge clk or negedge resetN)
begin
	if(!resetN)	begin 
        validVec <= {QUEUE_SIZE{1'b0}};
        
        prefetchReqVec <= {QUEUE_SIZE{1'b0}};
        headPtr <= {LOG_QUEUE_SIZE{1'b0}};;
        tailPtr <= {LOG_QUEUE_SIZE{1'b0}};;
        readDataPtr <= {LOG_QUEUE_SIZE{1'b0}};;
        errorCode <= 3'b0;
        burstOffset <= {BURST_LEN_WIDTH{1'b0}};
    end else begin
        errorCode <= 3'd0;
        case (reqOpcode)
            // readReqPref (Read requests which were initiated by transactions from the prefetching mechanism)
            // Assupmtion: Prefetcher will not demand an existing readReq
            3'd1: begin
                if(!isFull) begin
                    validVec <= validVec | tailBurstMask;
                    dataValidVec <= dataValidVec & (~tailBurstMask);
                    prefetchReqVec[tailPtr] <= 1'b1;
                    addrValid <= addrValid & (~tailBurstMask);
                    addrValid[tailPtr] <= 1'b1;
                    promiseCnt[tailPtr] <= {(PROMISE_WIDTH){1'b0}};
                    blockAddrMat[tailPtr] <= reqAddr;
                    tailPtr <= tailPtr + reqBurstLen;
                end else begin 
                    //Queue full!
                    errorCode <= 3'd2;
                end
            end

            // readReqMaster (Read requests which were initiated by transactions from the MASTER)
            3'd2: begin
                if(addrHit) begin
                    promiseCnt[addrIdx] <= promiseCnt[addrIdx] + 1'd1;
                    prefetchReqVec[addrIdx] <= 1'b0;
                end
                else if(!isFull) begin
                    validVec <= validVec | tailBurstMask;
                    dataValidVec <= dataValidVec & (~tailBurstMask);
                    prefetchReqVec[tailPtr] <= 1'b0;
                    addrValid <= addrValid & (~tailBurstMask);
                    addrValid[tailPtr] <= 1'b1;
                    promiseCnt[tailPtr] <= {{(PROMISE_WIDTH-1){1'b0}},1'b1};
                    blockAddrMat[tailPtr] <= reqAddr;
                    tailPtr <= tailPtr + reqBurstLen;
                end else begin 
                    //Queue full!
                    errorCode <= 3'd2;
                end
            end

            // readDataSlave (Receiving read data from SLAVE)
            3'd3: begin
                if(validVec[readDataPtr] != 1'b0) begin
                    dataValidVec[readDataPtr] <= 1'b1;
                    dataMat[readDataPtr] <= reqData;
                    lastVec[readDataPtr] <= reqLast;
                    readDataPtr <= readDataPtr + 1'b1;
                end else begin
                    errorCode <= 3'd4; //Read data overflow
                end
            end 

            // readDataPromise (Return data block that MASTER requested and is valid).
                // Pops head if fulfilled all head promises, and nextHead is valid & his promise > 0.
            3'd4: begin
                if(!pr_r_valid) begin
                    errorCode <= 3'd3; //Requesting data read when not ready
                end else begin
                    if(!dataReady_curBurst) begin //Head's promise == 0, nextHead is ready
                        //Pop (even if data is invalid)
                        validVec <= validVec & (~curBurstMask);
                        headPtr = headPtr + reqBurstLen;
                    end 
                    //Current head's data is ready
                    burstOffset <= burstOffset + 1'b1;

                    if(lastVec[headPtr + burstOffset] == 1'b1) begin
                        promiseCnt[headPtr] = promiseCnt[headPtr] - 1'b1;
                        burstOffset <= 1'b0;
                    end
                end
            end

            //Invalid opcode
            default: 
                errorCode <= 3'd1; 
        endcase
	end
end

endmodule

//todo throw error if getting 'data read' when not expected (validVec[readDataPtr] == 0)
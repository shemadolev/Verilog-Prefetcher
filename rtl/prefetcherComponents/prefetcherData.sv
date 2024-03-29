/* Module name: prefetcher data path
 * Description: prefetch data path is the base module (queue) of a prefetcher. main capabilities:
 *              * Stores outstanding requests and data responses from DRAM
 *              * Supports 4 opreations, for each block in the queue, according to 5 opcodes: 
                    0 - NOP
                    1 - readReqPref - associated with a prefetched read request. 
                                        Reserves a block, or multiple blocks in a burst-case, for the data response from the subordinate, 
                                        doesn't affect the promise counter.
                    2 - readReqManager(AXI AR/Read Request) - associates with a read request from the manager. 
                                                                Reserves a block, or multiple blocks in a burst-case, for the data response from the subordinate, 
                                                                and increments the promise counter of this block.
                    3 - readDataSubordinate(AXI R/Read Data): Stores reqData & reqLast into the next block that expects data.
                    4 - readDataPromise: Pops head if fulfilled all head promises, and nextHead is valid & his promise > 0,
                                            mark that a read successfully fulfilled.
                * errorCode:
                    0 - no error, 1 - Invalid opcode, 2 - ReadReq to full queue, 3 - Requesting data read when not ready, 4 - Read data overflow
 */
`resetall
`timescale 1ns / 1ps

module	prefetcherData #(
    parameter LOG_QUEUE_SIZE = 4'd8, // the size of the queue [2^x] 
    localparam [0:LOG_QUEUE_SIZE] QUEUE_SIZE = 1<<LOG_QUEUE_SIZE,
    parameter LOG_BLOCK_DATA_BYTES = 3'd6, //[Bytes]
    localparam BLOCK_DATA_SIZE_BITS = (1<<LOG_BLOCK_DATA_BYTES)<<3, //shift left by 3 to convert Bytes->bits
    parameter ADDR_BITS = 7'd64, // the size of the address [bits]
    parameter PROMISE_WIDTH = 3'd3 // the log size of the promise's counter
)(
    input logic	    clk,
    input logic     resetN,
    input logic     [0:ADDR_BITS-1] reqAddr,
    input logic	    [0:LOG_QUEUE_SIZE-1] reqBurstLen, //Must not change during work, cannot be >= the size of queue
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
logic [0:LOG_QUEUE_SIZE-1] headPtr, tailPtr, addrIdx, burst_len;
logic [0:LOG_QUEUE_SIZE-1] readDataPtr; //Points to next block that readDataSubordinate writes to 
logic [0:LOG_QUEUE_SIZE] validCnt;
logic isEmpty, isFull, dataReady_curBurst, dataReady_nxtBurst, active;
logic [0:LOG_QUEUE_SIZE-1] burstOffset; //For readDataPromise: Offset inside a burst

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
                (.headIdx(headPtr), .tailIdx(headPtr + burst_len),
                 .outMask(curBurstMask)
                );

//vector of 1's for the current tail burst
vectorMask #(.LOG_WIDTH(LOG_QUEUE_SIZE)) tailBurst_mask
                (.headIdx(tailPtr), .tailIdx(tailPtr + burst_len),
                 .outMask(tailBurstMask)
                );
                
assign burst_len = reqBurstLen + 1;
assign active = |validVec; //at least one block is valid
assign respData = dataReady_curBurst ? dataMat[headPtr + burstOffset] : dataMat[headPtr + burst_len + burstOffset]; //Pass data in head/head+1, based on promise&dataValid of head
assign respLast = lastVec[headPtr + burstOffset];
assign isFull = ((QUEUE_SIZE - validCnt) < {{1'b0},{burst_len}}) & active;
assign isEmpty = ~|validVec;
assign almostFull = (validCnt + (crs_almostFullSpacer * burst_len)  >= QUEUE_SIZE) & active;
assign dataReady_curBurst = (validVec[headPtr + burstOffset] && dataValidVec[headPtr + burstOffset] == 1'b1 && promiseCnt[headPtr] > {(PROMISE_WIDTH){1'b0}});
assign dataReady_nxtBurst = (validVec[headPtr + burst_len] && dataValidVec[headPtr + burst_len] == 1'b1 && promiseCnt[headPtr + burst_len] > {(PROMISE_WIDTH){1'b0}});
assign pr_r_valid = (dataReady_curBurst || ((promiseCnt[headPtr] == {(PROMISE_WIDTH){1'b0}}) && dataReady_nxtBurst)) & active;
assign hasOutstanding = |((dataValidVec & validVec) ^ validVec);

// 0 - NOP ,1 - readReqPref,  2 - readReqManager(AXI AR/Read Request), 3 - readDataSubordinate(AXI R/Read Data), 4 - readDataPromise

always_ff @(posedge clk or negedge resetN)
begin
	if(!resetN)	begin 
        validVec <= {QUEUE_SIZE{1'b0}};
        
        prefetchReqVec <= {QUEUE_SIZE{1'b0}};
        headPtr <= {LOG_QUEUE_SIZE{1'b0}};;
        tailPtr <= {LOG_QUEUE_SIZE{1'b0}};;
        readDataPtr <= {LOG_QUEUE_SIZE{1'b0}};;
        errorCode <= 3'b0;
        burstOffset <= {LOG_QUEUE_SIZE{1'b0}};
    end else begin
        errorCode <= 3'd0;

        case (reqOpcode)
            3'd0: ;//NOP - Do nothing

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
                    tailPtr <= tailPtr + burst_len;
                end else begin 
                    //Queue full!
                    errorCode <= 3'd2;
                end
            end

            // readReqManager (Read requests which were initiated by transactions from the MASTER)
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
                    tailPtr <= tailPtr + burst_len;
                end else begin 
                    //Queue full!
                    errorCode <= 3'd2;
                end
            end

            // readDataSubordinate (Receiving read data from SLAVE)
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
                        headPtr = headPtr + burst_len;
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

`resetall

//todo throw error if getting 'data read' when not expected (validVec[readDataPtr] == 0)

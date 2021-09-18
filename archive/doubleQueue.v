//TODO: Insert descrpition
// ...
//Note: If queue is full (=all valid bits are on), pushing will overwrite the last block.


module	doubleQueue	(
	clk,        //<i
	resetN,     //<i
	pushEn,     //<i
	inVector,   //<i
    popEn,      //<i
	
	dataVal,    //>o
    valid       //>o
);

input	clk;
input	resetN;
input	pushEn;
input	[DATA_BITS-1:0]	inVector;
input   popEn;

output	reg [DATA_BITS-1:0][REG_DEPTH-1:0] dataVal;
output  reg [REG_DEPTH-1:0] valid;

parameter DATA_BITS = 32; //Num of bits of the input data
parameter REG_DEPTH = 5; 

always @(posedge clk or negedge resetN)
begin
	if(!resetN)	begin
        valid <= 0;
	end
	else begin
		if(pushEn & !popEn) begin
			dataVal[REG_DEPTH-1:0] <= {dataVal[REG_DEPTH-2:0],inVector};
            valid[0] <= 1'b1;
        end
        else if(popEn & !pushEn) begin 
            dataVal[REG_DEPTH-2:0] <= dataVal[REG_DEPTH-1:1];
            valid[REG_DEPTH-1] <= 1'b0;
        end
	end
end

endmodule

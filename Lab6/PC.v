module PC (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,
    input                   [ 0 : 0]            en,
    input                   [31 : 0]            npc,
    input                   [ 0 : 0]            stall_pc,

    output                  [31 : 0]            pc_out
);
reg [31:0] pc;
always @(posedge clk) begin
    if(rst)
        pc<=32'h00400000;
    else if(stall_pc)
        pc<=pc_out;
    else if(en)
        pc<=npc;
end

assign pc_out=pc;

endmodule
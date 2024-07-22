`define ADD                 5'B00000    
`define SUB                 5'B00010   
`define SLT                 5'B00100
`define SLTU                5'B00101
`define AND                 5'B01001
`define OR                  5'B01010
`define XOR                 5'B01011
`define SLL                 5'B01110   
`define SRL                 5'B01111    
`define SRA                 5'B10000  
`define SRC0                5'B10001
`define SRC1                5'B10010

module ALU (
    input                   [31 : 0]            alu_src0,
    input                   [31 : 0]            alu_src1,
    input                   [ 4 : 0]            alu_op,

    output      reg         [31 : 0]            alu_res
);

    always @(*) begin
        case(alu_op)
            `ADD  :
                alu_res = alu_src0 + alu_src1;
            `SUB:
                alu_res=alu_src0-alu_src1;
            `SLTU:
                if(alu_src0<alu_src1)
                    alu_res=1;
                else
                    alu_res=0;
            `SLT:
                if(alu_src0[31]==1&&alu_src1[31]==0)
                    alu_res=1;
                else if(alu_src0[31]==0&&alu_src1[31]==1)
                    alu_res=0;
                else if(alu_src0[30:0]<alu_src1[30:0])
                    alu_res=1;
                else
                    alu_res=0;
            `AND:
                alu_res=alu_src0&alu_src1;
            `OR:
                alu_res=alu_src0|alu_src1;
            `SLL:
                alu_res=alu_src0<<alu_src1;
            `SRL:
                alu_res=alu_src0>>alu_src1;
            `SRA:
                alu_res=alu_src0>>>alu_src1;
            `SRC0:
                alu_res=alu_src0;
            `SRC1:
                alu_res=alu_src1;
            default :
                alu_res = 32'H0;
        endcase
    end
endmodule


module Decoder (
    input [1:0]ctrl,
    input enable,
    output reg res_en,src0_en,src1_en,op_en
);
    always @(*) begin
        if(enable==1)begin
            if(ctrl==2'b00)begin
                res_en=0;
                src0_en=0;
                src1_en=0;
                op_en=1;
            end
            else if(ctrl==2'b01)begin
                res_en=0;
                src0_en=1;
                src1_en=0;
                op_en=0;
            end
            else if(ctrl==2'b10)begin
                res_en=0;
                src0_en=0;
                src1_en=1;
                op_en=0;
            end
            else begin
                res_en=1;
                src0_en=0;
                src1_en=0;
                op_en=0;
            end
        end
        else begin
            res_en=0;
            src0_en=0;
            src1_en=0;
            op_en=0;
        end
    end
endmodule


module Reg (
    input clk,
    input [4:0] in,
    input en,
    output [31:0] outdata
);
    reg [31:0] register;
    always @(posedge clk) begin
        if(en)begin
            case (in[4:4])
                1'b0:begin
                    register<={28'h0000000,in[3:0]};
                end 
                1'b1:begin
                    register<={28'hfffffff,in[3:0]};
                end
            endcase
        end
    end
    assign outdata=register;
endmodule

module Reg5 (
    input clk,
    input [4:0] in,
    input en,
    output [4:0] outdata
);
    reg [4:0] register;
    always @(posedge clk) begin
        if(en)begin
            register<=in;
        end
    end
    assign outdata=register;
endmodule

module Reg32 (
    input clk,
    input [31:0] in,
    input en,
    output [31:0] outdata
);
    reg [31:0] register;
    always @(posedge clk) begin
        if(en)begin
            register<=in;
        end
    end
    assign outdata=register;

endmodule


module Segment(
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,
    input                   [31 : 0]            output_data,
    output          reg     [ 3 : 0]            seg_data,
    output          reg     [ 2 : 0]            seg_an
);

parameter COUNT_NUM = 50_000_000 / 400;         // 100MHz to 400Hz
parameter SEG_NUM = 8;                          // Number of segments

reg [31:0] counter;
always @(posedge clk) begin
    if (rst)
        counter <= 0;
    else if (counter >= COUNT_NUM)
        counter <= 0;
    else
        counter <= counter + 1;
end

reg [2:0] seg_id;
always @(posedge clk) begin
    if (rst)
        seg_id <= 0;
    else if (counter == COUNT_NUM) begin
        if (seg_id >= SEG_NUM - 1)
            seg_id <= 0;
        else
            seg_id <= seg_id + 1;
    end
end

always @(*) begin
    seg_data = 0;
    case (seg_an)
        'd0     : seg_data = output_data[3:0]; 
        'd1     : seg_data = output_data[7:4];
        'd2     : seg_data = output_data[11:8];
        'd3     : seg_data = output_data[15:12];
        'd4     : seg_data = output_data[19:16];
        'd5     : seg_data = output_data[23:20];
        'd6     : seg_data = output_data[27:24];
        'd7     : seg_data = output_data[31:28];
        default : seg_data = 0;
    endcase
end

always @(*) begin
    seg_an = seg_id;
end
endmodule



module TOP (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,

    input                   [ 0 : 0]            enable,
    input                   [ 4 : 0]            in,
    input                   [ 1 : 0]            ctrl,

    output                  [ 3 : 0]            seg_data,
    output                  [ 2 : 0]            seg_an
);
    wire res_en,src0_en,src1_en,op_en;
    wire [31:0] res,src0,src1,outdata;
    wire [4:0] op;

    Decoder decoder(
        .ctrl(ctrl),
        .enable(enable),
        .res_en(res_en),
        .src0_en(src0_en),
        .src1_en(src1_en),
        .op_en(op_en)
    );

    Reg32 Res(
        .clk(clk),
        .in(res),
        .en(res_en),
        .outdata(outdata)
    );
    Reg Src0(
        .clk(clk),
        .in(in),
        .en(src0_en),
        .outdata(src0)
    );
    Reg Src1(
        .clk(clk),
        .in(in),
        .en(src1_en),
        .outdata(src1)
    );
    Reg5 Op(
        .clk(clk),
        .in(in),
        .en(op_en),
        .outdata(op)
    );

    ALU alu(
        .alu_src0(src0),
        .alu_src1(src1),
        .alu_res(res),
        .alu_op(op)
    );

    Segment segment(
        .clk(clk),
        .rst(rst),
        .output_data(outdata),
        .seg_an(seg_an),
        .seg_data(seg_data)
    );

endmodule
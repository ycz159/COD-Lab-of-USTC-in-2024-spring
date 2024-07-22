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
             `XOR:
                alu_res=alu_src0^alu_src1;
            `SLL:
                alu_res=alu_src0<<alu_src1[4:0];
            `SRL:
                alu_res=alu_src0>>alu_src1[4:0];
            `SRA:
                alu_res=alu_src0>>>alu_src1[4:0];
            `SRC0:
                alu_res=alu_src0;
            `SRC1:
                alu_res=alu_src1;
            default :
                alu_res = 32'H0;
        endcase
    end
endmodule


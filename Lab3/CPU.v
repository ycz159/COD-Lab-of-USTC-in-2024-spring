//`include "./include/config.v";

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
`define HALT_INST           32'H00100073

module CPU (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,

    input                   [ 0 : 0]            global_en,

/* ------------------------------ Memory (inst) ----------------------------- */
    output                  [31 : 0]            imem_raddr,
    input                   [31 : 0]            imem_rdata,

/* ------------------------------ Memory (data) ----------------------------- */
    input                   [31 : 0]            dmem_rdata, // Unused
    output                  [ 0 : 0]            dmem_we,    // Unused
    output                  [31 : 0]            dmem_addr,  // Unused
    output                  [31 : 0]            dmem_wdata, // Unused

/* ---------------------------------- Debug --------------------------------- */
    output                  [ 0 : 0]            commit,
    output                  [31 : 0]            commit_pc,
    output                  [31 : 0]            commit_inst,
    output                  [ 0 : 0]            commit_halt,
    output                  [ 0 : 0]            commit_reg_we,
    output                  [ 4 : 0]            commit_reg_wa,
    output                  [31 : 0]            commit_reg_wd,
    output                  [ 0 : 0]            commit_dmem_we,
    output                  [31 : 0]            commit_dmem_wa,
    output                  [31 : 0]            commit_dmem_wd,

    input                   [ 4 : 0]            debug_reg_ra,
    output                  [31 : 0]            debug_reg_rd
);


// TODO
wire [31:0] pc_out;
PC pc(
    .clk(clk),
    .rst(rst),
    .en(global_en),
    .npc(pc_out+4),
    .pc(pc_out)
);
assign imem_raddr=pc_out;

wire [4:0] alu_op,rf_ra0,rf_ra1,rf_wa;
wire [31 : 0] imm;
wire [0:0] rf_we,alu_src0_sel,alu_src1_sel;
DECODE decode(
    .inst(imem_rdata),
    .alu_op(alu_op),
    .imm(imm),
    .rf_ra0(rf_ra0),
    .rf_ra1(rf_ra1),
    .rf_wa(rf_wa),
    .rf_we(rf_we),
    .alu_src0_sel(alu_src0_sel),
    .alu_src1_sel(alu_src1_sel)
);

wire [31:0] alu_res,rf_rd0,rf_rd1;
REG_FILE reg_file(
    .clk(clk),
    .rf_ra0(rf_ra0),
    .rf_ra1(rf_ra1),
    .rf_wa(rf_wa),
    .rf_we(rf_we),
    .rf_wd(alu_res),
    .rf_rd0(rf_rd0),
    .rf_rd1(rf_rd1),
    .debug_reg_ra(debug_reg_ra),
    .debug_reg_rd(debug_reg_rd)
);

wire [31:0] alu_src0,alu_src1;
MUX mux0(
    .src0(pc_out),
    .src1(rf_rd0),
    .sel(alu_src0_sel),
    .res(alu_src0)
);
MUX mux1(
    .src0(rf_rd1),
    .src1(imm),
    .sel(alu_src1_sel),
    .res(alu_src1)
);

ALU alu(
    .alu_op(alu_op),
    .alu_src0(alu_src0),
    .alu_src1(alu_src1),
    .alu_res(alu_res)
);
/* -------------------------------------------------------------------------- */
/*                                    Commit                                  */
/* -------------------------------------------------------------------------- */

    wire [ 0 : 0] commit_if     ;
    assign commit_if = 1'H1;

    reg  [ 0 : 0]   commit_reg          ;
    reg  [31 : 0]   commit_pc_reg       ;
    reg  [31 : 0]   commit_inst_reg     ;
    reg  [ 0 : 0]   commit_halt_reg     ;
    reg  [ 0 : 0]   commit_reg_we_reg   ;
    reg  [ 4 : 0]   commit_reg_wa_reg   ;
    reg  [31 : 0]   commit_reg_wd_reg   ;
    reg  [ 0 : 0]   commit_dmem_we_reg  ;
    reg  [31 : 0]   commit_dmem_wa_reg  ;
    reg  [31 : 0]   commit_dmem_wd_reg  ;

    always @(posedge clk) begin
        if (rst) begin
            commit_reg          <= 1'H0;
            commit_pc_reg       <= 32'H0;
            commit_inst_reg     <= 32'H0;
            commit_halt_reg     <= 1'H0;
            commit_reg_we_reg   <= 1'H0;
            commit_reg_wa_reg   <= 5'H0;
            commit_reg_wd_reg   <= 32'H0;
            commit_dmem_we_reg  <= 1'H0;
            commit_dmem_wa_reg  <= 32'H0;
            commit_dmem_wd_reg  <= 32'H0;
        end
        else if (global_en) begin
            commit_reg          <= commit_if;
            commit_pc_reg       <= pc_out;       // TODO
            commit_inst_reg     <= imem_rdata;       // TODO
            commit_halt_reg     <= imem_rdata==`HALT_INST;       // TODO
            commit_reg_we_reg   <= rf_we;       // TODO
            commit_reg_wa_reg   <= rf_wa;       // TODO
            commit_reg_wd_reg   <= alu_res;       // TODO
            commit_dmem_we_reg  <= 0;
            commit_dmem_wa_reg  <= 0;
            commit_dmem_wd_reg  <= 0;
        end
    end

    assign commit               = commit_reg;
    assign commit_pc            = commit_pc_reg;
    assign commit_inst          = commit_inst_reg;
    assign commit_halt          = commit_halt_reg;
    assign commit_reg_we        = commit_reg_we_reg;
    assign commit_reg_wa        = commit_reg_wa_reg;
    assign commit_reg_wd        = commit_reg_wd_reg;
    assign commit_dmem_we       = commit_dmem_we_reg;
    assign commit_dmem_wa       = commit_dmem_wa_reg;
    assign commit_dmem_wd       = commit_dmem_wd_reg;
endmodule


module PC (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,
    input                   [ 0 : 0]            en,
    input                   [31 : 0]            npc,

    output      reg         [31 : 0]            pc
);
reg [31:0] q;
always @(posedge clk) begin
    if(rst)
        pc<=32'h00400000;
    else if(en)
        pc<=npc;
end

endmodule


module DECODE (
    input                   [31 : 0]            inst,

    output          reg        [ 4 : 0]            alu_op,
    output          reg        [31 : 0]            imm,

    output          reg        [ 4 : 0]            rf_ra0,
    output          reg        [ 4 : 0]            rf_ra1,
    output          reg        [ 4 : 0]            rf_wa,
    output          reg        [ 0 : 0]            rf_we,

    output          reg        [ 0 : 0]            alu_src0_sel,
    output          reg        [ 0 : 0]            alu_src1_sel
);
always @(*) begin
    case (inst[6:0])
        7'b0110011:begin//R-Type
            imm=32'h00000000;

            rf_ra0=inst[19:15];
            rf_ra1=inst[24:20];
            rf_wa=inst[11:7];
            rf_we=1'b1;

            alu_src0_sel=1'b1;
            alu_src1_sel=1'b0;

            case (inst[14:12])
                3'b000:begin//add,sub,
                    case (inst[31:25])
                        7'b0000000:begin//add
                            alu_op=`ADD;
                        end 
                        7'b0100000:begin//sub
                            alu_op=`SUB;
                        end
                    endcase
                end 
                3'b001:begin//sll
                    alu_op=`SLL;
                end
                3'b010:begin//slt
                    alu_op=`SLT;                   
                end
                3'b011:begin//sltu
                    alu_op=`SLTU;                   
                end
                3'b100:begin//xor
                    alu_op=`XOR;
                end
                3'b101:begin//srl,sra
                    case (inst[31:25])
                        7'b0000000:begin//srl
                            alu_op=`SRL;
                        end
                        7'b0100000:begin//sra
                            alu_op=`SRA;
                        end 
                    endcase
                end
                3'b110:begin//or
                    alu_op=`OR;
                end
                3'b111:begin//and
                    alu_op=`AND;
                end
            endcase
        end
        7'b0010011:begin//I-Type
            rf_ra0<=inst[19:15];
            rf_ra1<=5'b00000;
            rf_wa<=inst[11:7];
            rf_we<=1'b1;

            alu_src0_sel=1'b1;
            alu_src1_sel=1'b1;            
            
            case (inst[14:12])
                3'b000:begin//addi
                    alu_op=`ADD;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b010:begin//slti
                    alu_op=`SLT;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b011:begin//sltiu
                    alu_op=`SLTU;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end 
                3'b100:begin//xori
                    alu_op=`XOR;
                    imm={20'h00000,inst[31:20]};
                end
                3'b110:begin//ori
                    alu_op=`OR;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b111:begin//andi
                    alu_op=`AND;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b001:begin//slli
                    alu_op=`SLL;
                    imm={{20{inst[31:31]}},inst[31:20]};
                end
                3'b101:begin//srli,srai
                    case (inst[31:25])
                        7'b0000000: begin//srli
                            alu_op=`SRL;
                            imm={27'b0,inst[24:20]};
                        end
                        7'b0100000:begin//srai
                            alu_op=`SRA;
                            imm={27'b0,inst[24:20]};
                        end
                    endcase
                end
            endcase
        end 
        7'b0110111:begin//lui
            alu_op=`ADD;
            imm={inst[31:12],12'h000};

            rf_ra0<=5'b00000;
            rf_ra1<=5'b00000;
            rf_wa<=inst[11:7];
            rf_we<=1'b1;

            alu_src0_sel=1'b1;
            alu_src1_sel=1'b1;                        
        end
        7'b0010111:begin//auipc
            alu_op=`ADD;
            imm={inst[31:12],12'h000};

            rf_ra0<=5'b00000;
            rf_ra1<=5'b00000;
            rf_wa<=inst[11:7];
            rf_we<=1'b1;

            alu_src0_sel=1'b0;
            alu_src1_sel=1'b1;            
        end
/*    7'b1110011:begin
        case (inst[31:7])
            25'b0000_0000_0001_0000_0000_0000_0:begin
                
            end            
        endcase
    end*/
    endcase
end
endmodule

module REG_FILE (
    input                   [ 0 : 0]        clk,

    input                   [ 4 : 0]        rf_ra0,
    input                   [ 4 : 0]        rf_ra1,   
    input                   [ 4 : 0]        rf_wa,
    input                   [ 0 : 0]        rf_we,
    input                   [31 : 0]        rf_wd,
    input                   [ 4 : 0]        debug_reg_ra,
    
    output        reg       [31 : 0]        debug_reg_rd,
    output        reg          [31 : 0]        rf_rd0,
    output        reg          [31 : 0]        rf_rd1
);

    reg [31 : 0] reg_file [0 : 31];

    // 用于初始化寄存器
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            reg_file[i] = 0;
    end

    always @(posedge clk) begin
        if(rf_we&&rf_wa!=0)begin
            reg_file[rf_wa] <= rf_wd;
        end  
    end

    always @(*) begin
        debug_reg_rd=reg_file[debug_reg_ra];
        rf_rd0=reg_file[rf_ra0];
        rf_rd1=reg_file[rf_ra1];
    end

endmodule

module MUX # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           src0, src1,
    input                   [      0 : 0]           sel,

    output                  [WIDTH-1 : 0]           res
);

    assign res = sel ? src1 : src0;

endmodule

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
            `XOR:
                alu_res=alu_src0^alu_src1;
            `OR:
                alu_res=alu_src0|alu_src1;
            `SLL:
                alu_res=alu_src0<<alu_src1[4:0];
            `SRL:
                alu_res=alu_src0>>alu_src1[4:0];
            `SRA:
                alu_res=($signed(alu_src0))>>>alu_src1[4:0];
            `SRC0:
                alu_res=alu_src0;
            `SRC1:
                alu_res=alu_src1;
            default :
                alu_res = 32'H0;
        endcase
    end
endmodule

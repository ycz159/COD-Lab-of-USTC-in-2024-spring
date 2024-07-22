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
//new
`define jal     4'b1001
`define jalr    4'b1010

`define beq     4'b0000
`define bne     4'b0001
`define blt     4'b0100
`define bge     4'b0101
`define bltu    4'b0110
`define bgeu    4'b0111

`define I_beq     3'b000
`define I_bne     3'b001
`define I_blt     3'b100
`define I_bge     3'b101
`define I_bltu    3'b110
`define I_bgeu    3'b111


`define lb  4'b0000
`define lbu 4'b0001
`define lh  4'b0010
`define lhu 4'b0011
`define lw  4'b0100
`define sb  4'b1000
`define sh  4'b1010
`define sw  4'b1100

module CPU (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,

    input                   [ 0 : 0]            global_en,

/* ------------------------------ Memory (inst) ----------------------------- */
    output                  [31 : 0]            imem_raddr,
    input                   [31 : 0]            imem_rdata,

/* ------------------------------ Memory (data) ----------------------------- */
    input                   [31 : 0]            dmem_rdata,
    output                  [ 0 : 0]            dmem_we,
    output                  [31 : 0]            dmem_addr,
    output                  [31 : 0]            dmem_wdata,

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

    input                   [ 4 : 0]            debug_reg_ra,   // TODO
    output                  [31 : 0]            debug_reg_rd    // TODO
);

// TODO
assign dmem_we=global_en;
wire [31:0] pc_out,npc;
PC pc(
    .clk(clk),
    .rst(rst),
    .en(global_en),
    .npc(npc),
    .pc_out(pc_out)
);
assign imem_raddr=pc_out;

wire [31:0] alu_res;
wire [1:0] npc_sel;
NPC_MUX npc_mux(
    .npc_sel(npc_sel),
    .pc_add4(pc_out+4),
    .pc_offset(alu_res),
    .pc_j(alu_res&32'hfffffffe),
    .npc(npc)
);

wire [4:0] alu_op,rf_ra0,rf_ra1,rf_wa;
wire [31 : 0] imm;
wire [0:0] rf_we,alu_src0_sel,alu_src1_sel;
wire [3:0] dmem_access,br_type;
wire [1:0] rf_wd_sel;
DECODER decoder(
    .inst(imem_rdata),
    .alu_op(alu_op),
    .dmem_access(dmem_access),
    .imm(imm),
    .rf_ra0(rf_ra0),
    .rf_ra1(rf_ra1),
    .rf_wa(rf_wa),
    .rf_we(rf_we),
    .rf_wd_sel(rf_wd_sel),
    .alu_src0_sel(alu_src0_sel),
    .alu_src1_sel(alu_src1_sel),
    .br_type(br_type)
);

wire [31:0] rf_wd_mux_outdata,rf_rd0,rf_rd1;
REG_FILE reg_file(
    .clk(clk),
    .rf_ra0(rf_ra0),
    .rf_ra1(rf_ra1),
    .rf_wa(rf_wa),
    .rf_we(rf_we),
    .rf_wd(rf_wd_mux_outdata),
    .rf_rd0(rf_rd0),
    .rf_rd1(rf_rd1),
    .dbg_reg_ra(debug_reg_ra),
    .dbg_reg_rd(debug_reg_rd)
);

wire [31:0] alu_src0,alu_src1;
MUX2 mux0(
    .src0(pc_out),
    .src1(rf_rd0),
    .sel(alu_src0_sel),
    .res(alu_src0)
);
MUX2 mux1(
    .src0(rf_rd1),
    .src1(imm),
    .sel(alu_src1_sel),
    .res(alu_src1)
);

BRANCH branch(
    .br_type(br_type),
    .br_src0(rf_rd0),
    .br_src1(rf_rd1),
    .npc_sel(npc_sel)
);

ALU alu(
    .alu_op(alu_op),
    .alu_src0(alu_src0),
    .alu_src1(alu_src1),
    .alu_res(alu_res)
);
assign dmem_addr=alu_res;

wire [31:0] dmem_rd_out;
MUX4 rf_wd_mux(
    .src0(pc_out+4),
    .src1(alu_res),
    .src2(dmem_rd_out),
    .src3(32'h00000000),
    .sel(rf_wd_sel),
    .res(rf_wd_mux_outdata)
);

wire [31:0] dmem_wdata_slu;
SLU slu(
    .addr(alu_res),
    .dmem_access(dmem_access),
    .rd_in(dmem_rdata),
    .rd_out(dmem_rd_out),
    .wd_in(rf_rd1),
    .wd_out(dmem_wdata_slu)
);
assign dmem_wdata=dmem_wdata_slu;





    // Commit
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

    // Commit
    always @(posedge clk) begin
        if (rst) begin
            commit_reg          <= 1'B0;
            commit_pc_reg       <= 32'H0;
            commit_inst_reg     <= 32'H0;
            commit_halt_reg     <= 1'B0;
            commit_reg_we_reg   <= 1'B0;
            commit_reg_wa_reg   <= 5'H0;
            commit_reg_wd_reg   <= 32'H0;
            commit_dmem_we_reg  <= 1'B0;
            commit_dmem_wa_reg  <= 32'H0;
            commit_dmem_wd_reg  <= 32'H0;
        end
        else if (global_en) begin
            commit_reg          <= 1'B1;
            commit_pc_reg       <= pc_out;       // TODO
            commit_inst_reg     <= imem_rdata;       // TODO
            commit_halt_reg     <= imem_rdata==32'h00100073;       // TODO
            commit_reg_we_reg   <= rf_we;       // TODO
            commit_reg_wa_reg   <= rf_wa;       // TODO
            commit_reg_wd_reg   <= alu_res;       // TODO
            commit_dmem_we_reg  <= dmem_we;
            commit_dmem_wa_reg  <= dmem_addr;
            commit_dmem_wd_reg  <= dmem_wdata_slu;
        end
    end

    assign commit           = commit_reg;
    assign commit_pc        = commit_pc_reg;
    assign commit_inst      = commit_inst_reg;
    assign commit_halt      = commit_halt_reg;
    assign commit_reg_we    = commit_reg_we_reg;
    assign commit_reg_wa    = commit_reg_wa_reg;
    assign commit_reg_wd    = commit_reg_wd_reg;
    assign commit_dmem_we   = commit_dmem_we_reg;
    assign commit_dmem_wa   = commit_dmem_wa_reg;
    assign commit_dmem_wd   = commit_dmem_wd_reg;

endmodule


module PC (
    input                   [ 0 : 0]            clk,
    input                   [ 0 : 0]            rst,
    input                   [ 0 : 0]            en,
    input                   [31 : 0]            npc,

    output                  [31 : 0]            pc_out
);
reg [31:0] pc;
always @(posedge clk) begin
    if(rst)
        pc<=32'h00400000;
    else if(en)
        pc<=npc;
end

assign pc_out=pc;

endmodule

module NPC_MUX # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           pc_add4,pc_offset,pc_j,
    input                   [      1 : 0]           npc_sel,

    output        reg       [WIDTH-1 : 0]           npc
);

    always @(*) begin
        case (npc_sel)
            2'b00:
                npc = pc_add4; 
            2'b01:
                npc = pc_offset; 
            2'b10:
                npc = pc_j;
        endcase
    end

endmodule

module DECODER (
    input                   [31 : 0]            inst,

    output      reg         [ 4 : 0]            alu_op,

    output      reg         [ 3 : 0]            dmem_access,

    output      reg         [31 : 0]            imm,

    output                  [ 4 : 0]            rf_ra0,
    output                  [ 4 : 0]            rf_ra1,
    output                  [ 4 : 0]            rf_wa,
    output                  [ 0 : 0]            rf_we,
    output                  [ 1 : 0]            rf_wd_sel,

    output                  [ 0 : 0]            alu_src0_sel,
    output                  [ 0 : 0]            alu_src1_sel,

    output                  [ 3 : 0]            br_type
);

reg [4:0] rf_ra0_reg,rf_ra1_reg,rf_wa_reg;
reg [3:0] br_type_reg;
reg [0:0] rf_we_reg,alu_src0_sel_reg,alu_src1_sel_reg;
reg [1:0] rf_wd_sel_reg;

always @(*) begin

    case (inst[6:0])
        7'b0110011:begin//R-Type
            imm<=32'h00000000;

            rf_ra0_reg<=inst[19:15];
            rf_ra1_reg<=inst[24:20];
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b0;
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;

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
            rf_ra0_reg<=inst[19:15];
            rf_ra1_reg<=5'b00000;
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;            
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;

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
                    imm={{20{inst[31:31]}},inst[31:20]};
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

            rf_ra0_reg<=5'b00000;
            rf_ra1_reg<=5'b00000;
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;  
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;  
        end
        7'b0010111:begin//auipc
            alu_op=`ADD;
            imm={inst[31:12],12'h000};

            rf_ra0_reg<=5'b00000;
            rf_ra1_reg<=5'b00000;
            rf_wa_reg<=inst[11:7];
            rf_we_reg<=1'b1;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b1; 
            //new
            dmem_access=4'hf;
            rf_wd_sel_reg=2'b01;
            br_type_reg=4'hf;   
        end
        7'b1100011:begin//B-Type
            alu_op=`ADD;
            dmem_access=4'hf;
            imm={{20{inst[31:31]}},inst[7:7],inst[30:25],inst[11:8],1'b0};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=inst[24:20];
            rf_wa_reg=5'b00000;
            rf_we_reg=1'b0;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b1;

            case (inst[14:12])
                `I_beq:
                    br_type_reg=`beq;
                `I_bne:
                    br_type_reg=`bne;
                `I_blt:
                    br_type_reg=`blt;
                `I_bge:
                    br_type_reg=`bge;
                `I_bltu:
                    br_type_reg=`bltu;
                `I_bgeu:
                    br_type_reg=`bgeu;
            endcase
        end
        7'b1101111:begin//jal
            alu_op=`ADD;
            dmem_access=4'hf;
            imm={{12{inst[31:31]}},inst[19:12],inst[20:20],inst[30:21],1'b0};

            rf_ra0_reg=5'b00000;
            rf_ra1_reg=5'b00000;
            rf_wa_reg=inst[11:7];
            rf_we_reg=1'b1;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b0;
            alu_src1_sel_reg=1'b1;

            br_type_reg=`jal;

        end
        7'b1100111:begin//jalr
            alu_op=`ADD;
            dmem_access=4'hf;
            imm={{21{inst[31:31]}},inst[30:20]};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=5'b00000;
            rf_wa_reg=inst[11:7];
            rf_we_reg=1'b1;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;

            br_type_reg=`jalr;
            
        end
        7'b0000011:begin//L-Type
            alu_op=`ADD;
            imm={20'h00000,inst[31:20]};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=5'b00000;
            rf_wa_reg=inst[11:7];
            rf_we_reg=1'b1;
            rf_wd_sel_reg=2'b10;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;

            br_type_reg=4'hf;

            case (inst[14:12])
                3'b000:begin//lb
                    dmem_access=`lb;
                end 
                3'b001:begin//lh
                    dmem_access=`lh;
                end
                3'b010:begin//lw
                    dmem_access=`lw;
                end
                3'b100:begin//lbu
                    dmem_access=`lbu;
                end
                3'b101:begin//lhu
                    dmem_access=`lhu;
                end
                default:begin
                    dmem_access=4'b1111;
                end
            endcase
        end
        7'b0100011:begin//S-Type
            alu_op=`ADD;
            imm={inst[31:25],inst[11:7]};

            rf_ra0_reg=inst[19:15];
            rf_ra1_reg=inst[24:20];
            rf_wa_reg=5'b00000;
            rf_we_reg=1'b0;
            rf_wd_sel_reg=2'b00;

            alu_src0_sel_reg=1'b1;
            alu_src1_sel_reg=1'b1;

            br_type_reg=4'hf;
            case (inst[14:12])
                3'b000:begin//sb
                    dmem_access=`sb;
                end 
                3'b001:begin//sh
                    dmem_access=`sh;
                end
                3'b010:begin//sw
                    dmem_access=`sw;
                end
                default: begin
                    dmem_access=4'b1111;
                end
            endcase
        end
    endcase
end

assign rf_ra0=rf_ra0_reg;
assign rf_ra1=rf_ra1_reg;
assign rf_wa=rf_wa_reg;
assign rf_wd_sel=rf_wd_sel_reg;
assign br_type=br_type_reg;
assign rf_we=rf_we_reg;
assign alu_src0_sel=alu_src0_sel_reg;
assign alu_src1_sel=alu_src1_sel_reg;

endmodule

module REG_FILE (
    input                   [ 0 : 0]        clk,

    input                   [ 4 : 0]        rf_ra0,
    input                   [ 4 : 0]        rf_ra1,   
    input                   [ 4 : 0]        rf_wa,
    input                   [ 0 : 0]        rf_we,
    input                   [31 : 0]        rf_wd,

    output        reg          [31 : 0]        rf_rd0,
    output        reg          [31 : 0]        rf_rd1,
    input      [4:0] dbg_reg_ra,
    output reg [31:0] dbg_reg_rd
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
        else begin
           reg_file[rf_wa] <= reg_file[rf_wa]; 
        end
    end

    always @(*) begin
        rf_rd0=reg_file[rf_ra0];
        rf_rd1=reg_file[rf_ra1];
        dbg_reg_rd=reg_file[dbg_reg_ra];
    end

endmodule

module MUX2 # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           src0, src1,
    input                   [      0 : 0]           sel,

    output                  [WIDTH-1 : 0]           res
);

    assign res = sel ? src1 : src0;

endmodule

module MUX4 # (
    parameter               WIDTH                   = 32
)(
    input                   [WIDTH-1 : 0]           src0, src1, src2, src3,
    input                   [      1 : 0]           sel,

    output                  [WIDTH-1 : 0]           res
);

    assign res = sel[1] ? (sel[0] ? src3 : src2) : (sel[0] ? src1 : src0);

endmodule

module BRANCH(
    input                   [ 3 : 0]            br_type,

    input                   [31 : 0]            br_src0,
    input                   [31 : 0]            br_src1,

    output      reg         [ 1 : 0]            npc_sel
);

always @(*) begin
    case (br_type)          
        `jal:begin
            npc_sel=2'b01;
        end
        `jalr:begin
            npc_sel=2'b10;
        end  
        `beq:begin
            if(br_src0==br_src1)
                npc_sel=2'b01;
            else
                npc_sel=2'b00;
        end
        `bne:begin
            if(br_src0!=br_src1)
                npc_sel=2'b10;
            else
                npc_sel=2'b00;
        end           
        `blt:begin
            if(br_src0[31]==1'b1&&br_src1[31]==1'b0)
                npc_sel=2'b01;
            else if(br_src0[31]==1'b0&&br_src1[31]==1'b1)
                npc_sel=2'b00;
            else if(br_src0[30:0]<br_src1[30:0])
                npc_sel=2'b01;
            else 
                npc_sel=2'b00;
        end
        `bge:begin
            if(br_src0[31]==1'b0&&br_src1[31]==1'b1)
                npc_sel=2'b01;
            else if(br_src0[31]==1'b1&&br_src1[31]==1'b0)
                npc_sel=2'b00;
            else if(br_src0[30:0]>=br_src1[30:0])
                npc_sel=2'b01;
            else 
                npc_sel=2'b00;
        end
        `bltu:begin
            if(br_src0<br_src1)
                npc_sel=2'b01;
            else
                npc_sel=2'b00;
        end
        `bgeu:begin
            if(br_src0>=br_src1)
                npc_sel=2'b01;
            else
                npc_sel=2'b00;
    end
        default:
            npc_sel=2'b00;
    endcase
end

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
            `OR:
                alu_res=alu_src0|alu_src1;
             `XOR:
                alu_res=alu_src0^alu_src1;
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

module SLU (
    input                   [31 : 0]                addr,
    input                   [ 3 : 0]                dmem_access,

    input                   [31 : 0]                rd_in,
    input                   [31 : 0]                wd_in,

    output      reg         [31 : 0]                rd_out,
    output      reg         [31 : 0]                wd_out
);

always @(*) begin
    case (dmem_access)
        `lb:begin
            wd_out=rd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={{24{rd_in[7:7]}},rd_in[7:0]};
                end 
                1:begin
                    rd_out={{24{rd_in[15:15]}},rd_in[15:8]};
                end
                2:begin
                    rd_out={{24{rd_in[23:23]}},rd_in[23:16]};
                end
                3:begin
                    rd_out={{24{rd_in[31:31]}},rd_in[31:24]};
                end
            endcase
        end 
        `lbu:begin
            wd_out=rd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={24'h000000,rd_in[7:0]};
                end 
                1:begin
                    rd_out={24'h000000,rd_in[15:8]};
                end
                2:begin
                    rd_out={24'h000000,rd_in[23:16]};
                end
                3:begin
                    rd_out={24'h000000,rd_in[31:24]};
                end
            endcase
        end
        `lh:begin
            wd_out=rd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={{16{rd_in[15:15]}},rd_in[15:0]};
                end
                2:begin
                    rd_out={{16{rd_in[31:31]}},rd_in[31:16]};
                end 
                default: begin
                    rd_out=32'hffffffff;
                end
            endcase
        end
        `lhu:begin
            wd_out=wd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out={16'h0000,rd_in[15:0]};
                end
                2:begin
                    rd_out={16'h0000,rd_in[31:16]};
                end 
                default: begin
                    rd_out=32'hffffffff;
                end
            endcase
        end
        `lw:begin
            wd_out=wd_in;
            case (addr[3:0]%4)
                0:begin
                    rd_out=rd_in;
                end 
                default:begin
                    rd_out=32'hffffffff;
                end 
            endcase
        end
        `sb:begin
            rd_out=32'h00000000;
            case (addr[3:0]%4)
                0:begin
                    wd_out={rd_in[31:8],wd_in[7:0]};
                end 
                1:begin
                    wd_out={rd_in[31:16],wd_in[7:0],rd_in[7:0]};
                end
                2:begin
                    wd_out={rd_in[31:24],wd_in[7:0],rd_in[15:0]};
                end
                3:begin
                    wd_out={rd_in[7:0],rd_in[23:0]};
                end 
            endcase
        end
        `sh:begin
            rd_out=32'h00000000;
            case (addr[3:0]%4)
                0:begin
                    wd_out={rd_in[31:16],wd_in[15:0]};
                end 
                2:begin
                    wd_out={wd_in[31:16],rd_in[15:0]};
                end
                default: begin
                    wd_out=rd_in;
                end
            endcase
        end
        `sw:begin
            rd_out=32'h00000000;
            case (addr[3:0]%4)
                0:begin
                    wd_out=wd_in;
                end 
                default:begin
                    wd_out=rd_in;
                end 
            endcase
        end
        default:begin
            wd_out=rd_in;
            rd_out=32'h00000000;
        end
    endcase
end

endmodule
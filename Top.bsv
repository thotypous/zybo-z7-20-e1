import ConfigReg::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import Vector::*;
import StmtFSM::*;
import TriState::*;

import GetPut_Aux::*;
import Semi_FIFOF::*;

import AXI4_Types::*;

typedef 12   Wd_Slave_Id;
typedef 32   Wd_Addr;
typedef 32   Wd_Slave_Data;
typedef  0   Wd_User;

interface AXI4_IFC;
    interface AXI4_Slave_IFC  #(Wd_Slave_Id,  Wd_Addr, Wd_Slave_Data,  Wd_User)  slave;
    (*always_ready*)
    method Bit#(1) irq;
endinterface

typedef Bit#(Wd_Addr) Addr;

interface TopIfc;
    interface AXI4_IFC axi;
    (*always_ready,always_enabled*)
    method Action put_rx(Bit#(1) rxp, Bit#(1) rxn);
    method Inout#(Bit#(1)) txp;
    method Inout#(Bit#(1)) txn;
endinterface

(* synthesize *)
module mkTop(TopIfc);
    FIFOF#(Bit#(1)) rxFifo <- mkSizedFIFOF(20000);
    Wire#(Bit#(1)) rxFifoEnqW <- mkWire;
    Reg#(Bool) overflownOnce[2] <- mkCReg(2, False);
    Reg#(Bool) triggered[3] <- mkCReg(3, False);

    Reg#(Bool) tx_en_reg <- mkReg(False);
    Reg#(Bit#(1)) txp_reg <- mkRegU;
    Reg#(Bit#(1)) txn_reg <- mkRegU;
    TriState#(Bit#(1)) txp_buf <- mkTriState(tx_en_reg, txp_reg);
    TriState#(Bit#(1)) txn_buf <- mkTriState(tx_en_reg, txn_reg);

    AXI4_Slave_Xactor_IFC #(Wd_Slave_Id,
                            Wd_Addr,
                            Wd_Slave_Data,
                            Wd_User) slave_xactor  <- mkAXI4_Slave_Xactor;

    rule trigger(!overflownOnce[0] && rxFifoEnqW == 1'b1);
        triggered[0] <= True;
    endrule

    rule rxFifo_enq(!overflownOnce[0] && triggered[1]);
        rxFifo.enq(rxFifoEnqW);
    endrule

    rule rxFifo_flag_overlow(!rxFifo.notFull);
        overflownOnce[0] <= True;
    endrule

    rule slave_rd;
        let rd_addr <- pop_o(slave_xactor.o_rd_addr);
        let addr = rd_addr.araddr[11:2];

        Bit#(Wd_Slave_Data) data = 32'hffffffff;  // default value

        if (addr == 0) begin           // noop for other addresses
            if (rxFifo.notEmpty) begin
                data = extend(pack(rxFifo.first));
                rxFifo.deq;
            end
        end

        AXI4_Rd_Data#(Wd_Slave_Id, Wd_Slave_Data, Wd_User)
        rd_data = AXI4_Rd_Data {rid:   rd_addr.arid,
                                rdata: data,
                                rresp: axi4_resp_okay,
                                rlast: True,
                                ruser: rd_addr.aruser};

        slave_xactor.i_rd_data.enq(rd_data);
    endrule

    rule slave_wr;
        let wr_addr <- pop_o(slave_xactor.o_wr_addr);
        let wr_data <- pop_o(slave_xactor.o_wr_data);

        let data = wr_data.wdata;
        let addr = wr_addr.awaddr[11:2];

        // TODO: use data, addr for something
        if (addr == 1) begin
            rxFifo.clear;
            overflownOnce[1] <= False;
            triggered[2] <= False;
        end

        AXI4_Wr_Resp#(Wd_Slave_Id, Wd_User)
        wr_resp = AXI4_Wr_Resp {bid:   wr_addr.awid,
                                bresp: axi4_resp_okay,
                                buser: wr_addr.awuser};

        slave_xactor.i_wr_resp.enq(wr_resp);
    endrule

    Stmt stmt = seq
        while(True) seq
            action
                txp_reg <= 1;
                txn_reg <= 0;
                tx_en_reg <= True;
            endaction
            delay(3);
            action
                tx_en_reg <= False;
            endaction
            delay(3);
            action
                txp_reg <= 0;
                txn_reg <= 1;
                tx_en_reg <= True;
            endaction
            delay(3);
            action
                tx_en_reg <= False;
            endaction
            delay(3+4);
        endseq
    endseq;

    mkAutoFSM(stmt);

    interface AXI4_IFC axi;
        interface slave = slave_xactor.axi_side;
        method irq = rxFifo.notEmpty ? 1 : 0;
    endinterface
    
    method Action put_rx(Bit#(1) rxp, Bit#(1) rxn);
        rxFifoEnqW <= rxp;
    endmethod

    method txp = txp_buf.io;
    method txn = txn_buf.io;
endmodule

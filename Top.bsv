import ConfigReg::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import Vector::*;

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
endinterface

(* synthesize *)
module mkTop(TopIfc);
    FIFOF#(Bit#(2)) rxFifo <- mkSizedFIFOF(100000);
    Wire#(Bit#(2)) rxFifoEnqW <- mkWire;
    Reg#(Bool) overflownOnce <- mkReg(False);

    AXI4_Slave_Xactor_IFC #(Wd_Slave_Id,
                            Wd_Addr,
                            Wd_Slave_Data,
                            Wd_User) slave_xactor  <- mkAXI4_Slave_Xactor;

    rule rxFifo_enq(!overflownOnce);
        rxFifo.enq(rxFifoEnqW);
    endrule

    rule rxFifo_flag_overlow(!rxFifo.notFull);
        overflownOnce <= True;
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

        AXI4_Wr_Resp#(Wd_Slave_Id, Wd_User)
        wr_resp = AXI4_Wr_Resp {bid:   wr_addr.awid,
                                bresp: axi4_resp_okay,
                                buser: wr_addr.awuser};

        slave_xactor.i_wr_resp.enq(wr_resp);
    endrule

    interface AXI4_IFC axi;
        interface slave = slave_xactor.axi_side;
        method irq = rxFifo.notEmpty ? 1 : 0;
    endinterface
    
    method Action put_rx(Bit#(1) rxp, Bit#(1) rxn);
        rxFifoEnqW <= {rxp, rxn};
    endmethod
endmodule

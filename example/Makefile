VIVADO    ?= vivado
INDEX     ?= 0
DUAL      ?= 0
AXIL      ?= 0
WRAP_QSFP ?= 0
BOARD     ?= v80
NCLK_F    ?= 391
DYNAMIC   ?= 0
MODE      ?= batch         # batch | gui

.PHONY: all clean

all:
	$(VIVADO) -mode $(MODE) \
	    -source create_dcmac_example.tcl \
	    -tclargs $(INDEX) $(DUAL) $(AXIL) $(WRAP_QSFP) $(BOARD) $(NCLK_F) $(DYNAMIC)

clean:
	rm -rf build vivado*.jou vivado*.log .Xil

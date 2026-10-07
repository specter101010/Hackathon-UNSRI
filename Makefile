RTL = rtl/dg_tile_ram.v rtl/dg_mac_lane.v rtl/dg_requant.v rtl/dg_tile_core.v rtl/dg_csr_top.v
.PHONY: test clean
test:
	mkdir -p build
	iverilog -g2005 -Wall -s dg_csr_top -o build/compile $(RTL)
	iverilog -g2012 -Wall -s tb_csr -o build/tb $(RTL) tb/tb_csr.v
	cd build && vvp tb
	iverilog -g2005 -Wall -s tb_requant -o build/tb_q rtl/dg_requant.v tb/tb_requant.v
	cd build && vvp tb_q
	iverilog -g2005 -Wall -s tb_scaling -Ptb_scaling.N=8 -o build/tb_8 $(RTL) tb/tb_scaling.v
	cd build && vvp tb_8
	iverilog -g2005 -Wall -s tb_scaling -Ptb_scaling.N=128 -o build/tb_128 $(RTL) tb/tb_scaling.v
	cd build && vvp tb_128
clean:
	rm -rf build

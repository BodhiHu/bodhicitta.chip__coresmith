lef read {/workspace/菩提树/coresmith/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef}
lef read {/workspace/菩提树/coresmith/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef}
gds read {/workspace/菩提树/coresmith/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds}
def read {/workspace/菩提树/coresmith/designs/cdna5-m1/pnr/tdm/tdm_routed.def}
load tdm
select top cell
extract all
ext2spice lvs
ext2spice -o {/workspace/菩提树/coresmith/designs/cdna5-m1/pnr/tdm/tdm.spice}
puts "SPICE written"
quit -noprompt

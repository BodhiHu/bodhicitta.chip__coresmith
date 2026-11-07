lef read {/workspace/菩提树/coresmith/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef}
lef read {/workspace/菩提树/coresmith/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef}
gds read {/workspace/菩提树/coresmith/.pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds}
def read {/workspace/菩提树/coresmith/designs/cdna5-m1/pnr/tdm/tdm_routed.def}
load tdm
flatten tdm_flat
load tdm_flat
select top cell
drc catchup
set n [drc listall count total]
set rpt [open {/workspace/菩提树/coresmith/designs/cdna5-m1/pnr/tdm/magic_drc.rpt} w]
puts $rpt "Design: tdm"
puts $rpt "DRC count: $n"
puts $rpt [drc listall why]
close $rpt
puts "DRC violations: $n"
quit -noprompt

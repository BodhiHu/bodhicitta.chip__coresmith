gds read pnr/tdm/tdm_mapped.gds
load tdm
select top cell
extract all
ext2spice lvs
ext2spice -o pnr/tdm/tdm_magic.spice
puts "EXTRACT DONE"
quit -noprompt

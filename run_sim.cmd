# RTL Simulation
make sim; 
make sim MODE=192; 
make sim MODE=256;

make sim VER=base; 
make sim MODE=192 VER=base; 
make sim MODE=256 VER=base;

make sim VER=sbox_cfa; 
make sim MODE=192 VER=sbox_cfa; 
make sim MODE=256 VER=sbox_cfa;

make sim VER=datapath32; 
make sim MODE=192 VER=datapath32; 
make sim MODE=256 VER=datapath32;i

# Synthesis
make syn; 
make syn MODE=192; 
make syn MODE=256;

make syn VER=base; 
make syn MODE=192 VER=base; 
make syn MODE=256 VER=base;

make syn VER=sbox_cfa; 
make syn MODE=192 VER=sbox_cfa; 
make syn MODE=256 VER=sbox_cfa;

make syn VER=datapath32; 
make syn MODE=192 VER=datapath32; 
make syn MODE=256 VER=datapath32;

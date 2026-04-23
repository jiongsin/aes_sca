# RTL Simulation
make sim; 
make sim MODE=192; 
make sim MODE=256;

make sim VER=base; 
make sim MODE=192 VER=base; 
make sim MODE=256 VER=base;

make sim VER=cfa; 
make sim MODE=192 VER=cfa; 
make sim MODE=256 VER=cfa;

make sim VER=datapath32; 
make sim MODE=192 VER=datapath32; 
make sim MODE=256 VER=datapath32;

# Synthesis
make syn; 
make syn MODE=192; 
make syn MODE=256;

make syn VER=base; 
make syn MODE=192 VER=base; 
make syn MODE=256 VER=base;

make syn VER=cfa; 
make syn MODE=192 VER=cfa; 
make syn MODE=256 VER=cfa;

make syn VER=datapath32; 
make syn MODE=192 VER=datapath32; 
make syn MODE=256 VER=datapath32;

# Pre Layout Simulation
make syn.sim; 
make syn.sim MODE=192; 
make syn.sim MODE=256;

make syn.sim VER=base; 
make syn.sim MODE=192 VER=base; 
make syn.sim MODE=256 VER=base;

make syn.sim VER=cfa; 
make syn.sim MODE=192 VER=cfa; 
make syn.sim MODE=256 VER=cfa;

make syn.sim VER=datapath32; 
make syn.sim MODE=192 VER=datapath32; 
make syn.sim MODE=256 VER=datapath32;


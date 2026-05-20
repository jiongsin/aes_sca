make saif syn syn.alp DESIGN=aes_ctr VER=sca MODE=128
find . -name "*chunk*" -exec rm -rf {} +
make saif syn syn.alp DESIGN=aes_ctr VER=sca MODE=192
find . -name "*chunk*" -exec rm -rf {} +
make saif syn syn.alp DESIGN=aes_ctr VER=sca MODE=256
find . -name "*chunk*" -exec rm -rf {} +
make saif syn syn.alp DESIGN=aes_ctr VER=base MODE=128
find . -name "*chunk*" -exec rm -rf {} +
make saif syn syn.alp DESIGN=aes_ctr VER=base MODE=192
find . -name "*chunk*" -exec rm -rf {} +
make saif syn syn.alp DESIGN=aes_ctr VER=base MODE=256
find . -name "*chunk*" -exec rm -rf {} +

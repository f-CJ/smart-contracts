@echo off
echo Loading Resources . . .
cd ../node_modules/.bin/
echo starting ganache-cli  . . .
./ganache-cli --gasLimit 0xfffffffffff -i 5777 -p 8545 -m 'grocery obvious wire insane limit weather parade parrot patrol stock blast ivory' -a 67 -e 10000000
ping 127.0.0.1 -n 5 > nul

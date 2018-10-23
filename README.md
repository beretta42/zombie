# Zombie Protocol #
for the Tandy Color Computer

This is a attempt at a UDP debugging/monitor/startup
code (in MC6809 assembler)

* UDP/IP stack
* DHCP client
* DNS look ups
* ARP for Ethernet
* Zombie protocol for Color Computer
- TCP (wip)

### Requirements for building ###

* lwtools  - William Astle's assembler, etc. for the 6809
* xxd      - a binary dumper that produces .h file for the master
* make     - builds everything.
* gcc      - Gnu's Compiler
* toolshed - (decb,makewav command) Color Computer toolkit

### To build ###
```
$ make
``` 

out will pop:

* zombie.dsk  - A disk image containing a DECB loadable zombie client
* zombie.bin  - zombie client executable
* master/zombie - a Linux master with CLI interface


### To Run: ###

1. setup tap interface (forward and NAT it)
2. start lwwire
    a  w/ packet interface
    b  might as well have zombie.dsk presented
3. run zombie master on a LAN connected computer
4. run "zombie.bin" on your color computer.

After loading/exec'ing  your zombie.bin will  go TSR, mooching  on the
60hz  timer interrupt.   It  will listen  on port  UDP  port 6999  for
command packets from a master.



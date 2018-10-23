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


# Set up tap interface
ip tuntap add dev tap0 mode tap
ip addr add 192.168.42.1/24 dev tap0
ip link set tap0 up
# Enable NAT and forwarding on the tap
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o wlp18s0b1 -j MASQUERADE
iptables -A FORWARD -i tap0 -o wlp18s0b1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i tap0 -o eth0 -j ACCEPT
# Run a dhcp server on the tap
dhcpd -f -cf zombie/dhcpd.test
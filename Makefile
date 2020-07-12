all: zombie.dsk server

AS = lwasm
ASFLAGS = -f obj 

SRCS = arp.s ip.s eth.s udp.s icmp.s dhcp2.s ip6809.s \
	resolv.s tcp.s encrypt.s igmp.s mdns.s wget.s
DRVS = lwwire.s coconic.s

OBJS = $(SRCS:.s=.o)

zombie.o: zombie.s
coconic.o: coconic.s
lwwire.o: lwwire.s
simnic.o: simnic.s
encrypt.o: encrypt.s
simtest.o: simtest.s

simtest.s19: $(OBJS) simnic.o simtest.o
	lwlink -fsrec -m simtest.map -s sim.link -o simtest.s19 $(OBJS) simtest.o simnic.o

zombie.bin: $(OBJS) coconic.o lwwire.o encrypt.o zombie.o
	lwlink -b -m zombie.map -s decb.link -o zombie.bin $(OBJS) zombie.o lwwire.o

zombie.dsk: zombie.bin
	rm -f zombie.dsk
	decb dskini zombie.dsk
	decb copy -2 -b zombie.bin zombie.dsk,ZOMBIE.BIN
	decb copy -l -0 -a AUTOEXEC.BAS zombie.dsk,AUTOEXEC.BAS

server:
	make -C master all

clean:
	rm -f *~ zombie.bin zombie.dsk zombie.map *.o simtest.s19 simtest.map
	make -C master clean

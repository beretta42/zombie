all: zombie.dsk server

AS = lwasm
ASFLAGS = -f obj 

SRCS = arp.s ip.s eth.s udp.s icmp.s zombie.s dhcp2.s ip6809.s \
	resolv.s tcp.s encrypt.s igmp.s mdns.s wget.s
DRVS = lwwire.s coconic.s

OBJS = $(SRCS:.s=.o)

coconic.o: coconic.s
lwwire.o: lwwire.s
encrypt.o: encrypt.s

zombie.bin: $(OBJS) coconic.o lwwire.o encrypt.o
	lwlink -b -m zombie.map -s decb.link -o zombie.bin $(OBJS) lwwire.o

zombie.dsk: zombie.bin
	rm -f zombie.dsk
	decb dskini zombie.dsk
	decb copy -2 -b zombie.bin zombie.dsk,ZOMBIE.BIN
	decb copy -l -0 -a AUTOEXEC.BAS zombie.dsk,AUTOEXEC.BAS

server:
	make -C master all

clean:
	rm -f *~ zombie.bin zombie.dsk zombie.map *.o
	make -C master clean

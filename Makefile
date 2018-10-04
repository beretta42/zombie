all: zombie.dsk

AS = lwasm
ASFLAGS = -f obj 

SRCS = arp.s ip.s eth.s udp.s icmp.s lwwire.s zombie.s dhcp2.s ip6809.s \
	resolv.s

OBJS = $(SRCS:.s=.o)

zombie.bin: $(OBJS)
	lwlink -b -m zombie.map -s decb.link -o zombie.bin $(OBJS)

zombie.dsk: zombie.bin
	rm -f zombie.dsk
	decb dskini zombie.dsk
	decb copy -2 -b zombie.bin zombie.dsk,ZOMBIE.BIN
	decb copy -l -0 -a AUTOEXEC.BAS zombie.dsk,AUTOEXEC.BAS

clean:
	rm -f *~ zombie.bin zombie.dsk zombie.map *.o


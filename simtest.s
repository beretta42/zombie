	include "zombie.def"

	export	start
	export  insize
	export  inmax
	export  inbuf
	export  put_char

ANN_TO	equ	5*60		; announcement timeout (5 sec)

	.area	.start
prog_start equ *
	.area	.end
prog_end equ *

	.area	.data
insize	rmb	2		; size of packet in input buffer
inbuf	rmb	2		; pointer to input buffer
inmax	.dw	576+14+5	; max size of input buffer


stack	rmb	64		; a private stack
stacke
sstack  rmb	2		; saved entry stack frame
time	rmb	2		; a ticker
atime	rmb	2		; announce every so often

	.area	.code

name	fcn	"BRETT'S COCO"
ibroad	.db	255,255,255,255


acia_handle
	ldx	#mess@
	jsr	puts
	rti
mess@	fcn	"acia"

packet_handle
	ldx	#mess@
	jsr	puts
	jsr	dev_in
	rti
mess@	fcn	"packet"

reset_handle
	ldx	#mess@
	jsr	puts
	rti
mess@	fcn	"reset"
	
irq_handle
	ldb	$ff00
	bmi	acia_handle
	ldb	$ff10
	bmi	packet_handle
	ldb	$ff20
	bmi	timer_handle
	ldb	$ff30
	bmi	reset_handle
	ldx	#mess@
	jsr	puts
	rti
mess@	fcn	"unknown irq"
	
timer_handle
	sts	sstack,pcr
	leas	stacke,pcr
	;; increment time
	ldd	time,pcr
	addd	#1
	std	time,pcr
	;; check announce timer
	ldd	atime,pcr
	beq	a@
	subd	#1
	bne	a@
	lbsr	announce
	ldd	#ANN_TO
a@	std	atime,pcr
	;; call ip6809's ticker
	lbsr	tick
	lds	sstack,pcr
b@	rti


put_char
	stb	$ff01
	rts
	
putstr	
a@	ldb	,x+
	beq	out@
	stb	$ff01
	bra	a@
out@	rts

puts
	jsr	putstr
	ldb	#10
	stb	$ff01
	rts
	
putdb	pshs	b
	ldb	#2
	stb	$ff00
	ldb	#'d
	stb	$ff01
	puls	b,pc

wait	pshs	b
a@	ldb	$ff00
	beq	a@
	ldb	$ff01
	puls	b,pc

hello	fcn	"Zombie for Sim6809"

start	orcc	#$50		; turn off interrupts
	lds	#$8000
	ldx	#hello
	jsr	puts
	ldb	#2		; don't buffer output
	stb	$ff00
	ldb	#$80		; turn on 60hz timer interrupts
	stb	$ff20
	ldd	#0
	std	time,pcr
	std	atime,pcr
	lbsr	ip6809_init	; initialize system
	lbsr	dev_init	; init device
	ldx	#$3900
	lbsr	freebuff
	ldx	#$3c00
	lbsr	freebuff
	ldx	#$3f00
	lbsr	freebuff
	ldx	#$4200		; add a buffers to freelist
	lbsr	freebuff	;
	jsr 	wait
	ldx	#hello
	jsr	puts
	andcc	#~$10		; turn on irq interrupt
	;; dhcp
	leax	ibroad,pcr
	lbsr	dhcp_init
	lbcs	error
	ldx	#mess@
	lbsr	puts
	jsr	print
*	lbsr	http_get
	lbsr	igmp_test
	lbsr	igmp_test
	;; mdns
	lbsr	mdns_init
	;; start zombie
	;; setup a socket
b@	ldb	#C_UDP
	lbsr	socket
	ldx	conn,pcr
	ldd	#7000		; source port is ephemeral
	std	C_SPORT,x
	ldd	#7000		; dest port 7000
	std	C_DPORT,x
	ldd	ipbroad,pcr
	std	C_DIP,x		; destination IP
	ldd	ipbroad+2,pcr
	std	C_DIP+2,x
	leay	call,pcr	; attach a callback
	sty	C_CALL,x
	;; initialize the timer
	ldd	#ANN_TO
	std	atime,pcr
a@	cwai	#$0
	bra	a@
error	ldx	#mess2@
	jsr	puts
	bra	a@
mess@	fcn	"DHCP"
mess2@	fcn	"Error"
	
;; callback for received datagrams
;; just print the udp's data as a string
call
	ldx	pdu,pcr
	ldb	,x
	cmpb	#1	; is read ?
	beq	cmd_read
	cmpb	#2	; is write?
	beq	cmd_write
	cmpb	#3	; is execute?
	beq	cmd_exec
	lbra	ip_drop

	export	cmd_read
cmd_read
	bsr	cmd_reply
	ldy	6,x
	ldu	4,x
	leax	8,x
a@	ldb	,u+
	stb	,x+
	leay	-1,y
	bne	a@
	tfr	x,d
	subd	pdu,pcr
	ldx	pdu,pcr
	lbsr	udp_out
	lbra	ip_drop

cmd_write
	bsr	cmd_reply
	ldy	6,x
	cmpy	#0		; fixme what to do if zero?
	beq	c@
b@	ldu	4,x
	leax	8,x
a@	ldb	,x+
	stb	,u+
	leay	-1,y
	bne	a@
c@	ldd	#4
	ldx	pdu,pcr
	lbsr	udp_out
	lbra	ip_drop


cmd_exec
	bsr	cmd_reply
	ldx	4,x
	pshs	x
	ldx	pdu,pcr
	ldd	pdulen,pcr
	lbsr	udp_out
	lbsr	ip_drop
	puls	x
	ldu	sstack,pcr
	stx	10,u
	rts

	;; mark packet as reply
cmd_reply
	ldy	conn,pcr
	ldd	ripaddr,pcr
	std	C_DIP,y
	ldd	ripaddr+2,pcr
	std	C_DIP+2,y
	ldb	,x
	orb	#$80
	stb	,x
	rts

announce
	lbsr	getbuff		; X = new buffer
	bcs	out@
	pshs	x
	leax	47,x		; pad for lower layers (DW+ETH+IP+UDP)
	pshs	x
	clr	,x+		; announce opcode
	leay	name,pcr
a@	lda	,y+
	sta	,x+
	bne	a@
	tfr	x,d
	subd	,s
	puls	x
	lbsr	udp_out
	puls	x
	lbsr	freebuff
out@	rts


cr	pshs	b
	ldb	#10
	stb	$ff01
	puls	b,pc

;;; print ipv4 settings
print
	leax	a@,pcr
	jsr	putstr
	leax	ipaddr,pcr
	lbsr	ipprint
	bsr	cr
	leax	b@,pcr
	jsr	putstr
	leax	ipmask,pcr
	lbsr	ipprint
	bsr	cr
	leax	c@,pcr
	jsr	putstr
	leax	ipbroad,pcr
	lbsr	ipprint
	bsr	cr
	leax	d@,pcr
	jsr	putstr
	leax	ipnet,pcr
	lbsr	ipprint
	bsr	cr
	leax	e@,pcr
	jsr	putstr
	leax	gateway,pcr
	lbsr	ipprint
	bsr	cr
	leax	f@,pcr
	jsr	putstr
	leax	dns,pcr
	lbsr	ipprint
	bsr	cr
	leax	g@,pcr
	jsr	putstr
	leax	bootfile,pcr
	jsr	putstr
	bsr	cr
	rts
a@	fcn	"IPADDR    "
b@	fcn	"NETMASK   "
c@	fcn	"BROADCAST "
d@	fcn	"NETADDR   "
e@	fcn	"GATEWAY   "
f@	fcn	"DNS       "
g@	fcn	"BOOTFILE  "
	.area	.intvec

	.dw	0
	.dw	0
	.dw	0
	.dw	irq_handle
	.dw	0
	.dw	0
	.dw	start

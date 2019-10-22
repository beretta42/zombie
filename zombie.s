	include "zombie.def"

	import	lsr1
	import	lsr2
	import	encrypt
	
	export	start
	export  insize
	export  inmax
	export  inbuf

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
ivect	rmb	2		; saved BASIC's irq vector
sstack  rmb	2		; saved entry stack frame
time	rmb	2		; a ticker
atime	rmb	2		; announce every so often
errno	rmb	1		; returned error code from rnp
replyf  rmb	1		; flipped when irq receives a reply
tof     rmb     1		; flipped when timed out
rnpaddr rmb	2		; rnp address

rx	rmb	80		; debug: a tcp rx buffer
	
	.area	.code

server	fcn	"play-classics.net"
uname	fcn	"beretta/zombie"
pass    fcn     "notapassword"


irq_handle
	lda	$ff02		; clear pia
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
	;; is BASIC irq vector set?
	ldd	ivect,pcr
	beq	b@
	;; yes tail call BASIC's normal vector
	jmp	[ivect]
	;; no just rti our selfs
b@	rti
	
start	orcc	#$50		; turn off interrupts
	ldd	#0
	std	time,pcr
	std	atime,pcr
	ldx	$10d
	stx	ivect,pcr
	leax	irq_handle,pcr
	stx	$10d
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
	andcc	#~$10		; turn on irq interrupt
	;; dhcp
	lbsr	dhcp_init
	lbcs	error
	lbsr	print
	lbsr	igmp_test
	lbsr	igmp_test
	;; debug tcp
	ldb	#C_TCP		; make tcp socket
	lbsr	socket
	ldx	conn,pcr
	ldd	#0		; ephemeral source port
	std	C_SPORT,x
	ldd	#4242
	std	C_DPORT,x	; destination port: TELNET
	ldd	#$c0a8
	std	C_DIP,x
	ldd	#$2a01
	std	C_DIP+2,x
	lbsr	tcp_connect
x@
	clr	,-s
w@	leax	msg@,pcr
	ldd	#14
	lbsr	tcp_send
	dec	,s
	bne	w@
	leas	1,s
t@	ldx	#$400
	ldd	#$200
	lbsr	tcp_recv
	cmpd	#0
	beq	y@
	bra	t@
y@	inc	$5ff
	lbsr	tcp_close
	bra	a@		; fixme: skip zombie startup
msg@	fcc	"Hello World!"
	.db	13,10
	;; start zombie
	;; lookup server
	leax	server,pcr
	lbsr	resolve
	bcc	b@
	inc	$501
	;; setup a socket
b@	ldb	#C_UDP
	lbsr	socket
	ldx	conn,pcr
	ldd	#0		; source port is ephemeral
	std	C_SPORT,x
	ldd	#6999		; dest port 6999
	std	C_DPORT,x
*	ldd	ipbroad,pcr
	ldd	ans,pcr
	std	C_DIP,x		; destination IP
	ldd	ans+2,pcr
*	ldd	ipbroad+2,pcr
	std	C_DIP+2,x
*	leay	call,pcr	; attach a callback
*	sty	C_CALL,x
	;; register with relay server
	lbsr	register
	;; initialize the timer
	ldd	#ANN_TO
	std	atime,pcr
	;; go back to BASIC
a@	rts
error	inc	$501
	bra	a@

;; callback for received datagrams
;; just print the udp's data as a string
call
	ldx	pdu,pcr		; check version / opcode
	ldd	,x		; get version / opcode
	cmpd	#$0105		; is correct?
	lbne	ip_drop		; no then drop
	ldd	10,x		; check protocol
	cmpd	#1		; fixme: need some standard protocol nos here
	lbne	ip_drop
	ldb	12,x
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
	ldy	5,x
	ldu	3,x
	leax	7,x
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
	ldy	5,x
	cmpy	#0		; fixme what to do if zero?
	beq	c@
b@	ldu	3,x
	leax	7,x
a@	ldb	,x+
	stb	,u+
	leay	-1,y
	bne	a@
c@	ldd	#15		; rnp header + 3 bytes of zombie header
	ldx	pdu,pcr
	lbsr	udp_out
	lbra	ip_drop


cmd_exec
	bsr	cmd_reply
	ldx	3,x
	pshs	x
	ldd	pdulen,pcr
	ldx	pdu,pcr
	lbsr	udp_out
	lbsr	ip_drop
	puls	x
	ldu	sstack,pcr
	stx	10,u
	clr	ivect,pcr
	clr	ivect+1,pcr
	rts

cmd_reply
	;; mark as rnp reply
	ldb	1,x
	orb	#$80
	stb	1,x
	;; flip source / dest address
	ldd	8,x		; get source rnp address
	std	6,x		; set dest rnp address
	ldd	rnpaddr,pcr	; get our address
	std	8,x		; set source address
	leax	12,x		; goto beginning of rnp route data
	rts

announce
	lbsr	getbuff		; X = new buffer
	bcs	out@
	pshs	x
	leax	47,x		; pad for lower layers (DW+ETH+IP+UDP)
	ldd	#0x0106		; version, ping opcode
	std	,x
	ldd	#2
	lbsr	udp_out
	puls	x
	lbsr	freebuff
out@	rts

	
cr	pshs	a
	lda	#$d
	jsr	$a282
	puls	a,pc

;;; print ipv4 settings
print
	leax	a@-1,pcr
	jsr	$b99c
	leax	ipaddr,pcr
	lbsr	ipprint
	bsr	cr
	leax	b@-1,pcr
	jsr	$b99c
	leax	ipmask,pcr
	lbsr	ipprint
	bsr	cr
	leax	c@-1,pcr
	jsr	$b99c
	leax	ipbroad,pcr
	lbsr	ipprint
	bsr	cr
	leax	d@-1,pcr
	jsr	$b99c
	leax	ipnet,pcr
	lbsr	ipprint
	bsr	cr
	leax	e@-1,pcr
	jsr	$b99c
	leax	gateway,pcr
	lbsr	ipprint
	bsr	cr
	leax	f@-1,pcr
	jsr	$b99c
	leax	dns,pcr
	lbsr	ipprint
	bsr	cr
	rts
a@	fcn	"IPADDR    "
b@	fcn	"NETMASK   "
c@	fcn	"BROADCAST "
d@	fcn	"NETADDR   "
e@	fcn	"GATEWAY   "
f@	fcn	"DNS       "



register
	;;  register our callback
	ldx	conn,pcr
	leay	reg_cb,pcr
	sty	C_CALL,x
	;;  build a buffer
e@	lbsr	getbuff		; X = new buffer
	lbcs	out@		; error
	pshs	x		; ( buf )
	leax	47,x		; dw + eth + ip + udp
	pshs	x		; ( buf udp )
	ldd	#0x0101		; version, register opcode
	std	,x
	leax	12,x		; jump to start of registration data
	clr	,x+		; zero attribute and encryption type
	clr	,x		;
	inc	,x+
	pshs	x		; ( buf udp pass )
	leay	pass,pcr	; copy password to buff
a@	lda	,y+
	sta	,x+
	bne	a@
	ldx	,s		; ( buf udp pass )
	leax	32,x		; copy username/node to buff
	leay	uname,pcr
b@	lda	,y+
	sta	,x+
	bne	b@
	;; encrypt
	ldd	#$aa5b
	std	lsr1,pcr
	ldd	#$33c3
	std	lsr1+2,pcr
	ldd	#$534e
	std	lsr2,pcr
	ldd	#$2210
	std	lsr2+2,pcr
	puls	x		; ( buf udp )
	ldy	#64
	lbsr	encrypt
	ldd	#12+2+64
	pshs	d
*	tfr	x,d
*	subd	,s
*	pshs	d		; ( buf udp size )
	;; send buffer
c@	ldx	conn,pcr	; set timer
	ldd	#60
	std	C_TIME,x
	clr	replyf,pcr	; clear flags
	clr	tof,pcr
	ldd	,s		; sendit
	ldx	2,s
	lbsr	udp_out
	;; wait for reply
d@	tst	tof,pcr
	bne	c@		; timeout? send again
	tst	replyf,pcr
	beq	d@		; no reply? test again
	;; test result
	ldb	errno,pcr
	bne	c@		; error? send again fixme: end this sometime
	;; connected
	leas	4,s		; ( buf )
	puls	x		; ( )
	lbsr	freebuff
	ldx	conn,pcr
	leay	call,pcr
	sty	C_CALL,x	; set call timer to normal call back
	clr	C_TIME,x	; clear timer (we'll use our own)
	clr	C_TIME+1,x	; fixme: should I use my own?
out@	rts
reg_cb
	cmpb	#C_CALLTO
	beq	to@
	ldx	pdu,pcr
	ldd	,x		; drop if not our version
	cmpd	#$0181		; drop if not reply to our registration
	lbne	ip_drop
	ldb	2,x		; get error code
	stb	errno,pcr
	inc	replyf,pcr
	lbra	ip_drop
to@	inc	tof,pcr
	rts

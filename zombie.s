	include "zombie.def"

	export	start
	export  put_char
	export	CPS

	import	ping
	import  ethtest

CPS	equ	60

ANN_TO	equ	5*CPS		; announcement timeout (5 sec)

	.area	.start
prog_start equ *
	.area	.end
prog_end equ *

	.area	.data

stack	rmb	64		; a private stack
stacke
ivect	rmb	2		; saved BASIC's irq vector
sstack  rmb	2		; saved entry stack frame
time	rmb	2		; a ticker
atime	rmb	2		; announce every so often

	.area	.code

name	fcn	"BRETT'S COCO"
ibroad	.db	255,255,255,255

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

hello_m	fcn	"ZOMBIE FOR COCO"
dhcp_m	fcn	"TRYING DHCP"
dhcp_fail_m
	fcn	"DHCP FAILED"
mdns_m	fcn	"STARTING MDNS"

start	orcc	#$50		; turn off interrupts
	ldx	#hello_m
	lbsr	puts
	ldd	#576+14+5	; max size of input buffer
	std	inmax,pcr
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
	ldx	#dhcp_m
	lbsr	puts
	leax	ibroad,pcr
	lbsr	dhcp_init
	lbcs	error
	lbsr	print
	;; mdns
	ldx	#mdns_m
	lbsr	puts
	lbsr	igmp_test
	lbsr	igmp_test
	lbsr	mdns_init
	;; testing here
	lbsr	ethtest
*	lbsr	ping
	lbsr	http_get
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
	;; go back to BASIC
a@	rts
error	ldx	#dhcp_fail_m
	lbsr	puts
	bra	a@

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
	clr	ivect,pcr
	clr	ivect+1,pcr
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


;;; print a char
;;;   b = char
;;;   modifies nothing
;;;   returns nothing
put_char
	exg	a,b
	jsr	$a282
	exg	a,b
	rts

cr	ldb	#$d
	lbra	put_char


putstr	pshs	x
a@	ldb	,x+
	beq	out@
	lbsr	put_char
	bra	a@
out@	puls	x,pc

puts	lbsr	putstr
	bra	cr

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
	lbsr	cr
	rts
a@	fcn	"IPADDR    "
b@	fcn	"NETMASK   "
c@	fcn	"BROADCAST "
d@	fcn	"NETADDR   "
e@	fcn	"GATEWAY   "
f@	fcn	"DNS       "
g@	fcn	"BOOTFILE  "

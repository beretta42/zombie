	include "zombie.def"

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
inmax	.dw	$200		; max size of input buffer


stack	rmb	64		; a private stack
stacke		
ivect	rmb	2		; saved BASIC's irq vector
sstack  rmb	2		; saved entry stack frame
time	rmb	2		; a ticker
atime	rmb	2		; announce every so often
	
	.area	.code

server	fcn	"play-classics.net"
uname	fcn	"beretta"

;;; pause
;;;   takes D = time in jiffies to wait
pause
	addd	time,pcr
a@	cmpd	time,pcr
	bne	a@
	rts

irq_handle
	lda	$ff02		; clear pia
	sts	sstack,pcr
	leas	stacke,pcr
	inc	$400		; tick screen fixme: remove
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
	;; tail call BASIC's normal vector
	jmp	[ivect]
	
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
	ldx	#$4200		; add a buffers to freelist
	lbsr	freebuff	;
	andcc	#~$10		; turn on irq interrupt
	;; dhcp
	lbsr	dhcp_init
	lbcs	error
	inc	$500
	;; lookup server
*	leax	server,pcr
*	lbsr	resolve
*	bcc	b@
*	inc	$501
	;; setup a socket
b@	ldb	#C_UDP
	lbsr	socket
	ldx	conn,pcr
	ldd	#0		; source port is ephemeral
	std	C_SPORT,x
	ldd	#6999		; dest port 6999
	std	C_DPORT,x
	ldd	#0xffff
*	ldd	ans,pcr
	std	C_DIP,x		; destination IP
*	ldd	ans+2,pcr
	std	C_DIP+2,x
	leay	call,pcr	; attach a callback
	sty	C_CALL,x
	;; send a boot announcement twice...
	lbsr	announce
	ldd	#ANN_TO
	std	atime,pcr
	;; go back to BASIC
a@	rts
error	inc	$501
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
	cmpy	#0
	bhi	debug
b@	ldu	3,x
	leax	7,x
a@	ldb	,x+
	stb	,u+
	leay	-1,y
	bne	a@
	tfr	x,d
	subd	pdu,pcr
	ldx	pdu,pcr
	lbsr	udp_out
	lbra	ip_drop
	export  debug
debug	bra	b@


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
	rts

cmd_reply
	ldy	conn,pcr
	ldb	,x
	orb	#$80		; change to reply
	stb	,x
	ldd	ripaddr,pcr	; send to host we've recv'd command from
	std	C_DIP,y
	ldd	ripaddr+2,pcr
	std	C_DIP+2,y
	rts

announce
	lbsr	getbuff		; X = new buffer
	bcs	out@
	pshs	x
	leax	47,x		; pad for lower layers (DW+ETH+IP+UDP)
	pshs	x
	ldd	#0
	std	,x++		; message type, return
	std	,x++		; XID
	std	,x++		; address
	std	,x++		; size
	leau	uname,pcr	; copy user name
a@	lda	,u+
	sta	,x+
	bne	a@
	tfr	x,d		; calc packet size
	subd	,s
	puls	x
	lbsr	udp_out
	puls	x
	lbsr	freebuff
out@	rts

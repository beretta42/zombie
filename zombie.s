	include "zombie.def"

	import	tcp_connect
	import	tcp_send
	import	tcp_close
	import  tcp_recv

	
	export	start
	export  insize
	export  inmax
	export  inbuf

	.area	.start
prog_start equ *
	.area	.end
prog_end equ *

	.area	.data
insize	.dw	0		; size of packet in input buffer
inbuf	.dw	$600		; pointer to input buffer
inmax	.dw	$200		; max size of input buffer


stack	rmb	256		; a private stack
stacke		
ivect	rmb	2		; saved BASIC's irq vector
sstack  rmb	2		; saved entry stack frame
sstack1	rmb	2		; saved stack
time	.dw	0		; a ticker
	
	.area	.code

server	fcn	"play-classics.net"

;;; pause
;;;   takes D = time in jiffies to wait
pause
	addd	time
a@	cmpd	time
	bne	a@
	rts

irq_handle
	lda	$ff02		; clear pia
	inc	$400		; tick screen fixme: remove
	;; increment time
	ldd	time
	addd	#1
	std	time
	;; call ip6809's ticker
	sts	sstack
	jsr	tick
	lds	sstack
	;; tail call BASIC's normal vector
	jmp	[ivect]

	
start	orcc	#$50		; turn off interrupts
	sts	sstack1
	ldx	$10d
	stx	ivect
	ldx	#irq_handle
	stx	$10d
	lds	#stacke
	jsr	ip6809_init	; initialize system
	jsr	dev_init	; init device
	ldx	#$600		; add a buffers to freelist
	jsr	freebuff	;
	ldx	#$800
	jsr	freebuff
*	ldx	#$a00
*	jsr	freebuff
	andcc	#~$10		; turn on irq interrupt
	ldx	#ipmask
	jsr	ip_setmask
	;; dhcp
	jsr	dhcp_init
	lbcs	error
	inc	$500
	;; lookup server
	ldx	#server
*	jsr	resolve
	;; setup a socket
	ldb	#C_UDP
	jsr	socket
	ldx	conn
	ldd	#0		; source port is ephemeral
	std	C_SPORT,x
	ldd	#6999		; dest port 6999
	std	C_DPORT,x
	ldd	#$ffff
*	ldd	ans
	std	C_DIP,x		; destination IP
*	ldd	ans+2
	std	C_DIP+2,x
	ldd	#call		; attach a callback
	std	C_CALL,x
	;; send a boot announcement twice...
	;; (ARP may eat the first one!)
	jsr	getbuff		; X = new buffer
	leax	47,x		; pad for lower layers (DW+ETH+IP+UDP)
	pshs	x
	ldd	#0
	sta	0,x		; message type
	std	1,x		; XID
	std	3,x		; address
	std	5,x		; size
	ldd	#7		; size of PDU
	jsr	udp_out2
	ldd	#60
	jsr	pause
	puls	x
	ldd	#7
	jsr	udp_out2
	ldx	inbuf
	jsr	freebuff
	;; go back to BASIC
a@
	lds	sstack1
	rts
error	inc	$501
	bra	a@

;; callback for received datagrams
;; just print the udp's data as a string
call
	ldx	pdu
	ldb	,x
	cmpb	#1	; is read ?
	beq	cmd_read
	cmpb	#2	; is write?
	beq	cmd_write
	cmpb	#3	; is execute?
	beq	cmd_exec
	ldx	inbuf
	jsr	freebuff
	rts

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
	subd	pdu
	ldx	pdu
	jsr	udp_out2
	export debug
debug
	ldx	inbuf
	jmp	freebuff

cmd_write
	bsr	cmd_reply
	ldy	5,x
	ldu	3,x
	leax	7,x
a@	ldb	,x+
	stb	,u+
	leay	-1,y
	bne	a@
	tfr	x,d
	subd	pdu
	ldx	pdu
	jsr	udp_out2
	ldx	inbuf
	jmp	freebuff

cmd_exec
	bsr	cmd_reply
	ldx	3,x
	pshs	x
	ldd	pdulen
	ldx	pdu
	jsr	udp_out2
	ldx	inbuf
	jsr	freebuff
	puls	x
	ldu	sstack
	stx	10,u
	rts

cmd_reply
	ldy	conn
	ldb	,x
	orb	#$80		; change to reply
	stb	,x
	ldd	ripaddr		; send to host we've recv'd command from
	std	C_DIP,y
	ldd	ripaddr+2
	std	C_DIP+2,y
	rts


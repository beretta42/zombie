	include "zombie.def"

	export	start
	export  insize
	export  inmax
	export  inbuf
	export	time
	export	pause


	.area	.data
insize	.dw	0		; size of packet in input buffer
inbuf	.dw	$600		; pointer to input buffer
inmax	.dw	$200		; max size of input buffer

stack	rmb	256		; a private stack
stacke		
	
time	.dw	0		; a ticker
	
	.area	.code

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
	jsr	tick
	rti

	
start	orcc	#$50		; turn off interrupts
	ldx	#irq_handle
	stx	$10d
	lds	#stacke
	jsr	ip6809_init	; initialize system
	jsr	dev_init	; init device
	andcc	#~$10		; turn on irq interrupt
	ldx	#ipmask
	jsr	ip_setmask
	;; dhcp
	jsr	dhcp_init
	bcs	error
	inc	$500
	;; send some data
	jsr	resolve
	inc	$501
	;; send a upd packet to server
	ldb	#C_UDP
	jsr	socket
	ldx	conn
	ldd	#6999
	std	C_DPORT,x
	ldd	ans
	std	C_DIP,x
	ldd	ans+2
	std	C_DIP+2,x
	ldx	inbuf
	leax	47,x
	pshs	x
	ldy	#s0@
t1@	ldb	,y+
	stb	,x+
	bne	t1@
	tfr	x,d
	subd	,s
	ldx	,s++
	pshs	d,x
	jsr	send
	ldd	#4*60
	jsr	pause
	puls	d,x
	jsr	send
	jsr	close
	;; setup a socket
	ldb	#C_UDP
	jsr	socket
	ldx	conn
	ldd	#6809
	std	C_SPORT,x
	ldd	#call
	std	C_CALL,x
	;; do main loop
a@	jsr	dev_poll
	bcs	p1@		; nothing there so pause
	ldx	inbuf
	jsr	eth_in		; process via ethernet
	bra	a@
p1@	ldd	#7
	jsr	pause
	bra	a@
error	inc	$501
	bra	a@
s0@	fcn	"Hello, from Brett's CoCo"
	

;; a test callback
;; just print the udp's data as a string
call
	ldx	pdu
	leax	-1,x
	jsr	$b99c
	inc	$520
	rts



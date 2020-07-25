;;;
;;;  A test application for IP socket layer
;;;
;;;     This is to reveal potential API problems
;;;

	include "zombie.def"

	.area	.data
seq	.dw	2

	.area	.code

	export ping
ping
	clr	seq,pcr
	clr	seq+1,pcr
	ldb	#C_IP		; make a IP socket
	lbsr	socket
	ldx	conn,pcr
	ldd	#1		; set our IP protocol (ICMP)
	std	C_DPORT,x
	ldd	#$0a08
	std	C_DIP,x
	ldd	#$030a
	std	C_DIP+2,x
	leay	call,pcr	; install callback
	sty	C_CALL,x
	bsr	timeout
a@	bra	a@


call	cmpb	#C_CALLTO
	lbeq	timeout
	ldb	#'.
	lbsr	put_char
	lbra	ip_drop


timeout	ldx	conn,pcr	; reset timer
	ldd	#CPS
	std	C_TIME,x
	;; get a buffer
	lbsr	getbuff
	pshs	x
	leax	39,x		; reserve space for underlying protos
	pshs	x		; fixme: BAD why am I guessing how much?
	;; build packet
	ldd	#$0800		; type 8 code 0 (echo/ping)
	std	,x++
	ldd	#$0000
	std	,x++		; make room for cksum
	ldd	#$0102		; ID number
	std	,x++
	ldd	seq,pcr		; sequence no
	std	,x++
	addd	#1
	std	seq,pcr
	leau	mess,pcr
a@	ldb	,u+		; append data to packet
	stb	,x+
	bne	a@
	;; calc cksum
	pshs	x
	tfr	x,d
	subd	2,s
	tfr	d,y
	ldx	2,s
	ldd	#0
	lbsr	ip_cksum
	std	2,x
	puls	x
	;; send packet
	tfr	x,d
	subd	,s
	puls	x
	lbsr	ip_send
	;; free packet
	puls	x
	lbsr	freebuff
	rts

mess	fcn	"Ping for ip6809: Now is the time for all good men"

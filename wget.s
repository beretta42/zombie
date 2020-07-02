;;; a basic http getter

	include "zombie.def"

CRLF	equ	$0d0a


	export http_get

	.area	.data
buf	rmb	768


	.area	.code

http_get:
	ldb	#C_TCP
	lbsr	socket
	;; fixme: error check here
	ldx	conn,pcr
	ldd	#$0a08
	std	C_DIP,x
	ldd	#$2a01
	std	C_DIP+2,x
	ldd	#8080
	std	C_DPORT,x
	lbsr	tcp_connect
	;; send GET request
	leax	msg,pcr
	ldd	#26
	lbsr	tcp_send
	;; get answer
c@	leax	buf,pcr
	ldd	#512
	lbsr	tcp_recv
	cmpd	#0
	beq	a@
	;; print answer
	tfr	d,y
b@	lda	,x+
	jsr	$a282
	leay	-1,y
	bne	b@
	bra	c@
a@	ldx	conn,pcr
	lbsr	tcp_close
d@	inc	$400
	bra	d@



msg:	fcc	"GET /test.txt HTTP/1.1"
	.dw	CRLF
	.dw	CRLF

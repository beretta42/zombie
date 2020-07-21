;;; a basic http getter
;;;   This needs PIC-ifying

	include "zombie.def"

LF	equ	$0a
CR	equ	$0d
SP	equ	$20
CRLF	equ	$0d0a


	export http_get

	.area	.data

len	rmb	1
buf	rmb	1024
ptr	rmb	2

lbuf	rmb	255

clen	rmb	8
ctos	.dw	ctos

	.area	.code


putb	exg	a,b
	jsr	$a282
	exg	a,b
	rts

puts	pshs	x
a@	ldb	,x+
	beq	out@
	bsr	putb
	bra	a@
out@	ldb	#CR
	bsr	putb
	puls	x,pc


zero	ldu	ctos
	ldd	#0
	pshu	d
	pshu	d
	stu	ctos
	rts

dup	ldu	ctos
	pulu	d,y
	ldu	ctos
	pshu	d,y
	stu	ctos
	rts

mul2	ldu	ctos
	leau	3,u
	lsl	,u
	rol	,-u
	rol	,-u
	rol	,-u
	rts

add	ldu	ctos
	leay	4,u
	ldd	2,u
	addd	2,y
	std	2,y
	ldd	,u
	adcb	1,y
	stb	1,y
	adca	,y
	sta	,y
	sty	ctos
	rts

pushb	ldu	ctos
	pshu	b
	clr	,-u
	clr	,-u
	clr	,-u
	stu	ctos
	rts

mul10	bsr	mul2
	bsr	dup
	bsr	mul2
	bsr	mul2
	bsr	add
	rts


;;; convert string to long int
atol	bsr	zero
a@	ldb	,x+
	subb	#$30
	bmi	done@
	cmpb	#9
	bhi	done@
	pshs	b
	bsr	mul10
	puls	b
	bsr	pushb
	bsr	add
	bra	a@
done@	rts


;;; gets a byte from TCP
getb:	pshs	a,x
	;; test for bytes in local buffer
	tst	len
	bne	a@
	;; no bytes to try to load buffer
	ldx	#buf
	stx	ptr
	ldd	#255
	jsr	tcp_recv
	stb	len
	;; there's  bytes in the buffer get one
a@	dec	len
	ldx	ptr
	ldb	,x+
	stx	ptr
	puls	a,x,pc


;;; gets a line from tcp
;;; takes: x - buffer, b - char max
gets	decb
	pshs	b,x
a@	jsr	getb
	cmpb	#CR
	beq	out@
	stb	,x+
	dec	,s
	beq	drop@
	bra	a@
out@	jsr	getb		; drop LF
	clr	,x+		; add a zero
	puls	b,x,pc
drop@	jsr	getb
	cmpb	#CR
	beq	out@
	bra	drop@

status
	ldx	#lbuf
	ldb	#255
	jsr	gets		; get a line
	jsr	puts		; print it
a@	ldb	,x+
	beq	nf@
	cmpb	#SP
	bne	a@
	ldb	,x+
	subb	#$30
	bmi	nf@
	cmpb	#9
	bhi	nf@
	rts
nf@	bra	nf@


strcmp	pshs	x,y
a@	ldb	,y+
	beq	out@
	cmpb	,x+
	beq	a@
out@	puls	x,y,pc


headers
a@	ldx	#lbuf
	ldb	#255		; begin get a line
	jsr	gets
	tst	,x		; is empty (CRLF) only
	beq	out@
	jsr	puts
	ldy	#lenstr@
	jsr	strcmp
	beq	len@
	bra	a@
out@	rts
len@	leax	16,x
	jsr	atol
	bra	a@
lenstr@ fcn	"Content-Length: "


sends	pshs	d,x
a@	tst	,x+
	bne	a@
	tfr	x,d
	subd	2,s
	ldx	2,s
	lbsr	tcp_send
	puls	d,x,pc

http_get:
	;; setup internal buffer
	clr	len
	ldb	#C_TCP
	lbsr	socket
	;; fixme: error check here
	ldx	conn,pcr
	ldd	#$0a08
	std	C_DIP,x
	ldd	#$0001
	std	C_DIP+2,x
	ldd	#80
	std	C_DPORT,x
	lbsr	tcp_connect
	;; send GET request
	leax	msg,pcr
	lbsr	sends
	;; get replay
	jsr	status
	cmpb	#2
	bne	out@
	;; get headers
	jsr	headers
	;; get payload
c@	leax	buf,pcr
	ldd	#1024
	lbsr	tcp_recv
	cmpd	#0
	beq	out@
	lda	#'.
	jsr	$a282
	bra	c@
out@	ldx	conn,pcr
	lbsr	tcp_close
d@	inc	$400
	bra	d@



msg:	fcc	"GET / HTTP/1.0"
	.dw	CRLF
	fcc	"Host: fuzix.play-classics.net"
	.dw	CRLF
	fcc	"User-Agent: wget-for-ip6809/.0"
	.dw	CRLF,CRLF,0

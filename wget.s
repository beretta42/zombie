;;; a basic http getter
;;;   This needs PIC-ifying

	include "zombie.def"

BS	equ	$08
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
	cmpa	#LF
	bne	a@
	lda	#CR
a@	cmpa	#9
	beq	tab@
	jsr	$a282
	exg	a,b
	rts
tab@	ldb	#SP
	bsr	putb
	bsr	putb
	bsr	putb
	bsr	putb
	rts

puts	pshs	x
a@	ldb	,x+
	beq	out@
	bsr	putb
	bra	a@
out@	puls	x,pc

putscr	bsr	puts
	ldb	#CR
	bsr	putb
	rts

putm	pshs	x,y
	cmpd	#0
	beq	out@
	tfr	d,y
a@	ldb	,x+
	bsr	putb
	leay	-1,y
	bne	a@
out@	puls	x,y,pc


drop	ldu	ctos
	leau	4,u
	stu	ctos
	rts

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


;;; pointers to string-ified URL
host	.dw	0
user	.dw	0
port	.dw	0
path	.dw	0
defpath fcn	"/"

;;; parse a Url
;;; x = URL buffer
;;; returns
parse_url
	ldd	#80		; set default port
	std	port
	ldd	#defpath
	std	path
	pshs	y
	ldy	#p@		; check for "http://"
	jsr	strcmp
	bne	err@
	leax	7,x		; x points past "http://"
	stx	host
a@	ldb	,x+
	beq	ok@
	cmpb	#':
	beq	port@
	cmpb	#'@
	beq	user@
	cmpb	#'/
	beq	end@
	bra	a@
end@	clr	-1,x
	ldb	,x
	stx	path
	bra	ok@
port@	clr	-1,x
	jsr	atol
	ldy	ctos
	leax	-1,x
	stx	path
	ldd	2,y
	std	port
	jsr	drop
	leax	-1,x
	bra	ok@
user@	clr	-1,x
	ldy	host
	sty	user
	stx	host
	bra	a@
ok@	clra
	puls	y,pc
err@	coma
	puls	y,pc
p@	fcn	"http://"	; fixme: for now we'll require an authority

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
	jsr	putscr		; print it
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
*	jsr	puts
	ldy	#lenstr@
	jsr	strcmp
	beq	len@
	bra	a@
out@	rts
len@	leax	16,x
	jsr	atol
	lbsr	drop
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


lptr	.dw	lbuf

appstr	ldu	lptr
a@	ldb	,x+
	beq	out@
	stb	,u+
	bra	a@
out@	stu	lptr
	rts

sendstr	ldd	lptr
	subd	#lbuf
	ldx	#lbuf
	lbsr	tcp_send
	ldd	#lbuf
	std	lptr
	rts

prompt	ldx	#p@
	lbra	puts
p@	fcn	"url > "

getchar	pshs	a
a@	jsr	$a1cb
	beq	a@
	jsr	$a282
	tfr	a,b
	puls	a,pc

	.area	.data
urlbuf	rmb	256
	.area	.code

geturl	pshs	x
	ldx	#urlbuf
a@	jsr	getchar
	cmpb	#CR
	beq	cr@
	cmpb	#BS
	beq	bs@
	stb	,x+
	bra	a@
cr@	clr	,x
	puls	x,pc
bs@	leax	-1,x
	bra	a@

http_get:
b@	bsr	prompt
	bsr	geturl
	ldx	#urlbuf
	jsr	putscr
	ldx	#urlbuf
	jsr	parse_url
	;; send host name to resolver
	ldx	host
	jsr	resolve
	bcs	b@
	;; setup internal buffer
a@	clr	len
	ldb	#C_TCP
	lbsr	socket
	;; fixme: error check here
	ldx	conn,pcr
	ldd	ans
	std	C_DIP,x
	ldd	ans+2
	std	C_DIP+2,x
	ldd	port
	std	C_DPORT,x
	lbsr	tcp_connect
	bcs	out@
	;; send GET request
	ldx	#msg1
	jsr	appstr
	ldx	path
	jsr	appstr
	ldx	#msg2
	jsr	appstr
	jsr	sendstr
	ldx	#msg3
	jsr	appstr
	ldx	host
	jsr	appstr
	ldx	#msg4
	jsr	appstr
	jsr	sendstr
	ldx	#msg5
	jsr	appstr
	jsr	sendstr
	;; get replay
	jsr	status
	cmpb	#2
	bne	out@
	;; get headers
	jsr	headers
	;; print payload still in the buffer
	ldx	ptr
	clra
	ldb	len
	jsr	putm
	;; print payload from rest of reads
c@	leax	buf,pcr
	ldd	#1024
	lbsr	tcp_recv
	cmpd	#0
	beq	out@
	lbsr	putm
	bra	c@
out@	ldx	conn,pcr
	lbsr	tcp_close
	lbsr	close
	lbra	b@
d@	inc	$400
	bra	d@


msg1:	fcn	"GET "
msg2:	fcc	" HTTP/1.0"
	.dw	CRLF,0
msg3:	fcn	"Host: "
msg4:	.dw	CRLF,0
msg5:	fcc	"User-Agent: wget-for-ip6809/.0"
	.dw	CRLF,CRLF,0

;;;
;;;
;;;  This is a simple internet name resolver
;;; 
;;;
	include "zombie.def"

	export	ans

	.area	.data
retry	rmb	1		; send this many queries, max
ans	rmb	4		; resolved address, if any
flag	rmb	1		; 

	.area	.code

;;; resolves name
;;;   takes X = name
;;;   returns X = ptr to ip
;;;   returns C set on error
      export  resolve
resolve
	ldb	#3
	stb	retry
	;; make and bind socket - DNS
	ldb	#C_UDP	 	; socket is a UDP
	jsr	socket
	bcs	bad@		; handle running out of sockets
	ldx	conn		; conn is newly opened sockets
	ldd	dns		; set IP to system dns server
	std	C_DIP,x		; our DNS server from dns
	ldd	dns+2
	std	C_DIP+2,x
	ldd	#53		; port 53 - dns
	std	C_DPORT,x
	ldd	#4*60		; timeout socket at 2 secs fixme: change to 2
	std	C_TIME,x
	ldd	#call		; "call" is our callback (below)
	std	C_CALL,x
	jsr	query		; send initial query
a@	jsr	dev_poll	; and poll loop
	bcs	p1@
	ldx	inbuf
	jsr	eth_in
	ldb	flag
	bne	out@
	bra	a@
p1@	ldd	#7
	jsr	pause
	bra	a@
bad@	coma
	rts
out@	jsr	close
	ldb	#1
	cmpb	flag
	rts


	export	query
;; send query packet to server
query
	ldx	inbuf		; fixme: we shouldn't know about this
	leax	47,x		; leave room for lower layer
	pshs	x
	ldd	mac+2		; use our mac as a ID field
	std	,x++
	ldd	#$0100		; recursive search
	std	,x++		; and a bunch of other stuff
	ldd	#1
	std	,x++		; one question
	clrb
	std	,x++		; no answers
	std	,x++		; no name servers
	std	,x++		; no auth
	; append name
	bsr	 appname
	ldd	 #1		; qtype A - host
	std	 ,x++
	std	 ,x++		; qclass IN - internet
	; finish and send
	tfr	x,d		; calc length
	subd	,s
	puls	x		; get pdu back
	jsr	send		
	rts

name	fcn	"www.play-classics.net"
	.db	0

appname
	ldy	#name
a@	leau	,x+
	clrb
b@	lda	,y+
	beq	out@
	cmpa	#'.
	beq	next@
	sta	,x+
	incb
	bra	b@
next@	stb	,u+
	bra	a@
out@	stb	,u+
	clr	,x+
	rts

	export  call
call	cmpb	#C_CALLTO
	beq	to@
	;; filter out bad answers
	ldx	pdu
	ldd	,x		; is our ID?
	cmpd	mac+2
	bne	out@
	ldd	2,x		; is a reponse?
	bita	#$80
	beq	out@
	bitb	#$f		; error code?
	bne	out@
	ldd	6,x		; answers?
	beq	out@
	;; ok this is our answer packet
	leau    12,x		; scan/skip questions
a@	bsr	skip
next@	leau	4,u		; skip over type/class
	ldd	4,x		; decrement question number
	subd	#1
	std	4,x
	bne	a@
	;; U points to first answer, get it.
ans@	bsr	skip
c@	leau	10,u
	ldd	,u++
	std	ans
	ldd	,u
	std	ans+2
	inc	flag
out@	rts	
to@	dec	retry
	beq	err@
	jsr	query
	rts
err@	inc	flag
	inc	flag
	rts

;; skips over name
skip
	ldb	,u
	andb	#$c0
	bne	ref@
	ldb	,u+
	beq	out@
	leau	b,u
	bra	skip
ref@	leau	2,u
out@	rts

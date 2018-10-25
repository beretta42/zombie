;;;
;;;
;;;  This is a simple internet name resolver
;;; 
;;;
	include "zombie.def"

	export	ans

DNSTO	equ	3*60		; 2 second timeout
	
	.area	.data
retry	rmb	1		; send this many queries, max
ans	rmb	4		; resolved address, if any
flag	rmb	1		;
qptr	rmb	2		; ptr to query text name

	.area	.code

;;; resolves name
;;;   takes X = name
;;;   returns X = ptr to ip
;;;   returns C set on error
      export  resolve
resolve
	stx	qptr,pcr
	ldb	#3
	stb	retry,pcr
	clr	flag,pcr
	;; make and bind socket - DNS
	ldb	#C_UDP	 	; socket is a UDP
	lbsr	socket
	bcs	bad@		; handle running out of sockets
	ldx	conn,pcr	; conn is newly opened sockets
	ldd	dns,pcr		; set IP to system dns server
	std	C_DIP,x		; our DNS server from dns
	ldd	dns+2,pcr
	std	C_DIP+2,x
	ldd	#53		; port 53 - dns
	std	C_DPORT,x
	ldd	#DNSTO		; timeout socket at 2 secs
	std	C_TIME,x
	leay	call,pcr
	sty	C_CALL,x
	bsr	query		; send initial query
a@	tst	flag,pcr
	beq	a@
out@	lbsr	close
	ldb	#1
	cmpb	flag,pcr
	rts
bad@	coma
	rts


	export	query
;; send query packet to server
query
	lbsr	getbuff
	bcs	err@	
	pshs	x
	leax	47,x		; leave room for lower layer
	pshs	x
	ldd	mac+2,pcr	; use our mac as a ID field
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
	lbsr	send
	puls	x
	lbra	freebuff
err@	rts
	
appname
	ldy	qptr,pcr
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
	ldx	pdu,pcr
	ldd	,x		; is our ID?
	cmpd	mac+2,pcr
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
	std	ans,pcr
	ldd	,u
	std	ans+2,pcr
	inc	flag,pcr
out@	lbra	ip_drop
to@	dec	retry,pcr
	beq	err@
	ldy	conn,pcr
	ldd	#DNSTO
	std	C_TIME,y
	lbra	query
err@	inc	flag,pcr
	inc	flag,pcr
	bra	out@

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

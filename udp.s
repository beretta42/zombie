	include "zombie.def"

	export udp_init
	export udp_in
	export udp_out
*	export sport
*	export dport
	export pdu
	export pdulen

	.area .data
pdu	rmb	2		; pdu address of received packet
pdulen	rmb	2		; pdu length of received packet
eport	rmb	2		; next ephemeral port number
	
	.area .code

	;; initialize the udp subsystem
udp_init
	ldd	#$c000
	std	eport
	rts

udp_in:	;; scan for matching socket
	jsr	for_sock
a@	jsr	next_sock
	lbcs	ip_drop
	ldy	conn
	ldb	C_FLG,y		; is a UDP socket?
	cmpb	#C_UDP
	bne	a@
	ldd	2,x		; dest port = our source?
	cmpd	C_SPORT,y
	bne	a@
	;; found our socket
	;; record pdu / length
	leay	8,x
	sty	pdu
	ldy	rlen
	leay	-8,y
	sty	pdulen
	;; call the callback (if set)
	ldx	conn
	ldx	C_CALL,x
	beq	b@
	ldb	#C_CALLRX
	jsr	,x
b@	rts


udp_out:
	rts
*	addd	#8
*	pshs	d
*	leax	-8,x
*	std	4,x		; save length in packet
*	clr	6,x		; clear checksum
*	clr	7,x		;
*	leay	,x		; copy source and dest ports
*	ldu	#sport
*	ldb	#4
*	jsr	memcpy
*	ldb	#17
*	stb	proto
*	puls	d		; get total size back
*	jmp	ip_out		; onto ip!

	
	export	udp_out2
udp_out2:	
	addd	#8
	pshs	d
	leax	-8,x
	std	4,x		; save length in packet
	clr	6,x		; clear/disable checksum
	clr	7,x		;
	leay	,x		; copy source and dest ports
	ldu	conn
	ldd	C_SPORT,u	; check for zero port
	bne	s@
	jsr	ephem		; go get ephemeral port
s@	leau	C_SPORT,u
	ldb	#4
	jsr	memcpy
	ldb	#17		; fixme: smells
	stb	proto
	puls	d		; get total size back
	jmp	ip_out2		; onto ip!


ephem:	pshs	x
	ldx	conn		; stack conn ptr
	pshs	x
a@	jsr	for_sock	; start iterating
b@	jsr	next_sock
	bcs	out@
	ldd	eport
	cmpd	C_SPORT,x	; get src port of socket
	bne	b@		; no then check next socket
	addd	#1		; yes then try next port
	bne	s@		; did we wrap to zero?
	ldd	#$c000		; yes then start at beg of ephem ports
s@	std	eport		; save in eport
	bra	a@		; start socket scan afresh
out@	puls	x		; restore conn ptr
	stx	conn
	ldd	eport
	std	C_SPORT,x	; save 
	addd	#1
	std	eport
	puls	x,pc

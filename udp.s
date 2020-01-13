	include "zombie.def"

	export udp_init
	export udp_in
	export udp_out
	export pdu
	export pdulen
	export pduport

	.area .data
pdu	rmb	2		; pdu address of received packet
pdulen	rmb	2		; pdu length of received packet
pduport	rmb	2		; source port of received packet
eport	rmb	2		; next ephemeral port number
	
	.area .code

	;; initialize the udp subsystem
udp_init
	ldd	#$c000
	std	eport,pcr
	rts

udp_in:	;; scan for matching socket
	lbsr	for_sock
a@	lbsr	next_sock
	lbcs	ip_drop
	ldy	conn,pcr
	ldb	C_FLG,y		; is a UDP socket?
	cmpb	#C_UDP
	bne	a@
	ldd	2,x		; dest port = our source?
	cmpd	C_SPORT,y
	bne	a@
	;; found our socket
	;; record pdu / length
	leay	8,x
	sty	pdu,pcr
	ldy	rlen,pcr
	leay	-8,y
	sty	pdulen,pcr
	ldd	,x
	std	pduport,pcr
	;; call the callback (if set)
	ldx	conn,pcr
	ldx	C_CALL,x
	beq	b@
	ldb	#C_CALLRX
	jsr	,x
b@	rts


	export	udp_out
udp_out:	
	addd	#8
	pshs	d
	leax	-8,x
	std	4,x		; save length in packet
	clr	6,x		; clear/disable checksum
	clr	7,x		;
	leay	,x		; copy source and dest ports
	ldu	conn,pcr
	ldd	C_DIP,u
	std	dipaddr,pcr
	ldd	C_DIP+2,u
	std	dipaddr+2,pcr
	ldd	C_SPORT,u	; check for zero port
	bne	s@
	lbsr	ephem		; go get ephemeral port
s@	leau	C_SPORT,u
	ldb	#4
	lbsr	memcpy
	ldb	#17		; fixme: smells
	stb	proto,pcr
	puls	d		; get total size back
	lbra	ip_out		; onto ip!


ephem:	pshs	x
	ldx	conn,pcr	; stack conn ptr
	pshs	x
a@	lbsr	for_sock	; start iterating
b@	lbsr	next_sock
	bcs	out@
	ldd	eport,pcr
	cmpd	C_SPORT,x	; get src port of socket
	bne	b@		; no then check next socket
	addd	#1		; yes then try next port
	bne	s@		; did we wrap to zero?
	ldd	#$c000		; yes then start at beg of ephem ports
s@	std	eport,pcr	; save in eport
	bra	a@		; start socket scan afresh
out@	puls	x		; restore conn ptr
	stx	conn,pcr
	ldd	eport,pcr
	std	C_SPORT,x	; save 
	addd	#1
	std	eport,pcr
	puls	x,pc

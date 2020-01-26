	include "zombie.def"

	export icmp_in
	export icmp_out


	.area	.data

	.area	.code


;;; process an incoming icmp packet
;;;   takes: x = layer 4 pdu ptr
icmp_in:
	ldb	,x		; get type
	cmpb	#8		; is ping then pong
	beq	pong
	;; find a connection
	lbsr	for_sock
a@	lbsr	next_sock
	lbcs	ip_drop
	ldy	conn,pcr
	ldb	C_FLG,y
	cmpb	#C_ICMP
	bne	a@
	;; check for ID == source port
	ldd	4,x		; get packet's ID
	cmpd	C_SPORT,y
	bne	a@
	;; we found our connection
	;; record pdu length
	stx	pdu,pcr
	ldd	rlen,pcr
	std	pdulen,pcr
	ldx	conn,pcr
	ldx	C_CALL,x
	beq	b@
	ldb	#C_CALLRX
	jsr	,x
b@	lbra	ip_drop


pong:
	ldb	#1		; icmp protocol's number
	stb	proto,pcr
	ldd	ripaddr,pcr	; copy received address
	std	dipaddr,pcr
	ldd	ripaddr+2,pcr
	std	dipaddr+2,pcr
	clra			; clear out header
	clrb
	std	,x		; make packet a reply
	std	2,x		; zero out cksum
	;; recalc icmp cksum
	ldy	rlen,pcr
	ldd	#0
	lbsr	ip_cksum
	std	2,x
	;; send to ip
	ldd	rlen,pcr
	lbsr	ip_out
	lbra	ip_drop


icmp_out:
	ldy	conn,pcr
	addd	#6		; add space for constructing header
	pshs	d
	leax	-6,x
	ldd	#$0800		; set echo request, code 0
	std	,x
	ldd	C_SPORT,y
	std	4,x
	ldd	#0		; set cksum
	std	2,x
	ldy	,s
	lbsr	ip_cksum
	std	2,x
	ldy	conn,pcr
	ldd	C_DIP,y
	std	dipaddr,pcr
	ldd	C_DIP+2,y
	std	dipaddr+2,pcr
	ldb	#1
	stb	proto,pcr
	puls	d		; get pdu size back
	lbra	ip_out		; send it vi ip

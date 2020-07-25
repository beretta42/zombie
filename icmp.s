	include "zombie.def"

	export icmp_in


	.area	.data

	.area	.code


;;; process an incoming icmp packet
;;;   takes: x = layer 4 pdu ptr
icmp_in:
	ldb	,x		; get type
	cmpb	#8		; is ping then pong
	beq	pong
	lbra	ip_cont_filter


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

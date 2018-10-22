
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
	lbra	ip_drop
pong:
	ldb	#1		; icmp protocol's number
	stb	proto
	ldd	ripaddr		; copy received address
	std	dipaddr
	ldd	ripaddr+2
	std	dipaddr+2
	clra			; clear out header
	clrb
	std	,x		; make packet a reply
	std	2,x		; zero out cksum
	;; calc cksum
	ldy	rlen		; fixme: shouldn't ip_out do the cksum for us?
	ldd	#0
	jsr	ip_cksum
	std	2,x
	;; send to ip
	ldd	rlen
	jsr	ip_out
	lbra	ip_drop

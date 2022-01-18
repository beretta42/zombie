	include "zombie.def"

	export  eth_init
	export	eth_in
	export	eth_out
	export  eth_send
	export  eth_setaddr
	export  mac
	export  dmac
	export	type
	export	cmp_mac
	export	bmac
	
	.area	.data
dmac	rmb	6
mac	rmb	6
type	rmb 	2

	.area	.code

;;; fixme: mac should go in a well know place
;;;   for conjiguring into ROMS
bmac	.db	-1,-1,-1,-1,-1,-1
;;; keep this stuff together for easier copying to actual packet header,
;;; 	but all this stuff should go into RAM!!! (and out of area .code)
;;;     this means initing 'mac'.
mirror
	.db	-1,-1,-1,-1,-1,-1
	.db	0,1,2,3,4,5
	.dw	0x806
	
cmp_mac
	pshs	y,u	
	ldd	,u++
	cmpd	,y++
	bne	out@
	ldd	,u++
	cmpd	,y++
	bne	out@
	ldd	,u
	cmpd	,y
out@	puls	y,u,pc

	;; init this module
eth_init
	IFNDEF  ETH_ONLY
	lbsr	arp_init
	ENDC
	leau	mirror,pcr
	leay	dmac,pcr
	ldb	#14
	lbra	memcpy

eth_in:	std	pdulen,pcr
	;; filter on Destination address
	tfr	x,u
	leay	mac,pcr		; is our MAC ?
	lbsr	cmp_mac
	beq	cont@
	lda	,x		; is Broadcast / Multicast MAC?
	anda	#1
	bne	cont@
	lbra	ip_drop	       ; none of above, drop it.
cont@	;; todo: find a raw eth connection here
	;; distribute to upper layers
	stx	pdu,pcr
	ldd	12,x
	leax	14,x
	IFNDEF  ETH_ONLY
	cmpd	#$806		; is ARP?
	lbeq	arp_in
	cmpd	#$800		; is IPv4?
	lbeq	ip_in
	ENDC
	;; scan table for matching socket
	ldx	pdu,pcr
	lbsr	for_sock
a@	lbsr	next_sock
	lbcs	ip_drop
	ldy	conn,pcr
	ldb	C_FLG,y
	cmpb	#C_ETH
	bne	a@
	ldd	C_DPORT,y
	cmpd	12,x
	bne	a@
	;; found match
	ldx	C_CALL,y
	beq	b@
	ldb	#C_CALLRX
	jsr	,x
b@	rts

	

eth_out:
	IFNDEF  ETH_ONLY
	lbsr	arp_resolve
	bcs	out@		; dont send if we sent an ARP request
	ENDC
eth2	addd	#14		; add ethernet header length
	pshs	d
	leax	-14,x		; alloc eth header
	leay	,x
	leau	dmac,pcr
	ldb	#14
	lbsr	memcpy
	puls	d
	lbsr	dev_send	; send to device
out@	rts


eth_send:
	pshs	d,x
	ldx	conn,pcr
	ldd	C_DIP,x
	std	dmac,pcr
	ldd	C_DIP+2,x
	std	dmac+2,pcr
	ldd	C_DIP+4,x
	std	dmac+4,pcr
	ldd	C_DPORT,x
	std	type,pcr
	puls	d,x
	bra	eth2

eth_setaddr:
	pshs	x
	ldd	,x++
	std	mac,pcr
	ldd	,x++
	std	mac+2,pcr
	ldd	,x++
	std	mac+4,pcr
	puls	x
	jmp	dev_setaddr

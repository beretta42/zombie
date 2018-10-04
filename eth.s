	include "zombie.def"

	export	eth_in
	export	eth_out
	export  mac
	export  dmac
	export	type
	export	cmp_mac
	export	bmac
	
	.area	.data


	.area	.code

;;; fixme: mac should go in a well know place
;;;   for conjiguring into ROMS
bmac	.db	-1,-1,-1,-1,-1,-1
;;; keep this stuff together for easier copying to actual packet header,
;;; 	but all this stuff should go into RAM!!! (and out of area .code)
;;;     this means initing 'mac'.
dmac	.db	-1,-1,-1,-1,-1,-1
mac	.db	0,1,2,3,4,5	
type	.dw	0x806	
	
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

eth_in
	;; filter for mac or broadcast
	tfr	x,u
	ldy	#mac	
	jsr	cmp_mac
	beq	cont@
	ldy	#bmac
	jsr	cmp_mac
	beq	cont@
	;; drop
drop	coma
	rts
cont@	;; todo: find a raw eth connection here
	;; distribute to upper layers
	ldd	12,x
	leax	14,x
	cmpd	#$806		; is ARP?
	lbeq	arp_in
	cmpd	#$800		; is IPv4?
	lbeq	ip_in
	bra	drop
	

eth_out:
	jsr	arp_resolve
	bcs	out@		; dont send if we sent an ARP request
	addd	#14		; add ethernet header length
	pshs	d
	leax	-14,x		; alloc eth header
	leay	,x
	ldu	#dmac
	ldb	#14
	jsr	memcpy
	puls	d
	jsr	dev_send	; send to device
out@	rts

;;; Internet Group Management Protocol
;;;  version 1, maybe 2.

	include "zombie.def"

	.area .data
pgroup:	.db	224,0,0,251	; mdns test	
	
	.area .code

	export igmp_in
igmp_in:
	lda	,x		; is a query packet?
	cmpa	#$11
	bne	out@
	leau	4,x
	leay	pgroup,pcr	; is our group?
	lbsr	ip_cmp
	beq	a@
	ldd	,u
	bne	out@
	ldd	2,u
	bne	out@
	;; send our report
a@	lbsr	igmp_test
out@	lbra	ip_drop

;;; takes X = ptr to ip group no
	export igmp_test
igmp_test:	
	ldd	pgroup,pcr	; new IP dest ip to our group
	std	dipaddr,pcr
	ldd	pgroup+2,pcr
	std	dipaddr+2,pcr
	;; build a unsolicited report message
	lbsr	getbuff
	bcs	err@
	pshs	x
	leax	47,x 		; leave room for lower layers
	pshs	x
	ldd	#$1600		; type, time
	std	,x++
	ldd	#$0000		; check sum
	std	,x++
	ldd	pgroup,pcr
	std	,x++
	ldd	pgroup+2,pcr
	std	,x
	puls	x		; calc and set cksum
	ldd	#0
	ldy	#8
	lbsr	ip_cksum
	std	2,x
	ldb	#2		; set ip protocol
	stb	proto,pcr
	ldd	#8		; length of igmp packet
	lbsr	ip_out
	puls	x
	lbsr	freebuff
err@	rts

	include "zombie.def"

	export  arp_init
	export	arp_in
	export	memcpy
	export	memclr
	export  arp_resolve
	export  arp_setbroad

;;;  ARP local database
;;;    todo: timestamp needed?
;;; 0   1b - used marker, 0 = unused
;;; 1   6b - mac address field
;;; 7   4b - ip address field
;;; 11b   - size of record

	.area	.data
ARPMAX	equ	8
	;; add some predefined entries for broadcasts
adb
	rmb	11*ARPMAX
adb_end rmb	2		; storage for pointer to itselft, (PIC)
outbuf	rmb	2		; tmp storage for outgoing buffer

	.area	.code


mirror	.db	1
	.dw	$ffff,$ffff,$ffff
	.db	255,255,255,255
	.db	1
	.dw	$ffff,$ffff,$ffff
broad	.db	192,168,42,255	; todo: set arp table for local broacast
mirrore


memcpy
	lda	,u+
	sta	,y+
	decb
	bne	memcpy
	rts

memclr
a@	clr	,y+
	decb
	bne	a@
	rts

;;; set the broadcast ip to eth mapping
arp_setbroad:
	ldd	,x++
	std	adb+broad-mirror,pcr
	ldd	,x++
	std	adb+broad-mirror+2,pcr
	rts

;;; initialize the arp sub-system
arp_init:
	leax	adb_end,pcr	; so we can compare ptr to end
	stx	adb_end,pcr	; easily in PIC.
	leay	adb,pcr		; copy prebuilt broadcast entries
	leau	mirror,pcr
	ldb	#mirrore-mirror
	lbsr	memcpy
	ldb	#11*(ARPMAX-2)
	lbsr	memclr
	rts

;;; processes incoming arp things
;;;   X = ptr to layer 3
arp_in:
	ldd	,x		; get hardware type
	cmpd	#1		; is ethernet?
	lbne	ip_drop
	ldd	2,x		; get protocol type
	cmpd	#$800		; is ip?
	lbne	ip_drop
	;; todo check protocol/hardware address lengths?
	;; or can we rely on above type checks?
	ldd	6,x
	cmpd	#1		; request?
	beq	request_in
	cmpb	#2		; reply?
	beq	reply_in
	lbra	ip_drop

request_in:
	leay	24,x		; get target ip address
	leau	ipaddr,pcr
	lbsr	ip_cmp		; compare to ours
	lbne	ip_drop
	inc	7,x		; convert packet to reply
	;; copy sender to target
	leay	18,x
	leau	8,x
	ldb	#10
	lbsr	memcpy
	;; copy sender mac to our dmac
	leay	dmac,pcr
	leau	8,x
	ldb	#6
	lbsr	memcpy
	;; send reply
	ldd	mac,pcr
	std	8,x		; fill in our mac
	ldd	mac+2,pcr
	std	10,x
	ldd	mac+4,pcr
	std	12,x
	ldd	ipaddr,pcr	; fill in our IP
	std	14,x
	ldd	ipaddr+2,pcr
	std	16,x
	ldd	#$806
	std	type,pcr
	ldd	#28		; size of arp
	lbsr	eth_out
	lbra	ip_drop

reply_in:
	pshs	x		; save packet ptr
	leay	14,x		; compare received ip
	bsr	lookup		; find match in database
	bcc	found@
	bsr	findnew		; find empty entry
	bcc	found@
	bsr	purge
found@	tfr	x,y
	clr	,y		; mark record as used
	inc	,y+		;
	puls	x
	leau	8,x
	ldb	#10		; copy eth and ip addresses
	lbsr	memcpy		; to new record
	lbra	ip_drop



;;; purge an old record in databse
;;;   returns: X = record ptr
;;;   todo: actually purge something
purge:
	rts

;;; find an ip address in arp database
;;;   takes: y = ptr to ip
;;;   returns: x = ptr to record
;;;   returns: C set on error
lookup:
	;; start by looking up in database
	leax	adb,pcr
a@	tst	,x
	beq	next@
	leau	7,x
	lbsr	ip_cmp
	beq	found@
next@	leax	11,x
	cmpx	adb_end,pcr
	bne	a@
	;; not found
	coma
	rts
found@	clra
	rts


;;; find an unused entry in arp database
findnew:
	leax	adb,pcr
a@	tst	,x
	beq	found@
	leax	11,x
	cmpx	adb_end,pcr
	bne	a@
	coma
	rts
found@  clra
	rts


;;; attempt resolve ip address
;;;   takes: x - ptr to sending pdu
;;;   returns C set if arp request sent
;;;   todo: some of this could be speed up by precalculating things at bind?
arp_resolve:
	pshs	d,x,y,u
	stx	outbuf,pcr
	;; if not IP don't resolve
	ldd	type,pcr
	cmpd	#$800
	bne	ok@
	;; if multicast IP then translate
	ldb	dipaddr,pcr
	andb	#$f0
	cmpb	#$e0
	beq	multicast
	;; if not local use gateway mac
	ldd	dipaddr,pcr
	anda	ipmask,pcr
	andb	ipmask+1,pcr
	cmpd	ipnet,pcr
	bne	use_gateway
	ldd	dipaddr+2,pcr
	anda	ipmask+2,pcr
	andb	ipmask+3,pcr
	cmpd	ipnet+2,pcr
	bne	use_gateway
	;; find in table
	leay	dipaddr,pcr
	lbsr	lookup
	bcc	found@
	;; else send request
	leau	dipaddr,pcr
	lbsr	arp_send
	bra	out@
found@	leau	1,x
b@	leay	dmac,pcr
	ldb	#6
	lbsr	memcpy
ok@	clra
out@	puls	d,x,y,u,pc
	export use_gateway
use_gateway
	leay	gateway,pcr
	lbsr	lookup
	bcc	found@
	;; not found! arp for the gateway IP then...
c@	leau	gateway,pcr
	lbsr	arp_send
	bra	out@
multicast:
	ldd	#$0100
	std	dmac,pcr
	ldd	#$5e00
	std	dmac+2,pcr
	ldd	#$00fb
	std	dmac+4,pcr
	bra	ok@


;;; send an arp
;;;   takes U = ptr ipaddr to lookup
arp_send
	ldx	outbuf,pcr	; fixme: hinky... this is called on *output*
	leax	5+14,x
	pshs	x
	ldd	#1
	std	,x++
	ldd	#$800
	std	,x++
	ldd	#$0604
	std	,x++
	ldd	#1
	std	,x++
	leay	16,x
	ldb	#4
	lbsr	memcpy
	;; fill out sender
	leay	,x
	leau	mac,pcr
	ldb	#6
	lbsr	memcpy
	leay	6,x
	leau	ipaddr,pcr
	ldb	#4
	lbsr	memcpy
	;; fill out target
	leay	10,x
	ldb	#6
	lbsr	memclr
	;; send
	ldd	#$806
	std	type,pcr
	puls	x
	ldd	#28
	lbsr	eth_out
	coma
	rts

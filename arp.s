	include "zombie.def"

	export	arp_in
	export	memcpy
	export	memclr
	export  arp_resolve
	
;;;  ARP local database
;;;    todo: timestamp needed?
;;; 0   1b - used marker, 0 = unused 
;;; 1   6b - mac address field
;;; 7   4b - ip address field
;;; 11b   - size of record 
	
	.area	.data
ARPMAX	equ	8
	;; add some predefined entries for broadcasts
adb	.db	1
	.dw	$ffff,$ffff,$ffff
	.db	255,255,255,255
	.db	1
	.dw	$ffff,$ffff,$ffff
	.db	192,168,42,255 	; todo: set arp table for local broacast
	zmb	11*ARPMAX
adb_end

;;; this is a pre-built arp request buffer
;;;  todo: really need a separate ARP buffer?
	rmb	5	      ; room for dw header
	rmb	14	      ; room for ethernet header
	;; arp starts here
tmp	.dw	$1	      ; hardware type: ethernet
	.dw	$800	      ; protocol type: ipv4
	.db	6	      ; hardware len
	.db	4	      ; protocol len
	.dw	1	      ; request
	;; the rest is filled out here
tmp1	rmb	20

	rmb	47		; a temp buffer for sending arp requests
	
	.area	.code
	

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

	
;;; processes incoming arp things
;;;   X = ptr to layer 3
arp_in:
	ldd	,x		; get hardware type
	cmpd	#1		; is ethernet?
	bne	drop
	ldd	2,x		; get protocol type
	cmpd	#$800		; is ip?
	bne	drop
	;; todo check protocol/hardware address lengths?
	;; or can we rely on above type checks?
	ldd	6,x
	cmpd	#1		; request?
	beq	request_in
	cmpb	#2		; reply?
	beq	reply_in
drop:	coma
	rts

request_in:
	leay	24,x		; get target ip address
	ldu	#ipaddr
	jsr	ip_cmp		; compare to ours
	bne	drop
	inc	7,x		; convert packet to reply
	;; copy sender to target
	leay	18,x
	leau	8,x
	ldb	#10
	jsr	memcpy
	;; copy sender mac to our dmac
	ldy	#dmac
	leau	8,x
	ldb	#6
	jsr	memcpy
	;; send reply
	ldd	mac
	std	8,x		; fill in our mac
	ldd	mac+2
	std	10,x
	ldd	mac+4
	std	12,x
	ldd	ipaddr		; fill in our IP
	std	14,x
	ldd	ipaddr+2
	std	16,x
	ldd	#$806
	std	type
	ldd	#28		; size of arp
	jsr	eth_out
	bra	drop
	
reply_in:
	pshs	x		; save packet ptr
	leay	14,x		; compare received ip
	bsr 	lookup		; find match in database
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
	jsr	memcpy		; to new record
	bra	drop
	


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
	ldx	#adb
a@	tst	,x
	beq	next@
	leau	7,x
	jsr	ip_cmp
	beq	found@
next@	leax	11,x
	cmpx	#adb_end
	bne	a@
	;; not found
	coma
	rts
found@	clra
	rts	
	

;;; find an unused entry in arp database
findnew:
	ldx	#adb
a@	tst	,x
	beq	found@
	leax	11,x
	cmpx	#adb_end
	bne	a@
	coma
	rts
found@  clra
	rts


;;; attempt resolve ip address
;;;   returns C set if arp request sent
;;;   todo: some of this could be speed up by precalculating things at bind?
arp_resolve:
	pshs	d,x,y,u
	;; if not IP don't resolve
	ldd	type
	cmpd	#$800
	bne	ok@
	;; if not local use gateway mac
	ldd	dipaddr
	anda	ipmask
	andb	ipmask+1
	cmpd	ipnet
	bne	use_gateway
	ldd	dipaddr+2
	anda	ipmask+2
	andb	ipmask+3
	cmpd	ipnet+2
	bne	use_gateway	
	;; find in table
	ldy	#dipaddr
	jsr	lookup
	bcc	found@
	;; else send request
	ldu	#dipaddr
	jsr	arp_send
	bra	out@
found@	leau	1,x
b@	ldy	#dmac
	ldb	#6
	jsr	memcpy
ok@	clra
out@	puls	d,x,y,u,pc
use_gateway
	ldy	#gateway
	jsr	lookup
	bcc	found@
	;; not found! arp for the gateway IP then...
c@	ldu	#gateway
	jsr	arp_send
	bra	out@


;;; send an arp
;;;   takes U = ptr ipaddr to lookup
arp_send
	ldx	#tmp1
	leay	16,x
	ldb	#4
	jsr	memcpy
	;; fill out sender
	leay	,x
	ldu	#mac
	ldb	#6
	jsr	memcpy
	leay	6,x
	ldu	#ipaddr
	ldb	#4
	jsr	memcpy
	;; fill out target
	leay	10,x
	ldb	#6
	jsr	memclr
	;; send
	ldd	#$806
	std	type
	ldx	#tmp
	ldd	#28
	jsr	eth_out
	coma
	rts

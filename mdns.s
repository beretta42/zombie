	include "zombie.def"

CL_IN	equ	1
TY_A	equ	1
TY_ANY	equ	255
TY_PTR	equ	12
TY_SRV  equ     33
TY_TXT  equ     16
TY_AAAA equ	28

TTL	equ	4500

	.area .data
list	rmb	7*2		; list of ptrs to records
lptr	rmb	2		; ptr to end of records
iptr	rmb	2		; ptr to iterate over records
lno	rmb	1		; number of ptrs
temp	rmb	2		; temp to save original y before

	.area .code

hostname
	.db	0		; flag
	.db	4
	fcc	"coco"
	.db	5
	fcc	"local"
	.db	0
	.dw	TY_A		; type
	.dw	CL_IN		; class
	.dw	0		; ttl
	.dw	TTL
	.dw	4		; rlength (A rec)
myip	rmb	4		; rr (A rec)


service
	.db	0		; flag
	.db	12
	fcc	"brett's coco"
	.db	7
	fcc	"_zombie"
	.db     4
	fcc	"_udp"
	.db	5
	fcc	"local"
	.db	0
	.dw	TY_SRV
	.dw	CL_IN
	.dw	0
	.dw	TTL
	.dw	end@-*-2		; rlength
	.dw	00			; priority
	.dw	00			; weight
	.dw	6809
	.db	4
	fcc	"coco"
	.db	5
	fcc	"local"
	.db	0
end@

text
	.db	0
	.db	12
	fcc	"brett's coco"
	.db	7
	fcc	"_zombie"
	.db	4
	fcc	"_udp"
	.db	5
	fcc	"local"
	.db	0
	.dw	TY_TXT
	.dw	CL_IN
	.dw	0
	.dw	TTL
	.dw	end@-*-2
	.db	11
	fcc	"file=awsome"
end@

ptr	.db	0		; flag
	.db	7
	fcc	"_zombie"
	.db	4
	fcc	"_udp"
	.db	5
	fcc	"local"
	.db	0
	.dw	TY_PTR
	.dw	CL_IN
	.dw	0
	.dw	TTL
	.dw	end@-*-2
	.db	12
	fcc	"brett's coco"
	.db	7
	fcc	"_zombie"
	.db	4
	fcc	"_udp"
	.db	5
	fcc	"local"
	.db	0
end@


gen
	.db	0		; flag
	.db	9
	fcc	"_services"
	.db	7
	fcc	"_dns-sd"
	.db	4
	fcc	"_udp"
	.db	5
	fcc	"local"
	.db	0
	.dw	TY_PTR
	.dw	CL_IN
	.dw	0
	.dw	TTL
	.dw	end@-*-2
	.db	7
	fcc	"_zombie"
	.db	4
	fcc	"_udp"
	.db	5
	fcc	"local"
	.db	0
end@

;;; initialize the mDNS subsystem
	export mdns_init
mdns_init:
	pshs	y
	leax	list,pcr	; reset list stack
	leay	hostname,pcr	; push our hostname onto list
	sty	,x++
	leay	service,pcr
	sty	,x++
	leay	ptr,pcr
	sty	,x++
	leay	gen,pcr
	sty	,x++
	leay	text,pcr
	sty	,x++
	ldd	#0
	std	,x
	stx	lptr,pcr
	ldd	ipaddr,pcr	; set our A entry's IP
	std	myip,pcr
	ldd	ipaddr+2,pcr
	std	myip+2,pcr
	clr	lno,pcr		; clear number of matches
	ldb	#C_UDP		; make a UDP socket
	lbsr	socket
	ldx	conn,pcr
	ldd	#5353		; set src/dest ports
	std	C_SPORT,x
	std	C_DPORT,x
	ldd	#$e000		; set IP address
	std	C_DIP,x
	ldd	#$00fb
	std	C_DIP+2,x
	leay	call,pcr	; set callback
	sty	C_CALL,x
	puls	y,pc

;;; call back for mdns
call:	cmpb	#C_CALLTO
	beq	timeout		; if timeout do that instead
	ldx	pdu,pcr
	tst	2,x		; is not a query?
	bmi	out@
	ldd	4,x		; get number of questions
	beq	out@		; if none ignore
	tsta			; more than 256 questions? - ignore
	bne	out@
	pshs	b		; push no onto stack to count
	leay	12,x		; y is start of questions
a@	leau	list,pcr	; start at beginning of list
	stu	iptr,pcr	;
	ldu	,u
b@	leau	1,u		; point past our local flag
	lbsr	compare
	bcs	next@
	lda	#1
	sta	-1,u
	inc	lno,pcr
next@	ldu	iptr,pcr	; increment record ptr
	leau	2,u
	stu	iptr,pcr
	ldu	,u		; load up next record
	bne	b@		; check next record if there's more
	lbsr	skipname	; skip name, type
	leay	4,y		; skip type, class
	dec	,s
	bne	a@
	leas	1,s		; drop question counter
d@	tst	lno,pcr
	beq	out@
	lbsr	lfsr		; pump random
	ldb	rand,pcr	; get random no.
	clra
	andb	#7		; from 1 - 32 jiffies (16-500ms)
	beq	d@
	ldy	conn,pcr
	std	C_TIME,y
out@	lbra	ip_drop


timeout:
	;; alloc and make static part of DNS
	lbsr	getbuff
	pshs	x
	leax	39,x
	pshs	x
	clr	,-s		; counter of answers
	ldd	#0		; trans ID
	std	,x++
	ldd	#$8400		; reponse + auth
	std	,x++
	ldd	#0		; question
	std	,x++
	std	,x++		; answers
	std	,x++		; auth
	std	,x++		; additional
	;; append each flagged entry
	leau	list,pcr
	stu	iptr,pcr
	ldu	,u
a@	lda	,u+
	bne	append@
next@	ldu	iptr,pcr
	leau	2,u
	stu	iptr,pcr
	ldu	,u
	bne	a@
	;; send it!
	clr	lno,pcr
	clra
	puls	b		; get answer counter
	ldy	,s
	std	6,y		; save no of answers
	tfr	x,d
	subd	,s
	puls	x
	lbsr	udp_out
	puls	x
	lbra	freebuff
append@ clr	-1,u		; clear flag for this entry
	inc	,s		; increment answer count
	;; copy name
b@	lda	,u+
	sta	,x+
	beq	cont@
c@	ldb	,u+
	stb	,x+
	deca
	bne	c@
	bra	b@
	;; copy fixed
cont@	ldd	,u++		; type
	std	,x++
	ldd	,u++		; class
	std	,x++
	ldd	,u++		; ttl
	std	,x++
	ldd	,u++
	std	,x++
	ldd	,u++		; RR length
	std	,x++
	;; copy rest of record
d@	lda	,u+
	sta	,x+
	decb
	bne	d@
	bra	next@

;;; compare names
;;;   takes y = ptr dns name
;;;   takes x = ptr to start of dns packet (possible compressed)
;;;   takes u = ptr to name (non compressed)
;;;   returns C clear if names are equal
compare:
	pshs	d,y,u
a@	lda	,y+		; get and compare length
	cmpa	#$c0
	bhs	ptr@
c@	cmpa	,u+
	bne	ne@
	tsta			; check for zero (end of name)
	beq	cont@
	;; is a length, loop each byte
b@	ldb	,y+
	cmpb	,u+
	bne	ne@
	deca
	bne	b@
	bra	a@
cont@	ldy	2,s		; reload Y as compression
	lbsr	skipname	; might have changed it
	ldd	,y++		; check type
	cmpd	#TY_ANY
	beq	any@
	cmpd	,u++
	bne	ne@
d@	ldd	,y++		; check class
	cmpd	,u++
	bne	ne@
ok@	clra
	puls	d,y,u,pc
ne@	coma
	puls	d,y,u,pc
ptr@	ldb	,y+		; get length
	anda	#~$c0
	leay	d,x		; add to packet base
	lda	,y+		; get that byte instead
	bra	c@
any@	leau	2,u
	bra	d@


;;; skip Y reg past a name
skipname:
	lda	,y+
	beq	out@		; done
	cmpa	#$c0
	bhs	ptr@
	leay	a,y		; skip past this name
	bra	skipname
ptr@	leay	1,y
out@	rts

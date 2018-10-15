	include "zombie.def"

	export	ip_in
	export	ip_out
	export	ipaddr
	export  ip_cmp
	export	ip_cksum
	export	proto
	export  dipaddr
	export	ripaddr
	export	ipbroad
	export	rlen
	export	ipnet
	export	ipmask
	export	gateway
	export	dns
	export  ip_setmask

	.area	.data
	rmb	47		; todo: fixme: for sending settings
ipaddr	.db	0,0,0,0		; our IP address
ipmask	.db	0,0,0,0		; our netmask
ipbroad	.db	0,0,0,0		; our broadcast address (calculated)
ipnet	.db	0,0,0,0		; our local network address (calculated)
gateway	.db	0,0,0,0		; our IP gateway / router
dns	.db	0,0,0,0		; our dns server

dipaddr .db	-1,-1,-1,-1		; destination ip address
proto	.db	17			; layer 4 protocol (udp)
ripaddr	.db	0,0,0,0			; most recv packet source ip (remote)
rlen	.dw	0			; length of recv packet PDU 
	
	.area	.code



;;; sets ip address
;;;   takes X - ptr to ip4 address
	ldd	,x
	std	ipaddr
	ldd	2,x
	std	ipaddr+2
	rts

;;; sets ip network address
;;;   takes X - ptr to mask
ip_setmask:
	ldd	,x
	std	ipmask
	ldd	2,x
	std	ipmask+2
	;; calculate broadcast address
	ldd	ipmask
	coma
	comb
	ora	ipaddr
	orb	ipaddr+1
	std	ipbroad
	ldd	ipmask+2
	coma
	comb
	ora	ipaddr+2
	orb	ipaddr+3
	std	ipbroad+2
	;; calculate network address
	ldd	ipmask
	anda	ipaddr
	andb	ipaddr+1
	std	ipnet
	ldd	ipmask+2
	anda	ipaddr+2
	andb	ipaddr+3
	std	ipnet+2
	rts

ip_cmp:
	pshs	y,u
	ldd	,u++
	cmpd	,y++
	bne	out@
	ldd	,u
	cmpd	,y
out@	puls	y,u,pc



;;; Process incoming layer 3 ip packets
;;;   takes: X - ptr layer 2 pdu (start of ip header)
;;;   returns: C clear if
ip_in:	
	;; check version (we only do version 4)
	ldb	,x
	andb	#$f0
	cmpb	#$40
	bne	drop
	;; check for fragments (we don't do fragments)
	ldb	6,x
	bitb	#$20
	bne	drop
	;; check dest ip address if not any address (0,0,0,0)
	;; then only accept packets with our IP
	ldd	ipaddr
	bne	a@
	ldd	ipaddr+2
	bne	a@
	bra	cont@
a@	leau	16,x
	ldy	#ipaddr		; is our ip?
	jsr	ip_cmp
	beq	cont@
	ldy	#ipbroad	; is broadcast ip?
	jsr	ip_cmp
	beq	cont@
drop:	coma
	rts
	;; packet looks good
cont@	ldd	12,x		; save source ip for use later
	std	ripaddr
	ldd	14,x
	std	ripaddr+2
	ldb	,x		; get vers/length
	andb	#$f		; just length
	lslb			; multiply by four
	lslb			; b is now length in bytes
	pshs	b
	clra
	pshs	d
	ldd	2,x
	subd	,s++
	std	rlen
	puls	b
	lda	9,x		; get packet type
	abx			; x is start of layer four
	cmpa	#17		; is udp?
	lbeq	udp_in		; go processes udp
	cmpa	#1		; is icmp?
	lbeq	icmp_in		; go answer ping
	cmpa	#6		; is tcp?
	lbeq	tcp_in		; go process tcp
	bra	drop


ip_out:
	addd	#20
	leax	-20,x
	std	2,x		; save length
	ldd	#$800
	std	type
	ldd	#$4500		; fill out ver/len/ecn
	std	,x
	ldd	#$0000		; clear id/flgs/offset/cksum
	std	4,x
	std	6,x
	std	10,x
	lda	#$40
	ldb	proto
	std	8,x
	;; fill in src/dst ip
	ldd	ipaddr
	std	12,x
	ldd	ipaddr+2
	std	14,x
	ldd	dipaddr
	std	16,x
	ldd	dipaddr+2
	std	18,x
	;; calc cksum
	ldy	#20
	ldd	#0
	jsr	ip_cksum
	std	10,x
	ldd	2,x
	jmp	eth_out

	export	ip_out2
ip_out2:
	addd	#20
	leax	-20,x
	std	2,x		; save length
	ldd	#$800
	std	type
	ldd	#$4500		; fill out ver/len/ecn
	std	,x
	ldd	#$0000		; clear id/flgs/offset/cksum
	std	4,x
	std	6,x
	std	10,x
	lda	#$40
	ldb	proto
	std	8,x
	;; fill in src/dst ip
	ldd	ipaddr
	std	12,x
	ldd	ipaddr+2
	std	14,x
	ldy	conn
	ldd	C_DIP,y
	std	16,x
	ldd	C_DIP+2,y
	std	18,x
	;; calc cksum
	ldy	#20
	ldd	#0
	jsr	ip_cksum
	std	10,x
	ldd	2,x
	jmp	eth_out

;;; ipv4 checksum
;;;   takes X = pointer to data
;;;   takes D = begining cksum
;;;   takes Y = length
ip_cksum:
	pshs	x
	exg 	d,y
	lsra
	rorb
	pshs	cc
	exg	d,y
a@	addd	,x++
	adcb	#0
	leay	-1,y
	bne	a@
	puls	cc
	bcc	b@
	adda	,x+
	adcb	#0
b@	coma
	comb
	puls	x,pc
	


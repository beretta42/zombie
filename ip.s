	include "zombie.def"

	export 	ip_init
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
ipaddr	rmb	4		; our IP address
ipmask	rmb	4		; our netmask
ipbroad	rmb	4		; our broadcast address (calculated)
ipnet	rmb	4		; our local network address (calculated)
gateway	rmb	4		; our IP gateway / router
dns	rmb	4		; our dns server

dipaddr rmb	4		; destination ip address
proto	rmb	1		; layer 4 protocol (udp)
ripaddr	rmb	4		; most recv packet source ip (remote)
rlen	rmb	2		; length of recv packet PDU 
end	
	.area	.code



;;; sets ip address
;;;   takes X - ptr to ip4 address
	ldd	,x
	std	ipaddr,pcr
	ldd	2,x
	std	ipaddr+2,pcr
	rts

;;; sets ip network address
;;;   takes X - ptr to mask
ip_setmask:
	ldd	,x
	std	ipmask,pcr
	ldd	2,x
	std	ipmask+2,pcr
	;; calculate broadcast address
	ldd	ipmask,pcr
	coma
	comb
	ora	ipaddr,pcr
	orb	ipaddr+1,pcr
	std	ipbroad,pcr
	ldd	ipmask+2,pcr
	coma
	comb
	ora	ipaddr+2,pcr
	orb	ipaddr+3,pcr
	std	ipbroad+2,pcr
	;; calculate network address
	ldd	ipmask,pcr
	anda	ipaddr,pcr
	andb	ipaddr+1,pcr
	std	ipnet,pcr
	ldd	ipmask+2,pcr
	anda	ipaddr+2,pcr
	andb	ipaddr+3,pcr
	std	ipnet+2,pcr
	rts

ip_cmp:
	pshs	y,u
	ldd	,u++
	cmpd	,y++
	bne	out@
	ldd	,u
	cmpd	,y
out@	puls	y,u,pc


ip_init:
	leay	ipaddr,pcr
	ldb	#end-ipaddr
	lbra	memclr
	rts

;;; Process incoming layer 3 ip packets
;;;   takes: X - ptr layer 2 pdu (start of ip header)
;;;   returns: C clear if
ip_in:	
	;; check version (we only do version 4)
	ldb	,x
	andb	#$f0
	cmpb	#$40
	lbne	ip_drop
	;; check for fragments (we don't do fragments)
	ldb	6,x
	bitb	#$20
	lbne	ip_drop
	;; check dest ip address if not any address (0,0,0,0)
	;; then only accept packets with our IP
	ldd	ipaddr,pcr
	bne	a@
	ldd	ipaddr+2,pcr
	bne	a@
	bra	cont@
a@	leau	16,x
	leay	ipaddr,pcr
	lbsr	ip_cmp
	beq	cont@
	leay	ipbroad,pcr
	lbsr	ip_cmp
	beq	cont@
	lbra	ip_drop
	;; packet looks good
cont@	ldd	12,x		; save source ip for use later
	std	ripaddr,pcr
	ldd	14,x
	std	ripaddr+2,pcr
	ldb	,x		; get vers/length
	andb	#$f		; just length
	lslb			; multiply by four
	lslb			; b is now length in bytes
	pshs	b
	clra
	pshs	d
	ldd	2,x
	subd	,s++
	std	rlen,pcr
	puls	b
	lda	9,x		; get packet type
	abx			; x is start of layer four
	cmpa	#17		; is udp?
	lbeq	udp_in		; go processes udp
	cmpa	#1		; is icmp?
	lbeq	icmp_in		; go answer ping
	cmpa	#6		; is tcp?
	lbeq	tcp_in		; go process tcp
	lbra	ip_drop



	export	ip_out
ip_out:
	addd	#20
	leax	-20,x
	std	2,x		; save length
	ldd	#$800
	std	type,pcr
	ldd	#$4500		; fill out ver/len/ecn
	std	,x
	ldd	#$0000		; clear id/flgs/offset/cksum
	std	4,x
	std	6,x
	std	10,x
	lda	#$40
	ldb	proto,pcr
	std	8,x
	;; fill in src/dst ip
	ldd	ipaddr,pcr
	std	12,x
	ldd	ipaddr+2,pcr
	std	14,x
	ldy	conn,pcr
	ldd	C_DIP,y
	std	dipaddr,pcr
	std	16,x
	ldd	C_DIP+2,y
	std	dipaddr+2,pcr
	std	18,x
	;; calc cksum
	ldy	#20
	ldd	#0
	lbsr	ip_cksum
	std	10,x
	ldd	2,x
	lbra	eth_out

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
	


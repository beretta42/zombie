	include "zombie.def"

	export	dhcp_init

	.area	.data
oipaddr	rmb	4		; offered IP address
oserver	rmb	4		; server offering adress
vect	rmb	2		; discover/request vector

	.area	.code


dhcp_init:	
	;; set ip address to 0.0.0.0
	ldy	#ipaddr
	ldb	#4
	jsr	memclr
	;; set dest ip address to broadcast
	ldu	#ipbroad
	ldy	#dipaddr
	ldb	#4
	jsr	memcpy
	;; set port numbers
	ldd	#68
	std	sport
	ldd	#67
	std	dport
	;; wait till response received
	ldd	#discover
	std	vect
	jsr	poll
	bcs	bad@
	;; This is an offer to us - pull out offered ip
	ldd	16,x
	std	oipaddr
	ldd	18,x
	std	oipaddr+2
	;; pull out server id option
	leau	240,x	       ; start of options
c@	ldd	,u++
	cmpa	#54		; server id address?
	bne	d@
	pshs	b
	ldd	,u
	std	oserver
	ldd	2,u
	std	oserver+2
	puls	b
	bra	n@
d@	cmpa	#$ff		; end of options
	beq	e@
n@	leau	b,u
	bra	c@
	;; send request & wait for ack
e@	ldd	#request
	std	vect
	jsr	poll
	bcs	bad@
	;; pull out settings!
	ldd	oipaddr		; set IP address
	std	ipaddr
	ldd	oipaddr+2
	std	ipaddr+2
	leax	240,x		; skip to options
f@	ldb	,x+		; get option
	cmpb	#1		; subnet?
	beq	sub@
	cmpb	#3
	beq	router@
	cmpb	#6
	beq	dns@
	cmpb	#$ff
	beq	ok@
n1@	ldb	,x+
	abx
	bra	f@	
ok@	clra
	rts
bad@	coma
	rts
sub@	pshs	x
	leax	1,x
	jsr	ip_setmask
	puls	x
	bra	n1@
router@	ldd	1,x
	std	gateway
	ldd	3,x
	std	gateway+2
	bra	n1@
dns@	ldd	1,x
	std	dns
	ldd	3,x
	std	dns+2
	bra	n1@
	

poll	
	ldb	#3		; 3 retries
	stb	,-s
a@	ldb	#4*8		; 4 secs between retries 
	stb	,-s
	jsr	[vect]
	;; listen for offer from dhcp server
b@	jsr	dev_poll
	bcs	c@
	ldx	inbuf
	jsr	eth_in
	bcc	cont@
c@	ldd	#7
	jsr	pause
	dec	,s
	bne	b@
	leas	1,s		; remove timer
	dec	,s
	bne	a@
	leas	1,s		; remove retries
	coma
	rts
	;; check for our xid
cont@   ldx	pdu
	ldd	4,x
	cmpd	mac
	bne	b@
	ldd	6,x
	cmpd	mac+2
	bne	b@
	;; check for bootp reply
	ldb	,x
	cmpb	#2
	bne	b@
	leas	2,s
	clra
	rts
	
request
	ldx	inbuf
	leax	47,x
	pshs	x
	jsr	header
	;; append options
	ldd	#$3501		; option 53 request
	std	,x++
	ldb	#$3
	stb	,x+
	ldd	#$3204		; option 50 requested ip
	std	,x++
	ldd	oipaddr
	std	,x++
	ldd	oipaddr+2
	std	,x++
	ldd	#$3604		; option 54 server ip
	std	,x++		;   required by rfc
	ldd	oserver
	std	,x++
	ldd	oserver+2
	std	,x++
	ldb	#$ff		; option end
	stb	,x+	
	bra	mysend

discover
	ldx	inbuf
	leax	47,x
	pshs	x
	jsr	header
	;; append options
	ldd	#$3501
	std	,x++
	ldb	#$01
	stb	,x+
	ldb	#$ff
	stb	,x+
	bra	mysend

mysend
	tfr	x,d
	subd	,s
	puls	x
	jsr	udp_out
	rts

header
	;; request + type + size + flags
	ldd	#$0101
	std	,x++
	ldd	#$0600
	std	,x++
	;; our mac is our xid
	ldd	mac
	std	,x++
	ldd	mac+2
	std	,x++
	;; clear secs/flag/addresses
	leay	,x
	ldb	#20
	jsr	memclr
	leax	20,x
	;; put mac in CHADDR
	ldd	mac
	std	,x++
	ldd	mac+2
	std	,x++
	ldd	mac+4
	std	,x++
	;; clear rest of CHADDR + old BOOTP stuff
	leay	,x
	ldb	#202
	jsr	memclr
	leax	202,x
	;; magic cookie
	ldd	#$6382
	std	,x++
	ldd	#$5363
	std	,x++
	rts
	


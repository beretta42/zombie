	include "zombie.def"

	export	dhcp_init

	.area	.data
oipaddr	rmb	4		; offered IP address
oserver	rmb	4		; server offering adress
vect	rmb	2		; discover/request vector
itype	rmb	1		; incoming dhcp message type
etype	rmb	1		; expected incoming dhcp type
retry	rmb	1               ; retry counter
flag	rmb	1		; break flag

	.area	.code


dhcp_init:
	;; set ip address to 0.0.0.0
	leay	ipaddr,pcr
	ldb	#4
	lbsr	memclr
	;; open a socket
	ldb	#C_UDP
	lbsr	socket
	;; set dest ip address to broadcast
	ldx	conn,pcr
	ldd	#$ffff
	std	C_DIP,x
	std	C_DIP+2,x
	;; set port numbers
	ldd	#68
	std	C_SPORT,x
	ldd	#67
	std	C_DPORT,x
	;; set callback
	leay    cb_offer,pcr
	sty	C_CALL,x
	;; setup call back for discover/offer
	ldb	#2
	stb	etype,pcr
	leax	discover,pcr
	lbsr	poll
	bcs	bad@
	;; setup call back for request/ack
	ldb	#5
	stb	etype,pcr
	leax	request,pcr
	lbsr	poll
	bcs	bad@
	;; pull out settings from the option area
	;; and set ip6809's IP settings
	ldx	pdu,pcr
	ldd	oipaddr,pcr	; set IP address
	std	ipaddr,pcr
	ldd	oipaddr+2,pcr
	std	ipaddr+2,pcr
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
ok@	lbsr	close
	clra
	rts
bad@	lbsr	close
	coma
	rts
sub@	pshs	x
	leax	1,x
	lbsr	ip_setmask
	puls	x
	bra	n1@
router@	ldd	1,x
	std	gateway,pcr
	ldd	3,x
	std	gateway+2,pcr
	bra	n1@
dns@	ldd	1,x
	std	dns,pcr
	ldd	3,x
	std	dns+2,pcr
	bra	n1@


offer:
	ldd	16,x
	std	oipaddr,pcr
	ldd	18,x
	std	oipaddr+2,pcr
	;; pull out server id option
	leau	240,x	       ; start of options
c@	ldd	,u++
	cmpa	#53		; is dhcp type?
	beq	type@
	cmpa	#54		; server id address?
	beq	server@
d@	cmpa	#$ff		; end of options
	beq	end@
next@	leau	b,u
	bra	c@
type@	lda	,u
	sta	itype,pcr
	bra	next@
end@	rts
server@	pshs	b
	ldd	,u
	std	oserver,pcr
	ldd	2,u
	std	oserver+2,pcr
	puls	b
	bra	next@
	
	
request
	lbsr	getbuff
	pshs	x
	leax	47,x
	pshs	x
	lbsr	header
	;; append options
	ldd	#$3501		; option 53 request
	std	,x++
	ldb	#$3
	stb	,x+
	ldd	#$3204		; option 50 requested ip
	std	,x++
	ldd	oipaddr,pcr
	std	,x++
	ldd	oipaddr+2,pcr
	std	,x++
	ldd	#$3604		; option 54 server ip
	std	,x++		;   required by rfc
	ldd	oserver,pcr
	std	,x++
	ldd	oserver+2,pcr
	std	,x++
	ldb	#$ff		; option end
	stb	,x+	
	bra	mysend

discover
	lbsr	getbuff
	pshs	x
	leax	47,x
	pshs	x
	lbsr	header
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
	lbsr	udp_out
	puls	x
	lbsr	freebuff
	rts

header
	;; request + type + size + flags
	ldd	#$0101
	std	,x++
	ldd	#$0600
	std	,x++
	;; our mac is our xid
	;; fixme: randomize
	ldd	mac,pcr
	std	,x++
	ldd	mac+2,pcr
	std	,x++
	;; clear secs/flag/addresses
	leay	,x
	ldb	#20
	lbsr	memclr
	leax	20,x
	;; put mac in CHADDR
	ldd	mac,pcr
	std	,x++
	ldd	mac+2,pcr
	std	,x++
	ldd	mac+4,pcr
	std	,x++
	;; clear rest of CHADDR + old BOOTP stuff
	leay	,x
	ldb	#202
	lbsr	memclr
	leax	202,x
	;; magic cookie
	ldd	#$6382
	std	,x++
	ldd	#$5363
	std	,x++
	rts


poll	ldb	#4		; set retransmits to 4 then fail
	stb	retry,pcr
	stx	vect,pcr	; store the BOOTREQUEST method
	jsr	[vect,pcr]      ; and call it to send initial packet
	ldx	conn,pcr
	ldd	#4*60		; set timeout to 4 sec
	std	C_TIME,x
	clr	flag,pcr        ; clear return flag
	;; loop processing packets until the flag is set
a@	tst	flag,pcr
	beq	a@
	lda	#1
	cmpa	flag,pcr
	rts

	export	cb_offer
cb_offer
	cmpb	#C_CALLTO
	beq	to@
	;; filter for XID
	ldx	pdu,pcr
	ldd	4,x
	cmpd	mac,pcr
	lbne	ip_drop
	ldd	6,x
	cmpd	mac+2,pcr
	lbne	ip_drop
	;; filter for bootp reply
	ldb	,x
	cmpb	#2
	lbne	ip_drop
	;; get offer options / filter for expected DHCP
	lbsr    offer
	lda	itype,pcr
	cmpa	etype,pcr
	lbne	ip_drop
	inc	flag,pcr
	ldx	conn,pcr
	clr	C_TIME,x
	clr	C_TIME+1,x
	bra	ok@
	;; a timeout has happend
to@	dec	retry,pcr
	beq	fail@           ; no failing on out-of-retries yet
	jsr	[vect,pcr]        ; send BOOTREQUEST packet again
	ldd	#4*60		; reset timer
	ldx	conn,pcr
	std	C_TIME,x
	bra	ok@
fail@	inc	flag,pcr
	inc	flag,pcr
ok@	lbra	ip_drop

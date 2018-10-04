	include "zombie.def"

	export	dhcp_init
	export	debug

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
	ldy	#ipaddr
	ldb	#4
	jsr	memclr
	;; open a socket
	ldb	#C_UDP
	jsr	socket
	;; set dest ip address to broadcast
	ldx	conn
	ldd	#$ffff
	std	C_DIP,x
	std	C_DIP+2,x
	;; set port numbers
	ldd	#68
	std	C_SPORT,x
	ldd	#67
	std	C_DPORT,x
	;; set callback
	ldd     #cb_offer
	std	C_CALL,x
	;; setup call back for discover/offer
	ldb	#2
	stb	etype
	ldx	#discover
	jsr	poll
	bcs	bad@
	;; setup call back for request/ack
	ldb	#5
	stb	etype
	ldx	#request
	jsr	poll
	bcs	bad@
	;; pull out settings from the option area
	;; and set ip6809's IP settings
	ldx	pdu
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
ok@	jsr	close
	clra
	rts
bad@	jsr	close
	coma
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


offer:
	ldd	16,x
	std	oipaddr
	ldd	18,x
	std	oipaddr+2
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
	sta	itype
	bra	next@
end@	rts
server@	pshs	b
	ldd	,u
	std	oserver
	ldd	2,u
	std	oserver+2
	puls	b
	bra	next@
	
	
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
	jsr	udp_out2
	rts

header
	;; request + type + size + flags
	ldd	#$0101
	std	,x++
	ldd	#$0600
	std	,x++
	;; our mac is our xid
	;; fixme: randomize
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


poll	ldb	#4		; set retransmits to 4 then fail
	stb	retry
	stx	vect		; store the BOOTREQUEST method
	jsr	[vect]          ; and call it to send initial packet
	ldx	conn
	ldd	#4*60		; set timeout to 4 sec
	std	C_TIME,x
	clr	flag            ; clear return flag
	;; loop processing packets until the flag is set
a@	tst	flag
	bne	out@
	jsr	dev_poll
	bcs	p@
	ldx	inbuf
	jsr	eth_in
	bra	a@
p@	ldd	#7		; wait before polling DW server again
	jsr	pause		; fixme: app shouldn't know about DW
	bra	a@
out@	lda	#1
	cmpa	flag
	rts


cb_offer
	cmpb	#C_CALLTO
	beq	to@
	;; filter for XID
	ldx	pdu
	ldd	4,x
	cmpd	mac
	bne	drop@
	ldd	6,x
	cmpd	mac+2
	bne	drop@
	;; filter for bootp reply
	ldb	,x
	cmpb	#2
	bne	drop@
	;; get offer options / filter for expected DHCP
	jsr     offer
	lda	itype
	cmpa	etype
	bne	drop@
	inc	flag
	ldx	conn
	clr	C_TIME,x
	clr	C_TIME+1,x
	bra	ok@
	;; a timeout has happend
debug
to@	dec	retry
	beq	fail@           ; no failing on out-of-retries yet
	jsr	[vect]	        ; send BOOTREQUEST packet again
	ldd	#4*60		; reset timer
	ldx	conn
	std	C_TIME,x
drop@	
ok@	rts
fail@	inc	flag
	inc	flag
	rts

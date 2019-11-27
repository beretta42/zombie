	include "zombie.def"

	.area .data
flag	rmb    1		; user signal: 0 wait, 1 - closed, 2 - reset
retry	rmb    1
hptr	rmb    2
eport	rmb    2		; next ephemeral port no.
	.area .code


;;; passive open
;;;   for now, only one open
;;;   takes: conn = socket
	export tcp_listen
tcp_listen
	ldx	conn,pcr
	;; set source port to zero
	clr	C_DPORT,x
	clr	C_DPORT+1,x
	;; set new sequence to a random number
	lbsr	lfsr
	ldd	rand,pcr
	std	C_SNDN,x
	lbsr	lfsr
	ldd	rand,pcr
	std	C_SNDN+2,x
	;; reset sync flag
	clr	flag,pcr
	;; set timeout, callback, retries
	leay	listen_cb,pcr
	sty	C_CALL,x
	;; spin until released
a@	tst	flag,pcr
	beq	a@
	rts

;;; active open
;;;   takes: conn = socket
    	export tcp_connect
tcp_connect
	ldx	conn,pcr
	;; if ephemeral ports isn't set up
	;; then set.
	ldd	eport,pcr
	bne	b@
	ldd	rand,pcr
	ora	#$c0
	std	eport,pcr
b@	;; if our local port is 0 then pick an ephemeral port
	ldd     C_SPORT,x
	bne	c@
	lbsr	ephem
	;; set new sequence to a random number
c@	lbsr	lfsr
	ldd	rand,pcr
	std	C_SNDN,x
	lbsr	lfsr
	ldd	rand,pcr
	std	C_SNDN+2,x
	;; set timeout, callback, retries
	ldd	#60		; time out
	std	C_TIME,x
	leay	cb_ssent,pcr
	sty	C_CALL,x
	clr	flag,pcr
	ldb	#3
	stb	retry,pcr
	lbsr	tcp_syn
	;; sit and spin until released
a@	ldb	flag,pcr
	beq	a@
	ldb	#1
	cmpb	flag,pcr
	rts


;;; call-back for the listen state
	export listen_cb
listen_cb
	ldx	hptr,pcr
	ldy	conn,pcr
	cmpb	#C_CALLTO
	lbeq	to@
	;; is this a SYN?
	ldb	13,x
	bitb	#2
	beq	out@		; not a SYN
	;; record ack + 1 for the sync
	ldd	6,x
	addd	#1		; add 1 to ack no for syn
	std	C_RCVN+2,y
	ldd	4,x
	adcb	#0		; add carry into MSB
	adca	#0
	std	C_RCVN,y
	;; record dest port
	ldd	0,x
	std	C_DPORT,y
	;; record dest ip
	ldd	ripaddr,pcr
	std	C_DIP,y
	ldd	ripaddr+2,pcr
	std	C_DIP+2,y
	;; set out timeout
	ldx	conn,pcr
	ldd	#60
	std	C_TIME,x
	leay	cb_ssent,pcr
	sty	C_CALL,x
	ldb	#3
	stb	retry,pcr
	;; send out initial sync packet (from us)
	lbsr	ip_drop
	lbsr	tcp_syn
	rts
to@	rts
out@	lbra	ip_drop


ephem:	pshs	x
	ldx	conn,pcr	; stack conn ptr
	pshs	x
a@	lbsr	for_sock	; start iterating
b@	lbsr	next_sock
	bcs	out@
	ldd	eport,pcr
	cmpd	C_SPORT,x	; get src port of socket
	bne	b@		; no then check next socket
	addd	#1		; yes then try next port
	bne	s@		; did we wrap to zero?
	ldd	#$c000		; yes then start at beg of ephem ports
s@	std	eport		; save in eport
	bra	a@		; start socket scan afresh
out@	puls	x		; restore conn ptr
	stx	conn,pcr
	ldd	eport,pcr
	std	C_SPORT,x	; save 
	addd	#1
	std	eport,pcr
	puls	x,pc


;; callback for established state
        export	cb_estab
cb_estab
	ldx	hptr,pcr
	ldy	conn,pcr
	cmpb	#C_CALLTO
	lbeq	to@
	;; check seq number if doesn't match ours
	;; then drop it and ack for where we're at.
	ldd	4,x   	    ; check msb of seq
	cmpd	C_RCVN,y
	lbne	drop_and_ack
	ldd	6,x	    ; check lsb of seq
	cmpd	C_RCVN+2,y
	lbne	drop_and_ack
	;; check ack: if this packet acklowedges our
	;; queued send buffer then release it.
	ldd	C_SNDZ,y	; buffer empty?
	beq	d@
	ldd     8,x
	cmpd	C_SNDN,y
	bne	d@
	ldd	10,x
	cmpd	C_SNDN+2,y
	bne	d@
	ldx	C_SNDB,y
	lbsr	freebuff
	clr	C_SNDZ,y
	clr	C_SNDZ+1,y
	;; if the receive buffer is free
	;; then store this buffer
d@	ldd	#$0001		; push ack / release buffer flags
	pshs	d
	ldd	pdulen,pcr	; if no data bytes...skip
	beq	b@
	ldd	C_RCVZ,y	; if user buffer full.. skip
	bne	b@
	ldd	pdu,pcr
	std	C_RCVD,y
	ldd	pdulen,pcr
	std	C_RCVZ,y
	ldd	inbuf,pcr	; save frame buffer for releasing later
	stx	C_RCVB,y
	;; adjust expected sequence no for next
	ldd	C_RCVZ,y
	addd	C_RCVN+2,y
	std	C_RCVN+2,y
	ldd	C_RCVN,y
	adcb	#0
	adca	#0
	std	C_RCVN,y
	inc	,s		; set send ack flag
	clr	1,s		; don't release buffer
	;; is this a FIN packet?
b@	ldx     hptr,pcr
	ldb	13,x
	bitb	#1
	beq	a@
	ldy     conn,pcr
	inc	,s		; set send ack flag
	;; remember remote has closed
	ldb	#1
	stb	C_TFLG2,y
	;; signal userspace not to wait
	inc	flag,pcr
	;; FIN bit counts as a sequence byte, so adjust answer by 1
	ldd	C_RCVN+2,y
	addd	#1
	std	C_RCVN+2,y
	ldd	C_RCVN,y
	adcb	#0
	adca	#0
	std	C_RCVN,y
a@      tst	,s+		; send ack if needed
	beq	g@
	lbsr	tcp_ack
g@	tst	,s+		; release buffer if needed
	beq	out@
	lbra	ip_drop
out@	rts
	;; timeout received for this socket
	;; if send buffer is full then resend it
	;; if not then just reset timer
to@	ldd     C_SNDZ,y
	beq	s@
	lbsr	tcp_tx
s@	ldd	#60
	std	C_TIME,y
	rts
drop_and_ack
	lbsr	ip_drop
	lbra	tcp_ack


;; callback for active open, sync sent state
	export	cb_ssent
cb_ssent
	cmpb	#C_CALLTO
	beq	to@
	ldx	hptr,pcr
	ldy	conn,pcr
	ldd	6,x
	addd	#1		; add 1 to ack no for syn
	std	C_RCVN+2,y
	ldd	4,x
	adcb	#0		; add carry into MSB
	adca	#0
	std	C_RCVN,y
	lbsr	ip_drop
	lbsr	tcp_ack
	ldy	conn,pcr
	ldd	#cb_estab	; go to established state NOT PIC
	std	C_CALL,y
	inc	flag,pcr	; signal connected
	rts
to@	dec	retry,pcr
	beq	out1@
	lbsr	tcp_syn
	ldx	conn,pcr
	ldd	#60
	std	C_TIME,x
	rts
out1@	inc	flag,pcr	; signal closed to userspace
	inc	flag,pcr
	rts
	
;;; send a syn
	export tcp_syn
tcp_syn
	lbsr	getbuff
	pshs	x
	leax	39,x		; todo: check size
	pshs	x
	ldy	conn,pcr
	ldd	C_SPORT,y	; append port nos
	std	,x++
	ldd	C_DPORT,y
	std	,x++
	ldd	C_SNDN,y	; our sequence number
	std	,x++
	ldd	C_SNDN+2,y
	std	,x++
	;; inc our sequence no by one
	addd    #1
	std	C_SNDN+2,y
	ldd	C_SNDN,y
	adcb	#0
	adca	#0
	std	C_SNDN,y
	;; 
	ldd	#0
	std	,x++		; msb ack
	std	,x++		; lsb ack
	ldd	#$5002		; data offset, syn
	std	,x++
	ldd	#$200		; window
	std	,x++
	ldd	#0		; cksum
	std	,x++
	ldd	#0
	std	,x++		; urg ptr
	ldb	#6
	stb	proto,pcr
	ldd	C_DIP,y
	std	dipaddr,pcr
	ldd	C_DIP+2,y
	std	dipaddr+2,pcr
	tfr	x,d
	subd	,s
	puls	x
	lbsr	tcp_cksum
	lbsr	ip_out
	puls	x
	lbra	freebuff


;;; send an ack
	export tcp_ack
tcp_ack
a@	lbsr	getbuff
	bcs	a@
	pshs	x
	leax	39,x		; todo: check size
	pshs	x
	ldy	conn,pcr
	ldd	C_SPORT,y	; source port
	std	,x++
	ldd	C_DPORT,y	; destination port
	std	,x++
	ldd	C_SNDN,y	; msb seq
	std	,x++
	ldd	C_SNDN+2,y	; lsb seq
	std	,x++
	ldd	C_RCVN,y
	std	,x++		; msb ack
	ldd	C_RCVN+2,y
	std	,x++		; lsb ack
	ldd	#$5010		; data offset, ack
	std	,x++
	ldd	#$200		; window
	std	,x++
	ldd	#0		; cksum
	std	,x++
	ldd	#0
	std	,x++		; urg ptr
	ldb	#6
	stb	proto,pcr
	ldd	C_DIP,y
	std	dipaddr,pcr
	ldd	C_DIP+2,y
	std	dipaddr+2,pcr
	tfr	x,d
	subd	,s
	puls	x
	lbsr	tcp_cksum
	lbsr	ip_out
	puls	x
	lbra	freebuff


;;; close socket
;;;   takes: conn - socket ptr
        export  tcp_close
tcp_close
	ldy	conn,pcr
	;; send FIN
	ldb	#1		; set fin bit on empty packet
	stb	C_TFLG,y
	ldx	#0
	ldd	#0
	lbsr	tcp_send
	;; wait for ack
	clr	flag,pcr
	ldy	conn,pcr
a@	tst	flag,pcr
	beq	a@
	;; reset callback + timeout
	ldd	#0
	std	C_CALL,y
	rts

;;; received data
;;;  takes: D - lenth of buffer, X - buffer ptr
;;;  returns: D - lenth of data
;;;  returns: C set on error
        export  tcp_recv
tcp_recv
	pshs	d,x,y,u
	ldy	conn,pcr
	tst	C_TFLG2,y	; remote closed?
	bne	closed@
	clr	flag,pcr	; reset wait flag
	;; wait till there's data
a@	ldd	C_RCVZ,y
	bne	c@
	ldb	flag,pcr
	beq	a@
	;; close or reset
	cmpb	#1
	bra	d@
	;; copy data to application
c@	std	,s
	ldu	C_RCVD,y
	tfr	d,y
b@	lda	,u+
	sta	,x+
	leay	-1,y
	bne	b@
	;; free recv buffer, clear
	;; buffer size to allow more data
	ldy     conn,pcr
	ldx	C_RCVB,y
	lbsr	freebuff
	clr	C_RCVZ,y
	clr	C_RCVZ+1,y
	clra
d@	puls	d,x,y,u,pc
closed@	clr	,s
	clr	1,s
	puls	d,x,y,u,pc


;;; send data
;;;   takes: X ptr, D length
;;;   takes: conn - socket ptr
;;;    fixme: pushing extra unneccesary stuff on stack?
	export tcp_send
tcp_send
	pshs	d,x
	;; spin until socket's send buffer can be loaded
	ldy	conn,pcr
b@	ldd	C_SNDZ,y
	bne	b@
	;; spin until buffer is free
d@	lbsr	getbuff
	bcs	d@
	pshs	x
	leax	39,x		; todo: check size
	pshs	x
	ldy	conn,pcr
	ldd	2,s		; save the packet buffer ptr
	std	C_SNDB,y
	;; start filling out the packet
	ldd	C_SPORT,y	; source port
	std	,x++
	ldd	C_DPORT,y	; destination port
	std	,x++
	ldd	C_SNDN,y	; msb seq
	std	,x++
	ldd	C_SNDN+2,y	; lsb seq
	std	,x++
	leax	4,x		; reserve room for ack (filled out later)
	ldd	#$5010		; data offset, ack
	orb	C_TFLG,y	; or in additional flags
	std	,x++
	ldd	#$200		; window (may want to send this in tcp_tx)
	std	,x++
	ldd	#0		; cksum  (filled out later)
	std	,x++
	std	,x++		; urg ptr
	;; cat data from application to packet
	ldu	6,s
	ldy	4,s
	pshs	x		; save start of tcp data
	beq	c@
a@	ldb	,u+
	stb	,x+
	leay	-1,y
	bne	a@
	;; next sequence no = sequence no + segment length
c@	ldy	conn,pcr
	tfr	x,d
	subd	,s++		; subtract ptrs to get length
	addd	C_SNDN+2,y	; add to lsb of seq
	std	C_SNDN+2,y
	ldd	C_SNDN,y
	adcb	#0		
	adca	#0
	std	C_SNDN,y
	;; is a FIN packet then inc our next send by 1
	ldb     C_TFLG,y
	bitb	#1
	beq	e@
	ldd	C_SNDN+2,y
	addd	#1
	std	C_SNDN+2,y
	ldd	C_SNDN,y
	adcb	#0
	adca	#0
	std	C_SNDN,y
	;; set ack timeout to 1 sec
	ldd     #60
	std	C_TIME,y
	;; figure and set the packet's size 
e@	tfr	x,d
	subd	,s
	ldy	conn,pcr
	std	C_SNDZ,y
	leas	4,s
	;; send it
	lbsr	tcp_tx
	puls	d,x,pc

tcp_tx
	pshs	y
	ldy	conn,pcr
	ldx	C_SNDB,y
	leax	39,x
	ldb	#6
	stb	proto,pcr
	ldd	C_DIP,y
	std	dipaddr,pcr
	ldd	C_DIP+2,y
	std	dipaddr+2,pcr
	ldd	C_RCVN,y
	std	8,x
	ldd	C_RCVN+2,y
	std	10,x
	ldd	C_SNDZ,y
	lbsr	tcp_cksum
	lbsr	ip_out
	puls	y,pc

;; todo: precalculate the relatively static
;; calc pseudo-header
;;   takes: X
tcp_cksum
	pshs	d,x,y
	clr	16,x		; clear out old cksum
	clr	17,x
	ldd	ipaddr,pcr
	addd	ipaddr+2,pcr
	adcb	#0
	adca	#0
	ldy	conn,pcr
	addd	C_DIP,y
	adcb	#0
	adca	#0
	addd	C_DIP+2,y
	adcb	#0
	adca	#0
	addb	#6
	adca	#0
	addd	,s
	adcb	#0
	adca	#0
	ldy	,s
	lbsr	ip_cksum
	std	16,x
a@	puls	d,x,y,pc

	
	export	tcp_in
tcp_in	
	lbsr	for_sock
a@	lbsr	next_sock
	lbcs	ip_drop		; fixme: send reset here
	ldy	conn,pcr
	ldb	C_FLG,y		; is a TCP socket?
	cmpb	#C_TCP
	bne	a@
	ldd	2,x		; is packet's dest port our source port?
	cmpd	C_SPORT,y
	bne	a@
	ldd	C_DPORT,y	; is socket listening?
	beq	go@
	cmpd	,x              ; is packet's source port our dest port?
	bne	a@
	;; fixme: filter for anything else here? (cksum?)
	;; found our socket
	;; record pdu / length
go@	stx	hptr,pcr	; save the header pointer
	ldb	12,x		; data offset
	lsrb			; multiply by 4 - header size in bytes
	lsrb			; (its in top nibble.. so divide by 4 rather)
	leay	b,x		; add header length to packet base
	sty	pdu,pcr		; and store address to pdu
	ldy	rlen,pcr	; get the length
	negb			; subtract length from ip's length
	leay	b,y		; 
	sty	pdulen,pcr	; save the length of the tcp segment
	;; check for tcp reset
	ldb	13,x
	bitb	#4
	bne	tcp_reset
	;; call the callback
	ldx	conn,pcr
	ldx	C_CALL,x
	lbeq	ip_drop
	ldb	#C_CALLRX
	jmp	,x

tcp_reset:
	ldx	conn,pcr	; get connection ptr
	ldb	#3
	stb	flag,pcr	; set reset flag to userspace
	ldd	#0
	std	C_CALL,x
	lbra	ip_drop
	

;;; initialize the tcp subsystem
        export  tcp_init
tcp_init
	clr	eport,pcr
	clr	eport+1,pcr
	rts

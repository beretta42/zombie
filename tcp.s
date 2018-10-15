	include "zombie.def"

	.area .data
flag	rmb    1
retry	rmb    1
hptr	rmb    2
eport	rmb    2		; next ephemeral port no.
	.area .code

;;; active open
;;;   takes: conn = socket
    	export tcp_connect
tcp_connect
	ldx	conn
	;; if ephemeral ports isn't set up
	;; then set.
	ldd	eport
	bne	b@
	ldd	rand
	ora	#$c0
	std	eport
b@	;; if our local port is 0 then pick an ephemeral port
	ldd     C_SPORT,x
	bne	c@
	jsr	ephem
	;; set new sequence to a random number
c@	ldd	rand		
	std	C_SNDN,x
	jsr	lfsr
	ldd	rand
	std	C_SNDN+2,x
	;; set timeout, callback, retries
	ldd	#60		; time out
	std	C_TIME,x
	ldd	#cb_ssent	; waiting for syn/ack callback
	std	C_CALL,x
	clr	flag
	ldb	#3
	stb	retry
	jsr	tcp_syn
a@	ldb	flag
	beq	a@
	ldb	#1
	cmpb	flag
	rts


ephem:	pshs	x
	ldx	conn		; stack conn ptr
	pshs	x
a@	jsr	for_sock	; start iterating
b@	jsr	next_sock
	bcs	out@
	ldd	eport
	cmpd	C_SPORT,x	; get src port of socket
	bne	b@		; no then check next socket
	addd	#1		; yes then try next port
	bne	s@		; did we wrap to zero?
	ldd	#$c000		; yes then start at beg of ephem ports
s@	std	eport		; save in eport
	bra	a@		; start socket scan afresh
out@	puls	x		; restore conn ptr
	stx	conn
	ldd	eport
	std	C_SPORT,x	; save 
	addd	#1
	std	eport
	puls	x,pc


	
;; callback for established state
        export	cb_estab
cb_estab
	ldx	hptr
	ldy	conn
	cmpb	#C_CALLTO
	lbeq	to@
	;; check for reset here
	ldb     13,x
	bitb	#4
	beq	e@
	;; fixme: do something clever on reset here
	;; check seq number if doesn't match ours
	;; then drop it and ack for where we're at.
e@	ldd	4,x   	    ; check msb of seq
	cmpd	C_RCVN,y
	lbne	tcp_ack
	ldd	6,x	    ; check lsb of seq
	cmpd	C_RCVN+2,y
	lbne	tcp_ack
	;; check ack: if this packet acklowedges our
	;; queued send buffer then release it.
	ldd     8,x
	cmpd	C_SNDN,y
	bne	d@
	ldd	10,x
	cmpd	C_SNDN+2,y
	bne	d@
	ldx	C_SNDB,y
	jsr	freebuff
	clr	C_SNDZ,y
	clr	C_SNDZ+1,y
	;; if the receive buffer is free
	;; then store store this buffer
d@	ldd	pdulen
	beq	b@
	ldd	C_RCVZ,y
	lbne	tcp_ack
	ldd	pdu
	std	C_RCVD,y
	ldd	pdulen
	std	C_RCVZ,y
	ldd	inbuf
	stx	C_RCVB,y
	;; adjust for next
c@	ldd	C_RCVZ,y
	addd	C_RCVN+2,y
	std	C_RCVN+2,y
	ldd	C_RCVN,y
	adcb	#0
	adca	#0
	std	C_RCVN,y
	;; if final send ack
b@	ldx     hptr
	ldb	13,x
	bitb	#1
	beq	a@
	;; fin packet counts as one sequence byte
	ldy     conn
	clr	C_TFLG2,y
	ldd	C_RCVN+2,y
	addd	#1
	std	C_RCVN+2,y
	ldd	C_RCVN,y
	adcb	#0
	adca	#0
	std	C_RCVN,y
a@	jsr	tcp_ack
	rts
	;; timeout received for this socket
	;; if send buffer is full then resend it
	;; if not then just reset timer
to@	ldd     C_SNDZ,y
	beq	s@
	jsr	tcp_tx
s@	ldd	#60
	std	C_TIME,y
	rts
	

;; callback for active open, sync sent state
	export	cb_ssent
cb_ssent
	cmpb	#C_CALLTO
	beq	to@
	ldx	hptr
	ldy	conn
	;; if a reset then flag closed, stop this callback,
	ldb	13,x
	bitb	#$4
	beq	a@
	inc	flag
	inc	flag
	ldd	#0
	std	C_CALL,y
	rts
a@	ldd	6,x
	addd	#1		; add 1 to ack no for syn
	std	C_RCVN+2,y
	ldd	4,x
	adcb	#0		; add carry into MSB
	adca	#0
	std	C_RCVN,y
	jsr	tcp_ack
	ldy	conn
	ldd	#cb_estab	; go to established state
	std	C_CALL,y
	inc	flag
	rts
to@	dec	retry
	beq	out1@
	jsr	tcp_syn
	ldx	conn
	ldd	#60
	std	C_TIME,x
	rts
out1@	inc	flag
	inc	flag
	rts
	
;;; send a syn
	export tcp_syn
tcp_syn
	jsr	getbuff
	pshs	x
	leax	39,x		; todo: check size
	pshs	x
	ldy	conn
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
	stb	proto
	tfr	x,d
	subd	,s
	puls	x
	jsr	tcp_cksum
	jsr	ip_out2
	puls	x
	jmp	freebuff


;;; send an ack
	export tcp_ack
tcp_ack
a@	jsr	getbuff
	bcs	a@
	pshs	x
	leax	39,x		; todo: check size
	pshs	x
	ldy	conn
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
	stb	proto
	tfr	x,d
	subd	,s
	puls	x
	jsr	tcp_cksum
	jsr	ip_out2
	puls	x
	jmp	freebuff


;;; close socket
;;;   takes: conn - socket ptr
        export  tcp_close
tcp_close
	ldy	conn
	;; send FIN
	ldb	#1		; set fin bit on empty packet
	stb	C_TFLG,y
	stb	C_TFLG2,y
	ldx	#0
	ldd	#0
	jsr	tcp_send
	;; wait for ack
	ldy	conn
a@	ldd	C_SNDZ,y
	bne	a@
	;; clear fin bit
	ldy	conn		; fin done
	clr	C_TFLG,y
	;; and then wait for remote's fin
	ldy	conn
b@	tst	C_TFLG2,y
	bne	b@
	clr	,y
	rts

;;; received data
;;;  takes: D - lenth of buffer, X - buffer ptr
;;;  returns: D - lenth of data
        export  tcp_recv
tcp_recv
	pshs	d,x,y,u
	ldy	conn
	;; wait till there's data
a@	ldd	C_RCVZ,y
	beq	a@
	;; copy data to application
	std	,s
	ldu	C_RCVD,y
	tfr	d,y
b@	lda	,u+
	sta	,x+
	leay	-1,y
	bne	b@
	;; free recv buffer, clear
	;; buffer size to allow more data
	ldy     conn
	ldx	C_RCVB,y
	jsr	freebuff
	clr	C_RCVZ,y
	clr	C_RCVZ+1,y
	puls	d,x,y,u,pc
	


;;; send data
;;;   takes: X ptr, D length
;;;   takes: conn - socket ptr
;;;    fixme: pushing extra unneccesary stuff on stack?
	export tcp_send
tcp_send
	pshs	d,x
	;; spin until socket's send buffer can be loaded
	ldy	conn
b@	ldd	C_SNDZ,y
	bne	b@
	;; get a buffer and fill it out
	jsr	getbuff
	pshs	x
	leax	39,x		; todo: check size
	pshs	x
	ldy	conn
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
	ldb	C_TFLG,y	; or in additional flags
	orb	#$10
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
c@	ldy	conn
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
	ldy	conn
	std	C_SNDZ,y
	leas	8,s
	;; send it 
	jmp	tcp_tx

tcp_tx
	ldy	conn
	ldx	C_SNDB,y
	leax	39,x
	ldb	#6
	stb	proto
	ldd	C_RCVN,y
	std	8,x
	ldd	C_RCVN+2,y
	std	10,x
	ldd	C_SNDZ,y
	jsr	tcp_cksum
	jmp	ip_out2


;; todo: precalculate the relatively static
;; calc pseudo-header
;;   takes: X
tcp_cksum
	pshs	d,x
	ldd	ipaddr	
	addd	ipaddr+2
	adcb	#0
	adca	#0
	ldy	conn
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
	jsr	ip_cksum
	std	16,x
	puls	d,x,pc


	
	export	tcp_in
tcp_in	
	jsr	for_sock
a@	jsr	next_sock
	bcs	drop
	ldy	conn
	ldb	C_FLG,y		; is a TCP socket?
	cmpb	#C_TCP
	bne	a@
	ldd	,x		; is packet's source port our dest port?
	cmpd	C_DPORT,y
	bne	a@
	ldd	2,x		; is packet's dest port our source port?
	cmpd	C_SPORT,y
	bne	a@
	;; fixme: filter for anything else here? (cksum?)
	;; found our socket
	;; record pdu / length
	stx	hptr		; save the header pointer
	ldb	12,x		; data offset
	lsrb			; multiply by 4 - header size in bytes
	lsrb			; (its in top nibble.. so divide by 4 rather)
	leay	b,x		; add header length to packet base
	sty	pdu		; and store address to pdu
	ldy	rlen		; get the length
	negb			; subtract length from ip's length
	leay	b,y		; 
	sty	pdulen		; save the length of the tcp segment
	;; call the callback
	ldx	conn
	ldx	C_CALL,x
	beq	drop
	ldb	#C_CALLRX
	jsr	,x
drop	rts
	

;;; initialize the tcp subsystem
        export  tcp_init
tcp_init
	clr	eport
	clr	eport+1
	rts

	include "zombie.def"

	export	conn
	export	tab
	export  rand
	export  lfsr
	
	.area	.data
MAXBUF	equ	6		; fixme: defined by application
	;; a array of connections/sockets
tab	rmb	C_SIZE*6
tabe
	;; a free list of packet buffers
bufs	rmb	2*MAXBUF	; free buffer stack space
fptr	rmb	2		; free buffer stack pointer
fno	rmb	1		; number of buffer on free list
	
conn	rmb	2		; working socket

time	rmb	1		; polling pause timer
itime	rmb	1		; pause this much time after empty polls

rand	rmb	2		; random number
	
	.area	.code


;;; add a packet buffer to freelist
;;;    takes: X = buffer ptr
        export 	freebuff
freebuff
	pshs	cc,u
	cmpx	#0
	beq	out@
	orcc	#$10
	ldu	fptr,pcr
	stx	,--u
	stu	fptr,pcr
	inc	fno,pcr
out@	puls	cc,u,pc


;;; get a packet buffer from freelist
;;     takes: nothing
;;     returns: X = buffer ptr
;;     returns: C set on error (out of buffers)
        export	getbuff
getbuff	pshs	cc,u
	orcc	#$10
	tst	fno,pcr
	beq	err@
	ldu	fptr,pcr
	ldx	,u++
	stu	fptr,pcr
	dec	fno,pcr
	puls	cc
	clra
	puls	u,pc
err@	puls	cc
	coma
	puls	u,pc


;;; Drop the current input buffer
	export	ip_drop
ip_drop:
	pshs	x
	ldx	inbuf,pcr
	lbsr	freebuff
	puls	x,pc
	
;;; init stack
	export	ip6809_init
ip6809_init
	;; set random number seed
	ldd     #42
	std	rand,pcr
	;; clear socket/connection table
	leay	tab,pcr
	ldb	#tabe-tab
	lbsr	memclr
	;; init our data area
	leax	fptr,pcr
	stx	fptr,pcr
	clr	fno,pcr
	;; reset our pol timer
	ldb	#3		; fixme: should be set by something else?
	stb	itime,pcr
	stb	time,pcr
	;; init subsystems
	lbsr	eth_init
	lbsr	ip_init
	lbsr	udp_init
	lbsr	tcp_init
	rts

;;; get a socket
;;;   takes B = type (C_UDP)
;;;   sets conn to new socket, C set on error
        export	socket
socket	pshs	x
	lda	#8
	leax	tab,pcr
loop@	tst	C_FLG,x
	beq	found@
	leax	C_SIZE,x
	deca
	bne	loop@
	coma
	puls	x,pc
found@	stx	conn,pcr
	stb	,x
	leay	1,x
	ldb	#C_SIZE-1
	lbsr	memclr
	clra
	puls	x,pc

;;; send data to other end of socket
;;;   takes conn, X = pdu ptr, D = length
;;;   returns nothing
        export	send
send	; fixme: distribute to known protocols here
	; for now just udp
	lbra	udp_out


;;; closes a socket
;;;    takes conn
;;;    returns nothing
       	export close
close   clr    [conn,pcr]	; exciting!
	rts


;;; call this every tick
        export tick
tick	lbsr   lfsr
	ldy    conn,pcr
	ldx    inbuf,pcr	; push current working socket
	pshs   x,y
	;; iterate through each socket
	;; decrementing timer, and calling it's callback
	;; if zero
	lbsr    for_sock
a@	lbsr    next_sock
	bcs    poll@		; fixme: or should we goto poll?
	ldx    conn,pcr
	ldd    C_TIME,x
	beq    a@
	subd   #1
	std    C_TIME,x
	bne    a@
	ldy    C_CALL,x
	beq    a@
	ldb    #C_CALLTO
	jsr    ,y
	bra    a@
	;; poll device
debugp
poll@	dec    time,pcr		; decrement poll timer
	bne    out@
b@	lbsr   getbuff		; set buffer to new one
	bcs    out@
	stx    inbuf,pcr
	lbsr   dev_poll
	bcs    p@
	ldx    inbuf,pcr
	lbsr   eth_in
	ldb    #1
	stb    time,pcr
	bra    out@
p@	ldx    inbuf,pcr
	lbsr   freebuff
	ldb    itime,pcr	; reset pause timer
	stb    time,pcr
out@	puls   x,y
	stx    inbuf,pcr
	sty    conn,pcr
	rts


;;; start iterating over table via conn
        export	for_sock
for_sock
	pshs	x
	leax	tab-C_SIZE,pcr
	stx	conn,pcr
	puls	x,pc

;;; goto next socket
;;;    takes: nothing
;;;    returns: conn = next used socket, set C on none left
    	export next_sock 
next_sock
	pshs	x
	leax	tabe,pcr
	pshs	x
	ldx	conn,pcr
ns1	leax	C_SIZE,x
	cmpx	,s
	beq	nf@
	tst	,x
	beq	ns1
	stx	conn,pcr
	clra
	puls	d,x,pc
nf@	coma
	puls	d,x,pc



;; tick LFSR
lfsr
	ldd	rand,pcr
	lsra
	rorb
	bcc	a@
	eora	#$b4
a@	std	rand,pcr
	rts


;;; print a ip address/mask
;;;    takes X - ip addr ptr
	export	ipprint
ipprint
	pshs	d,x,u
	lda	#4
	sta	,-s
	bra	b@
a@	lda	#'.
	jsr	$a282
b@	clra
	ldb	,x+
	pshs	x
	jsr	$bdcc
	puls	x
	dec	,s
	bne	a@
	leas	1,s
	puls	d,x,u,pc

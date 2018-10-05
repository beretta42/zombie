	include "zombie.def"

	export	conn
	export	tab	
	
	.area	.data
MAXBUF	equ	1		; fixme: defined by application
	;; a array of connections/sockets
tab	rmb	C_SIZE*8
tabe
	;; a free list of packet buffers
bufs	rmb	2*MAXBUF	; free buffer stack space
fptr	rmb	2		; free buffer stack pointer
fno	rmb	1		; number of buffer on free list
	
conn	.dw	0		; working socket

time	.db	7		; polling pause timer
itime	.db	7		; pause this much time after empty polls
	
	.area	.code


;;; add a packet buffer to freelist
;;;    takes: X = buffer ptr
        export 	freebuff
freebuff
	pshs	cc,u
	orcc	#$10
	ldu	fptr
	stx	,--u
	stu	fptr
	inc	fno
	puls	cc,u,pc


;;; get a packet buffer from freelist
;;     takes: nothing
;;     returns: X = buffer ptr
;;     returns: C set on error (out of buffers)
        export	getbuff
getbuff	pshs	cc,u
	orcc	#$10
	tst	fno
	beq	err@
	ldu	fptr
	ldx	,u++
	stu	fptr
	dec	fno
	puls	cc
	clra
	puls	u,pc
err@	puls	cc
	coma
	puls	u,pc

	
;;; init stack
	export	ip6809_init
ip6809_init
	;; clear socket/connection table
	ldy	 #tab
	ldb	 #tabe-tab
	jsr	 memclr
	;; init our data area
	ldd    	 #fptr
	std	 fptr
	clr	 fno
	;; init subsystems
	jsr	 udp_init
	rts

;;; get a socket
;;;   takes B = type (C_UDP)
;;;   sets conn to new socket, C set on error
        export	socket
socket	pshs	x
	lda	#8
	ldx	#tab
loop@	tst	C_FLG,x
	beq	found@
	leax	C_SIZE,x
	deca
	bne	loop@
	coma
	puls	x,pc
found@	stx	conn
	stb	,x
	leay	1,x
	ldb	#C_SIZE-1
	jsr	memclr
	clra
	puls	x,pc

;;; send data to other end of socket
;;;   takes conn, X = pdu ptr, D = length
;;;   returns nothing
        export	send
send	; fixme: distribute to known protocols here
	; for now just udp
	jmp	udp_out2


;;; closes a socket
;;;    takes conn
;;;    returns nothing
       	export close
close   clr    [conn]	; exciting!
	rts


;;; call this every tick
        export tick
tick	ldy    conn
	ldx    inbuf		; push current working socket
	pshs   x,y
	;; iterate through each socket
	;; decrementing timer, and calling it's callback
	;; if zero
	jsr    for_sock
a@	jsr    next_sock
	bcs    poll@		; fixme: or should we goto poll?
	ldx    conn
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
poll@	dec    time		; decrement poll timer
	bne    out@
	jsr    getbuff		; set buffer to new one
	bcs    out@
	stx    inbuf
b@	jsr    dev_poll
	bcs    p@
	ldx    inbuf
	jsr    eth_in
	bra    b@
p@	ldx    inbuf
	jsr    freebuff
	ldb    itime		; reset pause timer
	stb    time
out@	puls   x,y
	stx    inbuf
	sty    conn
	rts


;;; start iterating over table via conn
        export	for_sock
for_sock
	pshs	x
	ldx	#tab-C_SIZE
	stx	conn
	puls	x,pc

;;; goto next socket
;;;    takes: nothing
;;;    returns: X/conn = next used socket, set C on none left
    	export next_sock 
next_sock
	pshs	x
	ldx	conn
ns1	leax	C_SIZE,x
	cmpx	#tabe
	beq	nf@
	tst	,x
	beq	ns1
	stx	conn
	clra
	puls	x,pc
nf@	coma
	puls	x,pc


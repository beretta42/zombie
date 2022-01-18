;;; A driver for RetroInnovation's CoCoNIC card
;;; based on the CS8900A chip
;;;


	include "zombie.def"

CARDCTL equ $ff80		; Jim's cartridge control register
NEWBASE equ $60			; LSB i/o base (out of MPI's way)

RXTX	equ $ff60		; uint16 data regsiter (LE)
PAGEPTR equ $ff6a		; uint16 pointer register (LE)
PAGEDATA equ $ff6c		; uint16 data register (LE)
TXCMD   equ $ff64
TXLEN   equ $ff66

	export	dev_init
	export  dev_send
	export  dev_poll
	export  dev_setaddr
	export  getpp
	export  setpp

	section .code

;;; Get a 16 bit word from packet page
;;;   takes: X address
;;;   returns: D data
getpp:
	tfr	x,d
	exg	a,b
	std	PAGEPTR
	ldd	PAGEDATA
	exg	a,b
	rts

;;; Set a 16 bit word to packet page
;;;   takes: X address, D data
;;;   returns: nothing
setpp:
	pshs	d
	tfr	x,d
	exg	a,b
	std	PAGEPTR
	puls	d
	exg	a,b
	std	PAGEDATA
	rts


;;; Called to set device address
dev_setaddr:
;; Set chip's MAC
	pshs	x,y
	tfr	x,y
	ldx	#$158		; X is MAC address in NIC
	ldd	,y++		; get first two MAC address bytes
	exg	a,b
	bsr	setpp
	ldd	,y++		; get next two MAC bytes
	exg	a,b
	leax	2,x
	bsr	setpp
	ldd	,y		; and set third two (6 bytes total)
	exg	a,b
	leax	2,x
	bsr	setpp
	puls	x,y,pc

;;; Called to initialize Device
;;;   returns: C set on error
dev_init:
	com	dev_need_poll
	pshs	x,y   ; save MAC address ptr
	;; change cards address to our non mpi base (ff60)
	ldd	#$55aa
	sta	CARDCTL
	stb	CARDCTL
	ldd	#$2201
	sta	CARDCTL
	stb	CARDCTL
	lda	#NEWBASE
	sta	CARDCTL
	;; check for card
	ldx	#0		; X = pp address
	bsr	getpp		; get reg: D = reg
	cmpd	#$630e		; compare chip signature
	bne	err@		; not same return error
	;; reset chip
	ldd	#$0040
	ldx	#$0114
	bsr	setpp
	;; turn on receiver / transmitter
	ldd	#$00d3		; Turn on receiver/transmitter
	ldx	#$112		;
	bsr	setpp		;
	ldd	#$0d05		; allow reception of our frames + broadcasts
	ldx	#$104		;
	bsr	setpp		;
	;; and return
	clrb			; clear C
	puls	x,y,pc
	;; return w/ error
err@	comb			; set C
	puls	x,y,pc		; return

;;; drop a frame
;;;   takes: nothing
;;;   returns: nothing
drop
	ldx	#$102
	lbsr	getpp
	orb	#$40
	bsr	setpp
	rts

;;; Send a packet to device
;;;   takes: X ptr to eth0 frame, D size
dev_send
	pshs	d,x,y		; save regs
	;; send transmit command, length
	ldd	#$00c0
	exg	a,b
	std	TXCMD
	puls	d
	exg	a,b
	std	TXLEN
	;; find rounded word length
	exg	a,b
	addd	#1
	lsra
	rorb
	tfr	d,y		; y is our count
	;; wait for room in NIC, drop received frames meanwhile
a@	ldx	#$138
	lbsr	getpp
	anda	#1
	bne	b@
	bsr	drop
	bra	a@
	;; send words from frame to NIC
b@	puls	x
c@	ldd	,x++
	std	RXTX
	leay	-1,y
	bne	c@
	;; return OK
	clrb
	puls	y,pc


;;; receive packet
;;;   returns: C set on no packet waiting
;;;   returns: insize = length
dev_poll
	pshs	d,x,y
	;; test for something waiting
	ldx	#$124
	lbsr	getpp
	anda	#$d
	beq	noth@		; nothing waiting
	;; these accesses are weird, and must be done in
	;; this order, it seems.
	lda	$ff61		; drop status
	ldb	$ff60
	ldb	$ff60		; get length
	lda	$ff61
	;; is too big?
	cmpd	inmax,pcr	;
	bhi	errbig@
	std	insize,pcr	; save as returned length
	;; round up
	addd	#1
	lsra
	rorb
	tfr	d,y		; Y = word count
	;; get words from NIC
	ldx	inbuf,pcr	; X = buffer
b@	ldd	RXTX		; get a word
	std	,x++		; save in buffer
	leay	-1,y		; dec counter
	bne	b@		; done?
	;; return
	clra
	puls	d,x,y,pc	; pull the rest
errbig@	lbsr	drop		; drop the packet
noth@	coma
	puls	d,x,y,pc	; pull the test

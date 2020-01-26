;;; todo: add lwwire packet chunk support (link layer fragmenting)



	include "zombie.def"

	export	dev_send
	export	dev_init
	export  dev_poll

; Used by DWRead and DWWrite
IntMasks equ   $50
NOINTMASK equ  1

; Hardcode these for now so that we can use below files unmodified
H6309    equ 0
BECKER   equ 1
ARDUINO  equ 0
JMCPBCK  equ 0
BAUD38400 equ 0


;;; use this to prevent driver from turning off interrupts during use
NOINTS	equ 0


ACK	equ $42


	.area	.code

; These files are copied almost as-is from HDB-DOS
	*PRAGMA nonewsource
	 include "dw.def"
	 include "dwread.s"
	 include "dwwrite.s"


;;; Send packet via lwwire
;;;   takes: X = ptr to pdu
;;;   takes: D = size of pdu
dev_send:
	pshs	cc
	IFEQ	NOINTS
	orcc	#$50
	ENDC
	leax	-5,x
	std	3,x
	addd	#5
	tfr	d,y
	ldd	#$f301
	std	0,x
	ldb	#$02
	stb	2,x
	lbsr	DWWrite
	puls	cc,pc

;;; Device initialization
;;;   return: C set on error
dev_init:
	pshs	cc
	IFEQ	NOINTS
	orcc	#$50
	ENDC
	ldd	#$f001
	std	,--s
	leax	,s
	ldy	#2
	lbsr	DWWrite
	leax	,s
	ldy	#1
	lbsr	DWRead
	bcs	err@		; frame error
	bne	err@		; timeout before all bytes received
	puls	d
	cmpa	#ACK
	bne	err@
	puls	cc
	clra
	rts
err@	puls	cc
	coma
	rts


;;; Poll device for awaiting packets
;;;   return C set on no packet waiting
dev_poll:
	pshs	cc
	IFEQ	NOINTS
	orcc	#$50
	ENDC
	;; see if any packet is waiting
	ldd	#$0100
	std	,--s
	ldb	#$f3
	stb	,-s
	leax	,s
	ldy	#3
	lbsr	DWWrite
	leas	1,s
	leax	,s
	ldy	#2
	lbsr	DWRead
	leas	2,s
	bne	no@
	bcs	no@
	ldd	-2,s
	beq	no@
	bmi	no@
	cmpd	inmax,pcr
	bhi	no@
	;; send get the packet
	std	insize,pcr
	ldd	#$0101
	std	,--s
	ldb	#$f3
	stb	,-s
	leax	,s
	ldy	#3
	lbsr	DWWrite
	leas	3,s
	;; get the packet data
	ldx	inbuf,pcr
	ldy	insize,pcr
	lbsr	DWRead
	bne	no@
	bcs	no@
yes@	puls	cc
	clra
	rts
no@	puls	cc
	coma
	rts

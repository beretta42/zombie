;;; A driver for sim6809 NIC interface
;;; based on the coconic driver
;;;


	include "zombie.def"

	export	dev_init
	export  dev_send
	export  dev_poll

	section .code


;;; Called to initialize Device
;;;   returns: C set on error
dev_init:
	;; and return
	clrb			; clear C
	rts


;;; Send a packet to device
;;;   takes: X ptr to eth0 frame, D size
dev_send
	pshs	d,x,y
	tfr	d,y
a@	ldb	,x+
	stb	$ff10
	leay	-1,y
	bne	a@
	stb	$ff11
	clrb
	puls	d,x,y,pc

RXTX	equ	42
;;; receive packet
;;;   returns: C set on no packet waiting
;;;   returns: insize = length
dev_poll
	pshs	d,x,y
	;; test for something waiting
	ldb	$ff10
	beq	noth@		; nothing waiting
	;; is too big?
	ldd	$ff11
	cmpd	inmax,pcr	;
	bhi	errbig@
	std	insize,pcr	; save as returned length
	;; get words from NIC
	tfr	d,y
	ldx	inbuf,pcr	; X = buffer
b@	ldb	$ff13		; get a word
	stb	,x+		; save in buffer
	leay	-1,y		; dec counter
	bne	b@		; done?
	;; return
	clra
	puls	d,x,y,pc	; pull the rest
errbig@	stb	$ff12		; drop it
noth@	coma
	puls	d,x,y,pc	; pull the test

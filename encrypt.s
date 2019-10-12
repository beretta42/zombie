	export	lsr1
	export	lsr2
	export  encrypt
	
	.area	.data


lsr1	rmb	4
lsr2	rmb	4

	.area	.code

step2
	leax	lsr2,pcr
	lsr	,x+
	ror	,x+
	ror	,x+
	ror	,x+
	bcc	a@
	leax	lsr2,pcr
	ldd	#$33d0
	eora	,x
	eorb	1,x
	std	,x
	;; return set
	ldb	#1
	rts
	;; return clear
a@	clrb
	rts


step1
	leax	lsr1,pcr
	andb	#1
	eorb	3,x
	andb	#1
	;; right shift
	lsr	,x+
	ror	,x+
	ror	,x+
	ror	,x+
	tstb
	beq	a@
	leax	lsr1,pcr
	ldd	#$edb8
	eora	,x
	eorb	1,x
	std	,x++
	ldd	#$8320
	eora	,x
	eorb	1,x
	std	,x
	ldb	#1
a@	rts

* ret ibit
step3
	pshs	a
	pshs	b
a@	ldb	,s
	bsr	step1
	pshs	b
	bsr	step2
	tst	,s+
	beq	a@
	leas	1,s
	puls	a,pc

* ret cnt
* a = byte	
stepb	pshs	x
	lda	#8
	pshs	a
	tfr	b,a
a@	tfr	a,b
	andb	#1
	bsr	step3
	lsra
	dec	,s
	bne	a@
	puls	b,x,pc


;;; fixme: need an a hashing function here
;;; see void hash(uint16_t salt, uint32_t k[], uint8_t *m, uint16_t size)
;;;
;;; 

	
	
;;; encrypt buffer
;;; set lsr1, lsr2 to key
;;; X = buffer addr
;;; Y = buffer size
encrypt
a@	clrb
	bsr	stepb
	ldb	,x
	eorb	lsr2+3,pcr
	stb	,x+
	leay	-1,y
	bne	a@

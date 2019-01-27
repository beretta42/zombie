

start	orcc	#$50
	leas	stacke,pcr
	;; apply map
	ldd	#$f000
	subd	start-18,pcr
	lsra
	lsra
	lsra
	lsra
	lsra
	clr     $ffa0           ; phys block 0 is always mapped to $0000
        ldy     #$ffa0
        leay    a,y             ; Y = beginning mmu
        ldb     #1              ; 1 is first os9 system block
c@      stb     ,y+             ; store bank no in mmu
        cmpy    #$ffa7          ; did we move to the last mmu block
        beq     d@              ; yes, then quit looping
        incb                    ; increment bank no
        bra     c@              ; repeat        
d@      ldb     #$3f            ; and mmu7 is always $3f
        stb     ,y
	;; copy last part of fe page
	leax	start-16,pcr
	ldu	#$fef0
	lda	#16
a@	ldb	,x+
	stb	,u+
	deca
	bne	a@
	;;  clear out dp
	ldx	#0
	clrb
b@	clr	,x+
	decb
	bne	b@
	;; setup gimme mirror
	ldx	#$90
	bsr	gime
	ldx	#$ff90
	bsr	gime
	;; setup screen
	bsr	scrSetup
	;; some os9 stuff
	ldx	$f009		; get kernel exec address
	leax	$f000,x		; make it absolute
	leau	start-18,pcr	; set U stack to just at size
	jmp	,x		; go run the kernel


;;; Setup memory with gimme setting, aka Do os9's work :(
;;;   takes: X = address
;;;   returns: nothing
;;;   modifies: nothing
gime
        pshs    d,x,u
        leau    table@,pcr
        lda     #16
a@      ldb     ,u+
        stb     ,x+
        deca
        bne     a@
        puls    d,x,u,pc
table@  .dw     $6c00
        .dw     $0000
        .dw     $0900
        .dw     $0000
        .dw     $0320
        .dw     $0000
        .db     $00
	.dw     $ec01
        .db     $00
	
;;; Setup Screen for os9 (sigh)
scrSetup
        pshs    d,x
        ;; set colors: green on black
        ldb     #$12
        stb     $ffbc
        ldb     #0
        stb     $ffbd
        ;; clear a screen's worth of video memory
        ldb     #$3b
        stb     $ffa0
        ldx     #$0000
        ldd     #$2020
a@      std     ,x++
        cmpx    #$0400
        bne     a@
        ;; set screen pointer up
        ldd     #8
        std     $0002
        clr     $ffa0
        puls    d,x,pc

	
	rmb	0x100
stacke



start	orcc	#$50
	ldx	#$ffa8
	clr	-8,x
	ldd	#$0001
	std	,x
	ldd	#$0203
	std	2,x
	ldd	#$0405
	std	4,x
	ldd	#$0607
	std	6,x
	ldb	$ffa2
	stb	2,x
	ldd	bounce,pcr
	std	$100
	ldd	bounce+2,pcr
	std	$102
	ldb	#1
	stb	$ff91
	ldy	#$200
	ldb	#2
	jmp	$100
bounce:
	stb	2,x
	jmp	,y


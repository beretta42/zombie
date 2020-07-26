;;; A test app for ethernet

	include	"zombie.def"


	export	ethtest

	.area	.data

	.area	.code


ethtest
	;; setup socket
	ldb	#C_ETH
	lbsr	socket
	ldx	conn,pcr
	ldd	#$ffff
	std	C_DIP,x
	ldd	#$ffff
	std	C_DIP+2,x
	ldd	#$ffff
	std	C_DIP+4,x
	ldd	#$6809
	std	C_DPORT,x
	leay	eth_call,pcr
	sty	C_CALL,x
	;; send packet
	lbsr	getbuff
	pshs	x
	leax	19,x
	pshs	x
	ldd	#$0102
	std	,x++
	ldd	#$0304
	std	,x++
	ldd	#$0506
	std	,x++
	tfr	x,d
	subd	,s
	puls	x
	lbsr	eth_send
	puls	x
	lbsr	freebuff
	rts


eth_call
	ldb	#'.
	lbsr	put_char
	lbra	ip_drop

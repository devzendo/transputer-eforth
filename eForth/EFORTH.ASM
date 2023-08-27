TITLE InMos Transputer 32-bit eForth

PAGE 60,132	;60 lines per page, 132 characters per line ( was 62,132 )

;===============================================================
;
;	eForth 1.0 by Bill Muench and C. H. Ting, 1990
;	Much of the code is derived from the following sources:
;		8086 figForth by Thomas Newman, 1981 and Joe smith, 1983
;		aFORTH by John Rible
;		bFORTH by Bill Muench
;
;	The goal of this implementation is to provide a simple eForth Model
;	which can be ported easily to many 8, 16, 24 and 32 bit CPU's.
;	The following attributes make it suitable for CPU's of the '90:
;
;		small machine dependent kernel and portable high level code
;		source code in the MASM format
;		direct threaded code
;		separated code and name dictionaries
;		simple vectored terminal and file interface to host computer
;		aligned with the proposed ANS Forth Standard
;		easy upgrade path to optimize for specific CPU
;
;	You are invited to implement this Model on your favorite CPU and
;	contribute it to the eForth Library for public use. You may use
;	a portable implementation to advertise more sophisticated and
;	optimized version for commercial purposes. However, you are
;	expected to implement the Model faithfully. The eForth Working
;	Group reserves the right to reject implementation which deviates
;	significantly from this Model.
;
;	As the ANS Forth Standard is still evolving, this Model will
;	change accordingly. Implementations must state clearly the
;	version number of the Model being tracked.
;
;	Representing the eForth Working Group in the Silicon Valley FIG Chapter.
;	Send contributions to:
;
;		Dr. C. H. Ting
;		156 14th Avenue
;		San Mateo, CA 94402
;		(415) 571-7639
;
;	32-bit Implementation for InMos Transputer by:
;		Bob Barr
;		c/o Mass Memory Technology
;		4113A Scotts Valley Drive
;		Scotts Valley, CA  95066
;		(408) 438-1887
;
;	Implementation for Parachute Transputer Emulator by:
;		Matt Gumbley
;		matt.gumbley@devzendo.org
;		@M0CUV@mastodon.radio
;
;===============================================================

		.TRANSPUTER

        INCLUDE         "boot/bootstrap.asm"

;; Version control

VER		EQU	01H			;major release version
EXT		EQU	02H			;minor extension

;; Constants

COMPO		EQU	040H			;lexicon compile only bit
IMEDD		EQU	080H			;lexicon immediate bit
MASKK		EQU	07F1FH			;lexicon bit mask

CELLL		EQU	4			;size of a cell
BASEE		EQU	10			;default radix
VOCSS		EQU	8			;depth of vocabulary stack

BKSPP		EQU	8			;backspace
LF		EQU	10			;line feed
CRR		EQU	13			;carriage return
ERRESC		EQU	27			;error escape
TIC		EQU	39			;tick

CALLL		EQU	0h	; was 0E890H NOP CALL opcodes

;; Memory allocation	0//code>--//--<name//up>--<sp//tib>--rp//em

EM		EQU	0x80400000              ;top of memory (4MB, the default Parachute RAM size)
COLDD		EQU	Boot2Start	        ;cold start vector

US		EQU	64*CELLL		;user area size in cells
RTS		EQU	64*CELLL		;return stack/TIB size

RPP		EQU	EM-8*CELLL		;start of return stack (RP0)
TIBB	        EQU	RPP-RTS 		;terminal input buffer (TIB)
SPP		EQU	TIBB-8*CELLL	        ;start of data stack (SP0)
UPP		EQU	EM-256*CELLL	        ;start of user area (UP0)
NAMEE		EQU	UPP-8*CELLL		;name dictionary
CODEE		EQU	COLDD+US		;code dictionary

;; Initialize assembly variables

_LINK	= 0					;force a null link
_NAME	= NAMEE 				;initialize name pointer
_CODE	= CODEE 				;initialize code pointer
_USER	= 4*CELLL				;first user variable offset

;; Define assembly macros


;	Compile a code definition header.

$CODE	MACRO	LEX,NAME,LABEL
	ALIGN	4				;;force to cell boundary
LABEL:						;;assembly label
	_CODE	= $				;;save code pointer
	_LEN	= (LEX AND 01FH)/CELLL		;;string cell count, round down
	_NAME	= _NAME-((_LEN+3)*CELLL)	;;new header on cell boundary
ORG	_NAME					;;set name pointer
	DD	 _CODE,_LINK			;;token pointer and link
	_LINK	= $				;;link points to a name string
	DB	LEX,NAME			;;name string
ORG	_CODE					;;restore code pointer
	ENDM

;	Compile a colon definition header.

$COLON	MACRO	LEX,NAME,LABEL
	$CODE	LEX,NAME,LABEL
	align	4
	ldc	8		;; point to dd DOLST (rel-dd-DOLST)
	ldpi			;; make prg rel -> absolute (&dd-DOLST)
	dup			;; second copy (&dd-DOLST &dd-DOLST)
	adc	4		;; point past the 'dd DOLST' (&next-word &dd-DOLST)
	rev			;; put incremented pointer under (&dd-DOLST &next-word)
	ldnl	0		;; fetch the pointer (&DOLST, &next-word)
	gcall			;; jump to it - call DOLST with the &next-word
	db	0,0
	dd	DOLST
	ENDM

;	Compile a user variable header.

$USER	MACRO	LEX,NAME,LABEL
	$CODE	LEX,NAME,LABEL
	align	4
	ldc	8		;; point to dd DOLST
	ldpi			;; make prg rel -> absolute
	dup			;; second copy
	adc	4		;; point past the 'dd DOLST'
	rev			;; put incremented pointer under
	ldnl	0		;; fetch the pointer
	gcall			;; jump to it
	db	0,0
	dd	DOLST
	DD	DOUSE,_USER			;;followed by doUSER and offset
	_USER	= _USER+CELLL			;;update user area offset
	ENDM

;	Compile an inline string.

D$	MACRO	FUNCT,STRNG
	DD	FUNCT				;;function
	_LEN	= $				;;save address of count byte
	DB	0,STRNG 			;;count byte and string
	_CODE	= $				;;save code pointer
ORG	_LEN					;;point to count byte
	DB	_CODE-_LEN-1			;;set count
ORG	_CODE					;;restore code pointer
	ALIGN	4
	ENDM


; Transputer assembly code macros and defines

entry1	equ	025fb2148h	; for direct threading 25 fb: move2dinit (?!), 21 48: ldc 18
entry2	equ	030f084fah	; 30:ldnl 0, f0:rev, 84:adc 4, fa:wsub
entry3	equ	0000000f6h	; f6:gcall
; Or is this executed as
; 48:ldc 8, 21 fb:ldpi, 25 fa:dup, 84:adc 4, f0:rev, 30:ldnl 0, f6:gcall?

; IServer I/O frames and link 0 addresses

REQ_POLLKEY     EQU 31
REQ_EXIT		EQU 35
REQ_PUTCHAR     EQU 90
STDOUT_STREAMID EQU 0x01
LINK0_OUTPUT    EQU 0x80000000
LINK0_INPUT     EQU 0x80000010

popx	macro			; pop tos to reg A
	ldl	spx		;; fetch sp
	dup			;; extra copy for fetch
	adc	4		;; bump up 1 level
	stl	spx		;; save it
	ldnl	0		;; get previous tos
	endm

pushx	macro			; push reg A to tos
	ldl	spx		;; sp
	adc	-4		;; adc -4
	stl	spx
	ldl	spx
	stnl	0		;; (sp) = n
	endm

celldn	macro			; bump A value down by 1 cell
	db	060h,08ch
	endm

uwait	macro			; kill a little time
	wcnt
	wcnt			; 2 wcnt operations (slow no-ops)
	endm

;
;	Assemble inline indirect threaded code ending.
$NEXT	MACRO
	ldl	ip			;; get ip
	dup
	adc	4			;; bump it one cell
	stl	ip			;; and save it back
	ldnl	0			;; get orig (ip)
	gcall				;; and jump to it
	ENDM

;; Main entry points and COLD start data

MAIN	SEGMENT USE32
ASSUME	CS:MAIN

ORG	COLDD			; Beginning of cold boot.

ORIG:
				; WPtr is at 800001C1 at this point
				; which is where primary boot put it
				; but that's in the UZERO..ULAST area
				; so set it to the end of this.
	ldc	ULAST
	gajw			; set workspace pointer to 0x800001E4
				; This gajw also changes priority - intended?
				; WPtr is now 800001E5

	mint			; most neg
	stl	0		; keep it handy
	clrj0break		; clear debug break
	timerdisableh		; disable hi-pri timer  ( timerdisableh )
	timerdisablel		; disable lo-pri timer  ( timerdisablel )

;	set initial return stack pointer
	ldc	RPP
	stl	rp

;	set initial data stack pointer
	ldc	SPP
	stl	spx

;	jump to cold start
	ldc	COLD
	gcall			; jump to it


; COLD start moves the following to USER variables.
; MUST BE IN SAME ORDER AS USER VARIABLES.

ALIGN  4					;align to cell boundary

UZERO:		DD	4 DUP (0)		;reserved
		DD	SPP			;SP0
		DD	RPP			;RP0
		DD	QRX			;'?KEY
		DD	TXSTO			;'EMIT
		DD	ACCEP			;'EXPECT
		DD	KTAP			;'TAP
		DD	TXSTO			;'ECHO
		DD	DOTOK			;'PROMPT
		DD	BASEE			;BASE
		DD	0			;tmp
		DD	0			;SPAN
		DD	0			;>IN
		DD	0			;#TIB
		DD	TIBB			;TIB
		DD	0			;CSP
		DD	INTER			;'EVAL
		DD	NUMBQ			;'NUMBER
		DD	0			;HLD
		DD	0			;HANDLER
		DD	0			;CONTEXT pointer
		DD	VOCSS DUP (0)		;vocabulary stack
		DD	0			;CURRENT pointer
		DD	0			;vocabulary link pointer
		DD	CTOP			;CP
		DD	NTOP			;NP
		DD	LASTN			;LAST
ULAST:

; Transputer initial workspace.
; Workspace local indices...
; Workspace[0] cannot be used; outbyte uses it.
inbyte	equ	01h		; single byte responses from the IServer are read here
; eForth VM registers
spx	equ	02h
ip	equ	03h
rp	equ	04h
scratch equ	05h

; Workspace area defined as symbols
OUTBYTE:	DD	0
INBYTE:		DD	0
SPX:		DD	0
IP:		DD	0
RP:		DD	0
SCRATCH:	DD	0

; There are only 64 cells between COLDD and here - if more workspace area is used
; watch out for collisions.. Currently SCRATCH is 800001F8 and CODEE is 80000220.

ORG	CODEE					;start code dictionary

;; Device dependent I/O

;   BYE 	( -- )
;		Exit eForth. 
;
		$CODE	3,'BYE',BYE
;		Terminate the IServer with a success exit code...
		ldc     LINK0_OUTPUT        ; (link0)
		ldc     REQ_EXIT            ; (req_exit link0)
		outbyte                     ; ()
		ldc     LINK0_OUTPUT        ; (link0)
		ldc		0	    ; (success link0)
		outword

;       	Read IServer response
		ldlp    inbyte              ; (&inbyte)
		ldc     LINK0_INPUT	    ; (link0 &inbyte)
		ldc     1                   ; (len=1 link0 &inbyte)
		in

;		Terminate Emulator.
		terminate


;   ?RX 	( -- c T | F )
;		Return input character and true, or a false if no input.

		$CODE	3,'?RX',QRX
		ldc     LINK0_OUTPUT        ; (link0)
		ldc     REQ_POLLKEY         ; (req_pollkey link0)
		outbyte                     ; ()

;		Read IServer response
		ldlp    inbyte              ; (&inbyte)
		ldc     LINK0_INPUT	    ; (link0 &inbyte)
		ldc     1                   ; (len=1 link0 &inbyte)
		in
		ldl	inbyte		    ; (inbyte)
		cj	QRX_RDCHR

;		No character is available, return false.
		ldc	0		    ; push a false
		pushx
		$NEXT

;		A character is available, read it and return true.
QRX_RDCHR:
		ldlp    inbyte              ; (&inbyte)
		ldc     LINK0_INPUT         ; (link0 &inbyte)
		ldc     1                   ; (len=1 link0 &inbyte)
		in
		ldl	inbyte      	    ; (inbyte)
 		pushx			    ; push char to tos
		ldc	-1
		pushx			    ; true on top of it
		$NEXT
		

;   TX! 	( c -- )
;		Send character c to the output device (IServer console).

		$CODE	3,'TX!',TXSTO
		ldc     LINK0_OUTPUT        ; (link0)
		ldc     REQ_PUTCHAR         ; (req_putchar link0)
		outbyte                     ; ()
		ldc     LINK0_OUTPUT        ; (link0)
		popx		            ; get the char (char link0)
		outbyte                     ; ()

;		Read (and ignore) IServer response
		ldlp    inbyte              ; (&inbyte)
		ldc     LINK0_INPUT	    ; (link0 &inbyte)
		ldc     1                   ; (len=1 link0 &inbyte)
		in

		$NEXT


;   !IO 	( -- )
;		Initialize the serial I/O devices.

		$CODE	3,'!IO',STOIO
		uwait			; kill time between writes
		$NEXT



;; The kernel

;   doLIT	( -- w )
;		Push an inline literal.

		$CODE	COMPO+5,'doLIT',DOLIT
		ldl	ip			; get ip
		dup				; dup it
		adc	4			; bump it up 1 cell
		stl	ip			; and save it
		ldnl	0			; get (ip)
		pushx				; push it to tos
		$NEXT

;   doLIST	( a -- )
;		Process colon list.
;		
;		(rtn-addr, &next-word --)

		$CODE	COMPO+6,'doLIST',DOLST
		stl	scratch 		; trash xputer rtn addr
						; this is after the gcall
						; in COLON
		stl	scratch 		; save target address
						; scratch=&next-word
		ldl	ip			; push ip onto return stack: (ip)
		ldl	rp			;   get rp (rp ip)
		celldn				;   adjust down 1 cell (rp+1 ip)
		dup				; (rp+1 rp+1 ip)
		stl	rp			; update rp (rp+1 ip)
		stnl	0			;   and put ip there ()
		ldl	scratch 		; get new list address (&next-word)
		stl	ip			; to ip
		$NEXT

;   EXIT	( -- )
;		Terminate a colon definition.

		$CODE	4,'EXIT',EXIT
		ldl	rp			;
		ldnl	0			; get (rp)
		stl	ip			; into ip
		ldl	rp			; adjust rp up
		adc	4			; ..by 1 cell
		stl	rp			;
		$NEXT

;   EXECUTE	( ca -- )
;		Execute the word at ca.

		$CODE	7,'EXECUTE',EXECU
		popx				; pop addr from stack
		gcall				; jump to it

;   next	( -- )
;		Run time code for the single index loop.
;		: next ( -- ) \ hilevel model
;		  r> r> dup if 1 - >r @ >r exit then drop cell+ >r ;

		$CODE	COMPO+4,'next',DONXT
		ldl	rp
		ldnl	0			; fetch the index
		db	060h,08fh		; adc -1
		dup				; extra copy for test
		ldl	rp
		stnl	0			; and back to (rp)
		mint				; sign bit set? (decr below 0)
		and
		eqc	0

		cj	NEXT1

		ldl	ip			; else, continue loop
		ldnl	0			; ip = (ip)
		stl	ip
		$NEXT

NEXT1:
		ldl	rp			; else, pop the index
		adc	4
		stl	rp
		ldl	ip
		adc	4
		stl	ip
		$NEXT

;   ?branch	( f -- )
;		Branch if flag is zero.

		$CODE	COMPO+7,'?branch',QBRAN
		popx				; get flag

		cj	BRAN1
						;else continue past
		ldl	ip			;point IP to next cell
		adc	4			;(past the inline branch)
		stl	ip
		$NEXT

BRAN1:
		ldl	ip			; get ip
		ldnl	0			; get (ip)  (the branch target)
		stl	ip			; ip = (ip)
		$NEXT

;   branch	( -- )
;		Branch to an inline address.

		$CODE	COMPO+6,'branch',BRAN
		ldl	ip			; get ip
		ldnl	0			; get (ip)
		stl	ip			; ip = (ip)
		$NEXT

;   !		( w a -- )
;		Pop the data stack to memory.

		$CODE	1,'!',STORE
		popx				; get the address
		popx				; ..and the data
		rev
		ldnl	0			; store it
		$NEXT

;   @		( a -- w )
;		Push memory location to the data stack.

		$CODE	1,'@',AT
		ldl	spx			; get pointer to tos
		ldnl	0			; get the addr
		ldnl	0			; get (addr)
		ldl	spx			; point to tos
		stnl	0			; set data to tos
		$NEXT

;   C!		( c b -- )
;		Pop the data stack to byte memory.

		$CODE	2,'C!',CSTOR
		popx				; get the addr
		popx				; ..and the byte
		rev
		sb				; store it
		$NEXT

;   C@		( b -- c )
;		Push byte memory location to the data stack.

		$CODE	2,'C@',CAT
		ldl	spx			; get the addr of tos
		ldnl	0			; get byte addr
		lb				; fetch the byte
		ldl	spx			; point to tos
		stnl	0			; and put the byte at tos
		$NEXT

;   RP@ 	( -- a )
;		Push the current RP to the data stack.

		$CODE	3,'RP@',RPAT
		ldl	rp			; get rp value
		pushx				; to tos
		$NEXT

;   RP! 	( a -- )
;		Set the return stack pointer.

		$CODE	COMPO+3,'RP!',RPSTO
		popx				; get the value
		stl	rp			; set to rp reg
		$NEXT

;   R>		( -- w )
;		Pop the return stack to the data stack.

		$CODE	2,'R>',RFROM
		ldl	rp			; get current rp
		ldnl	0			; get current (rp)
		ldl	rp			; adjust rp up one cell
		adc	4			;
		stl	rp			;
		pushx				; return data in tos
		$NEXT

;   R@		( -- w )
;		Copy top of return stack to the data stack.

		$CODE	2,'R@',RAT
		ldl	rp			; get rp
		ldnl	0			; get (rp)
		pushx				; to tos
		$NEXT

;   >R		( w -- )
;		Push the data stack to the return stack.

		$CODE	COMPO+2,'>R',TOR
		ldl	rp			; current rp
		celldn				; bump down 1 cell
		stl	rp			;
		popx				; get data
		ldl	rp			; get new rp
		stnl	0			; put on rp
		$NEXT

;   SP@ 	( -- a )
;		Push the current data stack pointer.

		$CODE	3,'SP@',SPAT
		ldl	spx			; get current sp
		pushx				; to tos
		$NEXT

;   SP! 	( a -- )
;		Set the data stack pointer.

		$CODE	3,'SP!',SPSTO
		popx				; get value
		stl	spx			; set in sp
		$NEXT

;   DROP	( w -- )
;		Discard top stack item.

		$CODE	4,'DROP',DROP
		ldl	spx			; get sp
		adc	4			; bump by 1 cell
		stl	spx			; and set it
		$NEXT

;   DUP 	( w -- w w )
;		Duplicate the top stack item.

		$CODE	3,'DUP',DUPP
		ldl	spx			; get sp
		ldnl	0			; get tos
		pushx				; push another copy
		$NEXT

;   SWAP	( w1 w2 -- w2 w1 )
;		Exchange top two stack items.

		$CODE	4,'SWAP',SWAP
		ldl	spx			;
		ldnl	0			; get tos
		ldl	spx			;
		ldnl	1			; get nos
		ldl	spx			;
		stnl	0			; nos -> tos
		ldl	spx			;
		stnl	1			; tos -> nos
		$NEXT

;   OVER	( w1 w2 -- w1 w2 w1 )
;		Copy second stack item to top.

		$CODE	4,'OVER',OVER
		ldl	spx			; point to stack
		ldnl	1			; get nos
		pushx				; push another copy
		$NEXT

;   0<		( n -- t )
;		Return true if n is negative.

		$CODE	2,'0<',ZLESS
		ldl	spx			; access the stack
		ldnl	0			; get value
		mint				; $8000.0000
		and				; sign bit
		eqc	0			; true if 0 or +
		not				; flip it
		ldl	spx			;
		stnl	0			;
		$NEXT

;   AND 	( w w -- w )
;		Bitwise AND.

		$CODE	3,'AND',ANDD
		popx				; get 1 parm
		ldl	spx			;
		ldnl	0			; get 2nd parm
		and				; do bitwise and
		ldl	spx			;
		stnl	0			; result to tos
		$NEXT

;   OR		( w w -- w )
;		Bitwise inclusive OR.

		$CODE	2,'OR',ORR
		popx				; get 1 parm
		ldl	spx			;
		ldnl	0			; get 2nd parm
		or				; do bitwise or
		ldl	spx			;
		stnl	0			; result to tos
		$NEXT

;   XOR 	( w w -- w )
;		Bitwise exclusive OR.

		$CODE	3,'XOR',XORR
		popx				; get 1 parm
		ldl	spx			;
		ldnl	0			; get 2nd parm
		xor				; do bitwise xor
		ldl	spx			;
		stnl	0			; result to tos
		$NEXT

;   UM+ 	( w w -- w cy )
;		Add two numbers, return the sum and carry flag.

		$CODE	3,'UM+',UPLUS
		ldc	0			; no carry in
		ldl	spx
		ldnl	0			; get one operand from tos
		ldl	spx
		ldnl	1			; get second operand from nos
		db	023h,0f7h		; do a long sum
		ldl	spx
		stnl	1			; store sum at nos
		ldl	spx
		stnl	0			; store cy at tos
		$NEXT

;; System and user variables

;   doVAR	( -- a )
;		Run time routine for VARIABLE and CREATE.

		$COLON	COMPO+5,'doVAR',DOVAR
		DD	RFROM,EXIT

;   UP		( -- a )
;		Pointer to the user area.

		$COLON	2,'UP',UP
		DD	DOVAR
		DD	UPP

;   doUSER	( -- a )
;		Run time routine for user variables.

		$COLON	COMPO+6,'doUSER',DOUSE
		DD	RFROM,AT,UP,AT,PLUS,EXIT

;   SP0 	( -- a )
;		Pointer to bottom of the data stack.

		$USER	3,'SP0',SZERO

;   RP0 	( -- a )
;		Pointer to bottom of the return stack.

		$USER	3,'RP0',RZERO

;   '?KEY       ( -- a )
;		Execution vector of ?KEY.

		$USER	5,"'?KEY",TQKEY

;   'EMIT       ( -- a )
;		Execution vector of EMIT.

		$USER	5,"'EMIT",TEMIT

;   'EXPECT     ( -- a )
;		Execution vector of EXPECT.

		$USER	7,"'EXPECT",TEXPE

;   'TAP        ( -- a )
;		Execution vector of TAP.

		$USER	4,"'TAP",TTAP

;   'ECHO       ( -- a )
;		Execution vector of ECHO.

		$USER	5,"'ECHO",TECHO

;   'PROMPT     ( -- a )
;		Execution vector of PROMPT.

		$USER	7,"'PROMPT",TPROM

;   BASE	( -- a )
;		Storage of the radix base for numeric I/O.

		$USER	4,'BASE',BASE

;   tmp 	( -- a )
;		A temporary storage location used in parse and find.

		$USER	COMPO+3,'tmp',TEMP

;   SPAN	( -- a )
;		Hold character count received by EXPECT.

		$USER	4,'SPAN',SPAN

;   >IN 	( -- a )
;		Hold the character pointer while parsing input stream.

		$USER	3,'>IN',INN

;   #TIB	( -- a )
;		Hold the current count and address of the terminal input buffer.

		$USER	4,'#TIB',NTIB
		_USER = _USER+CELLL

;   CSP 	( -- a )
;		Hold the stack pointer for error checking.

		$USER	3,'CSP',CSP

;   'EVAL       ( -- a )
;		Execution vector of EVAL.

		$USER	5,"'EVAL",TEVAL

;   'NUMBER     ( -- a )
;		Execution vector of NUMBER?.

		$USER	7,"'NUMBER",TNUMB

;   HLD 	( -- a )
;		Hold a pointer in building a numeric output string.

		$USER	3,'HLD',HLD

;   HANDLER	( -- a )
;		Hold the return stack pointer for error handling.

		$USER	7,'HANDLER',HANDL

;   CONTEXT	( -- a )
;		A area to specify vocabulary search order.

		$USER	7,'CONTEXT',CNTXT
		_USER = _USER+VOCSS*CELLL	;vocabulary stack

;   CURRENT	( -- a )
;		Point to the vocabulary to be extended.

		$USER	7,'CURRENT',CRRNT
		_USER = _USER+CELLL		;vocabulary link pointer

;   CP		( -- a )
;		Point to the top of the code dictionary.

		$USER	2,'CP',CP

;   NP		( -- a )
;		Point to the bottom of the name dictionary.

		$USER	2,'NP',NP

;   LAST	( -- a )
;		Point to the last name in the name dictionary.

		$USER	4,'LAST',LAST

;; Common functions

;   doVOC	( -- )
;		Run time action of VOCABULARY's.

		$COLON	COMPO+5,'doVOC',DOVOC
		DD	RFROM,CNTXT,STORE,EXIT

;   FORTH	( -- )
;		Make FORTH the context vocabulary.

		$COLON	5,'FORTH',FORTH
		DD	DOVOC
		DD	0			;vocabulary head pointer
		DD	0			;vocabulary link pointer

;   ?DUP	( w -- w w | 0 )
;		Dup tos if its is not zero.

		$COLON	4,'?DUP',QDUP
		DD	DUPP
		DD	QBRAN,QDUP1
		DD	DUPP
QDUP1:		DD	EXIT

;   ROT 	( w1 w2 w3 -- w2 w3 w1 )
;		Rot 3rd item to top.

		$COLON	3,'ROT',ROT
		DD	TOR,SWAP,RFROM,SWAP,EXIT

;   2DROP	( w w -- )
;		Discard two items on stack.

		$COLON	5,'2DROP',DDROP
		DD	DROP,DROP,EXIT

;   2DUP	( w1 w2 -- w1 w2 w1 w2 )
;		Duplicate top two items.

		$COLON	4,'2DUP',DDUP
		DD	OVER,OVER,EXIT

;   +		( w w -- sum )
;		Add top two items.

		$COLON	1,'+',PLUS
		DD	UPLUS,DROP,EXIT

;   D+		( d d -- d )
;		Double addition, as an example using UM+.
;
;		$COLON	2,'D+',DPLUS
;		DD	TOR,SWAP,TOR,UPLUS
;		DD	RFROM,RFROM,PLUS,PLUS,EXIT

;   NOT 	( w -- w )
;		One's complement of tos.

		$COLON	3,'NOT',INVER
		DD	DOLIT,-1,XORR,EXIT

;   NEGATE	( n -- -n )
;		Two's complement of tos.

		$COLON	6,'NEGATE',NEGAT
		DD	INVER,DOLIT,1,PLUS,EXIT

;   DNEGATE	( d -- -d )
;		Two's complement of top double.

		$COLON	7,'DNEGATE',DNEGA
		DD	INVER,TOR,INVER
		DD	DOLIT,1,UPLUS
		DD	RFROM,PLUS,EXIT

;   -		( n1 n2 -- n1-n2 )
;		Subtraction.

		$COLON	1,'-',SUBB
		DD	NEGAT,PLUS,EXIT

;   ABS 	( n -- n )
;		Return the absolute value of n.

		$COLON	3,'ABS',ABSS
		DD	DUPP,ZLESS
		DD	QBRAN,ABS1
		DD	NEGAT
ABS1:		DD	EXIT

;   =		( w w -- t )
;		Return true if top two are equal.

		$COLON	1,'=',EQUAL
		DD	XORR
		DD	QBRAN,EQU1
		DD	DOLIT,0,EXIT		;false flag
EQU1:		DD	DOLIT,-1,EXIT		;true flag

;   U<		( u u -- t )
;		Unsigned compare of top two items.

		$COLON	2,'U<',ULESS
		DD	DDUP,XORR,ZLESS
		DD	QBRAN,ULES1
		DD	SWAP,DROP,ZLESS,EXIT
ULES1:		DD	SUBB,ZLESS,EXIT

;   <		( n1 n2 -- t )
;		Signed compare of top two items.

		$COLON	1,'<',LESS
		DD	DDUP,XORR,ZLESS
		DD	QBRAN,LESS1
		DD	DROP,ZLESS,EXIT
LESS1:		DD	SUBB,ZLESS,EXIT

;   MAX 	( n n -- n )
;		Return the greater of two top stack items.

		$COLON	3,'MAX',MAX
		DD	DDUP,LESS
		DD	QBRAN,MAX1
		DD	SWAP
MAX1:		DD	DROP,EXIT

;   MIN 	( n n -- n )
;		Return the smaller of top two stack items.

		$COLON	3,'MIN',MIN
		DD	DDUP,SWAP,LESS
		DD	QBRAN,MIN1
		DD	SWAP
MIN1:		DD	DROP,EXIT

;   WITHIN	( u ul uh -- t )
;		Return true if u is within the range of ul and uh.

		$COLON	6,'WITHIN',WITHI
		DD	OVER,SUBB,TOR			;ul <= u < uh
		DD	SUBB,RFROM,ULESS,EXIT

;; Divide

;   UM/MOD	( udl udh u -- ur uq )
;		Unsigned divide of a double by a single. Return mod and quotient.

		$COLON	6,'UM/MOD',UMMOD
		DD	DDUP,ULESS
		DD	QBRAN,UMM4
		DD	NEGAT,DOLIT,15,TOR
UMM1:		DD	TOR,DUPP,UPLUS
		DD	TOR,TOR,DUPP,UPLUS
		DD	RFROM,PLUS,DUPP
		DD	RFROM,RAT,SWAP,TOR
		DD	UPLUS,RFROM,ORR
		DD	QBRAN,UMM2
		DD	TOR,DROP,DOLIT,1,PLUS,RFROM
		DD	BRAN,UMM3
UMM2:		DD	DROP
UMM3:		DD	RFROM
		DD	DONXT,UMM1
		DD	DROP,SWAP,EXIT
UMM4:		DD	DROP,DDROP
		DD	DOLIT,-1,DUPP,EXIT	;overflow, return max

;   M/MOD	( d n -- r q )
;		Signed floored divide of double by single. Return mod and quotient.

		$COLON	5,'M/MOD',MSMOD
		DD	DUPP,ZLESS,DUPP,TOR
		DD	QBRAN,MMOD1
		DD	NEGAT,TOR,DNEGA,RFROM
MMOD1:		DD	TOR,DUPP,ZLESS
		DD	QBRAN,MMOD2
		DD	RAT,PLUS
MMOD2:		DD	RFROM,UMMOD,RFROM
		DD	QBRAN,MMOD3
		DD	SWAP,NEGAT,SWAP
MMOD3:		DD	EXIT

;   /MOD	( n n -- r q )
;		Signed divide. Return mod and quotient.

		$COLON	4,'/MOD',SLMOD
		DD	OVER,ZLESS,SWAP,MSMOD,EXIT

;   MOD 	( n n -- r )
;		Signed divide. Return mod only.

		$COLON	3,'MOD',MODD
		DD	SLMOD,DROP,EXIT

;   /		( n n -- q )
;		Signed divide. Return quotient only.

		$COLON	1,'/',SLASH
		DD	SLMOD,SWAP,DROP,EXIT

;; Multiply

;   UM* 	( u u -- ud )
;		Unsigned multiply. Return double product.

		$COLON	3,'UM*',UMSTA
		DD	DOLIT,0,SWAP,DOLIT,15,TOR
UMST1:		DD	DUPP,UPLUS,TOR,TOR
		DD	DUPP,UPLUS,RFROM,PLUS,RFROM
		DD	QBRAN,UMST2
		DD	TOR,OVER,UPLUS,RFROM,PLUS
UMST2:		DD	DONXT,UMST1
		DD	ROT,DROP,EXIT

;   *		( n n -- n )
;		Signed multiply. Return single product.

		$COLON	1,'*',STAR
		DD	UMSTA,DROP,EXIT

;   M*		( n n -- d )
;		Signed multiply. Return double product.

		$COLON	2,'M*',MSTAR
		DD	DDUP,XORR,ZLESS,TOR
		DD	ABSS,SWAP,ABSS,UMSTA
		DD	RFROM
		DD	QBRAN,MSTA1
		DD	DNEGA
MSTA1:		DD	EXIT

;   */MOD	( n1 n2 n3 -- r q )
;		Multiply n1 and n2, then divide by n3. Return mod and quotient.

		$COLON	5,'*/MOD',SSMOD
		DD	TOR,MSTAR,RFROM,MSMOD,EXIT

;   */		( n1 n2 n3 -- q )
;		Multiply n1 by n2, then divide by n3. Return quotient only.

		$COLON	2,'*/',STASL
		DD	SSMOD,SWAP,DROP,EXIT

;; Miscellaneous

;   CELL+	( a -- a )
;		Add cell size in byte to address.

		$COLON	5,'CELL+',CELLP
		DD	DOLIT,CELLL,PLUS,EXIT

;   CELL-	( a -- a )
;		Subtract cell size in byte from address.

		$COLON	5,'CELL-',CELLM
		DD	DOLIT,0-CELLL,PLUS,EXIT

;   CELLS	( n -- n )
;		Multiply tos by cell size in bytes.

		$COLON	5,'CELLS',CELLS
		DD	DOLIT,CELLL,STAR,EXIT

;   ALIGNED	( b -- a )
;		Align address to the cell boundary.

		$COLON	7,'ALIGNED',ALGND
		DD	DUPP,DOLIT,0,DOLIT,CELLL
		DD	UMMOD,DROP,DUPP
		DD	QBRAN,ALGN1
		DD	DOLIT,CELLL,SWAP,SUBB
ALGN1:		DD	PLUS,EXIT

;   BL		( -- 32 )
;		Return 32, the blank character.

		$COLON	2,'BL',BLANK
		DD	DOLIT,' ',EXIT

;   >CHAR	( c -- c )
;		Filter non-printing characters.

		$COLON	5,'>CHAR',TCHAR
		DD	DOLIT,07FH,ANDD,DUPP	;mask msb
		DD	DOLIT,127,BLANK,WITHI	;check for printable
		DD	QBRAN,TCHA1
		DD	DROP,DOLIT,'_'          ;replace non-printables
TCHA1:		DD	EXIT

;   DEPTH	( -- n )
;		Return the depth of the data stack.

		$COLON	5,'DEPTH',DEPTH
		DD	SPAT,SZERO,AT,SWAP,SUBB
		DD	DOLIT,CELLL,SLASH,EXIT

;   PICK	( ... +n -- ... w )
;		Copy the nth stack item to tos.

		$COLON	4,'PICK',PICK
		DD	DOLIT,1,PLUS,CELLS
		DD	SPAT,PLUS,AT,EXIT

;; Memory access

;   +!		( n a -- )
;		Add n to the contents at address a.

		$COLON	2,'+!',PSTOR
		DD	SWAP,OVER,AT,PLUS
		DD	SWAP,STORE,EXIT

;   2!		( d a -- )
;		Store the double integer to address a.

		$COLON	2,'2!',DSTOR
		DD	SWAP,OVER,STORE
		DD	CELLP,STORE,EXIT

;   2@		( a -- d )
;		Fetch double integer from address a.

		$COLON	2,'2@',DAT
		DD	DUPP,CELLP,AT
		DD	SWAP,AT,EXIT

;   COUNT	( b -- b +n )
;		Return count byte of a string and add 1 to byte address.

		$COLON	5,'COUNT',COUNT
		DD	DUPP,DOLIT,1,PLUS
		DD	SWAP,CAT,EXIT

;   HERE	( -- a )
;		Return the top of the code dictionary.

		$COLON	4,'HERE',HERE
		DD	CP,AT,EXIT

;   PAD 	( -- a )
;		Return the address of a temporary buffer.

		$COLON	3,'PAD',PAD
		DD	HERE,DOLIT,80,PLUS,EXIT

;   TIB 	( -- a )
;		Return the address of the terminal input buffer.

		$COLON	3,'TIB',TIB
		DD	NTIB,CELLP,AT,EXIT

;   @EXECUTE	( a -- )
;		Execute vector stored in address a.

		$COLON	8,'@EXECUTE',ATEXE
		DD	AT,QDUP 		;?address or zero
		DD	QBRAN,EXE1
		DD	EXECU			;execute if non-zero
EXE1:		DD	EXIT			;do nothing if zero

;   CMOVE	( b1 b2 u -- )
;		Copy u bytes from b1 to b2.

		$COLON	5,'CMOVE',CMOVE
		DD	TOR
		DD	BRAN,CMOV2
CMOV1:		DD	TOR,DUPP,CAT
		DD	RAT,CSTOR
		DD	DOLIT,1,PLUS
		DD	RFROM,DOLIT,1,PLUS
CMOV2:		DD	DONXT,CMOV1
		DD	DDROP,EXIT

;   FILL	( b u c -- )
;		Fill u bytes of character c to area beginning at b.

		$COLON	4,'FILL',FILL
		DD	SWAP,TOR,SWAP
		DD	BRAN,FILL2
FILL1:		DD	DDUP,CSTOR,DOLIT,1,PLUS
FILL2:		DD	DONXT,FILL1
		DD	DDROP,EXIT

;   -TRAILING	( b u -- b u )
;		Adjust the count to eliminate trailing white space.

		$COLON	9,'-TRAILING',DTRAI
		DD	TOR
		DD	BRAN,DTRA2
DTRA1:		DD	BLANK,OVER,RAT,PLUS,CAT,LESS
		DD	QBRAN,DTRA2
		DD	RFROM,DOLIT,1,PLUS,EXIT ;adjusted count
DTRA2:		DD	DONXT,DTRA1
		DD	DOLIT,0,EXIT		;count=0

;   PACK$	( b u a -- a )
;		Build a counted string with u characters from b. Null fill.

		$COLON	5,'PACK$',PACKS
		DD	ALGND,DUPP,TOR		;strings only on cell boundary
		DD	OVER,DUPP,DOLIT,0
		DD	DOLIT,CELLL,UMMOD,DROP	;count mod cell
		DD	SUBB,OVER,PLUS
		DD	DOLIT,0,SWAP,STORE	;null fill cell
		DD	DDUP,CSTOR,DOLIT,1,PLUS ;save count
		DD	SWAP,CMOVE,RFROM,EXIT	;move string

;; Numeric output, single precision

;   DIGIT	( u -- c )
;		Convert digit u to a character.

		$COLON	5,'DIGIT',DIGIT
		DD	DOLIT,9,OVER,LESS
		DD	DOLIT,7,ANDD,PLUS
		DD	DOLIT,'0',PLUS,EXIT

;   EXTRACT	( n base -- n c )
;		Extract the least significant digit from n.

		$COLON	7,'EXTRACT',EXTRC
		DD	DOLIT,0,SWAP,UMMOD
		DD	SWAP,DIGIT,EXIT

;   <#		( -- )
;		Initiate the numeric output process.

		$COLON	2,'<#',BDIGS
		DD	PAD,HLD,STORE,EXIT

;   HOLD	( c -- )
;		Insert a character into the numeric output string.

		$COLON	4,'HOLD',HOLD
		DD	HLD,AT,DOLIT,1,SUBB
		DD	DUPP,HLD,STORE,CSTOR,EXIT

;   #		( u -- u )
;		Extract one digit from u and append the digit to output string.

		$COLON	1,'#',DIG
		DD	BASE,AT,EXTRC,HOLD,EXIT

;   #S		( u -- 0 )
;		Convert u until all digits are added to the output string.

		$COLON	2,'#S',DIGS
DIGS1:		DD	DIG,DUPP
		DD	QBRAN,DIGS2
		DD	BRAN,DIGS1
DIGS2:		DD	EXIT

;   SIGN	( n -- )
;		Add a minus sign to the numeric output string.

		$COLON	4,'SIGN',SIGN
		DD	ZLESS
		DD	QBRAN,SIGN1
		DD	DOLIT,'-',HOLD
SIGN1:		DD	EXIT

;   #>		( w -- b u )
;		Prepare the output string to be TYPE'd.

		$COLON	2,'#>',EDIGS
		DD	DROP,HLD,AT
		DD	PAD,OVER,SUBB,EXIT

;   strn	( n -- b u )
;		Convert a signed integer to a numeric string.

		$COLON	4,'strn',STRN
		DD	DUPP,TOR,ABSS
		DD	BDIGS,DIGS,RFROM
		DD	SIGN,EDIGS,EXIT

;   HEX 	( -- )
;		Use radix 16 as base for numeric conversions.

		$COLON	3,'HEX',HEX
		DD	DOLIT,16,BASE,STORE,EXIT

;   DECIMAL	( -- )
;		Use radix 10 as base for numeric conversions.

		$COLON	7,'DECIMAL',DECIM
		DD	DOLIT,10,BASE,STORE,EXIT

;; Numeric input, single precision

;   DIGIT?	( c base -- u t )
;		Convert a character to its numeric value. A flag indicates success.

		$COLON	6,'DIGIT?',DIGTQ
		DD	TOR,DOLIT,'0',SUBB
		DD	DOLIT,9,OVER,LESS
		DD	QBRAN,DGTQ1
		DD	DOLIT,7,SUBB
		DD	DUPP,DOLIT,10,LESS,ORR
DGTQ1:		DD	DUPP,RFROM,ULESS,EXIT

;   NUMBER?	( a -- n T | a F )
;		Convert a number string to integer. Push a flag on tos.

		$COLON	7,'NUMBER?',NUMBQ
		DD	BASE,AT,TOR,DOLIT,0,OVER,COUNT
		DD	OVER,CAT,DOLIT,'$',EQUAL
		DD	QBRAN,NUMQ1
		DD	HEX,SWAP,DOLIT,1,PLUS
		DD	SWAP,DOLIT,1,SUBB
NUMQ1:		DD	OVER,CAT,DOLIT,'-',EQUAL,TOR
		DD	SWAP,RAT,SUBB,SWAP,RAT,PLUS,QDUP
		DD	QBRAN,NUMQ6
		DD	DOLIT,1,SUBB,TOR
NUMQ2:		DD	DUPP,TOR,CAT,BASE,AT,DIGTQ
		DD	QBRAN,NUMQ4
		DD	SWAP,BASE,AT,STAR,PLUS,RFROM
		DD	DOLIT,1,PLUS
		DD	DONXT,NUMQ2
		DD	RAT,SWAP,DROP
		DD	QBRAN,NUMQ3
		DD	NEGAT
NUMQ3:		DD	SWAP
		DD	BRAN,NUMQ5
NUMQ4:		DD	RFROM,RFROM,DDROP,DDROP,DOLIT,0
NUMQ5:		DD	DUPP
NUMQ6:		DD	RFROM,DDROP
		DD	RFROM,BASE,STORE,EXIT

;; Basic I/O

;   ?KEY	( -- c T | F )
;		Return input character and true, or a false if no input.

		$COLON	4,'?KEY',QKEY
		DD	TQKEY,ATEXE,EXIT

;   KEY 	( -- c )
;		Wait for and return an input character.

		$COLON	3,'KEY',KEY
KEY1:		DD	QKEY
		DD	QBRAN,KEY1
		DD	EXIT

;   EMIT	( c -- )
;		Send a character to the output device.

		$COLON	4,'EMIT',EMIT
		DD	TEMIT,ATEXE,EXIT

;   NUF?	( -- t )
;		Return false if no input, else pause and if CR return true.

		$COLON	4,'NUF?',NUFQ
		DD	QKEY,DUPP
		DD	QBRAN,NUFQ1
		DD	DDROP,KEY,DOLIT,CRR,EQUAL
NUFQ1:		DD	EXIT

;   PACE	( -- )
;		Send a pace character for the file downloading process.

		$COLON	4,'PACE',PACE
		DD	DOLIT,11,EMIT,EXIT

;   SPACE	( -- )
;		Send the blank character to the output device.

		$COLON	5,'SPACE',SPACE
		DD	BLANK,EMIT,EXIT

;   SPACES	( +n -- )
;		Send n spaces to the output device.

		$COLON	6,'SPACES',SPACS
		DD	DOLIT,0,MAX,TOR
		DD	BRAN,CHAR2
CHAR1:		DD	SPACE
CHAR2:		DD	DONXT,CHAR1
		DD	EXIT

;   TYPE	( b u -- )
;		Output u characters from b.

		$COLON	4,'TYPE',TYPEE
		DD	TOR
		DD	BRAN,TYPE2
TYPE1:		DD	DUPP,CAT,EMIT
		DD	DOLIT,1,PLUS
TYPE2:		DD	DONXT,TYPE1
		DD	DROP,EXIT

;   CR		( -- )
;		Output a carriage return and a line feed.

		$COLON	2,'CR',CR
		DD	DOLIT,CRR,EMIT
		DD	DOLIT,LF,EMIT,EXIT

;   do$ 	( -- a )
;		Return the address of a compiled string.

		$COLON	COMPO+3,'do$',DOSTR
		DD	RFROM,RAT,RFROM,COUNT,PLUS
		DD	ALGND,TOR,SWAP,TOR,EXIT

;   $"|         ( -- a )
;		Run time routine compiled by $". Return address of a compiled string.

		$COLON	COMPO+3,'$"|',STRQP
		DD	DOSTR,EXIT		;force a call to do$

;   ."|         ( -- )
;		Run time routine of ." . Output a compiled string.

		$COLON	COMPO+3,'."|',DOTQP
		DD	DOSTR,COUNT,TYPEE,EXIT

;   .R		( n +n -- )
;		Display an integer in a field of n columns, right justified.

		$COLON	2,'.R',DOTR
		DD	TOR,STRN,RFROM,OVER,SUBB
		DD	SPACS,TYPEE,EXIT

;   U.R 	( u +n -- )
;		Display an unsigned integer in n column, right justified.

		$COLON	3,'U.R',UDOTR
		DD	TOR,BDIGS,DIGS,EDIGS
		DD	RFROM,OVER,SUBB
		DD	SPACS,TYPEE,EXIT

;   U.		( u -- )
;		Display an unsigned integer in free format.

		$COLON	2,'U.',UDOT
		DD	BDIGS,DIGS,EDIGS
		DD	SPACE,TYPEE,EXIT

;   .		( w -- )
;		Display an integer in free format, preceeded by a space.

		$COLON	1,'.',DOT
		DD	BASE,AT,DOLIT,10,XORR	;?decimal
		DD	QBRAN,DOT1
		DD	UDOT,EXIT		;no, display unsigned
DOT1:		DD	STRN,SPACE,TYPEE,EXIT	 ;yes, display signed

;   ?		( a -- )
;		Display the contents in a memory cell.

		$COLON	1,'?',QUEST
		DD	AT,DOT,EXIT

;; Parsing

;   parse	( b u c -- b u delta ; <string> )
;		Scan string delimited by c. Return found string and its offset.

		$COLON	5,'parse',PARS
		DD	TEMP,STORE,OVER,TOR,DUPP
		DD	QBRAN,PARS8
		DD	DOLIT,1,SUBB,TEMP,AT,BLANK,EQUAL
		DD	QBRAN,PARS3
		DD	TOR
PARS1:		DD	BLANK,OVER,CAT		;skip leading blanks ONLY
		DD	SUBB,ZLESS,INVER
		DD	QBRAN,PARS2
		DD	DOLIT,1,PLUS
		DD	DONXT,PARS1
		DD	RFROM,DROP,DOLIT,0,DUPP,EXIT
PARS2:		DD	RFROM
PARS3:		DD	OVER,SWAP
		DD	TOR
PARS4:		DD	TEMP,AT,OVER,CAT,SUBB	;scan for delimiter
		DD	TEMP,AT,BLANK,EQUAL
		DD	QBRAN,PARS5
		DD	ZLESS
PARS5:		DD	QBRAN,PARS6
		DD	DOLIT,1,PLUS
		DD	DONXT,PARS4
		DD	DUPP,TOR
		DD	BRAN,PARS7
PARS6:		DD	RFROM,DROP,DUPP
		DD	DOLIT,1,PLUS,TOR
PARS7:		DD	OVER,SUBB
		DD	RFROM,RFROM,SUBB,EXIT
PARS8:		DD	OVER,RFROM,SUBB,EXIT

;   PARSE	( c -- b u ; <string> )
;		Scan input stream and return counted string delimited by c.

		$COLON	5,'PARSE',PARSE
		DD	TOR,TIB,INN,AT,PLUS	;current input buffer pointer
		DD	NTIB,AT,INN,AT,SUBB	;remaining count
		DD	RFROM,PARS,INN,PSTOR,EXIT

;   .(		( -- )
;		Output following string up to next ) .

		$COLON	IMEDD+2,'.(',DOTPR
		DD	DOLIT,')',PARSE,TYPEE,EXIT

;   (		( -- )
;		Ignore following string up to next ) . A comment.

		$COLON	IMEDD+1,'(',PAREN
		DD	DOLIT,')',PARSE,DDROP,EXIT

;   \		( -- )
;		Ignore following text till the end of line.

		$COLON	IMEDD+1,'\',BKSLA
		DD	NTIB,AT,INN,STORE,EXIT

;   CHAR	( -- c )
;		Parse next word and return its first character.

		$COLON	4,'CHAR',CHAR
		DD	BLANK,PARSE,DROP,CAT,EXIT

;   TOKEN	( -- a ; <string> )
;		Parse a word from input stream and copy it to name dictionary.

		$COLON	5,'TOKEN',TOKEN
		DD	BLANK,PARSE,DOLIT,31,MIN
		DD	NP,AT,OVER,SUBB,CELLM
		DD	PACKS,EXIT

;   WORD	( c -- a ; <string> )
;		Parse a word from input stream and copy it to code dictionary.

		$COLON	4,'WORD',WORDD
		DD	PARSE,HERE,PACKS,EXIT

;; Dictionary search

;   NAME>	( na -- ca )
;		Return a code address given a name address.

		$COLON	5,'NAME>',NAMET
		DD	CELLM,CELLM,AT,EXIT

;   SAME?	( a a u -- a a f \ -0+ )
;		Compare u cells in two strings. Return 0 if identical.

		$COLON	5,'SAME?',SAMEQ
		DD	TOR
		DD	BRAN,SAME2
SAME1:		DD	OVER,RAT,CELLS,PLUS,AT
		DD	OVER,RAT,CELLS,PLUS,AT
		DD	SUBB,QDUP
		DD	QBRAN,SAME2
		DD	RFROM,DROP,EXIT 	;strings not equal
SAME2:		DD	DONXT,SAME1
		DD	DOLIT,0,EXIT		;strings equal

;   find	( a va -- ca na | a F )
;		Search a vocabulary for a string. Return ca and na if succeeded.

		$COLON	4,'find',FIND
		DD	SWAP,DUPP,CAT
		DD	DOLIT,CELLL,SLASH,TEMP,STORE
		DD	DUPP,AT,TOR,CELLP,SWAP
FIND1:		DD	AT,DUPP
		DD	QBRAN,FIND6
		DD	DUPP,AT,DOLIT,MASKK,ANDD,RAT,XORR
		DD	QBRAN,FIND2
		DD	CELLP,DOLIT,-1		;true flag
		DD	BRAN,FIND3
FIND2:		DD	CELLP,TEMP,AT,SAMEQ
FIND3:		DD	BRAN,FIND4
FIND6:		DD	RFROM,DROP
		DD	SWAP,CELLM,SWAP,EXIT
FIND4:		DD	QBRAN,FIND5
		DD	CELLM,CELLM
		DD	BRAN,FIND1
FIND5:		DD	RFROM,DROP,SWAP,DROP
		DD	CELLM
		DD	DUPP,NAMET,SWAP,EXIT

;   NAME?	( a -- ca na | a F )
;		Search all context vocabularies for a string.

		$COLON	5,'NAME?',NAMEQ
		DD	CNTXT,DUPP,DAT,XORR	;?context=also
		DD	QBRAN,NAMQ1
		DD	CELLM			;no, start with context
NAMQ1:		DD	TOR
NAMQ2:		DD	RFROM,CELLP,DUPP,TOR	;next in search order
		DD	AT,QDUP
		DD	QBRAN,NAMQ3
		DD	FIND,QDUP		;search vocabulary
		DD	QBRAN,NAMQ2
		DD	RFROM,DROP,EXIT 	;found name
NAMQ3:		DD	RFROM,DROP		;name not found
		DD	DOLIT,0,EXIT		;false flag

;; Terminal response

;   ^H		( bot eot cur -- bot eot cur )
;		Backup the cursor by one character.

		$COLON	2,'^H',BKSP
		DD	TOR,OVER,RFROM,SWAP,OVER,XORR
		DD	QBRAN,BACK1
		DD	DOLIT,BKSPP,TECHO,ATEXE,DOLIT,1,SUBB
		DD	BLANK,TECHO,ATEXE
		DD	DOLIT,BKSPP,TECHO,ATEXE
BACK1:		DD	EXIT

;   TAP 	( bot eot cur c -- bot eot cur )
;		Accept and echo the key stroke and bump the cursor.

		$COLON	3,'TAP',TAP
		DD	DUPP,TECHO,ATEXE
		DD	OVER,CSTOR,DOLIT,1,PLUS,EXIT

;   kTAP	( bot eot cur c -- bot eot cur )
;		Process a key stroke, CR or backspace.

		$COLON	4,'kTAP',KTAP
		DD	DUPP,DOLIT,CRR,XORR
		DD	QBRAN,KTAP2
		DD	DOLIT,BKSPP,XORR
		DD	QBRAN,KTAP1
		DD	BLANK,TAP,EXIT
KTAP1:		DD	BKSP,EXIT
KTAP2:		DD	DROP,SWAP,DROP,DUPP,EXIT

;   accept	( b u -- b u )
;		Accept characters to input buffer. Return with actual count.

		$COLON	6,'accept',ACCEP
		DD	OVER,PLUS,OVER
ACCP1:		DD	DDUP,XORR
		DD	QBRAN,ACCP4
		DD	KEY,DUPP
;		DD	BLANK,SUBB,DOLIT,95,ULESS
		DD	BLANK,DOLIT,127,WITHI
		DD	QBRAN,ACCP2
		DD	TAP
		DD	BRAN,ACCP3
ACCP2:		DD	TTAP,ATEXE
ACCP3:		DD	BRAN,ACCP1
ACCP4:		DD	DROP,OVER,SUBB,EXIT

;   EXPECT	( b u -- )
;		Accept input stream and store count in SPAN.

		$COLON	6,'EXPECT',EXPEC
		DD	TEXPE,ATEXE,SPAN,STORE,DROP,EXIT

;   QUERY	( -- )
;		Accept input stream to terminal input buffer.

		$COLON	5,'QUERY',QUERY
		DD	TIB,DOLIT,80,TEXPE,ATEXE,NTIB,STORE
		DD	DROP,DOLIT,0,INN,STORE,EXIT

;; Error handling

;   CATCH	( ca -- 0 | err# )
;		Execute word at ca and set up an error frame for it.

		$COLON	5,'CATCH',CATCH
		DD	SPAT,TOR,HANDL,AT,TOR	;save error frame
		DD	RPAT,HANDL,STORE,EXECU	;execute
		DD	RFROM,HANDL,STORE	;restore error frame
		DD	RFROM,DROP,DOLIT,0,EXIT ;no error

;   THROW	( err# -- err# )
;		Reset system to current local error frame an update error flag.

		$COLON	5,'THROW',THROW
		DD	HANDL,AT,RPSTO		;restore return stack
		DD	RFROM,HANDL,STORE	;restore handler frame
		DD	RFROM,SWAP,TOR,SPSTO	;restore data stack
		DD	DROP,RFROM,EXIT

;   NULL$	( -- a )
;		Return address of a null string with zero count.

		$COLON	5,'NULL$',NULLS
		DD	DOVAR			;emulate CREATE
		DD	0
		DB	99,111,121,111,116,101
		ALIGN	4

;   ABORT	( -- )
;		Reset data stack and jump to QUIT.

		$COLON	5,'ABORT',ABORT
		DD	NULLS,THROW

;   abort"      ( f -- )
;		Run time routine of ABORT" . Abort with a message.

		$COLON	COMPO+6,'abort"',ABORQ
		DD	QBRAN,ABOR1		;text flag
		DD	DOSTR,THROW		;pass error string
ABOR1:		DD	DOSTR,DROP,EXIT 	;drop error

;; The text interpreter

;   $INTERPRET	( a -- )
;		Interpret a word. If failed, try to convert it to an integer.

		$COLON	10,'$INTERPRET',INTER
		DD	NAMEQ,QDUP		;?defined
		DD	QBRAN,INTE1
		DD	AT,DOLIT,COMPO,ANDD	;?compile only lexicon bits
		D$	ABORQ,' compile only'
		DD	EXECU,EXIT		;execute defined word
INTE1:		DD	TNUMB,ATEXE		;convert a number
		DD	QBRAN,INTE2
		DD	EXIT
INTE2:		DD	THROW			;error

;   [		( -- )
;		Start the text interpreter.

		$COLON	IMEDD+1,'[',LBRAC
		DD	DOLIT,INTER,TEVAL,STORE,EXIT

;   .OK 	( -- )
;		Display 'ok' only while interpreting.

		$COLON	3,'.OK',DOTOK
		DD	DOLIT,INTER,TEVAL,AT,EQUAL
		DD	QBRAN,DOTO1
		D$	DOTQP,' ok'
DOTO1:		DD	CR,EXIT

;   ?STACK	( -- )
;		Abort if the data stack underflows.

		$COLON	6,'?STACK',QSTAC
		DD	DEPTH,ZLESS		;check only for underflow
		D$	ABORQ,' underflow'
		DD	EXIT

;   EVAL	( -- )
;		Interpret the input stream.

		$COLON	4,'EVAL',EVAL
EVAL1:		DD	TOKEN,DUPP,CAT		;?input stream empty
		DD	QBRAN,EVAL2
		DD	TEVAL,ATEXE,QSTAC	;evaluate input, check stack
		DD	BRAN,EVAL1
EVAL2:		DD	DROP,TPROM,ATEXE,EXIT	;prompt

;; Shell

;   PRESET	( -- )
;		Reset data stack pointer and the terminal input buffer.

		$COLON	6,'PRESET',PRESE
		DD	SZERO,AT,SPSTO
		DD	DOLIT,TIBB,NTIB,CELLP,STORE,EXIT

;   xio 	( a a a -- )
;		Reset the I/O vectors 'EXPECT, 'TAP, 'ECHO and 'PROMPT.

		$COLON	COMPO+3,'xio',XIO
		DD	DOLIT,ACCEP,TEXPE,DSTOR
		DD	TECHO,DSTOR,EXIT

;   FILE	( -- )
;		Select I/O vectors for file download.

		$COLON	4,'FILE',FILE
		DD	DOLIT,PACE,DOLIT,DROP
		DD	DOLIT,KTAP,XIO,EXIT

;   HAND	( -- )
;		Select I/O vectors for terminal interface.

		$COLON	4,'HAND',HAND
		DD	DOLIT,DOTOK,DOLIT,EMIT
		DD	DOLIT,KTAP,XIO,EXIT

;   I/O 	( -- a )
;		Array to store default I/O vectors.

		$COLON	3,'I/O',ISLO
		DD	DOVAR			;emulate CREATE
		DD	QRX,TXSTO		;default I/O vectors

;   CONSOLE	( -- )
;		Initiate terminal interface.

		$COLON	7,'CONSOLE',CONSO
		DD	ISLO,DAT,TQKEY,DSTOR	;restore default I/O device
		DD	HAND,EXIT		;keyboard input

;   QUIT	( -- )
;		Reset return stack pointer and start text interpreter.

		$COLON	4,'QUIT',QUIT
		DD	RZERO,AT,RPSTO		;reset return stack pointer
QUIT1:		DD	LBRAC			;start interpretation
QUIT2:		DD	QUERY			;get input
		DD	DOLIT,EVAL,CATCH,QDUP	;evaluate input
		DD	QBRAN,QUIT2		;continue till error
		DD	TPROM,AT,SWAP		;save input device
		DD	CONSO,NULLS,OVER,XORR	;?display error message
		DD	QBRAN,QUIT3
		DD	SPACE,COUNT,TYPEE	;error message
		D$	DOTQP,' ? '             ;error prompt
QUIT3:		DD	DOLIT,DOTOK,XORR	;?file input
		DD	QBRAN,QUIT4
		DD	DOLIT,ERRESC,EMIT	   ;file error, tell host
QUIT4:		DD	PRESE			;some cleanup
		DD	BRAN,QUIT1

;; The compiler

;   '           ( -- ca )
;		Search context vocabularies for the next word in input stream.

		$COLON	1,"'",TICK
		DD	TOKEN,NAMEQ		;?defined
		DD	QBRAN,TICK1
		DD	EXIT			;yes, push code address
TICK1:		DD	THROW			;no, error

;   ALLOT	( n -- )
;		Allocate n bytes to the code dictionary.

		$COLON	5,'ALLOT',ALLOT
		DD	CP,PSTOR,EXIT		;adjust code pointer

;   ,		( w -- )
;		Compile an integer into the code dictionary.

		$COLON	1,',',COMMA
		DD	HERE,DUPP,CELLP 	;cell boundary
		DD	CP,STORE,STORE,EXIT	;adjust code pointer, compile

;   [COMPILE]	( -- ; <string> )
;		Compile the next immediate word into code dictionary.

		$COLON	IMEDD+9,'[COMPILE]',BCOMP
		DD	TICK,COMMA,EXIT

;   COMPILE	( -- )
;		Compile the next address in colon list to code dictionary.

		$COLON	COMPO+7,'COMPILE',COMPI
		DD	RFROM,DUPP,AT,COMMA	;compile address
		DD	CELLP,TOR,EXIT		;adjust return address

;   LITERAL	( w -- )
;		Compile tos to code dictionary as an integer literal.

		$COLON	IMEDD+7,'LITERAL',LITER
		DD	COMPI,DOLIT,COMMA,EXIT

;   $,"         ( -- )
;		Compile a literal string up to next " .

		$COLON	3,'$,"',STRCQ
		DD	DOLIT,'"',WORDD         ;move string to code dictionary
		DD	COUNT,PLUS,ALGND	;calculate aligned end of string
		DD	CP,STORE,EXIT		;adjust the code pointer

;   RECURSE	( -- )
;		Make the current word available for compilation.

		$COLON	IMEDD+7,'RECURSE',RECUR
		DD	LAST,AT,NAMET,COMMA,EXIT

;; Structures

;   FOR 	( -- a )
;		Start a FOR-NEXT loop structure in a colon definition.

		$COLON	IMEDD+3,'FOR',FOR_
		DD	COMPI,TOR,HERE,EXIT

;   BEGIN	( -- a )
;		Start an infinite or indefinite loop structure.

		$COLON	IMEDD+5,'BEGIN',BEGIN
		DD	HERE,EXIT

;   NEXT	( a -- )
;		Terminate a FOR-NEXT loop structure.

		$COLON	IMEDD+4,'NEXT',NEXT
		DD	COMPI,DONXT,COMMA,EXIT

;   UNTIL	( a -- )
;		Terminate a BEGIN-UNTIL indefinite loop structure.

		$COLON	IMEDD+5,'UNTIL',UNTIL
		DD	COMPI,QBRAN,COMMA,EXIT

;   AGAIN	( a -- )
;		Terminate a BEGIN-AGAIN infinite loop structure.

		$COLON	IMEDD+5,'AGAIN',AGAIN
		DD	COMPI,BRAN,COMMA,EXIT

;   IF		( -- A )
;		Begin a conditional branch structure.

		$COLON	IMEDD+2,'IF',IFF
		DD	COMPI,QBRAN,HERE
		DD	DOLIT,0,COMMA,EXIT

;   AHEAD	( -- A )
;		Compile a forward branch instruction.

		$COLON	IMEDD+5,'AHEAD',AHEAD
		DD	COMPI,BRAN,HERE,DOLIT,0,COMMA,EXIT

;   REPEAT	( A a -- )
;		Terminate a BEGIN-WHILE-REPEAT indefinite loop.

		$COLON	IMEDD+6,'REPEAT',REPEA
		DD	AGAIN,HERE,SWAP,STORE,EXIT

;   THEN	( A -- )
;		Terminate a conditional branch structure.

		$COLON	IMEDD+4,'THEN',THENN
		DD	HERE,SWAP,STORE,EXIT

;   AFT 	( a -- a A )
;		Jump to THEN in a FOR-AFT-THEN-NEXT loop the first time through.

		$COLON	IMEDD+3,'AFT',AFT
		DD	DROP,AHEAD,BEGIN,SWAP,EXIT

;   ELSE	( A -- A )
;		Start the false clause in an IF-ELSE-THEN structure.

		$COLON	IMEDD+4,'ELSE',ELSEE
		DD	AHEAD,SWAP,THENN,EXIT

;   WHILE	( a -- A a )
;		Conditional branch out of a BEGIN-WHILE-REPEAT loop.

		$COLON	IMEDD+5,'WHILE',WHILE_
		DD	IFF,SWAP,EXIT

;   ABORT"      ( -- ; <string> )
;		Conditional abort with an error message.

		$COLON	IMEDD+6,'ABORT"',ABRTQ
		DD	COMPI,ABORQ,STRCQ,EXIT

;   $"          ( -- ; <string> )
;		Compile an inline string literal.

		$COLON	IMEDD+2,'$"',STRQ
		DD	COMPI,STRQP,STRCQ,EXIT

;   ."          ( -- ; <string> )
;		Compile an inline string literal to be typed out at run time.

		$COLON	IMEDD+2,'."',DOTQ
		DD	COMPI,DOTQP,STRCQ,EXIT

;; Name compiler

;   ?UNIQUE	( a -- a )
;		Display a warning message if the word already exists.

		$COLON	7,'?UNIQUE',UNIQU
		DD	DUPP,NAMEQ		;?name exists
		DD	QBRAN,UNIQ1		;redefinitions are OK
		D$	DOTQP,' reDef '         ;but warn the user
		DD	OVER,COUNT,TYPEE	;just in case its not planned
UNIQ1:		DD	DROP,EXIT

;   $,n 	( na -- )
;		Build a new dictionary name using the string at na.

		$COLON	3,'$,n',SNAME
		DD	DUPP,CAT		;?null input
		DD	QBRAN,PNAM1
		DD	UNIQU			;?redefinition
		DD	DUPP,LAST,STORE 	;save na for vocabulary link
		DD	HERE,ALGND,SWAP 	;align code address
		DD	CELLM			;link address
		DD	CRRNT,AT,AT,OVER,STORE
		DD	CELLM,DUPP,NP,STORE	;adjust name pointer
		DD	STORE,EXIT		;save code pointer
PNAM1:		D$	STRQP,' name'           ;null input
		DD	THROW

;; FORTH compiler

;   $COMPILE	( a -- )
;		Compile next word to code dictionary as a token or literal.

		$COLON	8,'$COMPILE',SCOMP
		DD	NAMEQ,QDUP		;?defined
		DD	QBRAN,SCOM2
		DD	AT,DOLIT,IMEDD,ANDD	;?immediate
		DD	QBRAN,SCOM1
		DD	EXECU,EXIT		;its immediate, execute
SCOM1:		DD	COMMA,EXIT		;its not immediate, compile
SCOM2:		DD	TNUMB,ATEXE		;try to convert to number
		DD	QBRAN,SCOM3
		DD	LITER,EXIT		;compile number as integer
SCOM3:		DD	THROW			;error

;   OVERT	( -- )
;		Link a new word into the current vocabulary.

		$COLON	5,'OVERT',OVERT
		DD	LAST,AT,CRRNT,AT,STORE,EXIT

;   ;		( -- )
;		Terminate a colon definition.

		$COLON	IMEDD+COMPO+1,';',SEMIS
		DD	COMPI,EXIT,LBRAC,OVERT,EXIT

;   ]		( -- )
;		Start compiling the words in the input stream.

		$COLON	1,']',RBRAC
		DD	DOLIT,SCOMP,TEVAL,STORE,EXIT

;   call,	( ca -- )
;		Assemble a call instruction to ca.

		$COLON	5,'call,',CALLC
;		 DD	 DOLIT,CALLL,COMMA,HERE  ;Direct Threaded Code
;		 DD	 CELLP,SUBB,COMMA	 ;DTC 8086 relative call
		dd	DOLIT,entry1,COMMA	; transputer abs call
		dd	DOLIT,entry2,COMMA
		dd	DOLIT,entry3,COMMA
		dd	COMMA			; compile in the target addr
		DD	EXIT

;   :		( -- ; <string> )
;		Start a new colon definition using next word as its name.

		$COLON	1,':',COLON
		DD	TOKEN,SNAME,DOLIT,DOLST
		DD	CALLC,RBRAC,EXIT

;   IMMEDIATE	( -- )
;		Make the last compiled word an immediate word.

		$COLON	9,'IMMEDIATE',IMMED
		DD	DOLIT,IMEDD,LAST,AT,AT,ORR
		DD	LAST,AT,STORE,EXIT

;; Defining words

;   USER	( u -- ; <string> )
;		Compile a new user variable.

		$COLON	4,'USER',USER
		DD	TOKEN,SNAME,OVERT
		DD	DOLIT,DOLST,CALLC
		DD	COMPI,DOUSE,COMMA,EXIT

;   CREATE	( -- ; <string> )
;		Compile a new array entry without allocating code space.

		$COLON	6,'CREATE',CREAT
		DD	TOKEN,SNAME,OVERT
		DD	DOLIT,DOLST,CALLC
		DD	COMPI,DOVAR,EXIT

;   VARIABLE	( -- ; <string> )
;		Compile a new variable initialized to 0.

		$COLON	8,'VARIABLE',VARIA
		DD	CREAT,DOLIT,0,COMMA,EXIT

;; Tools

;   _TYPE	( b u -- )
;		Display a string. Filter non-printing characters.

		$COLON	5,'_TYPE',UTYPE
		DD	TOR			;start count down loop
		DD	BRAN,UTYP2		;skip first pass
UTYP1:		DD	DUPP,CAT,TCHAR,EMIT	;display only printable
		DD	DOLIT,1,PLUS		;increment address
UTYP2:		DD	DONXT,UTYP1		;loop till done
		DD	DROP,EXIT

;   dm+ 	( a u -- a )
;		Dump u bytes from , leaving a+u on the stack.

		$COLON	3,'dm+',DMP
		DD	OVER,DOLIT,4,UDOTR	;display address
		DD	SPACE,TOR		;start count down loop
		DD	BRAN,PDUM2		;skip first pass
PDUM1:		DD	DUPP,CAT,DOLIT,3,UDOTR	;display numeric data
		DD	DOLIT,1,PLUS		;increment address
PDUM2:		DD	DONXT,PDUM1		;loop till done
		DD	EXIT

;   DUMP	( a u -- )
;		Dump u bytes from a, in a formatted manner.

		$COLON	4,'DUMP',DUMP
		DD	BASE,AT,TOR,HEX 	;save radix, set hex
		DD	DOLIT,16,SLASH		;change count to lines
		DD	TOR			;start count down loop
DUMP1:		DD	CR,DOLIT,16,DDUP,DMP	;display numeric
		DD	ROT,ROT
		DD	SPACE,SPACE,UTYPE	;display printable characters
		DD	NUFQ,INVER		;user control
		DD	QBRAN,DUMP2
		DD	DONXT,DUMP1		;loop till done
		DD	BRAN,DUMP3
DUMP2:		DD	RFROM,DROP		;cleanup loop stack, early exit
DUMP3:		DD	DROP,RFROM,BASE,STORE	;restore radix
		DD	EXIT

;   .S		( ... -- ... )
;		Display the contents of the data stack.

		$COLON	2,'.S',DOTS
		DD	CR,DEPTH		;stack depth
		DD	TOR			;start count down loop
		DD	BRAN,DOTS2		;skip first pass
DOTS1:		DD	RAT,PICK,DOT		;index stack, display contents
DOTS2:		DD	DONXT,DOTS1		;loop till done
		D$	DOTQP,' <sp'
		DD	EXIT

;   !CSP	( -- )
;		Save stack pointer in CSP for error checking.

		$COLON	4,'!CSP',STCSP
		DD	SPAT,CSP,STORE,EXIT	;save pointer

;   ?CSP	( -- )
;		Abort if stack pointer differs from that saved in CSP.

		$COLON	4,'?CSP',QCSP
		DD	SPAT,CSP,AT,XORR	;compare pointers
		D$	ABORQ,'stacks'          ;abort if different
		DD	EXIT

;   >NAME	( ca -- na | F )
;		Convert code address to a name address.

		$COLON	5,'>NAME',TNAME
		DD	CRRNT			;vocabulary link
TNAM1:		DD	CELLP,AT,QDUP		;check all vocabularies
		DD	QBRAN,TNAM4
		DD	DDUP
TNAM2:		DD	AT,DUPP 		;?last word in a vocabulary
		DD	QBRAN,TNAM3
		DD	DDUP,NAMET,XORR 	;compare
		DD	QBRAN,TNAM3
		DD	CELLM			;continue with next word
		DD	BRAN,TNAM2
TNAM3:		DD	SWAP,DROP,QDUP
		DD	QBRAN,TNAM1
		DD	SWAP,DROP,SWAP,DROP,EXIT
TNAM4:		DD	DROP,DOLIT,0,EXIT	;false flag

;   .ID 	( na -- )
;		Display the name at address.

		$COLON	3,'.ID',DOTID
		DD	QDUP			;if zero no name
		DD	QBRAN,DOTI1
		DD	COUNT,DOLIT,01FH,ANDD	;mask lexicon bits
		DD	UTYPE,EXIT		;display name string
DOTI1:		D$	DOTQP,' {noName}'
		DD	EXIT

;   SEE 	( -- ; <string> )
;		A simple decompiler.

		$COLON	3,'SEE',SEE
		DD	TICK			;starting address
		DD	CR,CELLP
SEE1:		DD	CELLP,DUPP,AT,DUPP	;?does it contain a zero
		DD	QBRAN,SEE2
		DD	TNAME			;?is it a name
SEE2:		DD	QDUP			;name address or zero
		DD	QBRAN,SEE3
		DD	SPACE,DOTID		;display name
		DD	BRAN,SEE4
SEE3:		DD	DUPP,AT,UDOT		;display number
SEE4:		DD	NUFQ			;user control
		DD	QBRAN,SEE1
		DD	DROP,EXIT

;   WORDS	( -- )
;		Display the names in the context vocabulary.

		$COLON	5,'WORDS',WORDS
		DD	CR,CNTXT,AT		;only in context
WORS1:		DD	AT,QDUP 		;?at end of list
		DD	QBRAN,WORS2
		DD	DUPP,SPACE,DOTID	;display a name
		DD	CELLM,NUFQ		;user control
		DD	QBRAN,WORS1
		DD	DROP
WORS2:		DD	EXIT

;; Hardware reset

;   VER 	( -- n )
;		Return the version number of this implementation.

		$COLON	3,'VER',VERSN
		DD	DOLIT,VER*256+EXT,EXIT

;   hi		( -- )
;		Display the sign-on message of eForth.

		$COLON	2,'hi',HI
		DD	STOIO,CR		;initialize I/O
		D$	DOTQP,'eForth v'        ;model
		DD	BASE,AT,HEX		;save radix
		DD	VERSN,BDIGS,DIG,DIG
		DD	DOLIT,'.',HOLD
		DD	DIGS,EDIGS,TYPEE	;format version number
		DD	BASE,STORE,CR,EXIT	;restore radix

;   'BOOT       ( -- a )
;		The application startup vector.

		$COLON	5,"'BOOT",TBOOT
		DD	DOVAR
		DD	HI			;application to boot

;   COLD	( -- )
;		The hilevel cold start sequence.

		$COLON	4,'COLD',COLD
COLD1:		DD	DOLIT,UZERO,DOLIT,UPP
		DD	DOLIT,ULAST-UZERO,CMOVE ;initialize user area
		DD	PRESE			;initialize stack and TIB
		DD	TBOOT,ATEXE		;application boot
		DD	FORTH,CNTXT,AT,DUPP	;initialize search order
		DD	CRRNT,DSTOR,OVERT
		DD	QUIT			;start interpretation
		DD	BRAN,COLD1		;just in case

;===============================================================

LASTN		EQU	_NAME+4 		;last name address


NTOP	EQU	_NAME-0 	;next available memory in name dictionary
CTOP	EQU	$+0		;next available memory in code dictionary

MAIN	ENDS
Boot2End:
END	ORIG

;===============================================================


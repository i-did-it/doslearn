; vi: syntax=masm


.8086
.MODEL SMALL

DGROUP GROUP CONST00, _ERRMSG, _BSS, _STACK

PCXHEADER STRUCT
	identifier	BYTE ?
	version			BYTE ?
	encoding		BYTE ?
	bpp					BYTE ?
	xmin				WORD ?
	ymin				WORD ?
	xmax				WORD ?
	ymax				WORD ?
PCXHEADER ENDS

STACKLENGTH EQU 1024 ; 1k STACK

_STACK	SEGMENT PARA STACK 'STACK'

				DB	STACKLENGTH DUP (?)

_STACK	ENDS

CR			EQU 0DH
LF			EQU 0AH

_ERRMSG	SEGMENT WORD PUBLIC 'DATA'

	; Pesan galat (kompatibel dengan DOS 2.0)
	ERR_UNKNOWN				DB 'Galat tidak dikenal! Nomor galat:'
	ERR_UNK_CODE			DB  ?, ?, CR, LF
	ERR_UNK_LEN				EQU $-ERR_UNKNOWN
	ERR_NOTPCX				DB 'Not A PCX file!$'	
	; ERR NOTPCXFILE	
	; 01
	ERR_INVFUNC				DB 'Nomor fungsi DOS tidak valid!$'
	ERR_FILENOTFOUND	DB 'Berkas tidak diketemukan!$'
	ERR_PATHNOTFOUND	DB 'Path tidak diketemukan!$'
	ERR_TOOMANYOPEN		DB 'Terlalu banyak berkas terbuka!$'
	ERR_ACCESSDENIED	DB 'Akses ditolak!$'
	ERR_HANDLEINVALID	DB 'Handle tidak valid!$'
	ERR_MCB_DESTROYED	DB 'MCB hilang atau rusak!$'
	ERR_INSUF_MEM			DB 'Memori tidak cukup!$'
	ERR_INV_MEMBLK		DB 'Blok memori tidak valid!$'
	; 09
	
_ERRMSG	ENDS

CONST00		SEGMENT WORD PUBLIC 'DATA'

	USAGE		DB	'PCXView Hak Cipta (c) 2021 Didiet Noor', CR, LF
					DB	'Penggunaan: pcxview [nama berkas]', CR, LF
	USGLEN	EQU	$-USAGE
	HEXBIT	DB	'0123456789ABCDEF'
CONST00		ENDS

CMDLEN		EQU		BYTE PTR SS:[80]
CMDLINE		EQU		BYTE PTR SS:[81]
MAXFLEN		EQU		255
PARA			EQU		16
PARASHIFT	EQU		4
RBUFLEN		EQU		1 * PARA
CGASEG		EQU		B800

_BSS		SEGMENT WORD PUBLIC 'DATA'
	PCXHDR	PCXHEADER <>
	FWIDTH	DW ?
	FHEIGHT	DW ?
	FNAME		DB MAXFLEN DUP (?)	
	FHANDLE	DW ?
	FSIZE		DW ?
	RBUF		DB RBUFLEN DUP (?)
	RBUFEND	EQU $
	WBUFLEN	DW ?
	WBUFSEG	DW ?
	PXLCNT  DW ?
_BSS		ENDS

_TEXT		SEGMENT WORD PUBLIC USE16 'CODE'

	SETFREE MACRO
		
		MOV	BX, SS
		MOV	AX, ES
		SUB	BX, AX

		MOV	AX, SP
		MOV	CL, 4
		SHR	AX, CL
		ADD	BX, AX
		INC	BX

		MOV	AH, 4AH
		INT 21H

	ENDM

	STDOUT	EQU 1
	PRINTUSAGE MACRO
		MOV	AX, DGROUP
		MOV	DS, AX
		MOV	AH, 40H
		MOV	BX, STDOUT
		MOV	CX, USGLEN
		MOV	DX, OFFSET USAGE
		INT	21H
	ENDM

	PRINTS	MACRO S
		MOV	AX, DGROUP
		MOV	DS, AX
		MOV	AH, 09H
		LEA	DX, S
		INT	21H
	ENDM

	TERMINATE MACRO EXITCODE
		MOV AH, 4CH
		MOV	AL, EXITCODE
		INT	21H
	ENDM

	byte2hex PROC NEAR WATCOM_C b:BYTE
		MOV	BX, OFFSET HEXBIT
		MOV	DL, b

		XOR	AX, AX
		MOV	SI, DX
		AND	SI,	0FH
		MOV	AH, BYTE PTR [BX + SI]
		
		MOV	SI, DX
		MOV	CL, 2
		SHR	SI, CL
		AND	SI, 0FH
		MOV	AL, BYTE PTR [BX + SI]
		RET
	byte2hex ENDP

	closefile PROC NEAR
		CMP	FHANDLE, 00H
		JE	@nothing
		MOV	AH, 3EH
		MOV	BX, FHANDLE
		INT 21H
	@nothing:
		RET
	closefile ENDP

	freemem PROC NEAR
		CMP	WBUFSEG, 00H
		JE	@nofree
		MOV	BX, WBUFSEG
		MOV	AH, 49H
		MOV	ES, BX
		INT	21H
	@nofree:
		RET
	freemem ENDP
	
	
	PRINT_UNKNOWN MACRO
		MOV		DX, AX ; ERROR CODE
		MOV		AX, DGROUP
		MOV		DS, AX
		MOV		ES, AX

		MOV		AX, DX
		
		CALL	byte2hex

		MOV		DI, OFFSET ERR_UNK_CODE
		STOSW

		MOV		AX, 40H
		MOV		BX, STDOUT
		MOV		CX, ERR_UNK_LEN
		MOV		DX, OFFSET ERR_UNKNOWN
		INT		21H
	ENDM

	PUSHREGS MACRO
		PUSH	AX
		PUSH  BX
		PUSH	CX
		PUSH	DX
		PUSH	SI
		PUSH	DI
	ENDM

	POPREGS MACRO
		POP		DI
		POP		SI
		POP		DX
		POP		CX
		POP		BX
		POP		AX
	ENDM

	readbuf	PROC NEAR
		
		PUSHREGS
		MOV		AH, 3FH
		MOV		BX, FHANDLE
		MOV		CX, RBUFLEN
		MOV		DX, OFFSET RBUF
		INT		21H
		POPREGS

		MOV		SI, OFFSET RBUF

		RET
	readbuf	ENDP

	drawpic PROC NEAR
		LOCAL wx: WORD, wy: WORD, cy: WORD, rem: WORD

		MOV		wx, AX
		MOV		wy, DX
		MOV		cy, 0

		MOV		AX, 0B800H
		MOV		ES, AX
		XOR		DI, DI		

		MOV		AH, 00H
		MOV		AL, 04H
		INT		10H

		MOV		AH, 0BH
		MOV		BH, 00H
		MOV		BL, 00H
		INT		10H

		MOV		AH, 0BH
		MOV		BH, 01H
		MOV		BL, 01H
		INT		10H

; -- debug
;		MOV		AX, wx
;		MOV		CL, 2
;		SHR		AX, CL
;		MOV		CX, AX
;		REP		MOVSB

;		MOV		SI, 80
;		
;		XOR		DI, DI
;		XOR		DI, 2000H
;		MOV		AX, wx
;		MOV		CL, 2
;		SHR		AX, CL
;		MOV		CX, AX
;		REP		MOVSB
; -- debug		

;		
		MOV		DX, cy
@nextline:
		XOR		CX, CX
		MOV		AX, wx
		MOV		CL, 2
		SHR		AX, CL
		MOV		CX, AX
		REP MOVSB
		MOV		DX, cy
		INC		DX
		CMP		DX, wy
		JAE		@endline	
		MOV		cy, DX
		
		XOR		DX, DX
		MOV		CX, 2
		MOV		AX, cy
		CWD
		DIV		CX
		MOV		rem, DX
		MOV		CX, 320 / 4 ; 4 pixels per byte
		MUL		CX
		MOV		DI, AX
		CMP		rem, 0
		JE		@nextline
		XOR		DI, 2000H
		JMP		@nextline
@endline:
		MOV		AH, 08H
		INT		21H

		MOV		AH, 00H
		MOV		AL, 03H
		INT		10H

		RET
	drawpic ENDP

	main	PROC FAR
		ASSUME CS:_TEXT, SS: DGROUP, DS: DGROUP, ES: NOTHING
	
		SETFREE
		CLD

		; PARSE COMMAND LINE
		; Jika tidak ada berkas yang ditulis, tampilkan USAGE lalu kemudian terminasi
		MOV	AX, DGROUP
		MOV ES, AX

		XOR	CX, CX
		MOV	CL, BYTE PTR DS:[80H]
		CMP	CL, 0
		JE	@printusage
		DEC	CX
		
		MOV	SI, 82H
		MOV	DI, OFFSET FNAME
		REP	MOVSB
		
		XOR	AX, AX
		STOSB

		MOV	AX, DGROUP
		MOV	DS, AX
		XOR	AX, AX

		; initialise needed vars
		MOV	FHANDLE, AX
		MOV	WBUFSEG, AX
		MOV	FWIDTH, AX
		MOV	FHEIGHT, AX

		; buka file

		MOV	AH, 3DH
		MOV	AL, 00H
		LEA	DX, FNAME
		INT	21H 
		JC	@on_error

		MOV	FHANDLE, AX

		MOV AH, 3FH
		MOV	BX, FHANDLE
		MOV	CX, SIZEOF PCXHEADER
		MOV	DX, OFFSET PCXHDR
		INT	21H
		JC	@on_error
		
		CMP	PCXHDR.identifier, 0AH
		JNE	@notapcxfile

		; calculate write buffer length
		MOV	AX, PCXHDR.xmax
		MOV	BX, PCXHDR.xmin
		SUB	AX, BX
		INC	AX

		MOV	FWIDTH, AX

		MOV	CX, PCXHDR.ymax
		MOV	BX, PCXHDR.ymin
		SUB	CX, BX
		INC	CX

		MOV	FHEIGHT, CX

		MUL	CX
		MOV	PXLCNT, AX

		MOV	CL, 2
		SHR	AX, CL
		MOV	WBUFLEN, AX		
		
		MOV	AH, 42H
		MOV	AL, 02H
		MOV	BX, FHANDLE
		XOR	CX, CX
		XOR	DX, DX
		INT	21H
		JC	@on_error

		SUB	AX, 80H
		MOV	FSIZE, AX

		MOV	AH, 42H
		MOV	AL, 00H
		MOV	BX, FHANDLE
		XOR	CX, CX
		MOV	DX, 80H
		INT	21H
		JC	@on_error


		; allocate memory
		; SIZE : WBUFLEN + 4 (WIDTH, HEIGHT)
		MOV	BX, WBUFLEN
		MOV	CL, PARASHIFT
		INC	BX ; 1 more paragraph for good measure
		SHR	BX, CL
		MOV	AH, 48H
		INT	21H
		JC	@on_error
			
		MOV	ES, AX
		XOR	AX, AX
		MOV	CX, WBUFLEN
		
		; ZERO OUT PIXEL DATA
		XOR DI, DI
		XOR AX, AX
		REP	STOSB

		; PROCESS PIXEL
		;	AH  - NOT USED
		; AL  - PROCESSED COLOUR
		; BX	- PIXEL REMAINING
		; CH	- COMBINED PIXEL VALUE
		; CL	- CURRENT SHIFT
		; DH	- CURRENT COLOUR
		; DL	- CURRENT COLOUR COUNT
		; SI	- SOURCE BUFFER INDEX
		; DI	- DESTINATION BUFFER
		XOR	DI, DI
		MOV	CX, 8H
		MOV	SI, RBUFEND
		MOV	BX, PXLCNT
	@nextbyte:
		CMP		SI, RBUFEND
		JB		@@1
		CALL	readbuf
		JC		@on_error
	@@1:
		MOV		AL, [SI]
		CMP		AL, 0C0H
		JB		@normalpixel
		INC		SI
		MOV		DL, AL
		AND		DL, 3FH
		CMP		SI, RBUFEND
		JB		@@2
		CALL	readbuf
		JC		@on_error
	@@2:
		LODSB
		JMP		@processpixel
	@normalpixel:
		INC SI
		MOV	DL, 1
	@processpixel:
		SUB	CL, 2
		SHL	AL, CL
		OR	CH, AL
		SHR	AL, CL
		DEC	BX
		JZ	@storepixel
		CMP	CL, 0
		JA	@advance
	@storepixel:
		MOV	DH, AL
		MOV	AL, CH
		STOSB
		MOV	AL, DH
		MOV	CX, 0008H
		CMP	BX, 0
		JE	@endprocess
	@advance:
		; advance to next byte
		DEC	DL
		JZ	@nextbyte
		JMP	@processpixel
	@endprocess:

		;TODO: draw to buffer
		;	

		MOV		AX, FWIDTH
		MOV		DX, FHEIGHT
		
		XOR		SI, SI

		MOV		BX, ES
		MOV		DS, BX
		XOR		BX, BX
		; ASSUME
		; DS:SI SOURCE
		CALL drawpic

		MOV		AX, DGROUP
		MOV		DS, AX

		; Deallocate memory, ES=previously allocated block
		MOV	ES, WBUFSEG
		MOV	AH, 49H
		INT 21H
		
		; tutup file
		MOV	AH, 3EH
		MOV	BX, FHANDLE
		INT	21H
		JC	@on_error

		TERMINATE 00H
	@on_error:
		CMP	AX, 01H
		JE	@invalidfunction
		CMP	AX, 02H
		JE	@filenotfound
		JMP	@unknown
	@invalidfunction:
		PRINTS ERR_INVFUNC
		JMP	@abnormalterm
	@filenotfound:
		PRINTS ERR_FILENOTFOUND
		JMP	@abnormalterm
	@unknown:
		PRINT_UNKNOWN
		JMP	@abnormalterm
	@notapcxfile:
		PRINTS ERR_NOTPCX
		JMP	@abnormalterm
	@printusage:
		PRINTUSAGE
		JMP @abnormalterm
	@abnormalterm:
		CALL	freemem
		CALL	closefile
		TERMINATE 01H
	main	ENDP

_TEXT		ENDS

END	main

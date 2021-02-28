; vi: syntax=masm

.8086
.MODEL SMALL

CR		EQU 0DH
LF		EQU 0AH

; PCX Header Structure
; -not used at the moment
PCXHEADER STRUCT 
	identifier	BYTE ?
	version			BYTE ?
	encoding		BYTE ?
	bpp					BYTE ?
	xstart			WORD ?
	ystart			WORD ?
	xend				WORD ?
	yend				WORD ?
	hres				WORD ?
	vres				WORD ?
	palette			BYTE 48 DUP (?)
	reserved		BYTE ?
	bitplanes		BYTE ?
	bpl					WORD ?
	paltype			WORD ?
	hscreen			WORD ?
	vscreen			WORD ?
	reserved2		BYTE 54 DUP (?)
PCXHEADER ENDS


; -------------- Segments who hold data ----------------------
DGROUP GROUP _DATA, _BSS, _STACK

_DATA		SEGMENT WORD PUBLIC 'DATA'
				
	USAGE		DB CR, LF, 'PCX2BIT - Copyright (c) 2021 Didiet Noor'
					DB CR, LF, '----------------------------------------'
					DB CR, LF, 'For trimming and converting 8-bit PCX to a 2-bit RAW colour'
					DB CR, LF, CR, LF
					DB			   'USAGE: PCX2BIT [file name]', CR, LF
	USAGELEN EQU $-USAGE

	EXT				DB					'CGA', 00H
	CGAK			DB					'CGAK'
	CGAX			DW					?
	CGAY			DW					?	

	ERR_FILE_NOT_FOUND		DB 'DOS ERROR: File Not Found', CR, LF, '$'
	ERR_UNKNOWN						DB 'DOS ERROR: Unknown', CR, LF, '$'
	ERR_NOT_PCX						DB 'Not A PCX File!', CR, LF, '$'
	ERR_MCB_CORRUP				DB 'DOS ERROR: Memory Control Block Destroyed', CR, LF, '$'
	ERR_INSUFFICIENT_MEM	DB 'DOS ERROR: Insufficient Memory', CR, LF, '$'
_DATA		ENDS

_BSS		SEGMENT WORD PUBLIC 'DATA'
	FILENAME		DB 20 DUP (?)
	TARGETFILE	DB 20 DUP (?)
	FH				WORD ?
	TFH				WORD ?
	BSSLEN			EQU $-FILENAME
_BSS		ENDS

_STACK	SEGMENT PARA STACK 'STACK'
			DB		1024 DUP (?)
_STACK	ENDS
; I'll put text on the beginning of the code
; All procedures follows WATCOM C calling convention

_TEXT		SEGMENT WORD PUBLIC USE16 'CODE'

; First and foremost is the nprint routine
;	AX = pointer to the buffer to be printed
; DX = buffer length
; AX, BX, CX, DX are all changed

nprint PROC NEAR WATCOM_C str: PTR, length: WORD
	
	ASSUME DS: DGROUP, SS: DGROUP, CS:_TEXT, ES: NOTHING

	; AX = PTR, DX = LENGTH
	STDOUT EQU 1

	XCHG	AX, DX ; To make DX holds the pointer needed for INT 21H
	MOV		CX, AX ; CX = length
	MOV		BX, STDOUT ; write to stdout
	MOV		AH, 40H ;
	INT		21H
	RET
nprint ENDP

prints MACRO str
	MOV	AH, 09H
	LEA	DX, str
	INT 21H
ENDM

; print usage 
printusage MACRO
	LEA		AX, USAGE
	MOV		DX, USAGELEN
	CALL	nprint
ENDM

; setting the rest of the program free
; so we can allocate later
; INPUT		ES = address of the PSP
; OUTPUT	-
; CLOBBERS AX, BX, CL, FLAGS
; Info : SS:SP points to the SS:SP which will point to the end of the program storage
;        Find out the length of the program to be tight-fitted
setfree	MACRO
		
	MOV		BX, SS
	MOV		AX, ES
	SUB		BX, AX ; ss-es => number of paragraph from PSP to the beginning of the stack

	MOV		AX, SP
	MOV		CL, 4
	SHR		AX, CL ; sp is in the end of the stack segment, means it's the length of the
							 ; stack segment
	ADD		BX, AX
	INC		BX			; ADD ONE PARAGRAPH just in case
	
	MOV		AH, 4AH ; Modify allocation
	INT		21H		
	
ENDM

; TERMINATE PROGRAM
exit MACRO statuscode
	MOV		AH, 4CH
	MOV		AL, statuscode
	INT		21H
ENDM

exitnormal MACRO
	exit 0
ENDM

; PARSING Command from the PSP
; ES: the stack segment of the PSP
; AX: the buffer address 
; DX: buffer length

; output
;	AX: actual length
; Notes: Command contains space, therefore we remove the preceding space
parsecommand PROC NEAR WATCOM_C buf: PTR, len: WORD

		CMDLENGTH EQU BYTE PTR ES:[80H]
		CMDLINE		EQU ES:[81H]

		MOV	CL, CMDLENGTH
		AND	CX, 0FH
		JNZ @@1

		printusage
		exit 1

@@1:
		DEC	CL
		CMP	CX, len
		JLE	@@2
		MOV	CX, len
		
@@2:
		LEA	SI, CMDLINE
		INC	SI
		MOV DI, buf
		
		PUSH	DS
		PUSH	CX

		; Exchange DS and ES, clobbering AX
		MOV		AX, ES
		MOV		DS, AX
		MOV		AX, DGROUP
		MOV		ES, AX
		
		CLD
		REP		MOVSB
		
		POP	 AX
		POP	 DS

		RET

parsecommand ENDP

closefile PROC NEAR WATCOM_C handle: WORD
	MOV	BX, handle
	MOV	AH, 3EH
	INT 21H
	RET
closefile ENDP

openfile	PROC NEAR WATCOM_C fname: PTR
	MOV	DX, fname
	XOR	AX, AX
	MOV	AH, 3DH
	INT 21H
	RET
openfile ENDP

createfile PROC NEAR WATCOM_C ftargetname: PTR
	MOV	DX, ftargetname
	XOR	AX, AX
	MOV	AH, 3CH
	MOV	CX, 0
	INT 21H
	RET
createfile ENDP

writefile PROC NEAR WATCOM_C handle: WORD, buff: PTR, length: WORD
		MOV		CX, length
		MOV		BX, AX
		XOR		AX, AX
		MOV		AH, 40H
		INT		21H
		RET
writefile ENDP

main PROC FAR
		MOV	AX, DGROUP
		MOV	DS, AX
		
		; NEEDS TO BE INVOKED BEFORE STACK SETUP
		; can't use local variable 
		setfree

		PUSH	BP
		MOV		BP, SP
		
		HEADERLENGTH	EQU 80H
		RBUFLEN				EQU 4H
		WBUFLEN				EQU 4H
		EXTRALEN			EQU 10 * 2 ; 10 BYTES FOR WORD
		STACKBOTTOM		EQU HEADERLENGTH + RBUFLEN + WBUFLEN + EXTRALEN
		SUB		SP, STACKBOTTOM; Reserve space on stack

;		LOCAL VARIABLES	
		TEMP				EQU SS:[BP - STACKBOTTOM]
		LINENUMBER	EQU	TEMP					+ 2
		TARGETBYTES	EQU	LINENUMBER		+ 2
		TARGETDIM		EQU	TARGETBYTES		+ 2
		QC					EQU	TARGETDIM		  + 4
		COLOR				EQU	QC						+ 1
		SHANDLE			EQU	COLOR					+ 1
		THANDLE			EQU	SHANDLE				+ 2
		HEADER			EQU THANDLE				+ 2
		RBUF				EQU	HEADER				+ HEADERLENGTH
		WBUF				EQU RBUF					+ RBUFLEN

		LEA		AX, FILENAME
		MOV		DX, 19 ; reduce one
		CALL	parsecommand

		; DONE PARSING COMMAND SET ES=DS
		MOV		TEMP, AX ; character count
		MOV		AX, DS
		MOV		ES, AX

		LEA		BX, FILENAME
		MOV		DI, TEMP
		MOV		BYTE PTR [BX + DI], 0H ; ASCIIZ
		
		;	target = FILENAME.CGA
		MOV		CX, TEMP
		SUB		CX, 3

		MOV		SI, BX
		LEA		DI, TARGETFILE
		REP		MOVSB
		LEA		SI, EXT
		MOV		CX, 4
		REP		MOVSB

		; open file
		
		LEA		AX, FILENAME
		CALL	openfile
		JC		@@on_error

		
		MOV		FH, AX
		MOV		SHANDLE, AX
		
		; create target file
		LEA		AX, TARGETFILE
		CALL	createfile
		JC		@@closeandexit

		MOV		TFH, AX
		Mov		THANDLE, AX

		MOV		BX, FH
		MOV		WORD PTR TEMP, DS		
			
		MOV		AX, SS
		MOV		DS, AX

		; Read File, BX assigned before
		MOV		AH, 3FH
		MOV		CX, 80H
		LEA		DX, HEADER		
		INT		21H
		
		MOV		DS, WORD PTR TEMP

		MOV		AL, BYTE PTR HEADER
		CMP		AL, 0AH
		JNE		@@closetargetandexit

		MOV		AX, WORD PTR HEADER + 8
		MOV		CX, WORD PTR HEADER + 4
		SUB		AX, CX
		INC		AX                       ; source buffer = line bytes X

		MOV		WORD PTR TARGETDIM, AX
		MOV		WORD PTR CGAX, AX

		MOV		DX, AX								
		MOV		CL, 2
		SHR		AX, CL									 ; destination byte = line bytes X / 4

		MOV		WORD PTR TARGETBYTES, AX

		MOV		CX, WORD PTR HEADER + 10
		MOV		AX, WORD PTR HEADER + 6
		SUB		CX, AX									 ; line number
		INC		CX

		MOV		WORD PTR [TARGETDIM + 2], CX
		MOV		WORD PTR LINENUMBER, CX
		MOV		WORD PTR CGAY, CX
	
		MOV		AH, 40H
		MOV		BX, TFH
		MOV		CX, 08H
		LEA		DX, CGAK
		INT		21H
		JC		@@closetargetandexit
	
		MOV		DS, WORD PTR TEMP
		
		MOV		AX, SS
		MOV		ES, AX
		XOR		SI, SI
		LEA		DI, RBUF 
		
		XOR		AX, AX ; ZERO OUT THE BUFFER
		MOV		CX,	RBUFLEN + WBUFLEN
		
		CLD
		REP		STOSB
	
		MOV		BX, FH
		MOV		CX, RBUFLEN
		
		MOV		TEMP, DS
		MOV		AX, SS
		MOV		DS, AX
		
		XOR		AX, AX
	; zero count
		MOV		QC, AX
		MOV		COLOR, AX

		LEA		DI, WBUF

@@readmore:
		LEA		SI, RBUF
		MOV		DX, SI
		MOV		AH, 3FH
		INT		21H
		JC		@@closeandexit
		
		XOR		CX, CX
		XOR		DX, DX
		
		MOV		CX, 0006H; INITIAL CX VALUE
@nextbyte:
		MOV		DL, [SI]
		CMP		DL, 0C0H
		JB		@normalpixel
		AND		DL, 3FH
		INC		SI
		LODSB	
		JMP		@processpixel
@normalpixel:
		MOV		AL, DL
		MOV		DL, 1

@nextquartet:
		MOV		CX, 06H
@processpixel:
		MOV		BYTE PTR COLOR, AL
@leshift:
		SHL		AL, CL
		OR		CH, AL
		CMP		CL, 0
		JZ		@storebyte
		SUB		CL, 2
		MOV		AL, BYTE PTR COLOR
		
		DEC		DL
		JZ		@readbufcheck

		JMP		@leshift
@readbufcheck:
		LEA		BX, [RBUF + RBUFLEN]
		CMP		SI, BX
		JNE		@nextbyte
		JMP		@@readmore
@storebyte:
		MOV		AL, CH
		STOSB
		MOV		AL, BYTE PTR COLOR
		LEA		BX, [WBUF + WBUFLEN]
		CMP		DI, BX
		JNE		@nextquartet
		LEA		DX, WBUF
		MOV		DI, DX
		MOV		BX, THANDLE
		MOV		CX, WBUFLEN
		MOV		AH, 40H
		INT		21H
		JMP		@nextquartet

		MOV		AX, SHANDLE
		CALL	closefile
		JC		@@on_error
		
		JMP @@termnormal

@@closetargetandexit:
		MOV		BX, TFH
		CALL	closefile
@@closeandexit:
		MOV		BX, FH
		CALL	closefile
@@on_error:
		CMP	AX, 02H
		JNE	@@@1
		prints	ERR_FILE_NOT_FOUND
		JMP	@@notnormal
@@@1:
		CMP	AX, 07H
		JNE	@@@2
		prints	ERR_MCB_CORRUP
		JMP	@@notnormal
@@@2:
		CMP	AX, 08H
		JNE	@@@3
		prints	ERR_INSUFFICIENT_MEM
		JMP @@notnormal	
@@@3:
		prints ERR_UNKNOWN
@@notnormal:
		MOV	SP, BP
		POP BP
		exit 1
@@termnormal:

		MOV	SP, BP
		POP BP
		exitnormal
		RET
main ENDP

_TEXT		ENDS

END main




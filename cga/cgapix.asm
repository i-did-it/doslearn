; vi: syntax=masm

.8086
.MODEL SMALL

PCXHEADER STRUCT
	
	identifier		BYTE ? ; 1
	version				BYTE ? ; 1
	rlebyte				BYTE ? ; 1
	bpp						BYTE ? ; 1 - only 8 bit accepted
	xmin					WORD ? ; 2
	ymin					WORD ? ; 2
	xmax					WORD ? ; 2
	ymax					WORD ? ; 2
	; ... the rest is unimportant
	; 116 bytes
PCXHEADER ENDS

DGROUP	GROUP _BSS, _DATA, _STACK

CR	EQU 0DH
LF	EQU	0AH

_DATA		SEGMENT WORD PUBLIC 'DATA'
		USAGE	DB CR, LF,
		      DB 'CGA File Viewer (c) 2021 Didiet Noor', CR, LF,
				  DB 'USAGE: CGAPIX [file_name].PCX', CR, LF, '$'
_DATA		ENDS

_BSS		SEGMENT WORD PUBLIC 'DATA'
	PCXHDR				PCXHEADER<>
	PCXHEADERLEN	EQU $-PCXHDR
	FHANDLE				DW ?
	TOTALREAD			DW ?
	TOTALPIXEL		DW ?
	RBYTE					DB ?
	FNAME					DB 14 DUP (?)
	BWIDTH				DW ?
	BHEIGHT				DW ?
_BSS		ENDS

_STACK	SEGMENT PARA STACK 'STACK'
		DB	512 DUP (?)
_STACK	ENDS

_TEXT		SEGMENT WORD PUBLIC USE16 'CODE'
	ASSUME CS: _TEXT, DS: DGROUP, CS: DGROUP, SS: DGROUP, ES: NOTHING

PRINTS MACRO txt
		MOV	AH, 09H
		MOV	DX, OFFSET txt
		INT	21H
ENDM

	STDOUT	EQU 1
	nprint PROC NEAR WATCOM_C s: PTR, len: BYTE
		MOV		CL, len
		MOV		DX, s
		MOV		AH, 40H
		MOV		BX, STDOUT
		INT		21H
		RET
	nprint ENDP

	main	PROC FAR
		CMDLEN		EQU		ES:[80H]
		CMDLINE		EQU		ES:[81H]
		; parse command line
		
		MOV		AX, DGROUP
		MOV		DS, AX
		
		XOR		CX, CX
		MOV		CL, BYTE PTR CMDLEN
		CMP		CL, 0
		JE		@termerror

		DEC		CX
		PUSH	CX

		MOV		BX, DS
		MOV		DX, ES

		XCHG	BX, DX
		
		MOV		DS, BX
		MOV		ES, DX
		
		MOV		DI, OFFSET FNAME
		MOV		SI, OFFSET CMDLINE + 1
		REP		MOVSB
		MOV		BYTE PTR ES:[DI], 0

		MOV		DS, DX	
		;POP		DX
		;MOV		AX, OFFSET FNAME
		;CALL	nprint

		XOR	AX, AX
		MOV	TOTALREAD, AX
		MOV	TOTALPIXEL, AX

		; OPEN FILE
		MOV		AH, 3DH
		MOV		AL, 00H
		LEA		DX, FNAME
		INT		21H
		
		JC		@termerror
		MOV		FHANDLE, AX
		
		MOV		AH, 3FH
		MOV		BX,	FHANDLE
		MOV		CX, PCXHEADERLEN
		LEA		DX, PCXHDR
		INT		21H

		MOV		AL, PCXHDR.identifier
		CMP		AL, 0AH
		JNE		@closeanderror
		MOV		AL, PCXHDR.bpp
		CMP		AL, 08H
		JNE		@closeanderror
		MOV		CX, PCXHDR.xmin
		MOV		AX, PCXHDR.xmax
		SUB		AX, CX
		JZ		@closeanderror
		INC		AX
		MOV		BWIDTH, AX
		MOV		CX, PCXHDR.ymin
		MOV		AX, PCXHDR.ymax
		SUB		AX, CX
		JZ		@closeanderror
		INC		AX
		MOV		BHEIGHT, AX

		MOV		AH, 42H
		MOV		AL, 01H
		MOV		BX, FHANDLE
		MOV		CX, 00H
		MOV		DX, 116
		INT		21H

		MOV		AH, 3FH
		MOV		BX, FHANDLE
		MOV		CX, 1
		LEA		DX, RBYTE
		INT		21H

		MOV		CX, TOTALREAD
		ADD		CX, AX
		MOV		TOTALREAD, CX
		
		; CLOSE FILE 
		MOV		BX, FHANDLE
		MOV		AH, 3EH
		INT		21H
		
		JMP		@termnormal

@closeanderror:
		MOV	BX, FHANDLE
		MOV	AH, 3EH
		INT 21H
@termerror:
		MOV		AX, DGROUP
		MOV		DS, AX	

		PRINTS USAGE
		MOV	AX, 4C01H
		INT 21H

@termnormal:
		MOV	AX, 4C00H
		INT 21H
	main	ENDP

_TEXT		ENDS

END	main

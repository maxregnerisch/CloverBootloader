DEFAULT_HANDLER_SIZE: equ 16 ; size of exception/interrupt stub
SYS_CODE_SEL64: equ 0x28 ; 64-bit code selector in GDT
PE_OFFSET_IN_MZ_STUB: equ 0x3c ; place in MsDos stub for offset to PE Header
VGA_FB: equ 0x000b8000 ; VGA framebuffer for 80x25 mono mode
VGA_LINE: equ 80 * 2 ; # bytes in one line
BASE_ADDR_64: equ 0x000200000
STACK_TOP: equ 0x0002fffc8
SIZE: equ 0x1000

struc EFILDR_IMAGE
CheckSum: resd 1
Offset: resd 1
Length: resd 1
FileName: resb 52
endstruc

struc EFILDR_HEADER
Signature: resd 1
HeaderCheckSum: resd 1
FileLength: resd 1
NumberOfImages: resd 1
endstruc

struc PE_HEADER
resb 6
NumberOfSections: resw 1
resb 12
SizeOfOptionalHeader: resw 1
resb 2
Magic: resb 2
AddrOfEntryPoint: resq 1
ImageBase: resq 1
endstruc

struc PE_SECTION_HEADER
resb 12
VirtualAddress: resq 1
SizeOfRawData: resd 1
PointerToRawData: resd 1
resb 16
endstruc

%macro StubWithNoCode 1
push 0 ; push error code place holder on the stack
push %1
jmp qword commonIdtEntry
%endmacro

%macro StubWithACode 1
times 2 nop
push %1
jmp qword commonIdtEntry
%endmacro

%macro PrintReg 2
mov esi, %1
call PrintString
mov rax, [rsp + %2]
call PrintQword
%endmacro

Copy code
bits 64
org BASE_ADDR_64
global _start
_start:
mov rsp, STACK_TOP
;
; set OSFXSR and OSXMMEXCPT because some code will use XMM registers
;
mov cr4, cr4 | 0x600

;
; Populate IDT with meaningful offsets for exception handlers...
;
sidt [REL Idtr]

vbnet
Copy code
mov	rax, StubTable
mov	ebx, eax		; use bx to copy 15..0 to descriptors
shr	eax, 16			; use ax to copy 31..16 to descriptors
				; 63..32 of descriptors is 0
mov	ecx, 0x100		; 100h IDT entries to initialize with unique entry points
mov	rdi, [REL Idtr + 2]
.StubLoop: ; loop through all IDT entries exception handlers and initialize to default handler
mov [rdi], bx ; write bits 15..0 of offset
mov word [rdi + 2], SYS_CODE_SEL64 ; SYS_CODE_SEL64 from GDT
mov word [rdi + 4], 0x8e00 ; type = 386

; Initialize serial console
mov edx, 0x3f8
mov eax, 115200 / 16
mov ecx, 0
mov al, 0x80
out dx, al
mov al, byte 3
out dx + 3, al
mov al, 0
out dx + 1, al
mov al, 1
out dx + 3, al
mov al, 7
out dx + 1, al
mov al, 0x0c
out dx, al
call PrintEfiLdrInfo

r
Copy code
call	RelocateKernel

call	LaunchKernel

hlt

; Unused boot information
; bootloader signature
BlockSignature: db "MIKELI.1"
; length of boot information
dd 0
; boot information
resb 62

.EfiLdrOffset: resq 1 ; Store offset to the entry point of EFILDR

Idtr:
Limit: dw 0x7ff ; 2047
Base: dd 0 ; will be filled with lidt

StubTable:
%define IdtDescSize 16 ; size of one idt descriptor
; 0
StubWithNoCode DivideError
; 1
StubWithNoCode DebugException
; 2
StubWithNoCode NmiInterrupt
; 3
StubWithNoCode Int3
; 4
StubWithNoCode OverflowException
; 5
StubWithNoCode BoundsCheck
; 6
StubWithNoCode InvalidOpcode
; 7
StubWithNoCode NoDevice
; 8
StubWithNoCode DoubleFault
; 9
StubWithNoCode CoprocessorSegmentOverrun
; 10
StubWithNoCode InvalidTss
; 11
StubWithNoCode SegmentNotPresent
; 12
StubWithNoCode StackException
; 13
StubWithNoCode GeneralProtectionFault
; 14
StubWithNoCode PageFault
; 15
StubWithNoCode UnknownException
; 16
StubWithNoCode CoprocessorError
; 17-31
times 15 resb IdtDescSize - DEFAULT_HANDLER_SIZE

bash
Copy code
; 32
StubWithACode TimerInterrupt
; 33
StubWithACode KeyboardInterrupt
; 34-255
times 222 resb IdtDescSize - DEFAULT_HANDLER_SIZE
RelocateKernel:
; get kernel address
mov rdi, [REL .EfiLdrOffset]
add rdi, esi

css
Copy code
; read the PE header for the kernel
mov	rsi, rdi
add	rsi, [rdi + PE_OFFSET_IN_MZ_STUB]
movzx	ecx, word [rsi + PE_HEADER.NumberOfSections]

; relocate kernel sections
xor	r8d, r8d			; calculate total number of kernel relocations
.SectionLoop2:
movzx eax, word [rsi + PE_HEADER.SizeOfOptionalHeader]
add rsi, eax
add rsi, PE_HEADER.Magic
lea r10, [rsi + PE_SECTION_HEADER.SizeOfRawData]
lea r9, [rsi + PE_SECTION_HEADER.VirtualAddress]
lea r11, [rsi + PE_SECTION_HEADER.PointerToRawData]
movzx edx, word [rsi + PE_SECTION

[org 0x7c00]
OS_OFFSET equ 0x1000
MAX_READ_TRIES equ 3
SECTORS_TO_READ equ 22

[bits 16]
begin:
    mov [BOOT_DRIVE], dl
    mov ax, 0
    mov ds, ax
    mov ss, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov bp, 0x9000
    mov sp, bp

;;; Get Drive Parameters
    mov ah, 8
    mov dl, [BOOT_DRIVE]
    mov di, 0
    clc
    int 0x13
    jnc get_params_no_error
;;; Print and stop if there is an error reading the drive parameters
    mov al, ah
    call print_byte
    call print_cm
    mov al, 'p'
    call print_char
    jmp $

get_params_no_error:
;;; Save some of the drive parameters
    add dh, 1
    mov [DRIVE_N_HEADS], dh
    and cl, 0x3f
    mov [DRIVE_SECTS_PER_TRACK], cl
    jmp load_kernel

%include "src/boot/gdt.asm"
%include "src/boot/enter_pm.asm"

[bits 16]
load_kernel:

;;; Read drive one sector at a time
    mov bl, 1
read:
    mov al, bl ; current sector to read
    call read_drive
    add bl, 1
    cmp bl, SECTORS_TO_READ
    jle read
    call enter_pm

;;; Reads one sector from the drive at the given LBA into the kernel memory
;;; space at the appropriate offset (assumming 512 byte sectors).
;;; Input:
;;;   [al] = LBA of sector to read
;;; Output:
;;;   [cf] = Set on error
;;;   [ah] = status, as returned by INT 0x13/AH=0x02
;;;   [al] = sectors transferred, as returned by INT 0x13/AH=0x02
read_drive:
    push cx
    push bx
    push ax

    mov byte [READ_TRY_COUNT], 0
read_drive_retry:
    add byte [READ_TRY_COUNT], 1
    mov cx, 0
    mov es, cx ; Ensure segment register [es] is zero for interrupt
;;; Calculate Offset for Kernel
    mov cl, al
    sub cl, 1
    shl cx, 9
    mov bx, OS_OFFSET
    add bx, cx

;;; Calculate C,H,S using algorithm from OSDev:
;;; https://wiki.osdev.org/Disk_access_using_the_BIOS_(INT_13h)
    mov ah, 0 ; Ensure top half of [ax] is zero so that [al] behaves as dividend
    div byte [DRIVE_SECTS_PER_TRACK]
    add ah, 1
    mov cl, ah
    mov ah, 0
    div byte [DRIVE_N_HEADS]
    mov dh, ah
    mov ch, al
    mov al, 1
    mov ah, 2
    mov dl, [BOOT_DRIVE]
    clc
    int 0x13 ;do read
    jnc read_drive_no_error

;;; If an error occurred during the read:
    call print_byte
    call print_cm
    mov al, ah
    call print_byte
    call print_cm
    mov bl, [READ_TRY_COUNT]
    mov al, bl
    call print_byte
    call print_cm
    mov ax, [esp] ; Restore [al] (LBA of sector to read from)
    call print_byte
    call print_nl
    cmp bl, MAX_READ_TRIES
    jl read_drive_retry
    jmp $

read_drive_no_error:
    pop bx ; Pop old value of ax
    pop bx
    pop cx
    ret

;;; Prints character in register al
print_char:
    push ax
    push bx
    mov ah, 0x0e
    mov bl, 1
    mov bh, 0
    int 0x10
    pop bx
    pop ax
    ret

print_half_byte:
    pushfd
    and al, 0x0F
    add al, 48
    cmp al, 57
    jle skip_hex
    add al, 7
skip_hex:
    call print_char
    popfd
    ret
        
print_byte:
    push ax

    mov ax, [esp]
    shr al, 4
    call print_half_byte
    mov ax, [esp]
    mov ah, 0
    call print_half_byte

    pop ax
    ret

print_word:
    push ax
    mov al, ah
    call print_byte
    mov ax, [esp]
    call print_byte
    pop ax
    ret

print_nl:
    push ax
    mov al, 10
    call print_char
    mov al, 13
    call print_char
    pop ax
    ret

print_cm:
    push ax
    mov al, 44
    call print_char
    pop ax
    ret
        
[bits 32]
begin_pm:
    call OS_OFFSET
    hlt


times 506 - ($ - $$) db 0 ;padding

READ_TRY_COUNT db 0
DRIVE_N_HEADS db 0
DRIVE_SECTS_PER_TRACK db 0
BOOT_DRIVE db 0 ;0x7dfd
;above is data that can always be found at 0x7dfd - n during boot process

dw 0xaa55 ;magic boot sector number

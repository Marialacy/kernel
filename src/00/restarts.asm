; rst 0x08
kcall:
    push hl
    inc sp \ inc sp
    pop hl
    push hl
    dec sp \ dec sp
    push de
    push bc
    push af

    ; HL has return address, stack is intact
    dec hl
    ld (hl), 0
    inc hl

    ld a, (hl)
    cp 0xDD
    jr z, _
    cp 0xFD
    jr z, _
    cp 0xED
    jr nz, ++_
_:
    inc hl ; Handle IX/IY prefix
_:
    inc hl

    ld c, (hl)
    inc hl
    ld b, (hl)
    dec hl

    push hl
        ld hl, threadTable + 1
        ld a, (currentThreadIndex)
        add a, a
        add a, a
        add a, a
        add a, l
        ld l, a
        jr nc, $+3
        inc h

        ld e, (hl)
        inc hl
        ld d, (hl)
    pop hl

    ex de, hl
    add hl, bc
    ex de, hl

    ld (hl), e
    inc hl
    ld (hl), d

    pop af
    pop bc
    pop de
    pop hl
    ret

; rst 0x10
lcall:
    push hl
    inc sp \ inc sp
    pop hl
    push hl
    dec sp \ dec sp
    push de
    push bc
    push af
        dec hl
        ld (hl), 0
        inc hl

        ld a, (hl)
        ld (hl), 0
        ld c, a
        inc hl
        ex de, hl
        ld hl, libraryTable
        ld a, (loadedLibraries)
        ld b, a
lmacro_SearchLoop:
        ld a, (hl)
        cp c
        jr z, _
        inc hl \ inc hl \ inc hl \ inc hl
        djnz lmacro_SearchLoop
        ld a, panic_library_not_found
        jp panic

_:      inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        
        ex de, hl

        ld a, 0xDD ; Handle IX/IY cases
        cp (hl)
        jr z, _
        ld a, 0xFD
        jr nz, ++_
_:
        inc hl
_:
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        add hl, bc        
        ex de, hl
        ld (hl), d
        dec hl
        ld (hl), e
    
    pop af
    pop bc
    pop de
    pop hl
    ret

; rst 0x20
; Here be dragons
pcall:
    push af ; Save AF
        ld a, i
        jp po, .pcall_noInt
        ld a, i
        jp po, .pcall_noInt
    pop af
    push hl ; This will become .returnPoint
        push hl ; This will become the pcall address
            push hl ; This saves HL
            inc sp \ inc sp
        inc sp \ inc sp
    inc sp \ inc sp
pop hl \ push hl ; Grab return address
    push hl
        push hl
            dec sp \ dec sp
                ; HL is the byte following the RST that got us here
                push af
                    ld a, (hl)
                    inc hl
                    setBankA
                    ld a, (hl)
                    inc a
                    ; HL = 0x8000 - (A * 3)
                    ld h, 0x80
                    ld l, a
                    xor a
                    sub l \ jr nc, $+3 \ dec h
                    sub l \ jr nc, $+3 \ dec h
                    sub l \ jr nc, $+3 \ dec h
                    ld l, a
                    ; HL is now the address of the jump table call, back up in the stack
                pop af
            inc sp \ inc sp ; Saved HL
        inc sp \ inc sp ; pcall address
        push hl \ pop hl
    inc sp \ inc sp ; .returnPoint
    ld hl, .returnPoint
    push hl
        dec sp \ dec sp
            dec sp \ dec sp
            pop hl
        ret ; Jump to pcall
.returnPoint:
    ei
    ret
.pcall_noInt:
    pop af
    push hl ; This will become the pcall address
        push hl ; This saves HL
        inc sp \ inc sp
    inc sp \ inc sp
pop hl \ push hl ; Grab return address
    push hl
        dec sp \ dec sp
            ; HL is the byte following the RST that got us here
            push af
                ld a, (hl)
                inc hl
                setBankA
                ld a, (hl)
                inc a
                ; HL = 0x8000 - (A * 3)
                ld h, 0x80
                ld l, a
                xor a
                sub l \ jr nc, $+3 \ dec h
                sub l \ jr nc, $+3 \ dec h
                sub l \ jr nc, $+3 \ dec h
                ld l, a
                ; HL is now the address of the jump table call, back up in the stack
            pop af
        inc sp \ inc sp ; Saved HL
    inc sp \ inc sp ; pcall address
    push hl
        dec sp \ dec sp
        pop hl
    ret ; Jump to pcall

; rst $28
bcall:
    push hl
    push af
        ld hl, (bcallHook)
        xor a
        cp h
        jr nz, _
        cp l
        ; KnightOS doesn't provide bcall support on its own. However, 3rd party programs
        ; can hook into RST $28 and provide their own bcall mechanism. This is to make
        ; compatibility layers possible with KnightOS. However, if no bcall hook is set,
        ; we kill the originating thread. This is because use of a bcall implies that a
        ; TIOS program is running, and without a compatibility layer (especially considering
        ; that it's using bcalls), it's extremely likely to crash the system if allowed
        ; to continue.
        jp z, killCurrentThread
_:  ; We have a hook, call it
    pop af
    jp (hl)

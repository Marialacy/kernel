;; clearBuffer [Display]
;;  Turns off all pixels on a screen buffer.
;; Inputs:
;;  IY: Screen buffer
clearBuffer:
    push hl
    push de
    push bc
        push iy \ pop hl
        ld (hl), 0
        ld d, h
        ld e, l
        inc de
        ld bc, 767
        ldir
    pop bc
    pop de
    pop hl
    ret

#ifndef COLOR ; Color fastCopy is implemented in display_color.asm
;; fastCopy [Display]
;;  Copies the screen buffer to the LCD.
;; Inputs:
;;  IY: Screen buffer
;; Notes:
;;  This routine will return immediately without drawing to the LCD if the calling thead does not have an
;;  LCD lock. Acquire one with [[getLcdLock]].
;;  On a TI-84+ CSE, this routine will draw the 96x64 monochrome buffer (the "legacy" buffer) to the LCD.
;;  The LCD should be set to legacy mode (see [[setLegacyLcdMode]]).
fastCopy:
        call hasLCDLock
        ret nz
fastCopy_skipCheck:
        push hl
        push bc
        push af
        push de
            ld a, i
            push af
                di                    ;DI is only required if an interrupt will alter the lcd.
                push iy \ pop hl
    
                ld c, 0x10
                ld a, 0x80
.setRow:
                in f, (c)
                jp m, .setRow
                out (0x10), a
                ld de, 12
                ld a, 0x20
.col:
                in f, (c)
                jp m, .col
                out (0x10),a
                push af
                    ld b,64
.row:
                    ld a, (hl)
.rowWait:
                    in f, (c)
                    jp m, .rowWait
                    out (0x11), a
                    add hl, de
                    djnz .row
                pop af
                dec h
                dec h
                dec h
                inc hl
                inc a
                cp 0x2C
                jp nz, .col
            pop af
        jp po, _
        ei
_:  pop de
    pop af
    pop bc
    pop hl
    ret
#endif
    
;; putSpriteXOR [Display]
;;  Draws an 8xB sprite on the screen buffer using XOR (invert) logic.
;; Inputs:
;;  IY: Screen buffer
;;  HL: Sprite pointer
;;  D, E: X, Y
;;  B: Height
putSpriteXOR:
    push af
    push bc
    push hl
    push de
    push ix
        push hl \ pop ix
        call .clipSprXOR
    pop ix
    pop de
    pop hl
    pop bc
    pop af
    ret
    
.clipSprXOR:
        ; Start by doing vertical clipping
        ld a, 0b11111111            ; Reset clipping mask
        ld (clip_mask), a
        ld a, e                     ; If ypos is negative
        or a                        ; try clipping the top
        jp m, .clipTop
        sub 64                      ; If ypos is >= 64
        ret nc                      ; sprite is off-screen
        neg                         ; If (64 - ypos) > height
        cp b                        ; don't need to clip
        jr nc, .vertClipDone
        ld b, a                     ; Do bottom clipping by
        jr .vertClipDone            ; setting height to (64 - ypos)

.clipTop:
        ld a, b                     ; If ypos <= -height
        neg                         ; sprite is off-screen
        sub e
        ret nc
        push af
            add a, b                ; Get the number of clipped rows
            ld e, 0                 ; Set ypos to 0 (top of screen)
            ld b, e                 ; Advance image data pointer
            ld c, a
            add ix, bc
        pop af
        neg                         ; Get the number of visible rows
        ld b, a                     ; and set as height

.vertClipDone:
        ; Now we're doing horizontal clipping
        ld c, 0                     ; Reset correction factor
        ld a, d
        cp -7                       ; If 0 > xpos >= -7
        jr nc, .clipLeft            ; clip the left side
        cp 96                       ; If xpos >= 96
        ret nc                      ; sprite is off-screen
        cp 89                       ; If 0 <= xpos < 89
        jr c, .horizClipDone        ; don't need to clip

.clipRight:
        and 7                       ; Determine the clipping mask
        ld c,a
        ld a, 0b11111111
.findRightMask:
        add a, a
        dec c
        jr nz, .findRightMask
        ld (clip_mask), a
        ld a, d
        jr .horizClipDone
    
.clipLeft:
        and 7                       ; Determine the clipping mask
        ld c, a
        ld a, 0b11111111
.findLeftMask:
        add a, a
        dec c
        jr nz, .findLeftMask
        cpl
        ld (clip_mask), A
        ld a, d
        add a, 96                   ; Set xpos so sprite will "spill over"
        ld c, 12                    ; Set correction

.horizClipDone:
        ; A = xpos
        ; E = ypos
        ; B = height
        ; IX = image address

        ; Now we can finally display the sprite.
        ld h, 0
        ld d, h
        ld l, e
        add hl, hl
        add hl, de
        add hl, hl
        add hl, hl

        ld e, a
        srl e
        srl e
        srl e
        add hl, de

        push iy \ pop de
        add hl, de

        ld d, 0                    ; Correct graph buffer address
        ld e, c                    ; if clipping the left side
        sbc hl, de

        and 7
        jr z, .aligned

        ld c, a
        ld de, 11

.rowLoop:
        push bc
            ld b, c
            ld a, (clip_mask)        ; Mask out the part of the sprite
            and (ix)                 ; to be horizontally clipped
            ld c, 0

.shiftLoop:
            srl a
            rr c
            djnz .shiftLoop

            xor (hl)
            ld (hl), a

            inc hl
            ld a, c
            xor (hl)
            ld (hl), a

            add hl, de
            inc ix
        pop bc
        djnz .rowLoop
        ret

.aligned:
        ld de, 12

.putLoop:
        ld a, (ix)
        xor (hl)
        ld (hl), a
        inc ix
        add hl, de
        djnz .putLoop
        ret
    
;; putSpriteAND [Display]
;;  Draws an 8xB sprite on the screen buffer using AND (turns pixels OFF) logic.
;; Inputs:
;;  IY: Screen buffer
;;  HL: Sprite pointer
;;  D, E: X, Y
;;  B: Height
putSpriteAND:
    push af
    push bc
    push hl
    push de
    push ix
        push hl \ pop ix
        call .clipSprAND
    pop ix
    pop de
    pop hl
    pop bc
    pop af
    ret
    
.clipSprAND:
        ; Start by doing vertical clipping
        ld a, 0b11111111            ; Reset clipping mask
        ld (clip_mask), a
        ld a, e                     ; If ypos is negative
        or a                        ; try clipping the top
        jp m, .clipTop2

        sub 64                      ; If ypos is >= 64
        ret nc                      ; sprite is off-screen

        neg                         ; If (64 - ypos) > height
        cp b                        ; don't need to clip
        jr nc, .vertClipDone2

        ld b, a                     ; Do bottom clipping by
        jr .vertClipDone2           ; setting height to (64 - ypos)

.clipTop2:
        ld a, b                     ; If ypos <= -height
        neg                         ; sprite is off-screen
        sub e
        ret nc

        push af
            add a, b                ; Get the number of clipped rows
            ld e,0                  ; Set ypos to 0 (top of screen)
            ld b, e                 ; Advance image data pointer
            ld c, a                 ;
            add ix, bc
        pop af
        neg                         ; Get the number of visible rows
        ld b, a                     ; and set as height

.vertClipDone2:
        ; Now we're doing horizontal clipping
        ld c, 0                     ; Reset correction factor
        ld a, d

        cp -7                       ; If 0 > xpos >= -7
        jr nc, .clipLeft2           ; clip the left side

        cp 96                       ; If xpos >= 96
        ret nc                      ; sprite is off-screen

        cp 89                       ; If 0 <= xpos < 89
        jr c, .horizClipDone2       ; don't need to clip

.clipRight2:
        and 7                       ; Determine the clipping mask
        ld c, a
        ld a, 0b11111111
.findRightMask2:
        add a, a
        dec c
        jr nz, .findRightMask2
        ld (clip_mask), a
        ld a, d
        jr .horizClipDone2

.clipLeft2:
        and 7                       ; Determine the clipping mask
        ld c, a
        ld a, 0b11111111
.findLeftMask2:
        add a, a
        dec c
        jr nz, .findLeftMask2
        cpl
        ld (clip_mask), a
        ld a, d
        add a, 96                   ; Set xpos so sprite will "spill over"
        ld c, 12                    ; Set correction

.horizClipDone2:
        ; A = xpos
        ; E = ypos
        ; B = height
        ; IX = image address

        ; Now we can finally display the sprite.
        ld h, 0
        ld d, h
        ld l, e
        add hl, hl
        add hl, de
        add hl, hl
        add hl, hl

        ld e, a
        srl e
        srl e
        srl e
        add hl, de

        push iy \ pop de
        add hl, de

        ld d, 0                 ; Correct graph buffer address
        ld e, c                 ; if clipping the left side
        sbc hl, de

        and 7
        jr z, .aligned2

        ld c, a
        ld de, 11

.rowLoop2:
        push bc
            ld b, c
            ld a, (clip_mask)        ; Mask out the part of the sprite
            and (ix)                 ; to be horizontally clipped
            ld c, 0

.shiftLoop2:
            srl a
            rr c
            djnz .shiftLoop2

            cpl
            and (hl)
            ld (hl), a

            inc hl
            ld a, c
            cpl
            and (hl)
            ld (hl), a
            
            add hl, de
            inc ix
        pop bc
        djnz .rowLoop2
        ret

.aligned2:
        ld de, 12

.putLoop2:
        ld a, (ix)
        cpl
        and (hl)
        ld (hl), a
        inc ix
        add hl, de
        djnz .putLoop2
        ret
    
;; putSpriteOR [Display]
;;  Draws an 8xB sprite on the screen buffer using OR (turns pixels ON) logic.
;; Inputs:
;;  IY: Screen buffer
;;  HL: Sprite pointer
;;  D, E: X, Y
;;  B: Height
putSpriteOR:
    push af
    push bc
    push hl
    push de
    push ix
        push hl \ pop ix
        call .clipSprOR
    pop ix
    pop de
    pop hl
    pop bc
    pop af
    ret
    
.clipSprOR:
        ; Start by doing vertical clipping
        ld a, 0b11111111         ; Reset clipping mask
        ld (clip_mask), a
        ld a, e                  ; If ypos is negative
        or a                     ; try clipping the top
        jp m, .clipTop3

        sub 64                   ; If ypos is >= 64
        ret nc                   ; sprite is off-screen

        neg                      ; If (64 - ypos) > height
        cp b                     ; don't need to clip
        jr nc, .vertClipDone3

        ld b, a                  ; Do bottom clipping by
        jr .vertClipDone3        ; setting height to (64 - ypos)

.clipTop3:
        ld a, b                  ; If ypos <= -height
        neg                      ; sprite is off-screen
        sub e
        ret nc

        push af
            add a, b             ; Get the number of clipped rows
            ld e, 0              ; Set ypos to 0 (top of screen)
            ld b, e              ; Advance image data pointer
            ld c, a
            add ix, bc
        pop af
        neg                      ; Get the number of visible rows
        ld b, a                  ; and set as height

.vertClipDone3:
        ; Now we're doing horizontal clipping
        ld c, 0                  ; Reset correction factor
        ld a, d

        cp -7                    ; If 0 > xpos >= -7
        jr nc, .clipLeft3        ; clip the left side

        cp 96                    ; If xpos >= 96
        ret nc                   ; sprite is off-screen

        cp 89                    ; If 0 <= xpos < 89
        jr c, .horizClipDone3    ; don't need to clip

.clipRight3:
        and 7                    ; Determine the clipping mask
        ld c, a
        ld a, 0b11111111
.findRightMask3:
        add a, a
        dec c
        jr nz, .findRightMask3
        ld (clip_mask), a
        ld a, d
        jr .horizClipDone3

.clipLeft3:
        and 7                    ; Determine the clipping mask
        ld c, a
        ld a, 0b11111111
.findLeftMask3:
        add a, a
        dec c
        jr nz, .findLeftMask3
        cpl
        ld (clip_mask), a
        ld a, d
        add a, 96                ; Set xpos so sprite will "spill over"
        ld c, 12                 ; Set correction

.horizClipDone3:
        ; A = xpos
        ; E = ypos
        ; B = height
        ; IX = image address

        ; Now we can finally display the sprite.
        ld h, 0
        ld d, h
        ld l, e
        add hl, hl
        add hl, de
        add hl, hl
        add hl, hl

        ld e, a
        srl e
        srl e
        srl e
        add hl, de

        push iy \ pop de
        add hl, de

        ld d, 0                 ; Correct graph buffer address
        ld e, c                 ; if clipping the left side
        sbc hl, de

        and 7
        jr z, .aligned3

        ld c, a
        ld de, 11

.rowLoop3:
        push bc
            ld b, c
            ld a, (clip_mask)        ; Mask out the part of the sprite
            and (ix)                 ; to be horizontally clipped
            ld c, 0

.shiftLoop3:
            srl a
            rr c
            djnz .shiftLoop3

            or (hl)
            ld (hl), a

            inc hl
            ld a, c
            or (hl)
            ld (hl), a

            add hl, de
            inc ix
        pop bc
        djnz .rowLoop3
        ret

.aligned3:
        ld de, 12

.putLoop3:
        ld a, (ix)
        or (hl)
        ld (hl), a
        inc ix
        add hl, de
        djnz .putLoop3
        ret
    
;; putSprite16XOR [Display]
;;  Draws a 16xB sprite on the screen buffer using XOR (invert) logic.
;; Inputs:
;;  IY: Screen buffer
;;  HL: Sprite pointer
;;  D, E: X, Y
;;  B: Height
;; Notes:
;;  Each 16-wide group of pixels is represented by two adjacent octets.
putSprite16XOR: ; By Jon Martin
    push af
    push hl
    push bc
    push de
    push ix
        push hl \ pop ix
        ld a, d
        call .putSprite16XOR
    pop ix
    pop de
    pop bc
    pop hl
    pop af
    ret

.putSprite16XOR:                
    ld h, 0
    ld l, e
    ld d, h
    add hl, hl
    add hl, de
    add hl, hl
    add hl, hl
    push iy \ pop de
    add hl, de
    ld e, a
    srl e
    srl e
    srl e
    ld d, 0
    add hl, de
    ld d, h
    ld e, l
    and 7
    jp z, .aligned
    ld c, a
    ld de, 12
.rowLoop:
    push bc
        ld b, c
        xor a
        ld d, (ix)
        ld e, (ix + 1)
.shiftLoop:
        srl d
        rr e
        rra
        djnz .shiftLoop
        inc hl
        inc hl
        xor (hl)
        ld (hl), a
        ld a, e
        dec hl
        xor (hl)
        ld (hl), a
        ld a, d
        dec hl
        xor (hl)
        ld (hl), a    
    pop bc
    ld de, 12
    add hl, de
    inc ix
    inc ix
    djnz .rowLoop
    ret
.aligned:
    ld de, 11 
.alignedLoop:
    ld a, (ix)
    xor (hl)
    ld (hl), a
    ld a, (ix + 1)
    inc hl
    xor (hl)
    ld (hl), a
    add hl, de
    inc ix
    inc ix
    djnz .alignedloop
    ret

;; putSprite16OR [Display]
;;  Draws a 16xB sprite on the screen buffer using OR (turns pixels ON) logic.
;; Inputs:
;;  IY: Screen buffer
;;  HL: Sprite pointer
;;  D, E: X, Y
;;  B: Height
;; Notes:
;;  Each 16-wide group of pixels is represented by two adjacent octets.
putSprite16OR:
    push af
    push hl
    push bc
    push de
    push ix
        push hl \ pop ix
        ld a, d
        call .putSprite16OR
    pop ix
    pop de
    pop bc
    pop hl
    pop af
    ret

.putSprite16OR:                
        ld h, 0
        ld l, e
        ld d, h
        add hl, hl
        add hl, de
        add hl, hl
        add hl, hl
        push iy \ pop de
        add hl, de
        ld e, a
        srl e
        srl e
        srl e
        ld d, 0
        add hl, de
        ld d, h
        ld e, l
        and 7
        jp z, .alignedOR
        ld c, a
        ld de, 12
.rowLoopOR:
        push bc
            ld b, c
            xor a
            ld d, (ix)
            ld e, (ix + 1)
.shiftLoopOR:
            srl d
            rr e
            rra
            djnz .shiftLoopOR
            inc hl
            inc hl
            xor (hl)
            ld (hl), a
            ld a, e
            dec hl
            or (hl)
            ld (hl), a
            ld a, d
            dec hl
            or (hl)
            ld (hl), a    
        pop bc
        ld de, 12
        add hl, de
        inc ix
        inc ix
        djnz .rowLoopOR
        ret
.alignedOR:
        ld de, 11 
.alignedLoopOR:
        ld a, (ix)
        or (hl)
        ld (hl), a
        ld a, (ix + 1)
        inc hl
        or (hl)
        ld (hl), a
        add hl, de
        inc ix
        inc ix
        djnz .alignedLoopOR
        ret

;; putSprite16AND [Display]
;;  Draws a 16xB sprite on the screen buffer using AND (turns pixels OFF) logic.
;; Inputs:
;;  IY: Screen buffer
;;  HL: Sprite pointer
;;  D, E: X, Y
;;  B: Height
;; Notes:
;;  Each 16-wide group of pixels is represented by two adjacent octets.
putSprite16AND:
    push af
    push hl
    push bc
    push de
    push ix
        push hl \ pop ix
        ld a, d
        call .putSprite16AND
    pop ix
    pop de
    pop bc
    pop hl
    pop af
    ret

.putSprite16AND:                
        ld h, 0
        ld l, e
        ld d, h
        add hl, hl
        add hl, de
        add hl, hl
        add hl, hl
        push iy \ pop de
        add hl, de
        ld e, a
        srl e
        srl e
        srl e
        ld d, 0
        add hl, de
        ld d, h
        ld e, l
        and 7
        jp z, .alignedAND
        ld c, a
        ld de, 12
.rowLoopAND:
        push bc
            ld b, c
            xor a
            ld d, (ix)
            ld e, (ix + 1)
.shiftLoopAND:
            srl d
            rr e
            rra
            djnz .shiftLoopAND
            inc hl
            inc hl
            xor (hl)
            ld (hl), a
            ld a, e
            dec hl
            cpl
            and (hl)
            ld (hl), a
            ld a, d
            dec hl
            cpl
            and (hl)
            ld (hl), a
        pop bc
        ld de, 12
        add hl, de
        inc ix
        inc ix
        djnz .rowLoopAND
        ret
.alignedAND:
        ld de, 11
.alignedLoopAND:
        ld a, (ix)
        cpl
        and (hl)
        ld (hl), a
        ld a, (ix + 1)
        inc hl
        cpl
        and (hl)
        ld (hl), a
        add hl, de
        inc ix
        inc ix
        djnz .alignedLoopAND
        ret

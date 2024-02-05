* SER4 device driver for QIMSI
*
* This file is part of the QIMSI QL interface support software
*
* Copyright (C) 2023 Jan Bredenbeek
* 
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <https://www.gnu.org/licenses/>.
*
* VERSION HISTORY:
*
* v0.1 20231014 JB  Use STX1 and SRX1 as device names for SerNet
* v0.2 20231015 JB  Device names changed to SER4/STX4/SRX4, unrolled sendbyte loop
* v0.3 20231018 JB  Pending input routine now returns byte waiting in D1
*                   Open routine now clears input fifo

txdata0 equ     $fed2
txdata1 equ     $fed3
rxdata  equ     $fed4
status  equ     $fed5
txempty equ     0
rxempty equ     1
rxoverr equ     3

        include mt_inc
        include err_inc
        include vect_inc

sendbyte macro
i       setnum  0
loop    maclab
        moveq   #1,d0
        and.b   d1,d0
        tst.b   (a1,d0.w)
        ror.b   #1,d1
i       setnum  [i]+1
        ifnum   [i] < 8 goto loop
        endm

; physical definition block

        offset  0

; first six entries unused, but included to get A3 right during I/O

        ds.l    1       ; link to next EXTINT routine
        ds.l    1       ; address of EXITINT routine
        ds.l    1       ; link to next polled routine
        ds.l    1       ; address of polled routine
        ds.l    1       ; link to next scheduler routine
        ds.l    1       ; address of scheduler routine
;
dev_link ds.l    1       ; link to next driver
dev_io  ds.l    1       ; physical I/O routine (jsr io.serio)
dev_open ds.l   1       ; open routine
        ds.l    1       ; close routine
        ds.l    1       ; JSR instruction to io.serio (short)
        ds.l    1       ; address of pending i/o routine
        ds.l    1       ; address of fetch byte routine
        ds.l    1       ; address of send byte routine
        ds.w    1       ; RTS instruction
pend_flg ds.b   1       ; pending flag
pend_byt ds.b   1       ; pending input byte
phys_sz equ     *       ; length of physical definition block

        section dev_fifo

devinit:
        moveq   #phys_sz,d1     ; allocate physical def block
        moveq   #0,d2
        moveq   #mt.alchp,d0
        trap    #1
        tst.l   d0
        bne.s   initerr
        lea     dev_def,a3      ; set up pointers
        lea     dev_open(a0),a2
        bsr.s   getaddr         ; open routine
        bsr.s   getaddr         ; close routine
        move.l  a2,dev_io(a0)   ; physical i/o routine
        move.w  #$4eb8,(a2)+    ; jsr absolute short
        move.w  io.serio,(a2)+  ; to io_serio
        bsr.s   getaddr         ; pending i/o routine
        bsr.s   getaddr         ; fetch character
        bsr.s   getaddr         ; send character
        move.w  #$4e75,(a2)     ; rts
        lea     dev_link(a0),a0 ; address of device link
        moveq   #mt.liod,d0     ; link in driver
        trap    #1
initerr rts

* calculate and store the absolute addresses required for io_serio

getaddr move.w  (a3)+,a1                ; get relative pointer
        lea     -2(a3,a1.w),a1          ; make address absolute
        move.l  a1,(a2)+                ; and store it
        rts
                    
dev_def dc.w    open-*          ; open routine
        dc.w    close-*         ; close routine
        dc.w    pend-*          ; pending input
        dc.w    fetch-*         ; fetch character
        dc.w    send-*          ; send char (gives err.bp)

* open routine: check name and create channel if matched.          
          
open:
        move.w  (a0),d0
        subq.w  #4,d0
        blt.s   notf            ; must be at least 4 chars
        move.l  #$dfdfdfff,d0   ; ensure uppercase
        and.l   2(a0),d0
        cmpi.l  #'SER4',d0      ; check against 'SER4'
        beq.s   open2
        cmpi.l  #'SRX4',d0      ; and against 'SRX4'
        beq.s   open2
        cmpi.l  #'STX4',d0      ; and against 'STX4'
        bne.s   notf            ; exit if not
open2
        moveq   #$18,d1         ; just the bare minimum
        move.w  mm.alchp,a2
        jsr     (a2)            ; create channel definition block
        bne.s   op_rts          ; oops...
        
empty_f bsr.s   fetch           ; make sure receive fifo is empty
        beq     empty_f
        moveq   #0,d0           ; signal OK
op_rts  
        rts

notf    moveq   #err.nf,d0
        rts

* close: simply release channel def block          
          
close   move.w  mm.rechp,a2
        jmp     (a2)
          
* check for pending input
          
pend    tst.b   pend_flg(a3)    ; is there input pending?
        bne.s   pending         ; yes
        moveq   #err.nc,d0      ; assume no pending input
        btst    #rxempty,status ; is RX fifo empty?
        bne.s   pendrts         ; yes, return NC
        st      pend_flg(a3)    ; signal 'pending byte in buffer'
        move.b  rxdata,d1       ; fetch byte
        move.b  d1,pend_byt(a3) ; and store it for later
        moveq   #0,d0           ; return OK
pendrts rts

pending move.b  pend_byt(a3),d1 ; get pending byte
        moveq   #0,d0           ; return OK
        rts

fetch   bsr     pend            ; test for pending input
        bne.s   fetchrts        ; nothing to fetch
        sf      pend_flg(a3)    ; clear pending input buffer
fetchrts:
        tst.l   d0
        rts                     ; return (D0 and D1 have been set already)

send    btst    #txempty,status ; is there room in the fifo
        beq.s   send_nc         ; no, return NC
;        moveq   #8-1,d2         ; count 8 bits
        lea     txdata0,a1      ; NB: txdata1 is 1 higher
;send_lp moveq   #1,d0
;        and.b   d1,d0           ; keep only bit 0 of d1
;        tst.b   (a1,d0.w)       ; read txdata0 or txdata1 as per bit 0
;        ror.b   #1,d1           ; rotate data byte
;        dbra    d2,send_lp      ; loop for 8 bits
        sendbyte                ; unroll loop
        moveq   #0,d0           ; return OK
        rts
send_nc moveq   #err.nc,d0      ; TX fifo full, return NC
        rts

        end

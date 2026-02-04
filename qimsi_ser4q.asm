* QIMSI ser4 driver, mini-Q68 part
*
* This file is part of the QIMSI QL interface support software
*
* Copyright (C) 2023-2025 Jan Bredenbeek
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
* v0.1 20231021 JB  Initial version
* v0.2 20231023 JB  Config block added
* v0.3 20231206 JB  XON/XOFF implemented, A6 now points to dataspace
* v0.4 20260105 JB  Added support for second (USB) port

                include 'assert_inc'
                include 'err_inc'
                include 'q_inc'
                include 'MultiConfig02'

version         setstr  0.4

pc_intr         equ     $18021
mc_stat         equ     $18063
init_stk        equ     $1c000
led             equ     $1c100

; ser comms keys
uart_txdata     equ     $1c200
uart_rxdata     equ     $1c204
uart_status     equ     $1c208	        ; ser port status

ser2_offset     equ     $20             ; offset of I/O addresses of second port

link_txdata     equ     $1c260
link_rxdata     equ     $1c264
link_status     equ     $1c268

q68..txmpty     equ     0            ; Read-only Transmit Buffer Empty
q68..rxmpty     equ     1            ; Read-only Receive Buffer Empty
q68..rxfrerr    equ     2            ; Read-only Receive Frame Error
q68..rxovr      equ     3            ; Read-only Receive Overrun Error
q68..rxfull     equ     4            ; Read-only Receive FIFO Full
q68..txstat     equ     6            ; bit set to enable transmit interrupt
q68..rxstat     equ     7            ; bit set to enable receive interrupt
q68.rxand       equ     2            ; value to AND status with to check for rx bit
q68.txand       equ     1            ; value to AND status with to check for rx bit
uart_prescale   equ     $1c20c          ; word
q68_prty        equ     1               ; no parity
q68_hand        equ     0               ;no handshake
q68_prhd        equ     q68_prty<<8+q68_hand   ; parity and handshake combined

buffer          equ     $2000           ; address of receive buffer
dataspace       equ     $19000          ; start of dataspace
; following variables are offsets from dataspace
blcount         equ     0               ; (W) blinker counter
bl_rate         equ     2               ; (W) blink rate
xof_thrs        equ     4               ; (W) threshold for sending XOFF
xon_thrs        equ     6               ; (W) threshold for sending XON
xonxoff         equ     8               ; (B) use XON/XOFF flow control or not
xonxoffp        equ     9               ; (B) xon or xoff pending send
txhold          equ     10              ; (B) remote requested to hold
rxhold          equ     11              ; (B) we requested remote to hold
xon             equ     'Q'-$40         ; xon character itself
xoff            equ     'S'-$40         ; xoff character itself
datasize        equ     *

        section qimsi_ser4q
        
base:
        dc.l    init_stk        ; initial stackpointer ($1c000)
        dc.l    start-base      ; start of program
        dcb.l   22,except-base  ; vectors 8-$5c
        dcb.l   8,main_int-base ; interrupt vectors

        dcb.l   16,0            ; cfgmagic should be at base+$C0!

; pre-configured values

cfgmagic dc.l   'QIMS'         ; magic number
cfgrev   dc.w   2               ; revision number
cfgbaud  dc.l   115200          ; baudrate (0-8)
cfgbits  dc.b   8               ; number of databits
cfgflow  dc.b   1               ; flow control
cfgbuf   dc.w    $6000          ; receive buffer size
cfgport  dc.b   1               ; port number (1 or 2)

         ds.w   0

; CONFIG block should go here

        mkcfstart
        mkcfhead {QIMSI_SER4},{[version]}
        
          mkcfitem 'QIS1',long,'B',cfgbaud,,,\
          {Baudrate (1200-230400)},1200,230400

          mkcfitem 'QIS2',word,'S',cfgbuf,,,\
          {Receive buffer size (16-24576)},16,24576

          mkcfitem 'QIS3',code,'X',cfgflow,,,\
          {XON/XOFF flow control},0,N,{No},-1,Y,{Yes},1,T,{Transparent}
          
          mkcfitem 'QIS4',code,'D',cfgbits,,,\
          {Number of data bits},7,7,7,8,8,8
          
          mkcfitem 'QIS5',code,'P',cfgport,,,\
          {Port number},1,1,{1 (UART)},2,2,{2 (USB)}

        mkcfblend
        
        mkcfend

; Exception vectors for debugging
; set blink rate 1 second and enable blinking led

except:
        move.w  #50,bl_rate(a6) ; set blink rate (slow)
        andi.w  #$f8ff,sr       ; enable interrupts
forever bra.s   forever         ; keep looping

        assert  blcount,bl_rate-2

; interrupt routine to be enabled on exception or receiver overrun

main_int:
        movem.l d0-d7/a0-a6,-(a7)
        lea     dataspace,a6
        movem.w blcount(a6),d0-d1 ; get blink counter and rate
        subq.w  #1,d0
        blt.s   led_on          ; < 0 means turn LED on
        lsr.w   #1,d1
        cmp.w   d1,d0           ; has it reached half rate?
        bne.s   int_end         ; no, skip
        sf      led             ; LED off
        bra.s   int_end
led_on  
        st      led             ; LED on
        move.w  d1,d0           ; reset counter
int_end 
        move.w  d0,blcount(a6)
        st      pc_intr         ; clear interrupt
        movem.l (a7)+,d0-d7/a0-a6
        rte

prescale                        ; prescaled values according to baud rate
        dc.w    2082,1041,520,259,129,64,42,21,10
; bauds                           ; allowed baud values
;        dc.l    1200,2400,4800,9600,19200,38400,57600,115200,230400

start:
        lea     dataspace,a6
        move.l  a6,a0
        moveq   #datasize/4,d0
clr_dat 
        clr.l   (a0)+           ; clear dataspace (and a bit more)
        dbra    d0,clr_dat
        moveq   #0,d0
        move.b  cfgport,d0      ; port number (1 or 2)
        subq.w  #1,d0           ; make it 0 or 1
        mulu    #ser2_offset,d0
        lea     uart_status,a0
        add.w   d0,a0           ; get base address of port
        move.b  #4,mc_stat      ; set MODE 4
        st      led             ; turn led on
        move.l  #400000,d1      ; 40 MHz / 100
        move.l  cfgbaud(pc),d0  ; initial baudrate number
        divu    #100,d0         ; divide by 100
        divu    d0,d1           ; D1 = 40e6/baud
        lsr.w   #3,d1           ; divide by 8
        addq.w  #1,d1           ; d2 = (40e6/baud/8 + 1)
        lsr.w   #1,d1
        subq.w  #1,d1           ; d2 = (40e6/baud/8 + 1) / 2 - 1
        move.w  d1,uart_prescale-uart_status(a0) ; set prescaler
	move.w	#50,bl_rate(a6) ; blink rate for overrun indicator
        lea     buffer,a2       ; buffer address for queue routines
        move.w  cfgbuf(pc),d1   ; buffer size
        bsr     io_qset         ; set up input queue
        move.w  d1,d0
        lsr.w   #2,d0
        move.w  d0,xof_thrs(a6) ; xoff threshold < 25% of queue free
        sub.w   d0,d1
        move.w  d1,xon_thrs(a6) ; xon threshold > 75% of queue free
        move.b  cfgflow(pc),xonxoff(a6) ; configured flow control
        lea     link_status,a1  ; FIFO link to QL side
        moveq   #$df-256,d0
        and.b   d0,(a0)         ; why ?
        
; main loop

main:
        bsr     io_qtest        ; test queue status
        tst.w   d2              ; is there room in the queue?
        beq.s   overrun         ; no! enable overrun blinking led
        tst.b   xonxoff(a6)     ; flow control enabled?
        beq.s   get_uart        ; no, skip
        cmp.w   xof_thrs(a6),d2 ; has queue less space than XOFF threshold?
        blt.s   hold_rx         ; yes, send XOFF
        cmp.w   xon_thrs(a6),d2 ; less space than XON threshold?
        blt.s   get_uart        ; yes, skip
        tst.b   rxhold(a6)      ; XOFF sent to remote?
        beq.s   get_uart        ; no, skip
        move.b  #xon,xonxoffp(a6) ; send XON to remote
        sf      rxhold(a6)
        bra.s   get_uart
hold_rx 
        move.b  #xoff,xonxoffp(a6) ; signal 'send XOFF'
        st      rxhold(a6)      ; and set flag
get_uart
        moveq   #q68.rxand,d0
        and.b   (a0),d0         ; test rxempty bit
        bne.s   put_fifo        ; nothing to receive
        move.b  uart_rxdata-uart_status(a0),d1 ; get byte
        tst.b   xonxoff(a6)     ; flow control enabled?
        beq.s   put_q           ; no, skip
        cmp.b   #xoff,d1        ; received XOFF?
        bne.s   tst_xon
        st      txhold(a6)      ; hold transmit if so
        bra.s   put_fifo

tst_xon cmp.b   #xon,d1         ; received XON?
        bne.s   put_q
        sf      txhold(a6)      ; resume transmit
        bra.s   put_fifo
put_q
        bsr     io_qin          ; put it into the queue
        bra.s   put_fifo        ; put next byte into fifo
overrun
        move.w  #10,bl_rate(a6) ; set fast blinking rate
        andi.w  #$f8ff,sr       ; enable interrupts for blinking led
put_fifo
        moveq   #q68.txand,d0
        and.b   (a1),d0         ; is there room in the receive fifo?
        beq.s   test_tx         ; no, skip
        bsr     io_qout         ; get byte from queue
        bne.s   test_tx         ; got nothing so skip
        move.b  d1,link_txdata-link_status(a1) ; put byte into fifo
test_tx
        moveq   #q68.txand,d0
        and.b   (a0),d0         ; is uart ready for a new byte?
        beq     main            ; no, loop back
        move.b  xonxoffp(a6),d1 ; XON/XOFF pending?
        bne.s   put_uart        ; yes, send it
        tst.b   txhold(a6)      ; remote requested to hold transmission?
        bne     main            ; yes, do not send
        moveq   #q68.rxand,d0
        and.b   (a1),d0         ; is there a byte in the send fifo?
        bne     main            ; no, loop back
        move.b  link_rxdata-link_status(a1),d1 ; get byte
put_uart
        move.b  d1,uart_txdata-uart_status(a0) ; send it to RS232
        clr.b   xonxoffp(a6)    ; clear any pending XON/XOFF
        bra     main            ; and loop back

* Queue routines taken from Minerva

* Set up a queue

* d1 -ip - length of queue (max. bytes in queue + 1, d1.w = 1..32767, we hope!)
* a2 -ip - pointer to queue
* a3 destroyed

io_qset
        move.l  d1,-(sp)
        ext.l   d1
        bsr.s   io_qsetl
        move.l  (sp)+,d1
        rts

* As above, but d1.l is used to set long queues!

io_qsetl
        lea     q_queue(a2,d1.l),a3 set pointer to end of queue
        clr.l   (a2)+           clear eoff and nextq
        move.l  a3,(a2)+        set end
        sub.l   d1,a3           start the queue in an arbitrary place = bottom
        move.l  a3,(a2)         set nextin
        move.l  a3,-(a3)        and nxtout
        subq.w  #q_nextin,a2    restore queue pointer
        rts

* Test status of a queue

* d0 -  o- error flag - 0, queue empty (nc) or eof
* d1 -  o- next byte in queue (all but d1.b preserved)
* d2 -  o- spare space in queue (bits 31..15 always zero)
* a2 -ip - pointer to queue
* a3 destroyed

io_qtest
        movem.l q_nextin(a2),d2/a3 get pointer to next bytes in/out
        move.b  (a3),d1         show caller next byte
        sub.l   a3,d2           set difference between in and out
        blt.s   set_spar        negative: wrapped, so just complement this
        bgt.s   set_wrap        positive: must take off the wrap length
        bsr.s   set_wrap        zero: queue empty, but we must still set space
say_why
        moveq   #err.ef,d0      end of file
        tst.b   (a2)            is it eof?
        bmi.s   rts0            yep - ccr is ok for that
err_nc
        moveq   #err.nc,d0      not complete
rts0
        rts

set_wrap
        moveq   #-q_queue,d0
        sub.l   a2,d0
        add.l   q_end(a2),d0    this is the overall queue area
        sub.l   d0,d2           so this'll be the free space, when complemented
set_spar
        not.l   d2              zero will mean no spare space in queue
        move.w  #32767,a3       we must return a positive word
        cmp.l   a3,d2
        bls.s   say_ok
        move.l  a3,d2           if the queue is oversize, return a max value
say_ok
        moveq   #0,d0
        rts

* Put bytes into a queue

* d0 -  o- error flag - queue full
* d1 -ip - byte to put in queue (discarded with no error if eof set)
* a2 -ip - pointer to queue
* a3 destroyed

io_qin
        tst.b   (a2)            is it eof? (eoff)
        bmi.s   say_ok          ... yes - throw it away (!!!)
        move.l  q_nextin(a2),a3 get pointer to end of queue
        move.b  d1,(a3)+        put byte regardless (there's alway a gap)
        cmp.l   q_end(a2),a3    is next pointer off end of queue
        blt.s   chk_next
        lea     q_queue(a2),a3  next is start of queue
chk_next
        cmp.l   q_nxtout(a2),a3 is queue full
        beq.s   err_nc
        move.l  a3,q_nextin(a2) save pointer to next in queue
        bra.s   say_ok

* Fetch bytes out of a queue

* d0 -  o- error flag - queue empty, and possibly at eof
* d1 -  o- byte from queue
* a2 -ip - pointer to queue
* a3 destroyed

io_qout
        move.l  q_nxtout(a2),a3 get pointer to next byte
        cmp.l   q_nextin(a2),a3 is there anything in queue
        beq.s   say_why         no - go tell caller nc/eof
        move.b  (a3)+,d1        fetch byte
        cmp.l   q_end(a2),a3    is next pointer off end of queue
        blt.s   save_out
        lea     q_queue(a2),a3  next is start of queue
save_out
        move.l  a3,q_nxtout(a2) save pointer to next in queue
        bra.s   say_ok

        end

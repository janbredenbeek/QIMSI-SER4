HIGH-SPEED SERIAL DRIVER FOR QIMSI
----------------------------------
QIMSI is a new multifunctional peripheral for the Sinclair QL which plugs into the extension ROM slot. It offers mass storage through micro-SDHC cards, a PS/2 mouse interface, a PS/2 external keyboard interface and sampled sound output. Details can be found at https://qlforum.co.uk/viewtopic.php?t=4534, ordering info at https://qlforum.co.uk/viewtopic.php?t=4535.

It is also equipped with a high-speed serial port which is controlled by the 'mini-Q68' FPGA chip. It offers speeds up to 230400 baud, which can be used to connect the QL to a PC or Q68 via SERnet. This driver is provided to make this port available as a new 'SER4' device.

Precautions
-----------
First of all: read the QIMSI manual, in particular the section describing the serial interface.

The serial interface is on the right-hand side of the QIMSI board as seen on the component side with the QL connector under (see page 4 of the QIMSI manual). It is recommended to solder three header pins onto the connector pads, on which you can solder the serial cable to (of course, assumed you have sufficient soldering skills or leave it to someone who have them!). The pin layout is as follows:

- pin 1: Ground (closest to the QL connector, also marked with a square pad)
- pin 2: TX Data (output)
- pin 3: RX Data (input, farthest from the QL connector).

When connecting to the DB-9 RS-232 connector on a PC or Q68, the wiring should be as follows:

| QIMSI | PC/Q68 |
|-------|--------|
|   1   |   5    |
|   2   |   2    |
|   3   |   3    |

NOTE: This assumes you have a straight-through cable between QIMSI and the other end. If you have a null-modem cable (used to connect two computers together), pins 2 and 3 will have to be reversed. If in doubt, please check the wiring using a multimeter. QIMSI's serial port has only minimal buffering so it's very likely that wrongly connecting pins 2 and 3 will fry your QIMSI, especially with PC ports which use 'real' RS-232 signal levels of +12 and -12 volts (unlike the Q68). The risk is entirely yours!

You may have noticed that QIMSI's serial interface lacks the RTS and CTS lines, used for hardware flow control. This is a bit unfortunate, as flow control now has to be done in software using the XON/XOFF protocol, or by sending data in blocks of certain size and waiting for the other end to acknowledge receipt, which degrades the speed at which you can transfer data. Using a line speed of 115200 baud, the maximum theoretical throughput you could achieve would be around 11K bytes per second. In practice, using SERnet between QIMSI and a Q68, we have achieved a throughput of around 4K bytes with the QL receiving and 8.5K bytes with the QL sending using a QL with Gold Card. Note that the latter speed is still twice as fast as the 'QLAN' network, and SERnet has the advantage that it can be used to connect a QL and a PC running QPC2.

Loading and activating the driver
---------------------------------
The QL part of the driver can simply be loaded using LRESPR <device>ser4_bin. You will now have an extra serial port named SER4 (the QL's original SER1 and SER2 ports will remain available, as will an optional SER3 interface such as superHermes). Note that SER4 accepts optional parameters for parity (O/E/M/S), flow control (I/H), and protocol (R/Z/C), but they are currently ignored (i.e. it always uses no parity, raw protocol and flow control is handled differently, see below).

In addition to SER4, this driver supports the SRX4/STX4 ports for receive-only and transmit-only channels, as required by the SERnet device. Whilst you cannot open a SRX4 channel to a port that has already been opened to SER4 and vice versa, you can open an STX channel to an already open SER4/SRX4 port. The original SMSQ/E specification allowed an unlimited number of STX channels to be opened to the same port, but this feature is currently not implemented (it was probably meant to send lots of individual files to a printer in quick succession, using transmit buffers of insane size, which I can hardly imagine a use case for nowadays).

Since QIMSI's serial port is controlled by the mini-Q68 chip, which runs independently of the QL, this driver has two parts. The code which runs on the mini-Q68 side (Q68_ROM.SYS) is a small 68000 machine code program that is loaded by the mini-Q68 on startup. It should be placed onto the micro-SD card, along with your QLWAx.WIN containers. Note that the same rules apply for the Q68_ROM.SYS file as for the .WIN containers: the file must be in contiguous sectors and within the first 16 entries in the FAT32 root directory. If you have deleted some files from this FAT32 partition first and then add new files, there is a big chance that the newly added files will **not** be in contiguous sectors (especially when using Windows) and loading Q68_ROM.SYS may fail. You can check if the Q68_ROM.SYS has loaded successfully by looking at QIMSI's LED; it should light up green within seconds after the QL has been turned on (while the QL is still booting).

The usual QL commands which control baudrate, buffer sizes and so on, have no effect on QIMSI's SER4 interface. There are two ways to configure them:

- Use the well-known **menuconfig** program (see https://dilwyn.qlforum.co.uk/config/index.html) to configure the Q68_ROM.SYS file. As this cannot be done from the QL itself, you will need a PC with access to the FAT32 partition and an emulator such as QPC2.
- Use the qimsi_sercfg program to configure the parameters from the QL itself. The syntax is EW qimsi_sercfg;"\<baudrate\> [databits [flowctrl [bufsize]]]". After this, you have to power-cycle the QL to activate the new settings.

The following properties can be configured:

- Baud rate. This speaks for itself. You can set all common rates from 1200 to 230400 baud. The only restriction is that it has to be a multiple of 100.
- Number of databits (7 or 8, usually 8).
- Receiver buffer size. You can specify sizes from 0 to 24K bytes. Since QIMSI cannot use hardware flow control, it is recommended to set this size as large as possible to avoid loss of data due to receiver overrun (people who have fought with the QL's dreaded SER1/SER2 ports will remember what I mean!). As the QL is quite slow with processing incoming data (even to RAM disk), it's better to avoid sending blocks of data larger than the receive buffer. If a receiver overrun happens, QIMSI will signal this by flashing its green LED on and off continually. It will keep working normally however, but the flashing will continue until you switch your QL off (there is currently no other way to reset the mini-Q68).\
Note that QIMSI has internal hardware FIFOs of 1K byte between the QL and mini-Q68 side in both the transmit and receive path. The receive buffer mentioned here is software-based and may be used for software flow control using XON/XOFF (see below).
- Flow control: May be either off (0, no flow control), or XON/XOFF(1). The XON/XOFF option attempts to control the incoming data flow by sending a XOFF character when the receive buffer is almost full, and sending a XON when the buffer has been emptied sufficiently. It also honours XON/XOFFs sent by the remote side when transmitting.\
This feature may not always work and is not transparent; if the data itself contains XON/XOFF characters (11h/13h) it will fail. 

Bugs
----
Lots of :-). Much of the code is still in development. However since there appears to be demand for it and I've been busy with other projects, I've decided to release it to the public. Please report any bugs in the Issues section.

Contributors
------------
The QIMSI interface itself is designed by Peter Graf, who also contributed the initial Q68_ROM.SYS code in C and the qimsi_sercfg program.

The SER4 driver is written by Jan Bredenbeek, who also rewrote and extended the Q68_ROM.SYS code in assembly.

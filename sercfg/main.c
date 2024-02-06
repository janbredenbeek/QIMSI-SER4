/*
 * SERCFG v1.0 
 *
 * Allows configuration of the QIMSI serial port from the QL
 * Usage: EW qimsi_sercfg;"<baudrate> [databits [flowctrl [bufsize]]]"
 * This file is part of the QIMSI Test software
 *
 * Copyright (C) 2023 Peter Graf
 * Copyright (C) 2024 Jan Bredenbeek
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, If not, see 
 * <https://www.gnu.org/licenses/>.
 *
 * VERSION HISTORY:
 *
 * v1.0 JB corrected error in parameter parsing, display current values
 *
 * v0.0 PG initial version
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "sdhc.h"

extern char* _endmsg;
timeout_t	_endtimeout = 250; // End message will be displayed for 5 seconds

typedef struct 
{
  unsigned int magic;
  unsigned short revision;
  unsigned int baudrate;
  unsigned char databits;
  unsigned char flowctrl;
  unsigned short bufsize;
} config_block;

config_block config;

unsigned char buf[512];
unsigned int startblock;
unsigned int size;

int main(int argc, char **argv)
{
  int ret;
  
  sdhc_card_select(1);
  ret = getfile_FAT32(buf, "Q68_ROM SYS", &startblock, &size);
  if (ret < 0)
  {
    sdhc_card_select(0);
    _endmsg = "Error: Could not access SDHC card";
    return -1;
  }
  else if (ret == 0)
  {
    sdhc_card_select(0);
    _endmsg = "Error: Q68_ROM.SYS not found";
    return -1;
  }
  sdhc_read_sector (startblock, buf);
  memcpy(&config, &buf[0xC0], sizeof(config_block));
  if (config.magic != 0x51494D53)  // magic number not 'QIMS'
  {
    sdhc_card_select(0);
    _endmsg = "Error: Unsupported ROM type";
    return -1;
  }
  if (config.revision < 1)
  {
    sdhc_card_select(0);
    _endmsg = "Error: ROM version too old";
    return -1;
  }
  printf("Current values:\n\n");
  printf("Baud rate: %u\n", config.baudrate);
  printf("Data bits: %u\n", config.databits);
  printf("Flow control: %u\n", config.flowctrl);
  printf("Receive buffer size: %u\n\n", config.bufsize);
  if (argc >= 2)
  {
    config.baudrate = atoi(argv[1]);
    if (argc >= 3)
      config.databits = atoi(argv[2]);
    if (argc >= 4)
      config.flowctrl = atoi(argv[3]);
    if (argc >= 5)
      config.bufsize = atoi(argv[4]);
    memcpy(&buf[0xC0], &config, sizeof(config_block));
    sdhc_write_sector (startblock, buf);
    sdhc_card_select(0);
    printf("New values:\n\n");
    printf("Baud rate: %u\n", config.baudrate);
    printf("Data bits: %u\n", config.databits);
    printf("Flow control: %u\n", config.flowctrl);
    printf("Receive buffer size: %u\n\n", config.bufsize);
    _endmsg = "Success: QIMSI MiniQ68 ROM image configured";
    return 0;
  }
  else
  {
    _endmsg = "Usage: qimsi_sercfg <baudrate> [databits [flowctrl [bufsize]]]";
    return -1;
  }
}

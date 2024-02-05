/*
 * This file is part of the Q68 Test software
 *
 * Copyright (C) 2007 Peter Graf <pgraf@q40.de>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#ifndef SDHC_H
#define SDHC_H

int getfile_FAT32(unsigned char buf[], char filename[], unsigned int* startblock, unsigned int* size);
unsigned char sdhc_read_sector (unsigned long addr, unsigned char* buffer);
unsigned char sdhc_write_sector (unsigned long addr, unsigned char* buffer);
void sdhc_card_select (unsigned char n);

#endif /* SDHC_H */

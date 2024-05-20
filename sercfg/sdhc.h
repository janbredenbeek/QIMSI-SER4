#ifndef SDHC_H
#define SDHC_H

int getfile_FAT32(unsigned char buf[], char filename[], unsigned int* startblock, unsigned int* size);
unsigned char sdhc_read_sector (unsigned long addr, unsigned char* buffer);
unsigned char sdhc_write_sector (unsigned long addr, unsigned char* buffer);
void sdhc_card_select (unsigned char n);

#endif /* SDHC_H */

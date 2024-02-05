#include "sdhc.h"

#define IF_ENABLE (dummy = *(volatile unsigned char*) 0xFEE0)
#define IF_DISABLE (dummy = *(volatile unsigned char*) 0xFEE1)
#define SPI_READ (* (volatile unsigned char*) 0xFEE4)
#define SPI_WRITE(x) (dummy = *(volatile unsigned char*) (0xFF00+x))

static volatile char dummy;

void sdhc_card_select (unsigned char n)
{
  dummy = *(volatile unsigned char*) (0xFEF0+n);
}

/* Sends a command to SDHC card using background transfer
   Used for non-bitbanging block read/write operations
   Might not be save during initialisation */
unsigned char sdhc_write_command_bg (unsigned char* cmd)
{
  unsigned char a, tmp;
  volatile unsigned short timeout;
  
  /* Dummy write, sends 8 clock pulses */
  SPI_WRITE(0xFF);

  /* Sends 6 Byte Command to SDHC card */
  for (a = 0;a<0x06;a++)
  {
    SPI_WRITE(*cmd++);
  }

  /* Wait for valid answer from SDHC card */
  tmp = 0xff;
  timeout = 0;
  while (tmp == 0xff)
  {
    SPI_WRITE(0xFF);
    tmp = SPI_READ;
    /* Try high value, because we run fast now */
    if (timeout++ > 1000)
      break; /* Terminate, SDHC card did not answer*/
  }
  return tmp;
}

/* Routine to write a block (512 Bytes) to SDHC card */
unsigned char sdhc_write_sector (unsigned long addr, unsigned char* buffer)
{
  unsigned char tmp;
  unsigned short a;
  unsigned char cmd[6];
  
  cmd[0]=0x58; cmd[1]=0x00; cmd[2]=0x00; cmd[3]=0x00; cmd[4]=0x00; cmd[5]=0xFF;

  /* SDHC */
  /* Addressing of MMC/SD-Cards was in Bytes */
  /* addr = addr << 9; */ /* addr = addr * 512 */

  cmd[1] = addr >>24;
  cmd[2] = addr >>16;
  cmd[3] = addr >>8;
  cmd[4] = addr;

  IF_ENABLE;

  /* Send Command cmd24 to SDHC-Card (Write 1 block/512 Bytes) */
  tmp = sdhc_write_command_bg(cmd);
  if (tmp != 0)
  {
    return(tmp);
  }

  /* Wait a moment and send clocks to SD/MMC card */
  /* *** Really 100 reads needed? Other implementation had just one *** */
  /* for (a=0;a<100;a++)  sdhc_read_byte(); */
  SPI_WRITE(0xFF);
  tmp = SPI_READ;

  /* Send Start Byte to SDHC card */
  SPI_WRITE(0xFE);

  /* Write Block (512 Bytes) to SDHC card */
  for (a=0;a<512;a++)
  {
    SPI_WRITE(*buffer++);
  }

  /* Write 2 CRC Bytes. Dummy values. CRC codes not used */
  SPI_WRITE(0xFF);
  SPI_WRITE(0xFF);

  /* No actual write, just make sure the last XFER is over, before we continue */
  /* SDHC1_WRITE = 0xFF; */

  /* Wait while SDHC card is busy */
  do
  {
    SPI_WRITE(0xFF);
  }
  while (SPI_READ != 0xff);
  /* Note: this transfers an extra byte, even after $FF is received,
     but we probably don't have to care */

  /* Set hardware chip select to high (SDHC card inactive) */
  IF_DISABLE;

  return(0);
}

/* Routine to read a block (512 Bytes) from SDHC card */
unsigned char sdhc_read_sector (unsigned long addr, unsigned char* buffer)
{
  unsigned short a;
  unsigned char cmd[6];
  unsigned char tmp;
  
  /* SDHC */
  /* Addressing of MMC/SD-Cards was in Bytes */
  /* addr = addr << 9; */ /* addr = addr * 512 */

  cmd[0] = 0x51;
  cmd[1] = addr >>24;
  cmd[2] = addr >>16;
  cmd[3] = addr >>8;
  cmd[4] = addr;
  cmd[5] = 0xFF;

  IF_ENABLE;

  /* Sends Command cmd 16 to SDHC card */
  if (sdhc_write_command_bg(cmd) != 0)
  {
    IF_DISABLE;
    return -1;
  }
  /* Wait for Start Byte from SDHC Card (FEh/Start Byte) */
  do
  {
    // This was needed in case we didn't use background transfer for command
    // SDHC1_WRITE = 0xFF;
    SPI_WRITE(0xFF);
    tmp = SPI_READ;
  }
  while (tmp != 0xFE);

  /* Read Block (normally 512 Bytes) from SDHC Card */
  for (a=0;a<512;a++)
  {
    // *buffer = sdhc_read_byte();
    SPI_WRITE(0xFF); *buffer = SPI_READ; buffer++;
  }

  /* 2 CRC-Bytes auslesen */
  SPI_WRITE(0xFF); /* CRC - Byte wird nicht ausgewertet */
  tmp = SPI_READ;
  SPI_WRITE(0xFF);
  tmp = SPI_READ;

  /* Set hardware chip select line high (SDHC Card inactive) */
  IF_DISABLE;

  return 0;
}


/* ----------------------------------------------------------------------- */
/* Detection of file in root directory of FAT32 formatted card             */
/* Return value -1=Error 0=Not detected, 1=Detected,                       */
/* Filename like this: "Q68_ROM SYS"                                       */
/* ----------------------------------------------------------------------- */

int getfile_FAT32(unsigned char buf[], char filename[], unsigned int* startblock, unsigned int* size)
{
  unsigned long off;
  unsigned long partition_start;
  unsigned long bytes_per_sector, sectors_per_cluster, res_sector_count,
    number_of_fats, sectors_per_fat, data_start, rootdir_start;
  unsigned short i;

  *startblock = 0;
  *size = 0;
  
  /* Read Master boot record */
  sdhc_read_sector(0, buf);
  if ((buf[0x1BE] != 0x00) && (buf[0x1BE] != 0x80))
  {
    /* Error: First primary partition missing */
    return -1;
  }
  partition_start = ((unsigned long)buf[0x1C9]<<24) | ((unsigned long)buf[0x1C8]<<16) |
  ((unsigned long)buf[0x1C7]<<8) | buf[0x1C6];
  /* First primary partition is at partition_start */

  /* Read Boot sector */
  sdhc_read_sector(partition_start, buf);
  if ((buf[0x52]!='F') || (buf[0x53]!='A') || (buf[0x54]!='T') ||
      (buf[0x55]!='3') || (buf[0x56]!='2'))
  {
    /* Error: No FAT32 partition */
    return -1;
  }
    
  bytes_per_sector = 0x100*buf[0x0C] + buf[0x0B];
  if (bytes_per_sector != 512)
  {
    /* Error: Bytes per sector not 512 */
    return -1;
  }
  sectors_per_cluster = buf[0x0d]; /* Powers of two from 1 to 128 */
  res_sector_count = ((unsigned long)buf[0x0F]<<8) | buf[0x0E];
  number_of_fats = buf[0x10];
  sectors_per_fat = ((unsigned long)buf[0x27]<<24) | ((unsigned long)buf[0x26]<<16) |
  ((unsigned long)buf[0x25]<<8) | buf[0x24];
  /* FAT32 Data Region Start */
  data_start = partition_start + res_sector_count +
    number_of_fats*sectors_per_fat;
  /* Important: cluster-2 for translation to sector */
  /* FAT32 Root Directory */
  rootdir_start = data_start + sectors_per_cluster*
  ((((unsigned long)buf[0x2F]<<24) | ((unsigned long)buf[0x2E]<<16) | ((unsigned long)buf[0x2D]<<8) | buf[0x2C]) - 2);

  /* Read Root directory */
  sdhc_read_sector(rootdir_start, buf);
  for(off=0; off<0x200; off+=0x20)
  {
    if (buf[off] == 0x00) /* No subsequent entry */
      break;
    for (i=0; i<11; i++)
    {
      if (buf[off+i] != filename[i]) break;
    }
    if (i==11)
    {
      *startblock = data_start + sectors_per_cluster * ((((unsigned long)buf[off+0x15]<<24) |
        ((unsigned long)buf[off+0x14]<<16) | ((unsigned long)buf[off+0x1B]<<8) | buf[off+0x1A]) - 2);
      /* Filename found */
      *size = ((unsigned long)buf[off+0x1F]<<24) | ((unsigned long)buf[off+0x1E]<<16) |
           ((unsigned long)buf[off+0x1D]<<8) | buf[off+0x1C];
      return 1;
    }
  }
  return 0;
}

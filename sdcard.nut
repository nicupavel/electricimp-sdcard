/* SDCard SPI bridge */

/* Author: Nicu Pavel <npavel@linuxconsulting.ro */
/* https://www.sdcard.org/downloads/pls/simplified_specs/ */
const SD_INIT_TIMEOUT = 2000;
/* SDCard IO commands */
const CMD0 = 0x00; /* GO_IDLE_STATE put SDCARD into idle state*/
const CMD1 = 0x01; /* SEND_OP_COND wait for SDCARD to get out of busy loop non-SDHC */
const CMD8 = 0x08; /* SEND_IF_COND verify SD Memory Card interface operating condition */
const CMD13 = 0x0D; /* SEND_STATUS read the card status register */
const CMD16 = 0x10; /* SET_BLOCK_SIZE */
const CMD17 = 0x11; /* READ_SINGLE_BLOCK read a block from an byte address */
const CMD24 = 0x18; /* WRITE_BLOCK write a single block to a byte address */
const ACMD41 = 0x29; /* SEND_OP_COND start card initialization */
const CMD55 = 0x37; /* APP_CMD escape for application specific command */
const CMD58 = 0x58; /* READ_OCR register command */

/* SDCARD register commands (like IO commands)*/
const REG_CSD = 0x09; /* send card specific data */
const REG_CID = 0x0a; /* send card indentification */

/* SDCARD Response codes */
const R1_READY_STATE = 0x00;
const R1_IDLE_STATE  = 0x01;
const R1_ILLEGAL_COMMAND = 0x04;
const DATA_RES_MASK = 0x1f;
const DATA_RES_ACCEPTED = 0x05;

/* SDCARD tokens */
const DATA_START_BLOCK = 0xfe;

/* SDCARD test sectors */
const testBlocks = "\x00\x01\x02\x03\x04\x05\x1f\xfe\xff";
class spiBridge
{
	/* port = hardware.spi189, clk = hardware.pin1, cs = hardware.pin2, si = hardware.pin8, so = hardware.pin9 */
	constructor(clock) //min 100 KHz
	{
		//hardware.configure(SPI_189);
        server.log("SPI configured at " + hardware.spi189.configure(0, clock) + "KHz");
	    hardware.pin2.configure(DIGITAL_OUT); //ChipSelect
	    
        hardware.pin2.write(0);
	    imp.sleep(0.01);
	    hardware.pin2.write(1);
	}
	
	function cs(state) 
    {
        /*server.log(format("Set CS to %d", state));*/
        hardware.pin2.write(state); 
        imp.sleep(0.001); 
        if (state) write(0xff); 
    }
    
    function write(data) 
    { 
        //server.log(format("Write: 0x%02x", data)); 
        hardware.spi189.write(format("%c", data)); 
    }
    
    function read() 
    { 
        write(0xff); //dummy write
        local data = hardware.spi189.read(1);
        
        if(data == null)
        {
            //server.log("SPI Read Failure");
            return -1;
        }
        //server.log(format("Read: %x", data[0]));
        return data[0];
    }
}

class SDCardIO extends spiBridge
{
	cardType = 0;
    sdhcSupport = false;
    commBuf = null;
    initialised = false;
        
	constructor()
	{
        commBuf = blob(512);
        commBuf.flush();
		base.constructor(4000);
	}
    
	function waitNotBusy(ms)
    {
        local retry = 0;
        
        while(read() != 0xff && retry < ms)
        {
            imp.sleep(0.001);
            retry++;
        }
        
        if (retry < ms)
            return true;
        
        return false;
    }
    
	function sendCommand(cmd, param)
	{
        
        local crc = 0x01;
        local response;
        local retry = 0;
        
        cs(0);
        
        waitNotBusy(300);
        
		write(cmd | 0x40);
        write((param & 0xff000000) >> 24);    
        write((param & 0x00ff0000) >> 16);
        write((param & 0x0000ff00) >> 8);
        write((param & 0x000000ff));        
        
        
        if (cmd == CMD0) crc = 0x95; //Valid CRC for GO_IDLE_STATE //TODO add CRC
        if (cmd == CMD8) crc = 0x87; //Valid CRC for CMD8 with 0x1aa arg others don't matter if card not setup in CRC mode
        write(crc);
        
		//Wait for valid response
        while (((response = read()) & 0x80)) 
        { 
            retry++;
            imp.sleep(0.001);
            if (retry >= SD_INIT_TIMEOUT) 
            {
                server.log("Timeout waiting for command reply");
                break;
                //return 0xff;
            }
        }
        //server.log(format("Got reply: 0x%02x for command 0x%02x after %d clocks", response, cmd, retry));
        return response;
	}
    
    function sendAdvCommand(cmd, param)
    {
        sendCommand(CMD55, 0x00);
        return sendCommand(cmd, param);
    }
    
    function initSDCard()
    {
        local i;
        local retry = 0;
        local r;
        local busyType = 0x00;
        
        cs(1);
        for (i = 0; i < 10; i++) //~80 pulses
            write(0xff);
            
        while (((r = sendCommand(CMD0, 0x00)) != R1_IDLE_STATE) && (retry < SD_INIT_TIMEOUT)) { imp.sleep(0.001); retry++; }
                
        if (retry < SD_INIT_TIMEOUT)
        {
            server.log("Card in idle mode");
        }
        else
        {
            server.log("Card in unknown state or not inserted");
            return false;
        }   
        
        retry = 0;
        //TODO set CRC on for SDCARD CRC mode
        
        //Detect card spec type
        if (sendCommand(CMD8, 0x1AA) & R1_ILLEGAL_COMMAND)
        {
            server.log("Card type SD1");
            cardType = 1;
        }
        else
        {
            local extreply;
            for (i = 0; i < 4; i++) extreply = read();
            if (extreply != 0xaa)
            {
                server.log("Unknown reply from card");
                return false;
                
            }
            server.log("Card type SD2");
            cardType = 2;
            busyType = 0x40000000;
        }
        
        server.show("Waiting for SDCard to be ready ...");
        retry = 0;
        //For old type cards
        //while ((cardType == 1) && ((r = sendCommand(CMD1, 0x00)) != R1_READY_STATE) && (retry < 0x2000)) {imp.sleep(0.001); retry++; }
        //For newer cards
        //while ((cardType == 2) && ((r = sendAdvCommand(ACMD41, param)) != R1_READY_STATE) && (retry < 0x2000)) {imp.sleep(0.001); retry++; }
        while (((r = sendAdvCommand(ACMD41, busyType)) != R1_READY_STATE) && (retry < SD_INIT_TIMEOUT)) {imp.sleep(0.001); retry++; }
        
        if (retry < SD_INIT_TIMEOUT)
        {
            server.log("Card no longer busy");
        }
        else
        {
            server.log("Card still busy after retries");
            return false;
        }
        
        /* TODO This breaks up SPI communication and writes 512 bytes to sdcard without reason !
        if (cardType == 2)
        {
            if (sendCommand(CMD58, 0))
            {
                server.log("Cannot get OCR register");
                return false;
            }
            if ((read() & 0xc0) == 0xc0)
            {
                sdhcSupport = true;
                server.log("Card is SDHC")
            }
            //Discard remaining OCR response
            for (i = 0; i < 3; i++) read();
        }
        
        //Set block size
        if (cardType == 1 || !sdhcSupport)
        {
            r = sendCommand(CMD16, 512); //Not needed for SDHC or type 2 cards
            server.log("Set block size reply: " + r);
        }
        */
        initialised = true;
        //cs(1);
        server.log("Card initialisation done successfully");
        
        return true;
    }
    
    function getSize()
    {
        if(!initialised) return 0;
        if(!readRegister(REG_CSD))
        {
            server.log("Cannot get size");
            return 0;
        }
        
        local csd = commBuf[0] >> 6;
        local size = 0;
        
        if (csd == 0) /* V1.0 CSD */
        {
            size = (((commBuf[8] & 0xc0) >> 6) | ((commBuf[7] & 0xff) << 2) | ((commBuf[6] & 0x03) << 10)) + 1;
            size = size << (((commBuf[10] & 0x80) >> 7) | ((commBuf[9] & 0x03) << 2)) + ((commBuf[5] & 0x0f) - 7);
        }
        else /* probably V2.0 CSD */
        {
            size = ((((commBuf[7] & 0x3f) << 16) | (commBuf[8] << 8) | commBuf[9] + 1)) << 10;    
        }
        
        /*
        local str = format("Size %d CSD ver: 0x%02x Info: 0x%02x 0x%02x 0x%02x", size, commBuf[0], commBuf[7], commBuf[8], commBuf[9]);
        server.log(str);
        */
        return size;
    }
    
    function readBlock(offset)
    {
        if (!initialised) return false;
        
        local retry = 0;
        local r;

        if (cardType == 1 || !sdhcSupport) 
            offset = offset << 9; // byte unit address
        
        if (r = sendCommand(CMD17, offset))
        {
            server.log("Error requesting block reply: " + r);
            return false;
        }
        /*
        r = sendCommand(CMD17, offset); //SDHC use block (512) unit address
        while ((r != 0x00) && (retry < 0x1000)) { retry++; r = read(); }
        
        if (retry >= 0x1000)
        {
            server.log("Error requesting block reply: " + r);
            return false;
        }
        */
        return readData(512);
    }
    
    //Writes data from comBuff at block offset
    function writeBlock(offset)
    {
        local r, r2;
        
        if (cardType == 1 || !sdhcSupport) 
            offset = offset << 9;

        //r = sendCommand(CMD24, offset);
        if (sendCommand(CMD24, offset))
        {
            server.log("Error setting write block");
            return false;
        }
        
        /*while ((r != 0x00) && (retry < 0x1000)) { retry++; r = read(); }
        if (retry >= 0x1000)
        {
            server.log("Error setting write block reply: " + r);
            return false;
        }
        */
        
        if (!writeData(DATA_START_BLOCK, 512))
        {
           //cs(1);
            return false;
        }
        
        
        r = sendCommand(CMD13, 0);
        r2 = read();
        
        server.log("Write programming replied: " + r + " " + r2);
        
        //cs(1);
        return true;
    }
    
    function readRegister(reg)
    {
        if (!initialised) return false;
        
        if (sendCommand(reg, 0))
        {
            server.log("Cannot read register");
            return false;
        }
        return readData(16);
    }
    
    //Write comBuff to a block location that was setup with writeBlock or starts a multiple block write depending on token
    function writeData(token, length)
    {
        local i;
        local retry = 0;
        local r;
        local crc = 0xFFFF; //TODO real CRC
        
        write(token);
        for (i = 0; i < length; i++)
            write(commBuf[i]);

        write(crc >> 8);
        write(crc & 0xff);
        
        while (((r = read()) == 0xff) && (retry < 0x1000)) retry++;
        if (retry >= 0x1000)
        {
            server.log("Write timeout");
            //cs(1);
            return false;
        }

        return true;
    }
    
    function readData(count)
    {
        local i;
        local retry = 0;
        local r;

        if (!initialised) return false;
        
        commBuf.flush();
        
        cs(0);
        
        /*while (((r = read()) == 0xff) && (retry < 0x1000)) { imp.sleep(0.001); retry++; }
        
        if (retry >= 0x1000)
        {
            server.log("Cannot start read");
            //cs(1);
            return false;
        }
        //server.log(format("Start read return: 0x%02x", r));
        */
        //if (r != DATA_START_BLOCK)
        //{
        //    server.log("Got " + r + " instead of DATA_START_BLOCK");
            retry = 0;
            while((read() != DATA_START_BLOCK) && (retry < 0x3000)) { imp.sleep(0.001); retry++; }
            if (retry >= 0x3000)
            {
                server.log("No start block returned");
                //cs(1);
                return false;
            }
        //}
                
        for(i = 0; i < count; i++)
        {
            commBuf[i] = read();
            //server.log(format("readData: 0x%02x", commBuf[i]));
        }      
        
        //Read and flush the CRC
        local crc = (read() << 8) | read();
        //cs(1);
        return true;
    }

    function dumpBuf()
    {
        local str = format("0x%02x 0x%02x 0x%02x 0x%02x 0x%02x", commBuf[0], commBuf[1], commBuf[2], commBuf[3], commBuf[4]); 
        /*
        local i;
        //string concatenation creates a new string each time
        for (i = 0; i < commBuf.len(); i++)
            str += format("0x%02x ", commBuf[i]); 
        */
        server.log(str);
    }
    
    function sumBuf()
    {
        local i, sum = 0;
        for (i = 0; i < commBuf.len(); i++)
            sum += commBuf[i];
        server.log("Block size: " + i + " with sum: " + sum);
    }
}

class FATFS
{
    sd = null;
    blocks = 0;
    constructor()
    {
        sd = SDCardIO();
    }
    
    function init()
    {
        if (!sd.initSDCard())
        {
            server.log("Cannot init sdcard.");
            return false;
        }

        blocks = sd.getSize();
        
        if (!sd.readBlock(0))
        {
            server.log("Cannot read sector 1");
            return false;
        }
        
        local ss = sd.commBuf[0x1fe] << 8 | sd.commBuf[0x1ff];
        server.log("Sector size: " + ss +" " + sd.commBuf[0x1fe] + " " + sd.commBuf[0x1ff]);

        server.show("Card size:" + blocks/1000/1000*512 + " MB");
        return true;
    }
}

server.log("SDCard Bridge Starting ...");
imp.configure("SDCard bridge", [], []);
imp.sleep(1);

fat <- FATFS();
if (!fat.init())
    server.show("Cannot init FATFS");

/* SPI device */
const SPI_189 = 0x55;

local spiDevice189 = 
{
	dev = SPI_189
	port = "spi189" /* hardware.spi189 */
	cs = 2 /* hardware.pin2 */
	clock = 1000
}

/* SDCard IO commands */
const GO_IDLE_STATE = 0x00; /* reset the sdcard */
const SEND_CSD = 0x09; /* send card specific data */
const SEND_CID = 0x0a; /* send card indentification */
const READ_SINGLE_BLOCK = 0x11; /* read a block from an byte address */
const WRITE_BLOCK = 0x18; /* write a block to a byte address */
const SEND_OP_COND = 0x29; /* start cand initialization */
const APP_CMD = 0x37; /* application command prefix */


class spiBridge
{
	spi = null;
	
	constructor(spiDevice)
	{
		spi = spiDevice;
		local cspin = spi.cs;
		/*cspin.configure(DIGITAL_OUT);
		hardware.configure(spi.dev);
		spiDevice.port.configure(0, spi.clock);
		*/
	}
	
	function cs(state) { /*spi.cs.write(state);*/ }
	function write(data) { /*spi.port.write(format("%c", data));*/ }
	function read() { /*local ret = spi.port.read(1); return ret[0];*/ return 0;}
}

class SDCardIO extends spiBridge
{
	
	constructor(spiDevice)
	{
		base.constructor(spiDevice);
	}
	
	function sendCommand(cmd, param)
	{
		cs(1);
		write(0xff);
		cmd = cmd | 0x40;
		write(cmd);
		write(param);
		write(0x95);
		write(0xff);
		write(0xff);
		return read();
	}

}

sd <- SDCardIO(spiDevice189);
sd.read();
sd.sendCommand(GO_IDLE_STATE, 0);
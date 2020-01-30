
# Electric IMP (https://electricimp.com) SPI SDCard interface

This source implements the MMC/SD SPI protocol for accessing/read/write data on sdcards.
To use this bridge you will need to at least configure the spiBridge class with proper pinouts:

	port = hardware.spi189
	clk = hardware.pin1
	cs = hardware.pin2
	si = hardware.pin8
	so = hardware.pin9



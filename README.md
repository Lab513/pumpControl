This is a matlab GUI for controlling an ISMATEC peristaltic pump over serial, featuring a periodical flush timer.

All code is non-blocking, but I use a number of timers and callbacks in there, and matlab is terrible at handling callbacks and interruptions, so if you have other sensitive interruption-based functions that you wish to execute in parallel, I recommend opening this GUI in another matlab machine. 

The serial commands for the pump are described in pages 36 to 41 of the manual. 


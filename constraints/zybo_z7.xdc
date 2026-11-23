## Digilent Zybo Z7-20 (XC7Z020-1CLG400C) constraints for fpga_top.
##
## IMPORTANT: Verify every pin against the official Digilent master XDC:
##   https://github.com/Digilent/digilent-xdc/blob/master/Zybo-Z7-Master.xdc
## before programming hardware.  Mistakes in constraints can damage I/O banks.
##
## Notes:
##  - The on-board USB-UART (CP2104) is wired to Zynq PS MIO14/MIO15, NOT to PL.
##    uart_txd therefore goes to JA Pmod pin 1 (N15).  Connect a USB-UART cable:
##      JA pin 1 (N15)   → USB-UART RX
##      JA pin 5 (GND)   → USB-UART GND
##    Open a terminal at 115200 8N1 on the resulting COM port.
##  - Zynq PL-only designs may see a PS-not-configured warning in Vivado; ignore it.

## 125 MHz system clock
set_property PACKAGE_PIN K17 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports clk]

## Push-buttons (active-high)
## btn0 = BTN0 → reset
set_property PACKAGE_PIN K18 [get_ports btn0]
set_property IOSTANDARD LVCMOS33 [get_ports btn0]

## User LEDs  LD0-LD3
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property PACKAGE_PIN G14 [get_ports {led[2]}]
set_property PACKAGE_PIN D18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## JA Pmod — UART TX on JA pin 1 (N15)
## Remaining JA pins available as spare I/O if needed.
set_property PACKAGE_PIN N15 [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

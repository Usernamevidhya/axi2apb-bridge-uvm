# Out-of-context synthesis constraints for axi2apb_top
# 100 MHz target clock. Tighten the period to find the maximum frequency.
create_clock -period 10.000 -name aclk [get_ports aclk]

obj-m += apple-ib-tb.o

# Include adaptive feature detection Makefile
-include $(PWD)/Makefile.adaptive

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean

install:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules_install

.PHONY: all clean install

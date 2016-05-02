DATE := $(shell date)

NAME = plopkexe
INIT = init
OBJS = plpkexec.o keyboard.o vt.o run.o tools.o log.o menu.o menuentry.o edit.o scan_syslinux.o scan_lilo.o scan_grub.o scan_grub2.o devices.o

# Add -m32 on 64bit OS
#UNAME := $(shell uname -m)
#ifeq ($(UNAME), x86_64)
#M = -m32 -march=i486 
#endif

# Enable dummy run and quit key
#D := -DDUMMY_RUN
#Q := -DQUIT_KEY

# Enable static linking
L := -static

# Force timeout
T := -DFORCE_TIMEOUT

# Enable kexec syscall mode (fails with invalid arguments)
#K := -DKEXEC_SYSCALL

# Force timeout
#C := -DFORCE_CMDLINE=\"modules-load=i2c_i801,i2c_dev,chromeos_laptop,cyapatp\"

# Set compile flags
CFLAGS 	= -g -c -Wunused -Wuninitialized -O2 $(Q) $(M) $(D) $(C) $(K)
LDFLAGS	= -Wall -D_FILE_OFFSET_BITS=64 -pthread $(L) $(M)
LINK	= $(CC) -o
CC	= g++
COMPILE = $(CC) $(CFLAGS)

$(NAME): $(OBJS) 
	$(LINK) $(NAME) $(LDFLAGS) $(OBJS) $(LIBS)
	strip -s -o $(INIT) $(NAME)

keyboard.o: keyboard.cpp keyboard.h
	$(COMPILE) keyboard.cpp

vt.o: vt.cpp vt.h
	$(COMPILE) vt.cpp

run.o: run.cpp run.h
	$(COMPILE) run.cpp

log.o: log.cpp log.h
	$(COMPILE) log.cpp

tools.o: tools.cpp tools.h
	$(COMPILE) tools.cpp

menu.o: menu.cpp menu.h
	$(COMPILE) menu.cpp

menuentry.o: menuentry.cpp menuentry.h
	$(COMPILE) menuentry.cpp

plpkexec.o: plpkexec.cpp plpkexec.h
	$(COMPILE) plpkexec.cpp

edit.o: edit.cpp edit.h
	$(COMPILE) edit.cpp

devices.o: devices.cpp devices.h
	$(COMPILE) devices.cpp

scan_syslinux.o: scan_syslinux.cpp scan_syslinux.h
	$(COMPILE) scan_syslinux.cpp

scan_lilo.o: scan_lilo.cpp scan_lilo.h
	$(COMPILE) scan_lilo.cpp

scan_grub.o: scan_grub.cpp scan_grub.h
	$(COMPILE) scan_grub.cpp

scan_grub2.o: scan_grub2.cpp scan_grub2.h
	$(COMPILE) scan_grub2.cpp

clean:
	rm -fv *.o ${INIT} $(NAME)

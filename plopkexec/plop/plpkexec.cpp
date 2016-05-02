/*
 *
 *  PlopKexec
 *
 *  Copyright (C) 2011  Elmar Hanlhofer
 *
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */


#define PROGRAM_VERSION 	"1.4"
#define PROGRAM_RELEASE_DATE	"2016/05/02"

#include <iostream>
#include <fstream>

//#include <string>
//#include <list>

#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <dirent.h>
#include <string.h>
#include <termios.h>

#include <errno.h>
#include <sys/reboot.h>
#include <sys/mount.h>
#include <sys/klog.h>
#include <linux/kexec.h>
#include <sys/syscall.h>
#include <linux/reboot.h>

#include "plpkexec.h"

#include "keyboard.h"
#include "vt.h"
#include "run.h"
#include "tools.h"

#include "log.h"
#include "edit.h"
#include "menu.h"
#include "devices.h"

#include "scan_syslinux.h"
#include "scan_lilo.h"
#include "scan_grub.h"
#include "scan_grub2.h"

Menu menu;
Logs logs;
Devices devices;
std::vector<string> Filesystems;

int quit;
int info_display_wait = 0;
bool dummy_scan = false;

void MountDefaults()
{
    char mountfs[2][3][10] = { 
	"none", "/proc", "proc",
	"none", "/sys", "sysfs",
	};

    for (int i = 0; i < 2; i++)
    {
	if (mount (mountfs[i][0], mountfs[i][1], mountfs[i][2], MS_MGC_VAL, "")) 
	{
	    Log ("Mounting %s failed", mountfs[i][1]);
	}
	else
	{
	    Log ("%s mounted", mountfs[i][1]);
	}
    }
}

void FetchFilesystems()
{
    std::string line;
    char fs[16] = {0};
    std::ifstream f("/proc/filesystems");

    while (std::getline(f, line)) {
	strncpy(fs, line.c_str(), 16);
	//Log ("Checking filesystem '%s'", fs);
	if ((strncasecmp (fs, "nodev", 5) != 0) && (strncasecmp (fs, "fuse", 4) != 0)) {
	        int i1 = 0; int i2 = 0;
		while ((fs[i1] != 0)) {
			if ((fs[i1] == '\t') || (fs[i1] == ' '))
				i1++;
			else
				fs[i2++] = fs[i1++];
		}
		fs[i2] = 0;

	    Filesystems.push_back(fs);
	    Log ("Supporting filesystem '%s'", Filesystems.back().c_str());
	}// else {
	//    Log ("Skipping '%s'", line.c_str());
	//}
    }
}

bool DummyScan ()
{
    if (dummy_scan)
        return true;

    menu.PrintStatusScanning ("/mnt");

    menu.SetCurrentDevice ("/mnt", false);

    ScanLilo lilo;
    lilo.Scan (&menu);

    ScanGrub grub;
    grub.Scan (&menu);

    ScanGrub2 grub2;
    grub2.Scan (&menu);

    ScanSyslinux syslinux;
    syslinux.Scan (&menu);

    menu.PrintStatusDefault();

    dummy_scan = true;

    return true;
}

#ifndef KEXEC_SYSCALL
void StartKernel (MenuEntry entry)
{
    string cmd;

    menu.PrintStatusLoadingKernel();
    menu.Print (true);

    Device d;
    d.Mount (entry.device.c_str(), entry.is_cdrom);

    cmd = "/kexec -l " + entry.kernel + " -x";
    if (entry.realmode)
    {
	cmd += " --real-mode";
    }

    if (entry.initrd.length() > 0)
    {
	cmd += " --initrd=" +  entry.initrd;
    }

    if (entry.append.length() > 0)
    {
	cmd += " --append=\"" + entry.append + "\"";
    }
    
    if (RunCmd (cmd.c_str()))
    {
	Log ("Kexec error: %s", cmd.c_str());
	umount ("/mnt");
	Log ("unmount /mnt");
	ClearScreen();
	menu.PrintStatusKexecError();
	return;
    }

    SetCursor (0, 0);
    TextColor(RESET, WHITE, BLACK);
    ClearScreen();
    SetCursor (0, 0);
    ShowCursor();
    printf ("Loading kernel...\n");
	    
    cmd = "/kexec -e";
    if (RunCmd (cmd.c_str()))
    {
	Log ("Kexec error: %s", cmd.c_str());
    }

    umount ("/mnt");
    Log ("unmount /mnt");
    HideCursor();
}

#else

void StartKernel (MenuEntry entry)
{
    FILE *kernel = NULL, *initrd = NULL;
    int kernel_fd = 0, initrd_fd = 0;
    unsigned long flags = 0;
    menu.PrintStatusLoadingKernel();
    menu.Print (true);
    bool progress = true;
    int loaded = 0;

    Device d;
    d.Mount (entry.device.c_str(), entry.is_cdrom);

    printf ("(New)Loading kernel...\n");

    kernel = fopen(entry.kernel.c_str(), "r");
    if (!kernel) {
	progress = false;
    } else {
	kernel_fd = fileno(kernel);
    }

    if (entry.initrd.length() > 0) {
	initrd = fopen(entry.initrd.c_str(), "r");
	if (!initrd) {
		progress = false;
	} else {
		initrd_fd = fileno(initrd);
	}
    } else {
	flags = KEXEC_FILE_NO_INITRAMFS;
    }

    //TODO: " --real-mode"

    //loaded = kexec_file_load(kernel_fd, initrd_fd, entry.append.length(), entry.append.c_str(), flags);
    loaded = syscall(SYS_kexec_file_load, kernel_fd, initrd_fd, entry.append.length(), entry.append.c_str(), flags);
    if (!progress || loaded) {
	Log ("(New) Kexec load error: (%d:%s) %s[%d]/ %s[%d] / %s", errno, strerror(errno), entry.kernel.c_str(), kernel_fd, entry.initrd.c_str(), initrd_fd, entry.append.c_str());

	umount ("/mnt");
	Log ("unmount /mnt");
	ClearScreen();
	menu.PrintStatusKexecError();
	return;
    }

    SetCursor (0, 0);
    TextColor(RESET, WHITE, BLACK);
    ClearScreen();
    SetCursor (0, 0);
    ShowCursor();

    printf ("(New)Starting kernel...\n");
    reboot(LINUX_REBOOT_CMD_KEXEC);
    Log ("(New) Kexec start error: (%d:%s) %s[%d]/ %s[%d] / %s", errno, strerror(errno), entry.kernel.c_str(), kernel_fd, entry.initrd.c_str(), initrd_fd, entry.append.c_str());

    umount ("/mnt");
    Log ("unmount /mnt");
    HideCursor();
}
#endif

static void *Timer (void *args)
{
    while (true)
    {
	while (menu.timeout < 1)
	{
	    usleep (10);
	    if (quit) return NULL;
	}

	while (menu.timeout > 1)
	{
	    menu.PrintTimeout();
	    sleep (1);
	    menu.timeout--;
	    if (quit) return NULL;
	}
    }
}

#ifndef DUMMY_RUN
static void *Dmesg (void *args)
{
    char line[2048];
    int pos;

    FILE *pf;
    pf = fopen ("/dev/kmsg", "r");
    if (!pf)
    {
	LogDmesg ("Unable to open /dev/kmsg");
	return NULL;
    }

    while (!feof (pf) && (fgets (line, sizeof (line) - 1, pf) != NULL)) {
	line[sizeof (line) - 1] = 0;
	RemoveNL (line);
	pos = FindChar (line, ';');
	if (pos > 0)
	{
	    LogDmesg ("%s", line + pos + 1);
	}

	if (quit) 
	{
	    break;
	}
    }

    fclose (pf);
    return NULL;
}
#endif

int main(int argc, char *argv[])
{
    char c = 0;
    double time;
    double nextcheck;

    pthread_t thread_id;
#ifndef DUMMY_RUN
    pthread_t thread_id2;
#endif

    quit = 0;

    logs.Init();

    Log ("PlopKexec build info: %s", __DATE__);
#ifdef QUIT_KEY
    Log ("Warning: QUIT_KEY enabled");
#endif

#ifdef DUMMY_RUN
    Log ("Warning: DUMMY_RUN enabled");
#endif

    menu.Init (PROGRAM_VERSION, " " PROGRAM_RELEASE_DATE " written by Elmar Hanlhofer https://www.plop.at");

#ifndef DUMMY_RUN
    MountDefaults();

    klogctl (6, NULL, 0); // disable printk's to console

#endif

    FetchFilesystems();

    menu.Print (true);

    nextcheck = Curtime() - 1;

//#ifndef DUMMY_RUN
    SetKBNonBlock (NB_ENABLE);

    // echo off, seen at codegurus
    termios oldt;
    tcgetattr (STDIN_FILENO, &oldt);
    termios newt = oldt;
    newt.c_lflag &= ~ECHO;
    tcsetattr (STDIN_FILENO, TCSANOW, &newt);

    HideCursor();
//#endif

    if (pthread_create (&thread_id, NULL, &Timer, NULL)) {
        Log ("Unable to create Timer thread");
    }
#ifndef DUMMY_RUN

    if (pthread_create (&thread_id2, NULL, &Dmesg, NULL)) {
        Log ("Unable to create Dmesg thread");
    }
#endif

    while (!quit) {
	int pressed;

	SetCursor (0, 0);
	usleep(1);

        pressed = KBHit();
        if (menu.timeout == 1) {
	    pressed = 1;
	}

	c = 0;
        if (pressed != 0)
        {
    	    if (menu.timeout == 1)
    	    {
    		menu.PrintTimeout();
    		c = 0x0a;
    	    }
    	    else
    	    {
        	c = fgetc (stdin);
        	if (menu.timeout > 0)
        	{
        	    menu.timeout = 0;
		    menu.PrintTimeout();
		}
    	    }
	    
	    menu.Print();
	    
	    switch (c)
    	    {
#ifdef QUIT_KEY
    		case 'q': // quit key for development
    		    quit = true;
    		    break;
#endif		
		
		case 'r':
		case 'R':
		    reboot (RB_AUTOBOOT);
		    break;

    		case 's':
    		case 'S':
    		    reboot (RB_POWER_OFF);
    		    break;

    		case 'e':
    		case 'E':
		    if (menu.SelectedType() == 0)
    		    {
    			Edit edit;
    			edit.Init();
    			edit.Show (menu.GetSelectedEntry());
    			if (edit.boot)
    			{
    			    menu.Print();
    			    StartKernel (edit.entry);
    			}
    		    }
		    menu.Print (true);
    		    break;

		case 'l':
		case 'L':
		    logs.Show();
		    menu.Print (true);
		    break;

    		    
    		case 27:
    		
        	    c = fgetc(stdin);
        	    c = fgetc(stdin);
        	    
        	    // clear buffer
            	    while (KBHit())
            	    {
                	fgetc (stdin);
            	    }

    		    switch (c)
    		    {
    			// page up
    			case 0x35:
    			    //fgetc(stdin); // dummy
    			    menu.KeyPageUp();
    			    break;
    			    
    			// home key
    			case 0x31:
    			case 0x48:
    			    menu.KeyHome();
    			    break;
    		    
    			// page down
    			case 0x36:
    			    //fgetc(stdin); // dummy
    			    menu.KeyPageDown();
    			    break;
    			
    			// end key
    			case 0x34:
    			case 0x46:
			    menu.KeyEnd();
    			    break;
    		    
    			// cursor up
    			case 0x41:
    			    menu.KeyUp();
    			    break;
    		    
    			// cursor down
    			case 0x42:
    			    menu.KeyDown();
    			    break;
    			    
    			// cursor right
    			case 0x43:
    			    logs.Show();
			    menu.Print (true);
			    break;

    		    
    		    }
    		
    		    break;
    		
    		case 0x0a:
		    int type = menu.SelectedType();
		    if ((type == 1) || (type == 2))
		    {
			menu.EnterSelected();
		    }
		    else
		    {
			StartKernel (menu.GetSelectedEntry());
		    }
		    menu.Print (true);
    		    break;
    	    }

        }

	time = Curtime();
	if (nextcheck - time < 0) {
#ifndef DUMMY_RUN
	    if (devices.Scan()) {
#else
	    if (DummyScan()) {
#endif
		menu.Print (true);
	    }

#ifndef FORCE_TIMEOUT
	    if (menu.timeout == 0) {
		    menu.SetTimeout(10);
	    }
#endif

	    nextcheck = Curtime() + 1;

	    if (menu.info_display_wait > 0) {
		menu.info_display_wait--;
	    }

	    menu.PrintStatusDefault();
	}
    }

//#ifndef DUMMY_RUN
    // without quit key, this will be never reached
    umount ("/mnt");
    Log ("unmount /mnt");

    ShowCursor();

    SetKBNonBlock(NB_DISABLE);
    tcsetattr (STDIN_FILENO, TCSANOW, &oldt);

    TextColor(RESET, WHITE, BLACK);
    SetCursor (0, 20);
//#endif
    return 0;
}

/*
 *
 *  plopKexec
 *
 *  Copyright (C) 2015  Elmar Hanlhofer
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

#include <unistd.h>
#include <stdlib.h>

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <dirent.h>
#include <sys/types.h>
#include <string.h>


#include "log.h"
#include "tools.h"

#include "scan_grub2.h"
#include "menu.h"
#include "menuentry.h"

void ScanGrub2::ScanConfigFile (char *dir, char *file_name)
{
    bool scan_kernel_setup = false;
    bool added_to_menu = false;
    bool found = false;
    bool variables = false;
    FILE *pf;
    //int default_boot_number = 0;

    pf = fopen (file_name, "r");
    if (!pf) {
	Log ("Couldn't open '%s'/'%s'", dir, file_name);
	ScanDirectory (dir);
	return;
    } else {
	Log ("Parsing '%s'/'%s'", dir, file_name);
    }

    MenuEntry menuEntry;

    menuEntry.Reset();
    menuEntry.check_default_boot = true;

    while (fgets (cfg_line, sizeof (cfg_line), pf)) {
	RemoveUnneededChars (cfg_line, '#');
	TabToSpace (cfg_line);
	StripChar (cfg_line, '{'); // dirty hack, use menuentry as start
        if (!variables && FindChar (cfg_line, '$')) {
		variables = true;
	}

	/*
	if ((strncasecmp (cfg_line, "set default", 11) == 0) && !FindChar (cfg_line, '$')) {
		GetValue(cfg_line);
		default_boot_number = atoi (cfg_line);
		continue;
	}
	*/

	if (strncasecmp (cfg_line, "menuentry ", 10) == 0) {
	    if (variables) {
	        Log ("Warning: Grub2 added menu entry '%s' with variable/s, they were removed.", cfg_line);
		variables = false;
	    }

	    // when a new label has been found then add the previous collected data to the menu
	    if (!added_to_menu && found) {
		menu->AddEntry (menuEntry);
		menuEntry.Reset();

		added_to_menu = true;
		found = false;
	    }
	    
	    StripChar (cfg_line, '"');
	    menuEntry.SetMenuLabel (cfg_line + 10);

	    scan_kernel_setup = true;
	}


	if (scan_kernel_setup) {
            //if (FindChar (cfg_line, '$'))
	    //    Log ("Grub2: Adding initrd/kernel args with variable '%s'", cfg_line);

    	    if (strncasecmp (cfg_line, "linux ", 6) == 0) {
		menuEntry.SetKernel (cfg_line + 6, dir);
		found = true;
		added_to_menu = false;
		
		char append[1024];
		strncpy (append, cfg_line + 6, sizeof (append));
		int start = Trim (append);
		int pos = FindChar (append + start, ' ');
		if (pos > -1) {
		    menuEntry.SetAppend (append + start + pos);
		}
	    } else if (strncasecmp (cfg_line, "initrd ", 7) == 0) {
		menuEntry.SetInitrd (cfg_line, dir);
	    }
	}
    }

    if (!added_to_menu && found) {
	menu->AddEntry (menuEntry);
    }

    fclose (pf);
}

void ScanGrub2::ScanDirectory (char *dir)
{
    DIR *pd;
    dirent *dirent;
    //char full_name[1024];

    pd = opendir (dir);
    if (!pd) {
	Log ("ls: '%s' doesn't exists", dir);
	return;
    }

    while (dirent = readdir (pd)) {
	if ((strcmp (dirent->d_name, ".") != 0) && (strcmp (dirent->d_name, "..") != 0)) {
	    Log ("ls: '%s'/'%s'", dir, dirent->d_name);
	    //menu->ResetParentID();
	    //sprintf (full_name, "%s/%s", dir, dirent->d_name);
	    //ScanConfigFile (dir, full_name);
	}
    }
    closedir (pd);
}

void ScanGrub2::Scan(Menu *m)
{
    menu = m;
    char full_name[1024];
    char check[6][2][256] = {
	"/mnt",			"grub.cfg",
	"/mnt/@/",		"grub.cfg",
	"/mnt/grub",		"grub.cfg",
	"/mnt/@/grub",		"grub.cfg",
	"/mnt/boot/grub",	"grub.cfg",
	"/mnt/@/boot/grub",	"grub.cfg"
    };

    menu->DisableDefaultBootCheckFlags();

    for (int i = 0; i < 6; i++) {
	//ScanDirectory (check[i]);
	Log ("Checking '%s'/'%s'", check[i][0], check[i][1]);
	menu->ResetParentID();
	sprintf (full_name, "%s/%s", check[i][0], check[i][1]);
	ScanConfigFile (check[i][0], full_name);
    }

    menu->SelectDefaultBootEntry();
}

/*
    Sloth - Mac OS X Graphical User Interface front-end for lsof
    Copyright (C) 2004-2010 Sveinbjorn Thordarson <sveinbjornt@simnet.is>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

*/

// HEADERS

#import <Cocoa/Cocoa.h>
#import "RegexKitLite.h"
#import "STUtil.h"
#import "STPathTextField.h"

/*
#import <Security/Authorization.h>
#import <SecurityFoundation/SFAuthorization.h>
#import <Security/Security.h>
#import "STPrivilegedTask.h"
*/

// DEFS

#define PROGRAM_NAME						@"Sloth"
#define PROGRAM_VERSION						@"1.5"
#define	PROGRAM_WEBSITE						@"http://sveinbjorn.org/sloth"
#define PROGRAM_DONATIONS					@"http://sveinbjorn.org/donations"
#define PROGRAM_DEFAULT_OUTPUT_FILENAME		@"Sloth-Output.txt"
#define PROGRAM_DEFAULT_LSOF_PATH			@"/usr/sbin/lsof"
#define PROGRAM_LSOF_NAME					@"lsof"

// INTERFACE

@interface SlothController : NSObject
{	
	//main window and controls
	IBOutlet id			slothWindow;
	
	IBOutlet id			progressBar;
	IBOutlet id			refreshButton;
	IBOutlet id			filterTextField;
	IBOutlet id			numItemsTextField;
    IBOutlet id			tableView;
	IBOutlet id			revealButton;
	IBOutlet id			killButton;
	IBOutlet id			lastRunTextField;
	
	//prefs
	IBOutlet id			prefsWindow;
	IBOutlet id			lsofPathTextField;
	
	//lsof version info window
	IBOutlet id			lsofVersionWindow;
	IBOutlet id			lsofVersionTextView;
	
	
	//array sets	
	NSMutableArray		*fileArray;
	NSMutableArray		*activeSet;
	NSMutableArray		*subset;
}

- (IBAction)reveal:(id)sender;
- (IBAction)refresh:(id)sender;
- (IBAction)kill:(id)sender;
- (IBAction)relaunchAsRoot:(id)sender;
- (IBAction)showPrefs:(id)sender;
- (IBAction)applyPrefs:(id)sender;
- (IBAction)restoreDefaultPrefs:(id)sender;
- (IBAction)showLsofVersionInfo:(id)sender;
- (IBAction)checkboxClicked: (id)sender;
- (void)filterResults;
@end

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

#import "SlothController.h"

@implementation SlothController

- (id)init
{
	if (self = [super init]) 
	{
		fileArray = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (void)initialize 
{ 
	NSDictionary *registrationDefaults = [NSDictionary dictionaryWithContentsOfFile: 
										  [[NSBundle mainBundle] pathForResource: @"RegistrationDefaults" ofType: @"plist"]];
    [[NSUserDefaults standardUserDefaults] registerDefaults: registrationDefaults];
}

- (void)awakeFromNib
{
	// sorting for tableview
	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
																	   ascending: YES selector:@selector(localizedCaseInsensitiveCompare:)];
	
	[tableView setSortDescriptors: [NSArray arrayWithObject: nameSortDescriptor]];
	
	// dragging from tableview
	[tableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
	[tableView registerForDraggedTypes:[NSArray arrayWithObjects: NSStringPboardType, nil]];
	
	// center and show window
	[slothWindow center];
	[slothWindow makeKeyAndOrderFront: self];
}

- (void)dealloc
{
	if (fileArray != NULL)
		[fileArray release];
	
	if (subset != NULL)
		[subset release];
	
	[super dealloc];
}

#pragma mark -

/************************************************************************************
 Run lsof and parse output for placement in the data browser
 This is the real juice function
 ************************************************************************************/

- (IBAction)refresh:(id)sender
{
	NSPipe			*pipe		= [NSPipe pipe];
	NSData			*data;
	int				i;
	BOOL			isDir		= FALSE;
	NSString		*pid		= @"";
	NSString		*process	= @"";
	NSString		*ftype		= @"";
	NSString		*fname		= @"";
	
	NSString		*output		= @"";
	NSArray			*lines;
	
	//first, make sure that we have a decent lsof
	NSString *launchPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"lsofPath"];
	if (![[NSFileManager defaultManager] fileExistsAtPath: launchPath isDirectory: &isDir] || isDir)
	{
		[STUtil alert: @"Invalid executable" subText: @"The 'lsof' utility you specified in the Preferences does not exist"];
		return;
	}
	
	//clear former item list and empty output value stored
	[fileArray removeAllObjects];
	
	//start progress bar animation	
	[progressBar setUsesThreadedAnimation: TRUE];
	[progressBar startAnimation: self];
	
	//
	// our command is:			lsof -F pcnt +c0
	//
	// OK, initialise task, run it, retrieve output
	{
		NSTask *lsof = [[NSTask alloc] init];
		[lsof setLaunchPath: launchPath];
		[lsof setArguments: [NSArray arrayWithObjects: @"-F", @"pcnt", @"+c0", nil]];
		[lsof setStandardOutput: pipe];
		[lsof launch];
		
		data = [[pipe fileHandleForReading] readDataToEndOfFile];
		
		[lsof release];
	}
	
	//get data output and format as an array of lines of text	
	output = [[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding];
	lines = [output componentsSeparatedByString:@"\n"];
	
	// parse each line
	for (i = 0; i < [lines count]-1; i++)
	{
		NSString *line = [lines objectAtIndex: i];
		
		//read first character in line
		if ([line characterAtIndex: 0] == 'p')
		{
			pid = [line substringFromIndex: 1];
		}
		else if ([line characterAtIndex: 0] == 'c')
		{
			process = [line substringFromIndex: 1];
		}
		else if ([line characterAtIndex: 0] == 't')
		{
			ftype = [line substringFromIndex: 1];
		}
		else if ([line characterAtIndex: 0] == 'n')
		{
			//we don't report Sloth or lsof info
			if ([process caseInsensitiveCompare: PROGRAM_NAME] == NSOrderedSame || [process caseInsensitiveCompare: PROGRAM_LSOF_NAME] == NSOrderedSame)
				continue;
			
			//check if we use full path
            NSString *rawPath = [line substringFromIndex: 1];            
            BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath: rawPath];
            NSNumber *canReveal = [NSNumber numberWithBool: fileExists];
            NSString *fullPath = rawPath;
            
			if (fileExists)
                fname = [rawPath lastPathComponent];
            else
                fname = rawPath;
			
            //order matters, see below
            NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
			
            [fileInfo setObject: process forKey: @"name"];
            [fileInfo setObject: [NSNumber numberWithLong: [pid intValue]] forKey: @"pid"];
            [fileInfo setObject: fname forKey: @"path"];
            [fileInfo setObject: fullPath forKey: @"fullPath"];
            [fileInfo setObject: canReveal forKey: @"canReveal"];
			
			//insert the desired elements
			if ([ftype caseInsensitiveCompare: @"VREG"] == NSOrderedSame || [ftype caseInsensitiveCompare: @"REG"] == NSOrderedSame) 
			{
				[fileInfo setObject: @"File" forKey: @"type"];
			} 
			else if ([ftype caseInsensitiveCompare: @"VDIR"] == NSOrderedSame  || [ftype caseInsensitiveCompare: @"DIR"] == NSOrderedSame) 
			{
				[fileInfo setObject: @"Directory" forKey: @"type"];
            } 
			else if ([ftype caseInsensitiveCompare: @"IPv6"] == NSOrderedSame || [ftype caseInsensitiveCompare: @"IPv4"] == NSOrderedSame) 
			{
                [fileInfo setObject: @"IP Socket" forKey: @"type"];
            } 
			else  if ([ftype caseInsensitiveCompare: @"unix"] == NSOrderedSame) 
			{
                [fileInfo setObject: @"Unix Socket" forKey: @"type"];
            } 
			else if ([ftype caseInsensitiveCompare: @"VCHR"] == NSOrderedSame || [ftype caseInsensitiveCompare: @"CHR"] == NSOrderedSame) 
			{
                [fileInfo setObject: @"Char Device" forKey: @"type"];
            }
			else
			{
				continue;
            }
            [fileArray addObject: fileInfo];
		}
	}
	
	activeSet = fileArray;
	[self filterResults];
	
	// update last run time
	[lastRunTextField setStringValue: [NSString stringWithFormat: @"Output at %@ ", [NSDate date]]];
	
	// stop progress bar and reload data
	[tableView reloadData];
	[progressBar stopAnimation: self];
}


// creates a subset of the list of files based on our filtering criterion
- (void)filterResults
{
	NSEnumerator *e = [fileArray objectEnumerator];
	id object;
	
	if (subset != NULL)
		[subset release];
	
	subset = [[NSMutableArray alloc] init];
	
	NSString *regex = [[NSString alloc] initWithString: [filterTextField stringValue]];
	
	while ( object = [e nextObject] )
	{
		BOOL filtered = NO;
		
		// let's see if it gets filtered by the checkboxes
		if ([[object objectForKey:@"type"] isEqualToString: @"File"] && ![[NSUserDefaults standardUserDefaults] boolForKey: @"showRegularFilesEnabled"])
			filtered = YES;
		if ([[object objectForKey:@"type"] isEqualToString: @"Directory"] && ![[NSUserDefaults standardUserDefaults] boolForKey: @"showDirectoriesEnabled"])
			filtered = YES;
		if ([[object objectForKey:@"type"] isEqualToString: @"IP Socket"] && ![[NSUserDefaults standardUserDefaults] boolForKey: @"showIPSocketsEnabled"])
			filtered = YES;
		if ([[object objectForKey:@"type"] isEqualToString: @"Unix Socket"] && ![[NSUserDefaults standardUserDefaults] boolForKey: @"showUnixSocketsEnabled"])
			filtered = YES;
		if ([[object objectForKey:@"type"] isEqualToString: @"Char Device"] && ![[NSUserDefaults standardUserDefaults] boolForKey: @"showCharacterDevicesEnabled"])
			filtered = YES;
		
		// see if regex in search field filters it out
		if (!filtered && [[filterTextField stringValue] length] > 0)
		{
			if ([[object objectForKey:@"name"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([[[object objectForKey:@"pid"] stringValue] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([[object objectForKey:@"path"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([[object objectForKey:@"fullPath"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
			else if ([[object objectForKey:@"type"] isMatchedByRegex: regex] == YES) 
				[subset addObject:object];
		}
		else if (!filtered)
			[subset addObject:object];
	}
	
	[regex release];
	
	activeSet = subset;
	
	/*	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
	 ascending: YES selector:@selector(localizedCaseInsensitiveCompare:)];
	 
	 activeSet = [[NSMutableArray arrayWithArray: [subset sortedArrayUsingDescriptors: [NSArray arrayWithObject: nameSortDescriptor]] ] retain];
	 */
	
	//activeSet = [subset sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	
	[numItemsTextField setStringValue: [NSString stringWithFormat: @"%d items", [activeSet count]]];
}


#pragma mark -


/************************************************************************************
 Send currently selected processes the termination signal (SIGKILL or SIGTERM)
 ************************************************************************************/

- (IBAction)kill:(id)sender
{
	int i;
	NSIndexSet *selectedRows = [tableView selectedRowIndexes];
	NSMutableDictionary *processesToTerminateNamed = [NSMutableDictionary dictionaryWithCapacity: 65536];
	NSMutableDictionary *processesToTerminatePID = [NSMutableDictionary dictionaryWithCapacity: 65536];
	
	// First, let's make sure there are selected items by checking for sane value
	if ([tableView selectedRow] < 0 || [tableView selectedRow] > [activeSet count])
		return;
	
	// Let's get the PIDs and names of all selected processes, using dictionaries to avoid duplicate entries
	for (i = 0; i < [activeSet count]; i++)
	{
		if ([selectedRows containsIndex: i])
		{
			[processesToTerminateNamed setObject: [[activeSet objectAtIndex: i] objectForKey: @"name"] 
										  forKey: [[activeSet objectAtIndex: i] objectForKey: @"name"]];
			
			[processesToTerminatePID setObject: [[activeSet objectAtIndex: i] objectForKey: @"pid"] 
										forKey: [[activeSet objectAtIndex: i] objectForKey: @"name"]];
		}
	}
	
	// Create comma-separated list of selected processes
	NSString *processesToKillStr = [[processesToTerminateNamed allKeys] componentsJoinedByString: @", "];
	
	// Ask user to confirm that he really wants to kill these
	if (![STUtil proceedWarning: @"Are you sure you want to kill the selected processes?" 
						subText: [NSString stringWithFormat: @"This will terminate these processes: %@", processesToKillStr] 
					 actionText: @"Kill"])
		return;
	
	// Get signal to send to process based on prefs
    int sigValue = [[NSUserDefaults standardUserDefaults] boolForKey: @"sigKill"] ? SIGKILL : SIGTERM;
	
	// iterate through list of PIDs, send each of them the kill/term signal
	for (i = 0; i < [processesToTerminatePID count]; i++)
	{
		int pid = [[[processesToTerminatePID allValues] objectAtIndex: i] intValue];
		int ret = kill(pid, sigValue);
		if (ret)
		{
			[STUtil alert: [NSString stringWithFormat: @"Failed to kill process %@", [[processesToTerminateNamed allValues] objectAtIndex: i]]
				  subText: @"The process may be owned by another user.  Relaunch Sloth as root to kill it."];
			return;
		}
	}
	
	[self refresh: self];
}

/*********************************************************
 Reveal currently selected item on the list in the Finder
 *********************************************************/
- (IBAction)reveal:(id)sender
{
    BOOL		isDir, i;
	NSIndexSet	*selectedRows = [tableView selectedRowIndexes];
	NSMutableDictionary *filesToReveal = [NSMutableDictionary dictionaryWithCapacity: 65536];
	
	// First, let's make sure there are selected items by checking for sane value
	if ([tableView selectedRow] < 0 || [tableView selectedRow] > [activeSet count])
		return;
	
	// Let's get the PIDs and names of all selected processes, using dictionaries to avoid duplicate entries
	for (i = 0; i < [activeSet count]; i++)
	{
		if ([selectedRows containsIndex: i])
		{
			[filesToReveal setObject: [[activeSet objectAtIndex: i] objectForKey: @"fullPath"] 
							  forKey: [[activeSet objectAtIndex: i] objectForKey: @"fullPath"]];
		}
	}
	
	// if more than 3 items are selected, we ask the user to confirm
	if ([filesToReveal count] > 3)
	{
		if (![STUtil proceedWarning: @"Are you sure you want to reveal the selected files?" 
							subText: [NSString stringWithFormat: @"This will reveal %d files in the Finder", [filesToReveal count]] 
						 actionText: @"Reveal"])
			return;
	}

	// iterate through files and reveal them using NSWorkspace
	for (i = 0; i < [filesToReveal count]; i++)
	{	
		NSString *path = [[filesToReveal allKeys] objectAtIndex: i];
		if ([[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir]) 
		{
			if (isDir)
				[[NSWorkspace sharedWorkspace] selectFile: NULL inFileViewerRootedAtPath: path];
			else
				[[NSWorkspace sharedWorkspace] selectFile: path inFileViewerRootedAtPath: NULL];
		}
	}
}

#pragma mark -

- (IBAction)relaunchAsRoot:(id)sender;
{
	NSTask	*theTask = [[NSTask alloc] init];
	
	//open Terminal.app
	[[NSWorkspace sharedWorkspace] launchApplication: @"Terminal.app"];
	
	//the applescript command to run as root via sudo
	NSString *osaCmd = [NSString stringWithFormat: @"tell application \"Terminal\"\n\tdo script \"sudo -b '%@'\"\nend tell",  [[NSBundle mainBundle] executablePath]];
	
	//initialize task -- we launc the AppleScript via the 'osascript' CLI program
	[theTask setLaunchPath: @"/usr/bin/osascript"];
	[theTask setArguments: [NSArray arrayWithObjects: @"-e", osaCmd, nil]];
	
	//launch, wait until it's done and then release it
	[theTask launch];
	[theTask waitUntilExit];
	[theTask release];
	
	[[NSApplication sharedApplication] terminate: self];
}

#pragma mark -

//////////// delegate and data source methods for the NSTableView /////////////

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return([activeSet count]);
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if ([[aTableColumn identifier] caseInsensitiveCompare: @"1"] == NSOrderedSame)
	{
		return([[activeSet objectAtIndex: rowIndex] objectForKey: @"name"]);
	}
	else if ([[aTableColumn identifier] caseInsensitiveCompare: @"2"] == NSOrderedSame)
	{
		return([[[activeSet objectAtIndex: rowIndex] objectForKey: @"pid"] stringValue]);
	}
	else if ([[aTableColumn identifier] caseInsensitiveCompare: @"3"] == NSOrderedSame)
	{
		return([[activeSet objectAtIndex: rowIndex] objectForKey: @"type"]);
	}
	else if ([[aTableColumn identifier] caseInsensitiveCompare: @"4"] == NSOrderedSame)
	{
		if ([[NSUserDefaults standardUserDefaults] boolForKey: @"showEntireFilePathEnabled"])
			return([[activeSet objectAtIndex: rowIndex] objectForKey: @"fullPath"]);
		else
			return([[activeSet objectAtIndex: rowIndex] objectForKey: @"path"]);
	}
	/*else if ([[aTableColumn identifier] caseInsensitiveCompare: @"5"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 4]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"6"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 5]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"7"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 6]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"8"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 7]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare: @"9"] == NSOrderedSame)
	 {
	 return([[rows objectAtIndex: rowIndex] objectAtIndex: 8]);
	 }*/
	return @"";
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	NSArray *newDescriptors = [tableView sortDescriptors];
	[activeSet sortUsingDescriptors: newDescriptors];
	[tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([tableView selectedRow] >= 0 && [tableView selectedRow] < [activeSet count])
	{
		NSMutableDictionary *item = [activeSet objectAtIndex: [tableView selectedRow]];
		BOOL canReveal = [[item objectForKey: @"canReveal"] boolValue];
		[revealButton setEnabled: canReveal];
		[killButton setEnabled: YES];
	}
	else
	{
		[revealButton setEnabled: NO];
		[killButton setEnabled: NO];
	}
}

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard
{
	int i;
	NSString *dragString = [NSString string];
	
	// Iterate through the list of displayed rows, each one that is selected goes to the clipboard
	for (i = 0; i < [activeSet count]; i++)
	{
		if ([rowIndexes containsIndex: i])
		{
			NSString *filePath;
			
			if ([[NSUserDefaults standardUserDefaults] boolForKey: @"showEntireFilePathEnabled"])
				filePath = [[activeSet objectAtIndex: i] objectForKey: @"fullPath"];
			else
				filePath = [[activeSet objectAtIndex: i] objectForKey: @"path"];
			
			NSString *rowString = [NSString stringWithFormat: @"%@\t%@\t%@\t%@\n",
								   [[activeSet objectAtIndex: i] objectForKey: @"name"],
								   [[[activeSet objectAtIndex: i] objectForKey: @"pid"] stringValue],
								   [[activeSet objectAtIndex: i] objectForKey: @"type"],
								   filePath];
			dragString = [dragString stringByAppendingString: rowString];
		}
	}
	
	[pboard declareTypes:[NSArray arrayWithObjects:NSStringPboardType, nil] owner: self];
	[pboard setString: dragString forType:NSStringPboardType];
	return YES;	
}

#pragma mark -

- (void)controlTextDidChange:(NSNotification *)aNotification
{	
	// two possible senders for this notification:  either lsofPathTextField or the resultFilter
	if ([aNotification object] == lsofPathTextField)
	{
		[[NSUserDefaults standardUserDefaults] setObject: [lsofPathTextField stringValue]  forKey:@"lsofPath"];
	}
	else
	{
		[self filterResults];
		[tableView reloadData];
	}
}

/*****************************************
 - Delegate for enabling and disabling menu items
 *****************************************/
- (BOOL)validateMenuItem: (NSMenuItem *)anItem 
{
	//reveal in finder / kill process only enabled when something is selected
	if (( [[anItem title] isEqualToString:@"Reveal in Finder"] || [[anItem title] isEqualToString:@"Kill Process"]) && [tableView selectedRow] < 0)
		return NO;
	
	return YES;
}


- (IBAction)checkboxClicked: (id)sender
{
	[self filterResults];
	[tableView reloadData];
}

#pragma mark -

//////////// PREFERENCES HANDLING ////////////////


/************************************************************************************
 Open window with Sloth Preferences
 ************************************************************************************/

- (IBAction)showPrefs:(id)sender
{
	[lsofPathTextField updateTextColoring];
	[prefsWindow center];
	[prefsWindow makeKeyAndOrderFront: sender];
}

- (IBAction)applyPrefs:(id)sender
{
	[prefsWindow performClose: self];
}

- (IBAction)restoreDefaultPrefs:(id)sender
{
	[lsofPathTextField setStringValue: PROGRAM_DEFAULT_LSOF_PATH];
}

/************************************************************************************
 Open window with lsof version information output
 ************************************************************************************/

- (NSString *) lsofVersionInfo
{
	BOOL			isDir;
	NSTask			*task;
	NSPipe			*pipe = [NSPipe pipe];
	NSData			*data;
    
	//get lsof path from prefs
	NSString *launchPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"lsofPath"];
	
	//make sure it exists
	if (![[NSFileManager defaultManager] fileExistsAtPath: launchPath isDirectory: &isDir] || isDir)
	{
		[STUtil alert: @"Invalid executable" subText: @"The 'lsof' utility you specified in the Preferences does not exist"];
		return NULL;
	}
	
	//run lsof -v to get version info
	task = [[NSTask alloc] init];
	[task setLaunchPath: launchPath];
	[task setArguments: [NSArray arrayWithObjects: @"-v", nil]];
	[task setStandardOutput: pipe];
	[task setStandardError: pipe];
	[task launch];
	
	//read the output from the command
	data = [[pipe fileHandleForReading] readDataToEndOfFile];
	
	[task release];
    
    return [[[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding] autorelease];
}

- (IBAction)showLsofVersionInfo:(id)sender
{
	[lsofVersionTextView setString: [self lsofVersionInfo]];
	[lsofVersionWindow center];
	[lsofVersionWindow makeKeyAndOrderFront: sender];
}

#pragma mark -

- (IBAction)supportSlothDevelopment:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: PROGRAM_DONATIONS]];
}

- (IBAction)visitSlothWebsite:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: PROGRAM_WEBSITE]];
}

@end

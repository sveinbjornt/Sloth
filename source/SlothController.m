/*
    Copyright (c) 2004-2016, Sveinbjorn Thordarson <sveinbjornt@gmail.com>
    Parts are Copyright (C) 2004-2006 Bill Bumgarner
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification,
    are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this
    list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice, this
    list of conditions and the following disclaimer in the documentation and/or other
    materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its contributors may
    be used to endorse or promote products derived from this software without specific
    prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
    IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
    INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
    NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
    PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

#import "SlothController.h"
#import "Common.h"
#import "Alerts.h"
#import "NSString+RegexMatching.h"

@interface SlothController ()
{
    IBOutlet NSWindow               *slothWindow;
    IBOutlet NSProgressIndicator    *progressBar;
    IBOutlet NSButton               *refreshButton;
    IBOutlet NSTextField            *filterTextField;
    IBOutlet NSTextField            *numItemsTextField;
    IBOutlet NSTableView            *tableView;
    IBOutlet NSButton               *revealButton;
    IBOutlet NSButton               *killButton;
    IBOutlet NSTextField            *lastRunTextField;
    
    NSMutableArray                  *fileArray;
    NSMutableArray                  *activeSet;
}

- (IBAction)reveal:(id)sender;
- (IBAction)refresh:(id)sender;
- (IBAction)kill:(id)sender;
- (IBAction)relaunchAsRoot:(id)sender;
- (IBAction)checkboxClicked:(id)sender;

@end

@implementation SlothController

- (instancetype)init {
	if ((self = [super init])) {
		fileArray = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (void)initialize {
    NSString *defaultsPath = [[NSBundle mainBundle] pathForResource:@"RegistrationDefaults" ofType:@"plist"];
	NSDictionary *registrationDefaults = [NSDictionary dictionaryWithContentsOfFile:defaultsPath];
    [DEFAULTS registerDefaults:registrationDefaults];
}

- (void)awakeFromNib {
    // put application icon in window title bar
    [slothWindow setRepresentedURL:[NSURL URLWithString:PROGRAM_WEBSITE]];
    NSButton *button = [slothWindow standardWindowButton:NSWindowDocumentIconButton];
    [button setImage:[NSApp applicationIconImage]];
    
	// sorting for tableview
	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
																	   ascending:YES
                                                                        selector:@selector(localizedCaseInsensitiveCompare:)];
	[tableView setSortDescriptors:@[nameSortDescriptor]];
	
	// dragging from tableview
	[tableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
	[tableView registerForDraggedTypes:@[NSStringPboardType]];
	
    [[slothWindow contentView] setWantsLayer:YES];
	[slothWindow makeKeyAndOrderFront:self];
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self refresh:self];
}

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu {
    // prevent popup menu when window icon/title is cmd-clicked
    return NO;
}

- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pasteboard {
    // prevent dragging of title bar icon
    return NO;
}

#pragma mark -

- (IBAction)refresh:(id)sender {
    
	[fileArray removeAllObjects];
    [refreshButton setEnabled:NO];
	
	[progressBar setUsesThreadedAnimation:TRUE];
	[progressBar startAnimation:self];
	
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [self updateWithLsofOutput];
        [self filterResults];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self updateItemCountTextField];
            // update last run time
//            [lastRunTextField setStringValue:[NSString stringWithFormat:@"Output at %@ ", [NSDate date]]];
            
            // stop progress indicator and reload data
            [tableView reloadData];
            [progressBar stopAnimation:self];
            
            [refreshButton setEnabled:YES];
        });
        
    });
}

- (void)updateItemCountTextField {
    NSString *str = [NSString stringWithFormat:@"Showing %d items of %d", (int)[activeSet count], (int)[fileArray count]];
    [numItemsTextField setStringValue:str];
    
}

- (void)updateWithLsofOutput {
    
    // our command is:			lsof -F pcnt +c0
    NSTask *lsof = [[NSTask alloc] init];
    [lsof setLaunchPath:PROGRAM_DEFAULT_LSOF_PATH];
    [lsof setArguments:@[@"-F", @"pcnt", @"+c0"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [lsof setStandardOutput:pipe];
    
    [lsof launch];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    
    //get data output and format as an array of lines of text
    NSString *output = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    
    NSString		*pid		= @"";
    NSString		*process	= @"";
    NSString		*ftype		= @"";
    
    // parse each line
    for (NSString *line in lines) {
        
        if ([line length] == 0) {
            continue;
        }
        
        //read first character in line
        if ([line characterAtIndex:0] == 'p')
        {
            pid = [line substringFromIndex:1];
        }
        else if ([line characterAtIndex:0] == 'c')
        {
            process = [line substringFromIndex:1];
        }
        else if ([line characterAtIndex:0] == 't')
        {
            ftype = [line substringFromIndex:1];
        }
        else if ([line characterAtIndex:0] == 'n')
        {
            //we don't report Sloth or lsof info
            if ([process isEqualToString:PROGRAM_NAME] || [process isEqualToString:PROGRAM_LSOF_NAME]) {
                continue;
            }
            
            //check if we use full path
            NSString *filePath = [line substringFromIndex:1];
            NSString *fileName = filePath;

            if ([filePath length] && [filePath characterAtIndex:0] == '/') {
                fileName = [filePath lastPathComponent];
            }
            
            //order matters, see below
            NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
            fileInfo[@"pname"] = process;
            fileInfo[@"pid"] = pid;
            fileInfo[@"filename"] = fileName;
            fileInfo[@"path"] = filePath;
            
            //insert the desired elements
            if ([ftype caseInsensitiveCompare:@"VREG"] == NSOrderedSame || [ftype caseInsensitiveCompare:@"REG"] == NSOrderedSame)
            {
                [fileInfo setObject:@"File" forKey:@"type"];
            }
            else if ([ftype caseInsensitiveCompare:@"VDIR"] == NSOrderedSame  || [ftype caseInsensitiveCompare:@"DIR"] == NSOrderedSame)
            {
                [fileInfo setObject:@"Directory" forKey:@"type"];
            }
            else if ([ftype caseInsensitiveCompare:@"IPv6"] == NSOrderedSame || [ftype caseInsensitiveCompare:@"IPv4"] == NSOrderedSame)
            {
                [fileInfo setObject:@"IP Socket" forKey:@"type"];
            }
            else  if ([ftype caseInsensitiveCompare:@"unix"] == NSOrderedSame)
            {
                [fileInfo setObject:@"Unix Socket" forKey:@"type"];
            } 
            else if ([ftype caseInsensitiveCompare:@"VCHR"] == NSOrderedSame || [ftype caseInsensitiveCompare:@"CHR"] == NSOrderedSame) 
            {
                [fileInfo setObject:@"Char Device" forKey:@"type"];
            }
            else
            {
                continue;
            }
            [fileArray addObject:fileInfo];
        }
    }
    
    activeSet = fileArray;
}

// creates a subset of the list of files based on our filtering criterion
- (void)filterResults
{
	NSMutableArray *subset = [[NSMutableArray alloc] init];
	
    BOOL showRegularFiles = [DEFAULTS boolForKey:@"showRegularFilesEnabled"];
    BOOL showDirectories = [DEFAULTS boolForKey:@"showDirectoriesEnabled"];
    BOOL showIPSockets = [DEFAULTS boolForKey:@"showIPSocketsEnabled"];
    BOOL showUnixSockets = [DEFAULTS boolForKey:@"showUnixSocketsEnabled"];
    BOOL showCharDevices = [DEFAULTS boolForKey:@"showCharacterDevicesEnabled"];
    
    NSString *filterString = [filterTextField stringValue];
    BOOL hasFilterString = [filterString length];
    NSRegularExpression *regex;
    if (hasFilterString) {
        regex = [NSRegularExpression regularExpressionWithPattern:filterString
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:nil];
    }
    
    for (NSDictionary *item in fileArray) {
        
		BOOL filtered = NO;
		
		// let's see if it gets filtered by the checkboxes
        NSString *type = item[@"type"];
		if (    ([type isEqualToString:@"File"] && !showRegularFiles) ||
                ([type isEqualToString:@"Directory"] && !showDirectories) ||
                ([type isEqualToString:@"IP Socket"] && !showIPSockets) ||
                ([type isEqualToString:@"Unix Socket"] && !showUnixSockets) ||
                ([type isEqualToString:@"Char Device"] && !showCharDevices) ) {
			filtered = YES;
        }
        
		// see if regex in search field filters it out
		if (filtered == NO && hasFilterString && regex)
		{
			if (    [item[@"pname"] isMatchedByRegex:regex] ||
                    [item[@"pid"] isMatchedByRegex:regex] ||
                    [item[@"path"] isMatchedByRegex:regex] ||
                    [item[@"type"] isMatchedByRegex:regex] ) {
                [subset addObject:item];
            }
		}
        else if (filtered == NO) {
			[subset addObject:item];
        }
	}
	
	activeSet = subset;
	
	/*	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
	 ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
	 
	 activeSet = [[NSMutableArray arrayWithArray:[subset sortedArrayUsingDescriptors:[NSArray arrayWithObject:nameSortDescriptor]] ] retain];
	 */
	
	//activeSet = [subset sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

#pragma mark -

- (IBAction)kill:(id)sender
{
	NSIndexSet *selectedRows = [tableView selectedRowIndexes];
	NSMutableDictionary *processesToTerminateNamed = [NSMutableDictionary dictionary];
	NSMutableDictionary *processesToTerminatePID = [NSMutableDictionary dictionary];
	
	// First, let's make sure there are selected items by checking for sane value
    if ([tableView selectedRow] < 0 || [tableView selectedRow] > [activeSet count]) {
		return;
    }
	
	// Let's get the PIDs and names of all selected processes, using dictionaries to avoid duplicate entries
	for (int i = 0; i < [activeSet count]; i++) {
		if ([selectedRows containsIndex:i]) {
			[processesToTerminateNamed setObject:[[activeSet objectAtIndex:i] objectForKey:@"name"] 
										  forKey:[[activeSet objectAtIndex:i] objectForKey:@"name"]];
			
			[processesToTerminatePID setObject:[[activeSet objectAtIndex:i] objectForKey:@"pid"] 
										forKey:[[activeSet objectAtIndex:i] objectForKey:@"name"]];
		}
	}
	
	// Create comma-separated list of selected processes
	NSString *processesToKillStr = [[processesToTerminateNamed allKeys] componentsJoinedByString:@", "];
	
	// Ask user to confirm that he really wants to kill these
	if ([Alerts proceedAlert:@"Are you sure you want to kill the selected processes?"
                      subText:[NSString stringWithFormat:@"This will terminate these processes:%@", processesToKillStr]
              withActionNamed:@"Kill"] == NO) {
		return;
    }
	
	// Get signal to send to process based on prefs
    int sigValue = SIGKILL;
	
	// iterate through list of PIDs, send each of them the kill/term signal
	for (int i = 0; i < [processesToTerminatePID count]; i++) {
		int pid = [[[processesToTerminatePID allValues] objectAtIndex:i] intValue];
		int ret = kill(pid, sigValue);
		if (ret) {
			[Alerts alert:[NSString stringWithFormat:@"Failed to kill process %@", [[processesToTerminateNamed allValues] objectAtIndex:i]]
				  subText:@"The process may be owned by another user.  Relaunch Sloth as root to kill it."];
			return;
		}
	}
	
	[self refresh:self];
}

- (IBAction)reveal:(id)sender {
	NSIndexSet *selectedRows = [tableView selectedRowIndexes];
	NSMutableDictionary *filesToReveal = [NSMutableDictionary dictionaryWithCapacity:65536];
	
	// First, let's make sure there are selected items by checking for sane value
    if ([tableView selectedRow] < 0 || [tableView selectedRow] > [activeSet count]) {
		return;
    }
	
	// Let's get the PIDs and names of all selected processes, using dictionaries to avoid duplicate entries
	for (int i = 0; i < [activeSet count]; i++)
	{
		if ([selectedRows containsIndex:i])
		{
			[filesToReveal setObject:[[activeSet objectAtIndex:i] objectForKey:@"fullPath"] 
							  forKey:[[activeSet objectAtIndex:i] objectForKey:@"fullPath"]];
		}
	}
	
	// if more than 3 items are selected, we ask the user to confirm
	if ([filesToReveal count] > 3)
	{
        if ([Alerts proceedAlert:@"Are you sure you want to reveal the selected files?"
                         subText:[NSString stringWithFormat:@"This will reveal %d files in the Finder", (int)[filesToReveal count]]
                 withActionNamed:@"Reveal"] == NO) {
			return;
        }
	}

	// iterate through files and reveal them in Finder
    for (NSString *path in filesToReveal) {
        [WORKSPACE selectFile:path inFileViewerRootedAtPath:path];
    }
}

#pragma mark -

- (IBAction)relaunchAsRoot:(id)sender {
	[WORKSPACE launchApplication:@"Terminal.app"];
	
	//the applescript command to run as root via sudo
	NSString *osaCmd = [NSString stringWithFormat:@"tell application \"Terminal\"\n\tdo script \"sudo -b '%@'\"\nend tell",  [[NSBundle mainBundle] executablePath]];
	
	//initialize task -- we launc the AppleScript via the 'osascript' CLI program
    NSTask *theTask = [[NSTask alloc] init];
    [theTask setLaunchPath:@"/usr/bin/osascript"];
	[theTask setArguments:@[@"-e", osaCmd]];
	[theTask launch];
	[theTask waitUntilExit];
	
	[[NSApplication sharedApplication] terminate:self];
}

#pragma mark - NSTableViewDataSource/Delegate

- (int)numberOfRowsInTableView:(NSTableView *)aTableView {
	return [activeSet count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    
    NSString *colIdentifier = [aTableColumn identifier];
    NSDictionary *item = [activeSet objectAtIndex:rowIndex];
    
    switch ([colIdentifier intValue]) {
        
        case 1:
            return item[@"pname"];
            break;
        case 2:
            return item[@"pid"];
            break;
        case 3:
            return item[@"type"];
            break;
        case 4:
        {
            NSString *key = [DEFAULTS boolForKey:@"showEntireFilePathEnabled"] ? @"path" : @"filename";
            return item[key];
        }
            break;
    }
    
//	if ([colIdentifier isEqualToString:@"1"])
//	{
//		return [[activeSet objectAtIndex:rowIndex] objectForKey:@"pname"];
//	}
//	else if ([colIdentifier isEqualToString:@"2"])
//	{
//		return [[activeSet objectAtIndex:rowIndex] objectForKey:@"pid"];
//	}
//	else if ([colIdentifier isEqualToString:@"3"])
//	{
//		return [[activeSet objectAtIndex:rowIndex] objectForKey:@"type"];
//	}
//	else if ([colIdentifier isEqualToString:@"4"])
//	{
//        return [[activeSet objectAtIndex:rowIndex] objectForKey:key];
//	}
	/*else if ([[aTableColumn identifier] caseInsensitiveCompare:@"5"] == NSOrderedSame)
	 {
	 return [[rows objectAtIndex:rowIndex] objectAtIndex:4]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare:@"6"] == NSOrderedSame)
	 {
	 return [[rows objectAtIndex:rowIndex] objectAtIndex:5]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare:@"7"] == NSOrderedSame)
	 {
	 return [[rows objectAtIndex:rowIndex] objectAtIndex:6]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare:@"8"] == NSOrderedSame)
	 {
	 return [[rows objectAtIndex:rowIndex] objectAtIndex:7]);
	 }
	 else if ([[aTableColumn identifier] caseInsensitiveCompare:@"9"] == NSOrderedSame)
	 {
	 return [[rows objectAtIndex:rowIndex] objectAtIndex:8]);
	 }*/
	return @"";
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors {
	NSArray *newDescriptors = [tableView sortDescriptors];
	[activeSet sortUsingDescriptors:newDescriptors];
	[tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	if ([tableView selectedRow] >= 0 && [tableView selectedRow] < [activeSet count]) {
		NSDictionary *item = [activeSet objectAtIndex:[tableView selectedRow]];
		BOOL canReveal = [FILEMGR fileExistsAtPath:item[@"path"]];
		[revealButton setEnabled:canReveal];
		[killButton setEnabled:YES];
	} else {
		[revealButton setEnabled:NO];
		[killButton setEnabled:NO];
	}
}

//- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard {
//	NSString *dragString = @"";
//	
//	// Iterate through the list of displayed rows, each one that is selected goes to the clipboard
//	for (int i = 0; i < [activeSet count]; i++) {
//		if ([rowIndexes containsIndex:i]) {
//			NSString *filePath;
//			
//			if ([DEFAULTS boolForKey:@"showEntireFilePathEnabled"])
//				filePath = [[activeSet objectAtIndex:i] objectForKey:@"path"];
//			else
//				filePath = [[activeSet objectAtIndex:i] objectForKey:@"filename"];
//			
//			NSString *rowString = [NSString stringWithFormat:@"%@\t%@\t%@\t%@\n",
//								   [[activeSet objectAtIndex:i] objectForKey:@"pname"],
//								   [[[activeSet objectAtIndex:i] objectForKey:@"pid"] stringValue],
//								   [[activeSet objectAtIndex:i] objectForKey:@"type"],
//								   filePath];
//			dragString = [dragString stringByAppendingString:rowString];
//		}
//	}
//	
//	[pboard declareTypes:@[NSStringPboardType] owner:self];
//	[pboard setString:dragString forType:NSStringPboardType];
//    
//	return YES;	
//}

#pragma mark -

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self filterResults];
    [self updateItemCountTextField];
    [tableView reloadData];
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem {
	//reveal in finder / kill process only enabled when something is selected
    if (( [[anItem title] isEqualToString:@"Reveal in Finder"] || [[anItem title] isEqualToString:@"Kill Process"]) && [tableView selectedRow] < 0) {
		return NO;
    }
	return YES;
}

- (IBAction)checkboxClicked:(id)sender {
	[self filterResults];
    [self updateItemCountTextField];
	[tableView reloadData];
}

#pragma mark -

- (IBAction)supportSlothDevelopment:(id)sender {
	[WORKSPACE openURL:[NSURL URLWithString:PROGRAM_DONATIONS]];
}

- (IBAction)visitSlothWebsite:(id)sender {
	[WORKSPACE openURL:[NSURL URLWithString:PROGRAM_WEBSITE]];
}

@end

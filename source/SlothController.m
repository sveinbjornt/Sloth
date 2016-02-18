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
    
    [tableView setTarget:self];
    [tableView setDoubleAction:@selector(rowDoubleClicked:)];

    // Observe defaults
    for (NSString *key in @[@"showCharacterDevicesEnabled",
                            @"showDirectoriesEnabled",
                            @"showEntireFilePathEnabled",
                            @"showIPSocketsEnabled",
                            @"showRegularFilesEnabled",
                            @"showUnixSocketsEnabled"]) {
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                                  forKeyPath:VALUES_KEYPATH(key)
                                                                     options:NSKeyValueObservingOptionNew
                                                                     context:NULL];
    }
    
    // Layer-backed window
    [[slothWindow contentView] setWantsLayer:YES];

    if ([DEFAULTS boolForKey:@"PreviouslyLaunched"] == NO) {
        [slothWindow center];
    }
	[slothWindow makeKeyAndOrderFront:self];
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [DEFAULTS setBool:YES forKey:@"PreviouslyLaunched"];
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

#pragma mark - Filtering

- (void)updateFiltering {
    [self filterResults];
    [self updateItemCountTextField];
    [tableView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self updateFiltering];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self updateFiltering];
}

- (void)updateItemCountTextField {
    NSString *str = [NSString stringWithFormat:@"Showing %d items of %d", (int)[activeSet count], (int)[fileArray count]];
    [numItemsTextField setStringValue:str];
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
        if (([type isEqualToString:@"File"] && !showRegularFiles) ||
            ([type isEqualToString:@"Directory"] && !showDirectories) ||
            ([type isEqualToString:@"IP Socket"] && !showIPSockets) ||
            ([type isEqualToString:@"Unix Socket"] && !showUnixSockets) ||
            ([type isEqualToString:@"Char Device"] && !showCharDevices)) {
            filtered = YES;
        }
        
        // see if regex in search field filters it out
        if (filtered == NO && hasFilterString && regex)
        {
            if ([item[@"pname"] isMatchedByRegex:regex] ||
                [item[@"pid"] isMatchedByRegex:regex] ||
                [item[@"path"] isMatchedByRegex:regex] ||
                [item[@"type"] isMatchedByRegex:regex]) {
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

#pragma mark - Update/parse results

- (IBAction)refresh:(id)sender {
    
	[fileArray removeAllObjects];
    [refreshButton setEnabled:NO];
	
	[progressBar setUsesThreadedAnimation:TRUE];
	[progressBar startAnimation:self];
	
    // update in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [self updateWithLsofOutput];
        [self filterResults];
        
        // update UI on main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateItemCountTextField];
            [tableView reloadData];
            [progressBar stopAnimation:self];
            [refreshButton setEnabled:YES];
        });
        
    });
}

- (void)updateWithLsofOutput {
    
    // our command is: lsof -F pcnt +c0
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
    
    NSString *pid = @"";
    NSString *process = @"";
    NSString *ftype = @"";
    
    // parse each line
    for (NSString *line in lines) {
        
        if ([line length] == 0) {
            continue;
        }
        
        switch ([line characterAtIndex:0]) {
            case 'p':
                pid = [line substringFromIndex:1];
                break;
            
            case 'c':
                process = [line substringFromIndex:1];
                break;
                
            case 't':
                ftype = [line substringFromIndex:1];
                break;
            
            case 'n':
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
                if ([ftype isEqualToString:@"VREG"] || [ftype isEqualToString:@"REG"]) {
                    fileInfo[@"type"] = @"File";
                }
                else if ([ftype isEqualToString:@"VDIR"] || [ftype isEqualToString:@"DIR"]) {
                    fileInfo[@"type"] = @"Directory";
                }
                else if ([ftype isEqualToString:@"IPv6"] || [ftype isEqualToString:@"IPv4"]) {
                    fileInfo[@"type"] = @"IP Socket";
                }
                else  if ([ftype isEqualToString:@"unix"]) {
                    fileInfo[@"type"] = @"Unix Socket";
                }
                else if ([ftype isEqualToString:@"VCHR"] || [ftype isEqualToString:@"CHR"]) {
                    fileInfo[@"type"] = @"Char Device";
                }
                else {
                    continue;
                }
                [fileArray addObject:fileInfo];

            }
                break;
        }
    }
    
    activeSet = fileArray;
}

#pragma mark - Interface

- (IBAction)kill:(id)sender {
    
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
			processesToTerminateNamed[activeSet[i][@"name"]] = activeSet[i][@"name"];
			
			processesToTerminatePID[activeSet[i][@"name"]] = activeSet[i][@"pid"];
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
		int pid = [[processesToTerminatePID allValues][i] intValue];
		int ret = kill(pid, sigValue);
		if (ret) {
			[Alerts alert:[NSString stringWithFormat:@"Failed to kill process %@", [processesToTerminateNamed allValues][i]]
				  subText:@"The process may be owned by another user.  Relaunch Sloth as root to kill it."];
			return;
		}
	}
	
	[self refresh:self];
}

- (IBAction)reveal:(id)sender {
    NSInteger rowNumber = [tableView selectedRow];
    [self showItem:activeSet[rowNumber]];
}

- (void)rowDoubleClicked:(id)object {
    NSInteger rowNumber = [tableView clickedRow];
    [self showItem:activeSet[rowNumber]];
}

- (void)showItem:(NSDictionary *)item {
    NSString *path = item[@"path"];
    if (path && [FILEMGR fileExistsAtPath:path]) {
        [WORKSPACE selectFile:path inFileViewerRootedAtPath:path];
    } else {
        NSBeep();
    }
}

#pragma mark - NSTableViewDataSource/Delegate

- (int)numberOfRowsInTableView:(NSTableView *)aTableView {
	return [activeSet count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    
    NSString *colIdentifier = [aTableColumn identifier];
    NSDictionary *item = activeSet[rowIndex];
    
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
    
	return @"";
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors {
	NSArray *newDescriptors = [tableView sortDescriptors];
	[activeSet sortUsingDescriptors:newDescriptors];
	[tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	if ([tableView selectedRow] >= 0 && [tableView selectedRow] < [activeSet count]) {
		NSDictionary *item = activeSet[[tableView selectedRow]];
		BOOL canReveal = [FILEMGR fileExistsAtPath:item[@"path"]];
		[revealButton setEnabled:canReveal];
		[killButton setEnabled:YES];
	} else {
		[revealButton setEnabled:NO];
		[killButton setEnabled:NO];
	}
}

#pragma mark - Menus

- (BOOL)validateMenuItem:(NSMenuItem *)anItem {
    //reveal in finder / kill process only enabled when something is selected
    if (( [[anItem title] isEqualToString:@"Reveal in Finder"] || [[anItem title] isEqualToString:@"Kill Process"]) && [tableView selectedRow] < 0) {
        return NO;
    }
    return YES;
}

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

- (IBAction)supportSlothDevelopment:(id)sender {
	[WORKSPACE openURL:[NSURL URLWithString:PROGRAM_DONATIONS]];
}

- (IBAction)visitSlothWebsite:(id)sender {
	[WORKSPACE openURL:[NSURL URLWithString:PROGRAM_WEBSITE]];
}

@end

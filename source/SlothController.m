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

#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
#import <stdio.h>
#import <unistd.h>
#import <dlfcn.h>

// New error code denoting that AuthorizationExecuteWithPrivileges no longer exists
OSStatus const errAuthorizationFnNoLongerExists = -70001;

@interface SlothController ()
{
    IBOutlet NSWindow *window;
    IBOutlet NSProgressIndicator *progressIndicator;
    IBOutlet NSButton *refreshButton;
    IBOutlet NSTextField *filterTextField;
    IBOutlet NSTextField *numItemsTextField;
    IBOutlet NSTableView *tableView;
    IBOutlet NSButton *revealButton;
    IBOutlet NSButton *killButton;
    
    IBOutlet NSOutlineView *outlineView;
    
    NSMutableArray *itemArray;
    NSMutableArray *activeItemSet;
    
    NSMutableDictionary *processIconDict;
    NSImage *genericExecutableIcon;
    int processCount;
    
    AuthorizationRef authorizationRef;
    BOOL authenticated;
    
    NSMutableArray *list;
}
@end

@implementation SlothController

- (instancetype)init {
	if ((self = [super init])) {
		itemArray = [[NSMutableArray alloc] init];
        processIconDict = [[NSMutableDictionary alloc] init];
        genericExecutableIcon = [[NSImage alloc] initByReferencingFile:GENERIC_EXEC_ICON_PATH];
        
        NSDictionary *firstParent = [NSDictionary dictionaryWithObjectsAndKeys:@"Foo",@"parent",[NSArray arrayWithObjects:@"Foox",@"Fooz", nil],@"children", nil];
        NSDictionary *secondParent = [NSDictionary dictionaryWithObjectsAndKeys:@"Bar",@"parent",[NSArray arrayWithObjects:@"Barx",@"Barz", nil],@"children", nil];
        list = [NSMutableArray arrayWithObjects:firstParent,secondParent, nil];
        

    }
    return self;
}

+ (void)initialize {
    NSString *defaultsPath = [[NSBundle mainBundle] pathForResource:@"RegistrationDefaults" ofType:@"plist"];
	NSDictionary *registrationDefaults = [NSDictionary dictionaryWithContentsOfFile:defaultsPath];
    [DEFAULTS registerDefaults:registrationDefaults];
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // put application icon in window title bar
    [window setRepresentedURL:[NSURL URLWithString:@""]];
    NSButton *button = [window standardWindowButton:NSWindowDocumentIconButton];
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
    [[window contentView] setWantsLayer:YES];
    
    if ([DEFAULTS boolForKey:@"PreviouslyLaunched"] == NO) {
        [window center];
    }
    [window makeKeyAndOrderFront:self];

    
    [DEFAULTS setBool:YES forKey:@"PreviouslyLaunched"];
    [self refresh:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self deauthenticate];
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
    activeItemSet = [self filterItems:itemArray];
    [self updateItemCountTextField];
    [tableView reloadData];
    [outlineView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [self updateFiltering];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self updateFiltering];
}

- (void)updateItemCountTextField {
    NSString *str = [NSString stringWithFormat:@"Showing %d items of %d", (int)[activeItemSet count], (int)[itemArray count]];
    [numItemsTextField setStringValue:str];
}

// creates a subset of the list based on our filtering criterion
- (NSMutableArray *)filterItems:(NSMutableArray *)items
{
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
    
    BOOL showAllTypes = (showRegularFiles && showDirectories && showIPSockets
                         && showUnixSockets && showCharDevices);
    if (showAllTypes && !hasFilterString) {
        return items;
    }
    
    NSMutableArray *subset = [[NSMutableArray alloc] init];
    
    for (NSDictionary *item in items) {
        
        BOOL filtered = NO;
        
        // let's see if it gets filtered by type
        if (showAllTypes == NO) {
            NSString *type = item[@"type"];
            if (([type isEqualToString:@"File"] && !showRegularFiles) ||
                ([type isEqualToString:@"Directory"] && !showDirectories) ||
                ([type isEqualToString:@"IP Socket"] && !showIPSockets) ||
                ([type isEqualToString:@"Unix Socket"] && !showUnixSockets) ||
                ([type isEqualToString:@"Char Device"] && !showCharDevices)) {
                filtered = YES;
            }
        }
        
        // see if it matches regex in search field filter
        if (filtered == NO && hasFilterString && regex)
        {
            if (([item[@"pname"] isMatchedByRegex:regex] ||
                [item[@"pid"] isMatchedByRegex:regex] ||
                [item[@"path"] isMatchedByRegex:regex] ||
                [item[@"type"] isMatchedByRegex:regex]) == NO) {
                filtered = YES;
            }
        }
        
        if (filtered == NO) {
            [subset addObject:item];
        }
    }
    
    return subset;
    
    /*	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name"
     ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
     
     activeSet = [[NSMutableArray arrayWithArray:[subset sortedArrayUsingDescriptors:[NSArray arrayWithObject:nameSortDescriptor]] ] retain];
     */
    
    //activeSet = [subset sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

#pragma mark - Update/parse results

- (IBAction)refresh:(id)sender {
    
	[itemArray removeAllObjects];
    [refreshButton setEnabled:NO];
	
	[progressIndicator setUsesThreadedAnimation:TRUE];
	[progressIndicator startAnimation:self];
	
    // update in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
        
            NSString *output = [self runLsof:authenticated];
            itemArray = [self parseLsofOutput:output];
            activeItemSet = [self filterItems:itemArray];
            
            // then update UI on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateItemCountTextField];
                [tableView reloadData];
                [outlineView reloadData];
                [progressIndicator stopAnimation:self];
                [refreshButton setEnabled:YES];
                [[tableView tableColumnWithIdentifier:@"pname"] setTitle:[NSString stringWithFormat:@"Processes (%d)", processCount]];
            });
        }
    });
}

- (NSString *)runLsof:(BOOL)isAuthenticated {
    // our command is: lsof -F pcnt +c0
    NSData *outputData;
    
    if (isAuthenticated) {
        
        const char *toolPath = [PROGRAM_DEFAULT_LSOF_PATH fileSystemRepresentation];
        NSArray *arguments = PROGRAM_LSOF_ARGS;
        NSUInteger numberOfArguments = [arguments count];
        char *args[numberOfArguments + 1];
        FILE *outputFile;
        
        // first, construct an array of c strings from NSArray w. arguments
        for (int i = 0; i < numberOfArguments; i++) {
            NSString *argString = arguments[i];
            NSUInteger stringLength = [argString length];
            
            args[i] = malloc((stringLength + 1) * sizeof(char));
            snprintf(args[i], stringLength + 1, "%s", [argString fileSystemRepresentation]);
        }
        args[numberOfArguments] = NULL;
        
        //use Authorization Reference to execute script with privileges
        OSStatus err = AuthorizationExecuteWithPrivileges(authorizationRef, toolPath, kAuthorizationFlagDefaults, args, &outputFile);
        
        // free the malloc'd argument strings
        for (int i = 0; i < numberOfArguments; i++) {
            free(args[i]);
        }

        NSFileHandle *outputFileHandle = [[NSFileHandle alloc] initWithFileDescriptor:fileno(outputFile) closeOnDealloc:YES];
        
        outputData = [outputFileHandle readDataToEndOfFile];
        
    } else {
        
        NSTask *lsof = [[NSTask alloc] init];
        [lsof setLaunchPath:PROGRAM_DEFAULT_LSOF_PATH];
        [lsof setArguments:PROGRAM_LSOF_ARGS];
        
        NSPipe *pipe = [NSPipe pipe];
        [lsof setStandardOutput:pipe];
        [lsof launch];
        
        outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
    }
    
    return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
}

- (NSMutableArray *)parseLsofOutput:(NSString *)outputString {
    // split into array of lines of text
    NSArray *lines = [outputString componentsSeparatedByString:@"\n"];
    
    NSMutableDictionary *processDict = [NSMutableDictionary dictionaryWithCapacity:1000];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:100000];
    
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
                
                if (processDict[process] == nil) {
                    processDict[process] = @{    @"name": process,
                                                 @"files": [NSMutableArray array]
                                            };
                }
                
                [processDict[process][@"files"] addObject:fileInfo[@"path"]];
                
                [items addObject:fileInfo];
            }
                break;
        }
    }
    
    [list removeAllObjects];
    for (NSString *k in [processDict allKeys]) {
        [list addObject:processDict[k]];
    }
    
    NSLog([list description]);
    
    return items;
}

#pragma mark - Interface

- (BOOL)killProcess:(int)pid {
    int sigValue = SIGKILL;
    int ret = kill(pid, sigValue);
    return (ret == 0);
}

- (IBAction)kill:(id)sender {
    NSUInteger selectedRow = [tableView selectedRow];
    NSDictionary *item = activeItemSet[selectedRow];
    int pid = [item[@"pid"] intValue];
	
	// Ask user to confirm that he really wants to kill these
    NSString *q = [NSString stringWithFormat:@"Are you sure you want to kill \"%@\"?", item[@"pname"]];
	if ([Alerts proceedAlert:q subText:@"This will send the process a SIGKILL signal." withActionNamed:@"Kill"] == NO) {
		return;
    }
	
    if ([self killProcess:pid] == NO) {
        [Alerts alert:@"Failed to kill process"
        subTextFormat:@"Could not kill process %@ (PID: %d)", item[@"pname"], pid];
			return;
	}
	
	[self refresh:self];
}

- (IBAction)showButtonClicked:(id)sender {
    NSInteger rowNumber = [tableView selectedRow];
    [self revealItemInFinder:activeItemSet[rowNumber]];
}

- (void)rowDoubleClicked:(id)object {
    NSInteger rowNumber = [tableView clickedRow];
    [self revealItemInFinder:activeItemSet[rowNumber]];
}

- (void)revealItemInFinder:(NSDictionary *)item {
    NSString *path = item[@"path"];
    if ([self canRevealItemAtPath:path]) {
        [WORKSPACE selectFile:path inFileViewerRootedAtPath:path];
    } else {
        NSBeep();
    }
}

- (BOOL)canRevealItemAtPath:(NSString *)path {
    return path && [FILEMGR fileExistsAtPath:path] && ![path hasPrefix:@"/dev/"];
}

- (NSImage *)iconForItem:(NSDictionary *)item {
    NSString *pid = item[@"pid"];
    
    ProcessSerialNumber psn;
    GetProcessForPID([pid intValue], &psn);
    NSDictionary *pInfoDict = (__bridge NSDictionary *)ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);
    
    if (pInfoDict[@"BundlePath"] && [pInfoDict[@"BundlePath"] hasSuffix:@".app"]) {
//        NSLog(@"Fetching for PID: %@ %@", pid, pInfoDict[@"BundlePath"]);
        processIconDict[pid] = [WORKSPACE iconForFile:pInfoDict[@"BundlePath"]];
    } else {
        processIconDict[pid] = genericExecutableIcon;
    }
    
//    [processIconDict[pid] setSize:NSMakeSize(16, 16)];
    
    return processIconDict[pid];
}

#pragma mark - Authentication

- (IBAction)lockWasClicked:(id)sender {
    if (!authenticated) {
        OSStatus err = [self authenticate];
        if (err == errAuthorizationSuccess) {
            authenticated = YES;
        } else {
            
            if (err == errAuthorizationFnNoLongerExists) {
                [Alerts alert:@"Authentication not available"
                      subText:@"Authentication does not work in this version of OS X"];
                return;
            }
            
            if (err != errAuthorizationCanceled) {
                NSBeep();
            }
            
            return;
        }
    } else {
        [self deauthenticate];
        authenticated = NO;
    }
    
    NSString *imgName = authenticated ? @"UnlockedIcon.icns" : @"LockedIcon.icns";
    [sender setImage:[NSImage imageNamed:imgName]];
}

- (OSStatus)authenticate {
    OSStatus err = noErr;
    const char *toolPath = [PROGRAM_DEFAULT_LSOF_PATH fileSystemRepresentation];
    
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // Create function pointer to AuthorizationExecuteWithPrivileges
    // in case it doesn't exist in this version of OS X
    static OSStatus (*_AuthExecuteWithPrivsFn)(AuthorizationRef authorization, const char *pathToTool, AuthorizationFlags options,
                                               char * const *arguments, FILE **communicationsPipe) = NULL;
    
    // Check to see if we have the correct function in our loaded libraries
    if (!_AuthExecuteWithPrivsFn) {
        // On 10.7, AuthorizationExecuteWithPrivileges is deprecated. We want
        // to still use it since there's no good alternative (without requiring
        // code signing). We'll look up the function through dyld and fail if
        // it is no longer accessible. If Apple removes the function entirely
        // this will fail gracefully. If they keep the function and throw some
        // sort of exception, this won't fail gracefully, but that's a risk
        // we'll have to take for now.
        // Pattern by Andy Kim from Potion Factory LLC
        _AuthExecuteWithPrivsFn = dlsym(RTLD_DEFAULT, "AuthorizationExecuteWithPrivileges");
        if (!_AuthExecuteWithPrivsFn) {
            // This version of OS X has finally removed this function. Exit with an error.
            err = errAuthorizationFnNoLongerExists;
            return err;
        }
    }
    
    // create authorization reference
    err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
    if (err != errAuthorizationSuccess) {
        return err;
    }
    
    // pre-authorize the privileged operation
    err = AuthorizationCopyRights(authorizationRef, &myRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (err != errAuthorizationSuccess) {
        return err;
    }

    return noErr;
}

- (void)deauthenticate {
    if (authorizationRef) {
        AuthorizationFree(authorizationRef, kAuthorizationFlagDestroyRights);
    }
}

#pragma mark - NSOutlineViewDataSource/Delegate

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if ([item isKindOfClass:[NSDictionary class]]) {
        return YES;
    }else {
        return NO;
    }
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    
    if (item == nil) { //item is nil when the outline view wants to inquire for root level items
        return [list count];
    }
    
    if ([item isKindOfClass:[NSDictionary class]]) {
        return [[item objectForKey:@"files"] count];
    }
    
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    
    if (item == nil) { //item is nil when the outline view wants to inquire for root level items
        return [list objectAtIndex:index];
    }
    
    if ([item isKindOfClass:[NSDictionary class]]) {
        return [[item objectForKey:@"files"] objectAtIndex:index];
    }
    
    return nil;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)theColumn byItem:(id)item
{
    
    if ([[theColumn identifier] isEqualToString:@"children"]) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            return [item objectForKey:@"name"];
        }
        return item;
    }
    
    return nil;
}


#pragma mark - NSTableViewDataSource/Delegate

- (int)numberOfRowsInTableView:(NSTableView *)aTableView {
	return [activeItemSet count];
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSDictionary *item = [activeItemSet objectAtIndex:row];
    NSString *identifier = [tableColumn identifier];
    
    if ([identifier isEqualToString:@"pname"]) {
        __block NSTableCellView *cellView = [tv makeViewWithIdentifier:identifier owner:self];

        cellView.textField.stringValue = item[@"pname"];
        NSImage *icon = processIconDict[item[@"pid"]];
        
        if (icon) {
            cellView.imageView.objectValue = icon;
        } else {
//            dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                __block NSImage *icon = [self iconForItem:item];
//                
//                // update UI on main thread
//                dispatch_sync(dispatch_get_main_queue(), ^{
                    cellView.imageView.objectValue = icon;
//                });
                
//            });
        }
//        cellView.imageView.objectValue = genericExecutableIcon;//
        return cellView;
    }
    
    for (NSString *k in @[@"pid", @"type", @"path"]) {
        if ([identifier isEqualToString:k]) {
            NSTextField *textField = [tv makeViewWithIdentifier:identifier owner:self];
            textField.objectValue = item[k];
            return textField;
        }
    }
    
    NSAssert1(NO, @"Unhandled table column identifier %@", identifier);
    
    return nil;
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors {
	NSArray *newDescriptors = [tableView sortDescriptors];
	[activeItemSet sortUsingDescriptors:newDescriptors];
	[tableView reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	if ([tableView selectedRow] >= 0 && [tableView selectedRow] < [activeItemSet count]) {
		NSDictionary *item = activeItemSet[[tableView selectedRow]];
        [revealButton setEnabled:[self canRevealItemAtPath:item[@"path"]]];
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

- (IBAction)visitSlothOnGitHubWebsite:(id)sender {
    [WORKSPACE openURL:[NSURL URLWithString:PROGRAM_GITHUB_WEBSITE]];
}

@end

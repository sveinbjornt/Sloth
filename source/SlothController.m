/*
    Copyright (c) 2004-2018, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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
#import "NSString+RegexConvenience.h"
#import "InfoPanelController.h"
#import "ProcessUtils.h"
#import "NSWorkspace+Additions.h"
#import "STPrivilegedTask.h"

#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
#import <stdio.h>
#import <unistd.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <pwd.h>

@interface SlothController ()
{
    IBOutlet NSWindow *window;
    
    IBOutlet NSMenu *itemContextualMenu;
    IBOutlet NSMenu *sortMenu;
    IBOutlet NSMenu *interfaceSizeSubmenu;
    IBOutlet NSMenu *accessModeSubmenu;
    IBOutlet NSMenu *filterMenu;
    IBOutlet NSMenu *openWithMenu;
    
    IBOutlet NSPopUpButton *volumesPopupButton;
    IBOutlet NSMenuItem *volumesMenuItem;
    
    IBOutlet NSProgressIndicator *progressIndicator;
    
    IBOutlet NSTextField *filterTextField;
    IBOutlet NSTextField *numItemsTextField;

    IBOutlet NSButton *revealButton;
    IBOutlet NSButton *killButton;
    IBOutlet NSButton *getInfoButton;
    
    IBOutlet NSButton *authenticateButton;
    IBOutlet NSMenuItem *authenticateMenuItem;
    
    IBOutlet NSButton *refreshButton;
    IBOutlet NSButton *disclosureButton;
    IBOutlet NSTextField *disclosureTextField;
    
    IBOutlet NSOutlineView *outlineView;
    IBOutlet NSTreeController *treeController;

    IBOutlet NSImageView *cellImageView;
    IBOutlet NSTextField *cellTextField;
    
    NSDictionary *type2icon;
    NSImage *genericExecutableIcon;
    
    AuthorizationRef authorizationRef;
    BOOL authenticated;
    BOOL isRefreshing;
    
    NSTimer *filterTimer;
    
    InfoPanelController *infoPanelController;
}
@property int totalFileCount;
@property (strong) IBOutlet NSMutableArray *content;
@property (strong) NSMutableArray *unfilteredContent;
@property (retain, nonatomic) NSArray *sortDescriptors;

@end

@implementation SlothController

- (instancetype)init {
    if ((self = [super init])) {
        genericExecutableIcon = [[NSImage alloc] initWithContentsOfFile:GENERIC_EXEC_ICON_PATH];
        
        // Mark these icons as templates so they're inverted on selection
        [[NSImage imageNamed:@"Socket"] setTemplate:YES];
        [[NSImage imageNamed:@"Pipe"] setTemplate:YES];

        // Map item types to icons
        type2icon = @{
            @"File": [NSImage imageNamed:@"NSGenericDocument"],
            @"Directory": [NSImage imageNamed:@"NSFolder"],
            @"Character Device": [NSImage imageNamed:@"NSActionTemplate"],
            @"Unix Socket": [NSImage imageNamed:@"Socket"],
            @"IP Socket": [NSImage imageNamed:@"NSNetwork"],
            @"Pipe": [NSImage imageNamed:@"Pipe"],

            // Just for Filter menu
            @"Applications": [NSImage imageNamed:@"NSDefaultApplicationIcon"],
            @"Home": [WORKSPACE iconForFileType:NSFileTypeForHFSTypeCode(kToolbarHomeIcon)]
        };
        
        _content = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *defaultsPath = [[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"];
        [DEFAULTS registerDefaults:[NSDictionary dictionaryWithContentsOfFile:defaultsPath]];
    });
}

- (IBAction)restoreDefaults:(id)sender {
    [DEFAULTS setBool:NO forKey:@"dnsLookup"];
    [DEFAULTS setBool:NO forKey:@"showProcessBinaries"];
    [DEFAULTS setBool:NO forKey:@"showCurrentWorkingDirectories"];
    [DEFAULTS setBool:YES forKey:@"friendlyProcessNames"];
    [DEFAULTS setBool:NO forKey:@"authenticateOnLaunch"];
    [DEFAULTS synchronize];
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Make sure lsof exists on the system
    if ([FILEMGR fileExistsAtPath:PROGRAM_LSOF_SYSTEM_PATH] == NO) {
        [Alerts fatalAlert:@"System corrupt" subTextFormat:@"No binary at path %@", PROGRAM_LSOF_SYSTEM_PATH];
        [[NSApplication sharedApplication] terminate:self];
    }
    
    // Put application icon in window title bar
    [window setRepresentedURL:[NSURL URLWithString:@""]];
    [[window standardWindowButton:NSWindowDocumentIconButton] setImage:[NSApp applicationIconImage]];
    
    // Hide Authenticate button & menu item if AEWP
    // is not available in this version of OS X
    if ([STPrivilegedTask authorizationFunctionAvailable] == NO) {
        [authenticateButton setHidden:YES];
        [authenticateMenuItem setAction:nil];
    }
    
    // Load system lock icon and set as icon for button & menu
    NSImage *lockIcon = [WORKSPACE iconForFileType:NSFileTypeForHFSTypeCode(kLockedIcon)];
    [lockIcon setSize:NSMakeSize(16, 16)];
    [authenticateButton setImage:lockIcon];
    [authenticateMenuItem setImage:lockIcon];
    
    [volumesMenuItem setSubmenu:[volumesPopupButton menu]];
    [filterTextField setStringValue:@""];
    
    // For some reason, IB isn't respecting template
    // settings so we have to do this manually (sigh)
    [[NSImage imageNamed:@"Kill"] setTemplate:YES];
    [[NSImage imageNamed:@"Kill"] setSize:NSMakeSize(20, 20)];
    [[NSImage imageNamed:@"Info"] setTemplate:YES];
    [[NSImage imageNamed:@"Info"] setSize:NSMakeSize(20, 20)];
    
    // Manually check the correct menu items for these submenus
    // on launch since we (annoyingly) can't use bindings for it
    [self checkItemWithTitle:[DEFAULTS stringForKey:@"interfaceSize"] inMenu:interfaceSizeSubmenu];
    [self checkItemWithTitle:[DEFAULTS stringForKey:@"accessMode"] inMenu:accessModeSubmenu];
    
    // Set icons for items in Filter menu
    NSArray<NSMenuItem *> *items = [filterMenu itemArray];
    for (NSMenuItem *i in items) {
        NSString *type = [i toolTip];
        if (type2icon[type]) {
            NSImage *img = type2icon[type];
            [img setSize:NSMakeSize(16, 16)];
            [i setImage:img];
        }
    }

    // Start observing defaults
    for (NSString *key in @[@"showCharacterDevices",
                            @"showDirectories",
                            @"showIPSockets",
                            @"showRegularFiles",
                            @"showUnixSockets",
                            @"showPipes",
                            @"showApplicationsOnly",
                            @"showHomeFolderOnly",
                            @"accessMode",
                            @"interfaceSize",
                            @"searchFilterCaseSensitive",
                            @"searchFilterRegex"]) {
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                                  forKeyPath:VALUES_KEYPATH(key)
                                                                     options:NSKeyValueObservingOptionNew
                                                                     context:NULL];
    }
    
    // Configure outline view
    [outlineView setDoubleAction:@selector(rowDoubleClicked:)];
    [outlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
    
    [self updateDiscloseControl];

    [self updateSorting];

    // Layer-backed window
    [[window contentView] setWantsLayer:YES];
    
    // If launching for the first time, center window
    if ([DEFAULTS boolForKey:@"PreviouslyLaunched"] == NO) {
        [window center];
        [DEFAULTS setBool:YES forKey:@"PreviouslyLaunched"];
    }
    [window makeKeyAndOrderFront:self];
    
    if ([DEFAULTS boolForKey:@"authenticateOnLaunch"]) {
        [self toggleAuthentication:self];
    }
    
    // Refresh immediately when app is launched
    [self refresh:self];
}

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu {
    // Prevent popup menu when window icon/title is cmd-clicked
    return NO;
}

- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pasteboard {
    // Prevent dragging of title bar icon
    return NO;
}

#pragma mark - Get and parse lsof results

- (IBAction)refresh:(id)sender {
    isRefreshing = YES;
    [numItemsTextField setStringValue:@""];
    [outlineView deselectAll:self];
    
    // Disable controls
    [refreshButton setEnabled:NO];
    [outlineView setEnabled:NO];
    [outlineView setAlphaValue:0.5];
    [filterTextField setEnabled:NO];
    
    // Center progress indicator and set it off
//    CGFloat x = (NSWidth([window.contentView bounds]) - NSWidth([progressIndicator frame])) / 2;
//    CGFloat y = (NSHeight([window.contentView bounds]) - NSHeight([progressIndicator frame])) / 2;
//    [progressIndicator setFrameOrigin:NSMakePoint(0,0)];
//    [progressIndicator setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [progressIndicator setUsesThreadedAnimation:TRUE];
    [progressIndicator startAnimation:self];

    // Run lsof asynchronously in the background, so interface doesn't lock up
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @autoreleasepool {
            NSString *output = [self runLsof:authenticated];

            int fileCount;
            self.unfilteredContent = [self parseLsofOutput:output numFiles:&fileCount];
            self.totalFileCount = fileCount;
            
            // Then update UI on main thread once task is done
            dispatch_async(dispatch_get_main_queue(), ^{
                
                // Re-enable controls
                [progressIndicator stopAnimation:self];
                [outlineView setEnabled:YES];
                [outlineView setAlphaValue:1.0];
                [refreshButton setEnabled:YES];
                [filterTextField setEnabled:YES];
                
                isRefreshing = NO;
                
                // Filter results
                [self updateFiltering];
            });
        }
    });
}

- (NSString *)lsofPath {
    return PROGRAM_LSOF_SYSTEM_PATH;
}

- (NSMutableArray *)lsofArguments {
    NSMutableArray *arguments = [PROGRAM_LSOF_ARGS mutableCopy];
    if ([DEFAULTS boolForKey:@"dnsLookup"] == NO) {
        // Add arguments to disable dns and port name lookup
        [arguments addObjectsFromArray:PROGRAM_LSOF_NO_DNS_ARGS];
    }
    return arguments;
}

- (NSString *)runLsof:(BOOL)isAuthenticated {
    NSData *outputData;
    
    if (isAuthenticated) {
        
        STPrivilegedTask *task = [[STPrivilegedTask alloc] init];
        [task setLaunchPath:[self lsofPath]];
        [task setArguments:[self lsofArguments]];
        [task launchWithAuthorization:authorizationRef];
        
        outputData = [[task outputFileHandle] readDataToEndOfFile];
        
    } else {
        
        NSTask *lsof = [[NSTask alloc] init];
        [lsof setLaunchPath:[self lsofPath]];
        [lsof setArguments:[self lsofArguments]];
        
        NSPipe *pipe = [NSPipe pipe];
        [lsof setStandardOutput:pipe];
        [lsof setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        [lsof setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
        [lsof launch];
        
        outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
    }
    
    return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
}

- (NSMutableArray *)parseLsofOutput:(NSString *)outputString numFiles:(int *)numFiles {
    // Lsof output has the following format:
    //
    //    p113                              // PROCESS INFO STARTS (pid)
    //    cloginwindow                          // name
    //    u501                                  // uid
    //    fcwd                              // FILE INFO STARTS (file descriptor)
    //    a                                     // access mode
    //    tDIR                                  // type
    //    n/path/to/directory                   // name / path
    //    f0                                // FILE INFO STARTS (file descriptor)
    //    au                                    // access mode
    //    tCHR                                  // type
    //    n/dev/null                            // name / path
    //    ...
    
    NSMutableArray *processList = [NSMutableArray array];
    *numFiles = 0;
    
    if (![outputString length]) {
        return processList;
    }
    
    NSMutableDictionary *currentProcess;
    NSMutableDictionary *currentFile;
    BOOL skip = FALSE;

    // Parse each line
    for (NSString *line in [outputString componentsSeparatedByString:@"\n"]) {
        if ([line length] == 0) {
            continue;
        }
        
        switch ([line characterAtIndex:0]) {
            
            // PID - First line of output for new process
            case 'p':
            {
                if (currentProcess && currentFile && !skip) {
                    [currentProcess[@"children"] addObject:currentFile];
                    currentFile = nil;
                    
                }
                
                // Set up new process dict
                currentProcess = [NSMutableDictionary dictionary];
                currentProcess[@"pid"] = [line substringFromIndex:1];
                currentProcess[@"type"] = @"Process";
                currentProcess[@"children"] = [NSMutableArray array];
                [processList addObject:currentProcess];                
            }
                break;
                
            // Process name
            case 'c':
                currentProcess[@"name"] = [line substringFromIndex:1];
                currentProcess[@"displayname"] = currentProcess[@"name"];
                break;
                
            // Process UID
            case 'u':
                currentProcess[@"userid"] = [line substringFromIndex:1];
                break;
            
            // File descriptor - First line of output for a file
            case 'f':
            {
                if (currentFile && !skip) {
                    [currentProcess[@"children"] addObject:currentFile];
                    currentFile = nil;
                }
                
                // New file info starting, create new file dict
                currentFile = [NSMutableDictionary dictionary];
                NSString *fd = [line substringFromIndex:1];
                currentFile[@"fd"] = fd;
                currentFile[@"pname"] = currentProcess[@"name"];
                currentFile[@"pid"] = currentProcess[@"pid"];
                currentFile[@"puserid"] = currentProcess[@"userid"];
                
                // txt files are program code, such as the application binary itself or a shared library
                if ([fd isEqualToString:@"txt"] && ![DEFAULTS boolForKey:@"showProcessBinaries"]) {
                    skip = TRUE;
                }
                // cwd and twd are current working directory and thread working directory, respectively
                else if (([fd isEqualToString:@"cwd"] || [fd isEqualToString:@"twd"]) && ![DEFAULTS boolForKey:@"showCurrentWorkingDirectories"]) {
                    skip = TRUE;
                }
                else {
                    skip = FALSE;
                }
            }
                break;
            
            // File access mode
            case 'a':
                currentFile[@"accessmode"] = [line substringFromIndex:1];
                break;
                
            // File type
            case 't':
            {
                NSString *ftype = [line substringFromIndex:1];
                
                if ([ftype isEqualToString:@"VREG"] || [ftype isEqualToString:@"REG"]) {
                    currentFile[@"type"] = @"File";
                }
                else if ([ftype isEqualToString:@"VDIR"] || [ftype isEqualToString:@"DIR"]) {
                    currentFile[@"type"] = @"Directory";
                }
                else if ([ftype isEqualToString:@"IPv6"] || [ftype isEqualToString:@"IPv4"]) {
                    currentFile[@"type"] = @"IP Socket";
                    currentFile[@"ipversion"] = ftype;
                }
                else  if ([ftype isEqualToString:@"unix"]) {
                    currentFile[@"type"] = @"Unix Socket";
                }
                else if ([ftype isEqualToString:@"VCHR"] || [ftype isEqualToString:@"CHR"]) {
                    currentFile[@"type"] = @"Character Device";
                }
                else if ([ftype isEqualToString:@"PIPE"]) {
                    currentFile[@"type"] = @"Pipe";
                    if ([currentFile[@"name"] isEqualToString:@""]) {
                        currentFile[@"displayname"] = @"Unnamed Pipe";
                    }
                }
                else {
                    //NSLog(@"Unrecognized file type: %@ : %@", ftype, [fileInfo description]);
                    skip = TRUE;
                }
                
                if (currentFile[@"type"]) {
                    currentFile[@"image"] = type2icon[currentFile[@"type"]];
                }
            }
                break;
            
            // File name / path
            case 'n':
            {
                currentFile[@"name"] = [line substringFromIndex:1];
                currentFile[@"displayname"] = currentFile[@"name"];
                
                // Some files when running in root mode have no type listed
                // and are only reported with the name "(revoked)". Skip those.
                if (!currentFile[@"type"] && [currentFile[@"name"] isEqualToString:@"(revoked)"]) {
                    skip = TRUE;
                }
            }
                break;
            
            // Protocol (IP sockets only)
            case 'P':
                currentFile[@"protocol"] = [line substringFromIndex:1];
                break;
                
            // TCP socket info (IP sockets only)
            case 'T':
            {
                NSString *socketInfo = [line substringFromIndex:1];
                if ([socketInfo hasPrefix:@"ST="]) {
                    currentFile[@"socketstate"] = [socketInfo substringFromIndex:3];
                }
                currentFile[@"displayname"] = [NSString stringWithFormat:@"%@ (%@)", currentFile[@"name"], currentFile[@"socketstate"]];
            }
                break;
        }
    }
    
    // Add the one remaining output item
    if (currentProcess && currentFile && !skip) {
        [currentProcess[@"children"] addObject:currentFile];
        currentFile = nil;
    }
    
    // Get additional info about the processes
    for (NSMutableDictionary *process in processList) {
        [self updateProcessInfo:process];
        *numFiles += [process[@"children"] count];
    }
        
    return processList;
}

// Get all sorts of additional info about process
// and then add it to the process info dictionary
- (void)updateProcessInfo:(NSMutableDictionary *)p {
    
    if (p[@"image"] == nil) {
        pid_t pid = [p[@"pid"] intValue];
        
        NSString *bundlePath = [ProcessUtils bundlePathForPID:pid];
        
        if (bundlePath) {
            p[@"image"] = [WORKSPACE iconForFile:bundlePath];
            p[@"bundle"] = @YES;
            p[@"app"] = @([ProcessUtils isAppProcess:pid]);
            p[@"path"] = bundlePath;
        } else {
            p[@"image"] = genericExecutableIcon;
            p[@"bundle"] = @NO;
            p[@"app"] = @NO;
            p[@"path"] = [ProcessUtils executablePathForPID:pid];
        }

        p[@"psn"] = [ProcessUtils carbonProcessSerialNumberForPID:pid];
        
        // On Mac OS X, lsof truncates process names that are longer than
        // 32 characters since it uses libproc. We can do better than that.
        if ([DEFAULTS boolForKey:@"friendlyProcessNames"]) {
            p[@"pname"] = [ProcessUtils macProcessNameForPID:pid];
        }
        if (!p[@"pname"]) {
            p[@"pname"] = [ProcessUtils fullKernelProcessNameForPID:pid];
        }
        if (!p[@"pname"]) {
            p[@"pname"] = [ProcessUtils procNameForPID:pid];
        }
        if (!p[@"pname"]) {
            p[@"pname"] = p[@"name"];
        }
        
        // Set process icon for all children (i.e. files)
        for (NSMutableDictionary *item in p[@"children"]) {
            item[@"pimage"] = p[@"image"];
        }
    }
    
    // Update display name to show number of open files for process
    p[@"displayname"] = [NSString stringWithFormat:@"%@ (%d)", p[@"pname"], (int)[p[@"children"] count]];
}

#pragma mark - Filtering

- (void)updateProcessCountHeader {
    NSString *headerTitle = [NSString stringWithFormat:@"%d processes - sorted by %@", (int)[self.content count], [DEFAULTS stringForKey:@"sortBy"]];
    [[[outlineView tableColumnWithIdentifier:@"children"] headerCell] setStringValue:headerTitle];
}

- (void)updateFiltering {
    if (isRefreshing) {
        return;
    }
    //NSLog(@"Filtering");
    
    // Filter content
    int matchingFilesCount = 0;
    self.content = [self filterContent:self.unfilteredContent numberOfMatchingFiles:&matchingFilesCount];
    
    // Update outline view header
    [self updateProcessCountHeader];
    
    // Update num items label
    NSString *str = [NSString stringWithFormat:@"Showing %d out of %d items", matchingFilesCount, self.totalFileCount];
    [numItemsTextField setStringValue:str];
    
    [outlineView reloadData];
    
    if ([DEFAULTS boolForKey:@"disclosure"]) {
        [outlineView expandItem:nil expandChildren:YES];
    } else {
        [outlineView collapseItem:nil collapseChildren:YES];
    }
}

// User typed in search filter
- (void)controlTextDidChange:(NSNotification *)aNotification {
    if (filterTimer) {
        [filterTimer invalidate];
    }
    filterTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateFiltering) userInfo:nil repeats:NO];
}

// VolumesPopUpDelegate
- (void)volumeSelectionChanged:(NSString *)volumePath {
    [self performSelector:@selector(updateFiltering) withObject:nil afterDelay:0.05];
}

// Some default changed
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([VALUES_KEYPATH(@"interfaceSize") isEqualToString:keyPath]) {
        [outlineView reloadData];
        return;
    }
    // The default that changed was one of the filters
    [self updateFiltering];
}

// Filter content according to active filters
- (NSMutableArray *)filterContent:(NSMutableArray *)unfilteredContent numberOfMatchingFiles:(int *)matchingFilesCount {
    
    BOOL showRegularFiles = [DEFAULTS boolForKey:@"showRegularFiles"];
    BOOL showDirectories = [DEFAULTS boolForKey:@"showDirectories"];
    BOOL showIPSockets = [DEFAULTS boolForKey:@"showIPSockets"];
    BOOL showUnixSockets = [DEFAULTS boolForKey:@"showUnixSockets"];
    BOOL showCharDevices = [DEFAULTS boolForKey:@"showCharacterDevices"];
    BOOL showPipes = [DEFAULTS boolForKey:@"showPipes"];
    
    BOOL showApplicationsOnly = [DEFAULTS boolForKey:@"showApplicationsOnly"];
    BOOL showHomeFolderOnly = [DEFAULTS boolForKey:@"showHomeFolderOnly"];
    
    BOOL searchCaseSensitive = [DEFAULTS boolForKey:@"searchFilterCaseSensitive"];
    BOOL searchUsesRegex = [DEFAULTS boolForKey:@"searchFilterRegex"];
    
    // Access mode filter
    NSString *accessModeFilter = [DEFAULTS stringForKey:@"accessMode"];
    BOOL hasAccessModeFilter = ([accessModeFilter isEqualToString:@"Any"] == NO);
    
    // Volumes filter
    NSString *volumesFilter = nil;
    BOOL hasVolumesFilter = ([[[volumesPopupButton selectedItem] title] isEqualToString:@"All"] == NO);
    if (hasVolumesFilter) {
        volumesFilter = [[volumesPopupButton selectedItem] toolTip];
    }
    
    // Path filters such as by volume or home folder should
    // exclude everything that isn't a file or directory
    if (hasVolumesFilter || showHomeFolderOnly) {
        showIPSockets = FALSE;
        showUnixSockets = FALSE;
        showCharDevices = FALSE;
        showPipes = FALSE;
    }
    
    // User home dir path prefix
    NSString *homeDirPath = NSHomeDirectory();
    
    // Search field filter
    NSMutableArray *searchFilters = [NSMutableArray array];
    NSString *fieldString = [[filterTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *filterStrings = [fieldString componentsSeparatedByString:@" "];
    
    for (NSString *fs in filterStrings) {
        NSString *s = [fs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([s length] == 0) {
            continue;
        }
        
        if (searchUsesRegex) {
            NSError *err;
            NSRegularExpressionOptions options = searchCaseSensitive ? 0 : NSRegularExpressionCaseInsensitive;
            
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:s
                                                                                   options:options
                                                                                     error:&err];
            if (!regex) {
                NSLog(@"Error creating regex: %@", [err localizedDescription]);
                continue;
            }
            [searchFilters addObject:regex];
        } else {
            [searchFilters addObject:s];
        }
    }
    
    BOOL hasSearchFilter = ([searchFilters count] > 0);
    BOOL showAllProcessTypes = !showApplicationsOnly;
    BOOL showAllItemTypes = (showRegularFiles &&
                             showDirectories &&
                             showIPSockets &&
                             showUnixSockets &&
                             showCharDevices &&
                             showPipes &&
                             !showHomeFolderOnly &&
                             !hasVolumesFilter);
    
    // Minor optimization: If there is no filtering, just return
    // unfiltered content instead of iterating over all items
    if (showAllItemTypes && showAllProcessTypes && !hasSearchFilter && !hasAccessModeFilter) {
        *matchingFilesCount = self.totalFileCount;
        return unfilteredContent;
    }
    
    NSMutableArray *filteredContent = [NSMutableArray array];
    
    // Iterate over each process, filter the children
    for (NSMutableDictionary *process in self.unfilteredContent) {
        
        NSMutableArray *matchingFiles = [NSMutableArray array];
        
        for (NSDictionary *file in process[@"children"]) {
            
            // Let's see if child gets filtered by type or path
            if (showAllItemTypes == NO) {
                
                if (showHomeFolderOnly && ![file[@"name"] hasPrefix:homeDirPath]) {
                    continue;
                }
                
                if (volumesFilter && ![file[@"name"] hasPrefix:volumesFilter]) {
                    continue;
                }
                
                NSString *type = file[@"type"];
                if (([type isEqualToString:@"File"] && !showRegularFiles) ||
                    ([type isEqualToString:@"Directory"] && !showDirectories) ||
                    ([type isEqualToString:@"IP Socket"] && !showIPSockets) ||
                    ([type isEqualToString:@"Unix Socket"] && !showUnixSockets) ||
                    ([type isEqualToString:@"Character Device"] && !showCharDevices) ||
                    ([type isEqualToString:@"Pipe"] && !showPipes)) {
                    continue;
                }
            }
            
            // Filter by access mode
            if (hasAccessModeFilter) {
                NSString *mode = file[@"accessmode"];
                if ([accessModeFilter isEqualToString:@"Read"] && ![mode isEqualToString:@"r"]) {
                    continue;
                }
                if ([accessModeFilter isEqualToString:@"Write"] && ![mode isEqualToString:@"w"]) {
                    continue;
                }
                if ([accessModeFilter isEqualToString:@"Read/Write"] && ![mode isEqualToString:@"u"]) {
                    continue;
                }
            }
            
            // See if it matches regex in search field filter
            if (hasSearchFilter) {
                
                int matchCount = 0;
                
                if (searchUsesRegex) {
                    
                    // Regex search
                    for (NSRegularExpression *regex in searchFilters) {
                        if (!([file[@"name"] isMatchedByRegex:regex] ||
                              [file[@"pname"] isMatchedByRegex:regex] ||
                              [file[@"pid"] isMatchedByRegex:regex] ||
                              [file[@"protocol"] isMatchedByRegex:regex] ||
                              [file[@"ipversion"] isMatchedByRegex:regex] ||
                              [file[@"socketstate"] isMatchedByRegex:regex])) {
                            break;
                        }
                        matchCount += 1;
                    }
                    
                } else {
                    
                    // Non-regex search
                    NSStringCompareOptions options = searchCaseSensitive ? 0 : NSCaseInsensitiveSearch;
                    
                    for (NSString *searchStr in searchFilters) {
                        if ([file[@"name"] rangeOfString:searchStr options:options].location == NSNotFound &&
                            [file[@"pname"] rangeOfString:searchStr options:options].location == NSNotFound &&
                            [file[@"pid"] rangeOfString:searchStr options:options].location == NSNotFound) {
                            break;
                        }
                        matchCount += 1;
                    }
                }
                
                // Skip if it doesn't match all filter strings
                if (matchCount != [searchFilters count]) {
                    continue;
                }
            }
            
            [matchingFiles addObject:file];
        }
        
        // If we have matching files for the process, and it's not being excluded as a non-app
        if ([matchingFiles count] && !(showApplicationsOnly && ![process[@"app"] boolValue])) {
            NSMutableDictionary *p = [process mutableCopy];
            p[@"children"] = matchingFiles;
            [self updateProcessInfo:p];
            [filteredContent addObject:p];
            *matchingFilesCount += [matchingFiles count];
        }
    }
    
    return filteredContent;
}

#pragma mark - Interface actions

- (IBAction)open:(id)sender {
    NSInteger selectedRow = ([outlineView clickedRow] == -1) ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    NSString *path = item[@"name"];
    
    if ([WORKSPACE canRevealFileAtPath:path] == NO || [WORKSPACE openFile:path] == NO) {
        NSBeep();
    }
}

- (BOOL)killProcess:(int)pid asRoot:(BOOL)asRoot {
    if (!asRoot) {
        return (kill(pid, SIGKILL) == 0);
    }
    
    // Kill process as root
    const char *toolPath = [@"/bin/kill" fileSystemRepresentation];
    
    AuthorizationRef authRef;
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // Create authorization reference
    OSStatus err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authRef);
    if (err != errAuthorizationSuccess) {
        return NO;
    }
    
    // Pre-authorize the privileged operation
    err = AuthorizationCopyRights(authRef, &myRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (err != errAuthorizationSuccess) {
        return NO;
    }
    
    // Create and launch authorized task
    STPrivilegedTask *task = [[STPrivilegedTask alloc] init];
    [task setLaunchPath:@(toolPath)];
    [task setArguments:@[@"-9", [NSString stringWithFormat:@"%d", pid]]];
    [task launchWithAuthorization:authRef];
    
    AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
    
    return YES;
}

- (IBAction)kill:(id)sender {
    NSInteger selectedRow = ([outlineView clickedRow] == -1) ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    
    if (item[@"pid"] == nil) {
        NSBeep();
        return;
    }
    
    int pid = [item[@"pid"] intValue];
    
    // Confirm
    BOOL optionKeyDown = (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) == NSAlternateKeyMask);
    if (optionKeyDown == NO) {
        if ([Alerts proceedAlert:[NSString stringWithFormat:@"Are you sure you want to kill “%@” (%d)?", item[@"pname"], pid]
                         subText:@"This will send the process a SIGKILL signal. Hold the option key (⌥) to avoid this prompt."
                 withActionNamed:@"Kill"] == NO) {
            return;
        }
    }

    // Kill it
    BOOL ownsProcess = [ProcessUtils isProcessOwnedByCurrentUser:pid];
    if ([self killProcess:pid asRoot:!ownsProcess] == NO) {
        [Alerts alert:@"Failed to kill process"
        subTextFormat:@"Could not kill process %@ (PID: %d)", item[@"pname"], pid];
        return;
    }
    
    [self refresh:self];
}

- (IBAction)show:(id)sender {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    [self revealItemInFinder:item];
}

- (IBAction)showInfoInFinder:(id)sender {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    [WORKSPACE showFinderGetInfoForFile:path];
}

- (IBAction)moveToTrash:(id)sender {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    
    BOOL optionKeyDown = (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) == NSAlternateKeyMask);
    if (!optionKeyDown) {
        // Ask user to confirm
        if ([Alerts proceedAlert:[NSString stringWithFormat:@"Move “%@” to the Trash?", [path lastPathComponent]]
                         subText:@"This will tell the Finder to move the specified file into your Trash folder. \
Hold the option key (⌥) to avoid this prompt."
                 withActionNamed:@"Move to Trash"] == NO) {
            return;
        }
    }
    
    // Move to trash, refresh in a bit to give Finder time to complete command. Tends to be slow :/
    if ([WORKSPACE moveFileToTrash:path]) {
        [self performSelector:@selector(outlineViewSelectionDidChange:) withObject:nil afterDelay:0.4];
        [outlineView performSelector:@selector(reloadData) withObject:nil afterDelay:0.6];
    }
}

- (IBAction)getInfo:(id)sender {
    NSInteger selectedRow = [outlineView selectedRow];
    if (selectedRow >= 0) {
        [self showInfoPanelForItem:[[outlineView itemAtRow:selectedRow] representedObject]];
    } else {
        NSBeep();
    }
}

- (void)showInfoPanelForItem:(NSDictionary *)item {
    // Create info panel lazily
    if (infoPanelController == nil) {
        infoPanelController = [[InfoPanelController alloc] initWithWindowNibName:@"InfoPanel"];
    }
    [infoPanelController loadItem:item];
    [infoPanelController showWindow:self];
}

// Called when user selects Copy menu item via Edit or contextual menu
- (void)copy:(id)sender {
    NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
    [pasteBoard clearContents];
    
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    if (selectedRow == -1) {
        NSBeep();
        return;
    }
    
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    
    // Write to pasteboard
    if ([FILEMGR fileExistsAtPath:item[@"name"]]) {
        [pasteBoard declareTypes:@[NSFilenamesPboardType] owner:nil];
        [pasteBoard setPropertyList:@[item[@"name"]] forType:NSFilenamesPboardType];
    }
    [pasteBoard setString:item[@"name"] forType:NSStringPboardType];
}

- (void)rowDoubleClicked:(id)object {
    NSInteger rowNumber = [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:rowNumber] representedObject];
    
    BOOL cmdKeyDown = (([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask) == NSCommandKeyMask);
    
    if (cmdKeyDown) {
        [self revealItemInFinder:item];
    } else {
        [self showInfoPanelForItem:item];
    }
}

- (void)revealItemInFinder:(NSDictionary *)item {
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    if ([WORKSPACE canRevealFileAtPath:path]) {
        if ([WORKSPACE selectFile:path inFileViewerRootedAtPath:[path stringByDeletingLastPathComponent]]) {
            return;
        }
    }
    NSBeep();
}

#pragma mark - Disclosure

- (IBAction)disclosureChanged:(id)sender {
    if ([DEFAULTS boolForKey:@"disclosure"]) {
        [outlineView expandItem:nil expandChildren:YES];
    } else {
        [outlineView collapseItem:nil collapseChildren:YES];
    }
    [self updateDiscloseControl];
}

- (void)updateDiscloseControl {
    if ([DEFAULTS boolForKey:@"disclosure"]) {
        [disclosureTextField setStringValue:@"Collapse all"];
        [disclosureButton setIntValue:1];
    } else {
        [disclosureTextField setStringValue:@"Expand all"];
        [disclosureButton setIntValue:0];
    }
}

#pragma mark - Sort

- (IBAction)sortChanged:(id)sender {
    NSArray *comp = [[sender title] componentsSeparatedByString:@" by "];
    NSString *sortBy = [[comp lastObject] lowercaseString];
    [DEFAULTS setObject:sortBy forKey:@"sortBy"];
    [self updateProcessCountHeader];
    [self updateSorting];
}

- (void)updateSorting {
    NSString *sortBy = [DEFAULTS objectForKey:@"sortBy"];
    
    // Default to sorting alphabetically by name
    NSSortDescriptor *sortDesc = [[NSSortDescriptor alloc] initWithKey:@"pname"
                                                             ascending:[DEFAULTS boolForKey:@"ascending"]
                                                              selector:@selector(localizedCaseInsensitiveCompare:)];
    
    // Integer comparison for string values block
    NSComparator integerComparisonBlock = ^(id first,id second) {
        NSUInteger cnt1 = [first intValue];
        NSUInteger cnt2 = [second intValue];
        
        if (cnt1 < cnt2) {
            return NSOrderedAscending;
        } else if (cnt1 > cnt2) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    };
    
    // Number of children (i.e. file count) comparison block
    NSComparator numChildrenComparisonBlock = ^(id first,id second) {
        NSUInteger cnt1 = [first count];
        NSUInteger cnt2 = [second count];
        
        if (cnt1 < cnt2) {
            return NSOrderedAscending;
        } else if (cnt1 > cnt2) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    };
    
    if ([sortBy isEqualToString:@"process id"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"pid"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:integerComparisonBlock];
    }
    
    if ([sortBy isEqualToString:@"user id"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"userid"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:integerComparisonBlock];
    }
    
    if ([sortBy isEqualToString:@"file count"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"children"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:numChildrenComparisonBlock];
    }
    
    self.sortDescriptors = @[sortDesc];
}

#pragma mark - Authentication

- (IBAction)toggleAuthentication:(id)sender {
    if (isRefreshing) {
        NSBeep();
        return;
    }
    
    if (!authenticated) {
        OSStatus err = [self authenticate];
        if (err == errAuthorizationSuccess) {
            authenticated = YES;
        } else {
            if (err != errAuthorizationCanceled) {
                NSBeep();
                NSLog(@"Authentication failed: %d", err);
            }
            return;
        }
    } else {
        [self deauthenticate];
    }
    
    OSType lockIconID = authenticated ? kUnlockedIcon : kLockedIcon;
    NSImage *img = [WORKSPACE iconForFileType:NSFileTypeForHFSTypeCode(lockIconID)];
    [img setSize:NSMakeSize(16, 16)];
    NSString *actionName = authenticated ? @"Deauthenticate" : @"Authenticate";
    NSString *ttip = authenticated ? @"Deauthenticate" : @"Authenticate to view all system processes";
    
    [authenticateButton setImage:img];
    [authenticateButton setToolTip:ttip];
    [authenticateMenuItem setImage:img];
    [authenticateMenuItem setTitle:actionName];
    [authenticateMenuItem setToolTip:ttip];
    
    [self refresh:self];
}

- (OSStatus)authenticate {
    OSStatus err = noErr;
    const char *toolPath = [[self lsofPath] fileSystemRepresentation];
    
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // Create authorization reference
    err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
    if (err != errAuthorizationSuccess) {
        return err;
    }
    
    // Pre-authorize the privileged operation
    err = AuthorizationCopyRights(authorizationRef, &myRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (err != errAuthorizationSuccess) {
        return err;
    }

    return noErr;
}

- (void)deauthenticate {
    if (authorizationRef) {
        AuthorizationFree(authorizationRef, kAuthorizationFlagDestroyRights);
        authorizationRef = NULL;
    }
    authenticated = NO;
}

#pragma mark - NSOutlineViewDelegate

- (void)outlineView:(NSOutlineView *)ov didClickTableColumn:(NSTableColumn *)tableColumn {
    [DEFAULTS setBool:![DEFAULTS boolForKey:@"ascending"] forKey:@"ascending"];
    [self updateSorting];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger selectedRow = [outlineView selectedRow];
    
    if (selectedRow >= 0) {
        NSMutableDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
        BOOL canReveal = [WORKSPACE canRevealFileAtPath:item[@"name"]];
        BOOL hasBundlePath = [WORKSPACE canRevealFileAtPath:item[@"path"]];
        [revealButton setEnabled:(canReveal || hasBundlePath)];
        [getInfoButton setEnabled:YES];
        [killButton setEnabled:YES];
        [infoPanelController loadItem:item];
        
        // We make the file path red if file has been moved or deleted
        if ([item[@"type"] isEqualToString:@"File"] || [item[@"type"] isEqualToString:@"Directory"]) {
            NSColor *color = canReveal ? [NSColor controlTextColor] : [NSColor redColor];
            item[@"displayname"] = [[NSAttributedString alloc] initWithString:item[@"name"]
                                                                   attributes:@{NSForegroundColorAttributeName: color}];
        }
    } else {
        [revealButton setEnabled:NO];
        [killButton setEnabled:NO];
        [getInfoButton setEnabled:NO];
        if (infoPanelController) {
            [[infoPanelController window] orderOut:self];
        }
    }
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    NSString *size = [DEFAULTS stringForKey:@"interfaceSize"];
    return [size isEqualToString:@"Compact"] ? 16.f : 20.f;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard {
    NSDictionary *item = [items[0] representedObject];
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    if (![FILEMGR fileExistsAtPath:path]) {
        return NO;
    }
    
    [pboard declareTypes:@[NSFilenamesPboardType] owner:self];
    [pboard setPropertyList:@[item[@"name"]] forType:NSFilenamesPboardType];
    [pboard setString:item[@"name"] forType:NSStringPboardType];
    
    return YES;
}

#pragma mark - Menus

- (void)menuWillOpen:(NSMenu *)menu {
    
    if (menu == sortMenu) {
        // Bindings should do this for us! Grr...
        NSArray *items = [menu itemArray];
        for (NSMenuItem *i in items) {
            NSControlStateValue on = [[[i title] lowercaseString] hasSuffix:[DEFAULTS objectForKey:@"sortBy"]];
            [i setState:on];
        }
        return;
    }
    
    // Dynamically generate contextual menu for item
    if (menu == itemContextualMenu) {
        NSDictionary *item = [[outlineView itemAtRow:[outlineView selectedRow]] representedObject];
        
        NSMenuItem *openItem = [itemContextualMenu itemAtIndex:0];
        NSMenuItem *copyItem = [itemContextualMenu itemAtIndex:9];
        NSMenuItem *killItem = [itemContextualMenu itemAtIndex:11];
        
        [killItem setTitle:[NSString stringWithFormat:@"Kill Process “%@” (%@)", item[@"pname"], item[@"pid"]]];
        
        if ([WORKSPACE canRevealFileAtPath:item[@"name"]]) {
    
            NSString *openTitle = @"Open";
            NSString *defaultApp = [WORKSPACE defaultHandlerApplicationForFile:item[@"name"]];
            if (defaultApp) {
                openTitle = [NSString stringWithFormat:@"Open with %@", [[defaultApp lastPathComponent] stringByDeletingPathExtension]];
            }
            
            [openItem setTitle:openTitle];
            [copyItem setTitle:[NSString stringWithFormat:@"Copy “%@”", [item[@"name"] lastPathComponent]]];
            
        } else {
            [openItem setTitle:@"Open"];
            [copyItem setTitle:@"Copy"];
        }

        return;
    }
    
    // Dynamically generate Open With submenu for item
    if (menu == [[itemContextualMenu itemAtIndex:1] submenu] || menu == openWithMenu) {
        NSDictionary *item = [[outlineView itemAtRow:[outlineView selectedRow]] representedObject];
        NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
        if ([item[@"type"] isEqualToString:@"Process"]) {
            path = nil;
        }
        [WORKSPACE openWithMenuForFile:path target:nil action:nil menu:menu];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    SEL action = [menuItem action];
    
    BOOL isAction = (action == @selector(show:) ||
                     action == @selector(showInfoInFinder:) ||
                     action == @selector(kill:) ||
                     action == @selector(getInfo:) ||
                     action == @selector(open:));
    
    // Actions on items should only be enabled when something is selected
    if (isAction && selectedRow < 0) {
        return NO;
    }
    
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    
    BOOL canReveal = [WORKSPACE canRevealFileAtPath:path];
    BOOL isProcess = [item[@"type"] isEqualToString:@"Process"];
    
    // Processes/apps can't be opened/trashed
    if (isProcess && action == @selector(open:)) {
        return NO;
    }
    if (isProcess && action == @selector(moveToTrash:)) {
        return NO;
    }

    // Only enabled for files the Finder can handle
    if (canReveal == NO && (action == @selector(show:) ||
                            action == @selector(showInfoInFinder:) ||
                            action == @selector(open:) ||
                            action == @selector(moveToTrash:))) {
        return NO;
    }
    
    if ((action == @selector(refresh:) || action == @selector(toggleAuthentication:)) && isRefreshing) {
        return NO;
    }
    
    return YES;
}

- (void)checkItemWithTitle:(NSString *)title inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in [menu itemArray]) {
        [item setState:NSControlStateValueOff];
    }
    [[menu itemWithTitle:title] setState:NSControlStateValueOn];
}

- (IBAction)interfaceSizeMenuItemSelected:(id)sender {
    [DEFAULTS setObject:[sender title] forKey:@"interfaceSize"];
    [self checkItemWithTitle:[sender title] inMenu:interfaceSizeSubmenu];
}

- (IBAction)accessModeMenuItemSelected:(id)sender {
    [DEFAULTS setObject:[sender title] forKey:@"accessMode"];
    [self checkItemWithTitle:[sender title] inMenu:accessModeSubmenu];
}

- (IBAction)find:(id)sender {
    [window makeFirstResponder:filterTextField];
}

- (IBAction)searchFieldOptionChanged:(id)sender {
    NSMenuItem *item = sender;
    NSString *key = [sender tag] ? @"searchFilterRegex" : @"searchFilterCaseSensitive";
    [DEFAULTS setBool:![DEFAULTS boolForKey:key] forKey:key]; // toggle
    // We shouldn't have to do this but bindings are flaky for NSSearchField menu templates
    [item setState:[DEFAULTS boolForKey:key]];
}

#pragma mark - Open websites

- (IBAction)visitSlothWebsite:(id)sender {
    [WORKSPACE openURL:[NSURL URLWithString:PROGRAM_WEBSITE]];
}

- (IBAction)visitSlothOnGitHubWebsite:(id)sender {
    [WORKSPACE openURL:[NSURL URLWithString:PROGRAM_GITHUB_WEBSITE]];
}

- (IBAction)supportSlothDevelopment:(id)sender {
    [WORKSPACE openURL:[NSURL URLWithString:PROGRAM_DONATIONS]];
}

@end

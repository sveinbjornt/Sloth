/*
    Copyright (c) 2004-2018, Sveinbjorn Thordarson <sveinbjornt@gmail.com>
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
#import "InfoPanelController.h"

#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
#import <stdio.h>
#import <unistd.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <stdlib.h>
#import <pwd.h>
#import <stdio.h>

// Function pointer to AuthorizationExecuteWithPrivileges
// in case it doesn't exist in this version of OS X
static OSStatus (*_AuthExecuteWithPrivsFn)(AuthorizationRef authorization,
                                           const char *pathToTool,
                                           AuthorizationFlags options,
                                           char * const *arguments,
                                           FILE **communicationsPipe) = NULL;

static inline uid_t uid_for_pid(pid_t pid) {
    uid_t uid = -1;
    
    struct kinfo_proc process;
    size_t proc_buf_size = sizeof(process);
    
    // Compose search path for sysctl. Here you can specify PID directly.
    const u_int path_len = 4;
    int path[path_len] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    
    int sysctl_result = sysctl(path, path_len, &process, &proc_buf_size, NULL, 0);
    
    // If sysctl did not fail and process with PID available - take UID.
    if ((sysctl_result == 0) && (proc_buf_size != 0)) {
        uid = process.kp_eproc.e_ucred.cr_uid;
    }
    
    return uid;
}

@interface SlothController ()
{
    IBOutlet NSWindow *window;
    
    IBOutlet NSMenu *sortMenu;
    IBOutlet NSMenu *interfaceSizeSubmenu;
    IBOutlet NSMenu *accessModeSubmenu;
    IBOutlet NSMenu *volumesMenu;
    IBOutlet NSMenu *filterMenu;
    IBOutlet NSPopUpButton *volumesPopupButton;
    
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
        type2icon = @{      @"File": [NSImage imageNamed:@"NSGenericDocument"],
                            @"Directory": [NSImage imageNamed:@"NSFolder"],
                            @"Character Device": [NSImage imageNamed:@"NSActionTemplate"],
                            @"Unix Socket": [NSImage imageNamed:@"Socket"],
                            @"IP Socket": [NSImage imageNamed:@"NSNetwork"],
                            @"Pipe": [NSImage imageNamed:@"Pipe"],
                            
                            // just for filter menu
                            @"Applications": [NSImage imageNamed:@"NSDefaultApplicationIcon"],
                            @"Home": [WORKSPACE iconForFileType:NSFileTypeForHFSTypeCode(kToolbarHomeIcon)]
                    };
        
        _content = [[NSMutableArray alloc] init];
        
        authorizationRef = NULL;
    }
    return self;
}

+ (void)initialize {
    NSString *defaultsPath = [[NSBundle mainBundle] pathForResource:@"RegistrationDefaults" ofType:@"plist"];
    NSDictionary *registrationDefaults = [NSDictionary dictionaryWithContentsOfFile:defaultsPath];
    [DEFAULTS registerDefaults:registrationDefaults];
}

#pragma mark -

- (BOOL)AEWPFunctionExists {
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
            // This version of OS X has finally removed AEWP
            return NO;
        }
    }
    return YES;
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Make sure lsof exists on the system
    if ([FILEMGR fileExistsAtPath:PROGRAM_LSOF_SYSTEM_PATH] == NO) {
        [Alerts fatalAlert:@"System corrupt" subTextFormat:@"No tool exists at the path %@", PROGRAM_LSOF_SYSTEM_PATH];
        [[NSApplication sharedApplication] terminate:self];
    }
    
    // Put application icon in window title bar
    [window setRepresentedURL:[NSURL URLWithString:@""]];
    NSButton *button = [window standardWindowButton:NSWindowDocumentIconButton];
    [button setImage:[NSApp applicationIconImage]];
    
    // Hide authenticate button if AuthorizationExecuteWithPrivileges
    // is not available in this version of OS X
    if ([self AEWPFunctionExists] == NO) {
        [authenticateButton setHidden:YES];
    }
    
    // Manually check correct menu items for these submenus
    // on launch since we (annoyingly) can't use bindings for it
    [self checkItemWithTitle:[DEFAULTS stringForKey:@"interfaceSize"] inMenu:interfaceSizeSubmenu];
    [self checkItemWithTitle:[DEFAULTS stringForKey:@"accessMode"] inMenu:accessModeSubmenu];
    
    // Set icons in filter menu
    NSArray<NSMenuItem *> *items = [filterMenu itemArray];
    for (NSMenuItem *i in items) {
        NSString *type = [i toolTip];
        if (type2icon[type]) {
            NSImage *img = type2icon[type];
            [img setSize:NSMakeSize(16, 16)];
            [i setImage:img];
        }
    }
    
    // Load system lock icon and set as icon for button & menu
    NSImage *lockIcon = [WORKSPACE iconForFileType:NSFileTypeForHFSTypeCode(kLockedIcon)];
    [lockIcon setSize:NSMakeSize(16, 16)];
    [authenticateButton setImage:lockIcon];
    [authenticateMenuItem setImage:lockIcon];

    // Observe defaults
    for (NSString *key in @[@"showCharacterDevices",
                            @"showDirectories",
                            @"showIPSockets",
                            @"showRegularFiles",
                            @"showUnixSockets",
                            @"showPipes",
                            @"showApplicationsOnly",
                            @"showHomeFolderOnly",
                            @"accessMode",
                            @"interfaceSize"]) {
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
    
    // Refresh immediately when app is launched
    [self refresh:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self deauthenticate];
}

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu {
    // Prevent popup menu when window icon/title is cmd-clicked
    return NO;
}

- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pasteboard {
    // Prevent dragging of title bar icon
    return NO;
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
    
    // Update header
    [self updateProcessCountHeader];
    
    // Update label
    NSString *str = [NSString stringWithFormat:@"Showing %d out of %d items", matchingFilesCount, self.totalFileCount];
    [numItemsTextField setStringValue:str];

    // Reload
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
    
    // Access mode filter
    NSString *accessModeFilter = [DEFAULTS stringForKey:@"accessMode"];
    BOOL hasAccessModeFilter = ([accessModeFilter isEqualToString:@"Any"] == NO);
    
    // Volumes filter
    NSString *volumesFilter = nil;
    BOOL hasVolumesFilter = ([[[volumesPopupButton selectedItem] title] isEqualToString:@"All"] == NO);
    if (hasVolumesFilter) {
        volumesFilter = [[volumesPopupButton selectedItem] toolTip];
    }
    
    // User home dir path prefix
    NSString *homeDirPath = NSHomeDirectory();
    
    // Regex search field filter
    NSMutableArray *regexes = [NSMutableArray array];
    NSString *fieldString = [[filterTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *filterStrings = [fieldString componentsSeparatedByString:@" "];

    // Create regex for each whitespace-separated search filter strings
    for (NSString *fs in filterStrings) {
        NSString *s = [fs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([s length] == 0) {
            continue;
        }
        
        NSError *err;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:s
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&err];
        if (!regex) {
            NSLog(@"Error creating regex: %@", [err localizedDescription]);
            continue;
        }
        [regexes addObject:regex];
    }
    
    BOOL hasRegexFilter = ([regexes count] > 0);
    BOOL showAllProcessTypes = !showApplicationsOnly;
    BOOL showAllFileTypes = (showRegularFiles && showDirectories && showIPSockets && showUnixSockets
                         && showCharDevices && showPipes && !showHomeFolderOnly);
    
    // If there is no filter, just return unfiltered content
    if (showAllFileTypes && showAllProcessTypes && !hasRegexFilter && !hasVolumesFilter && !hasAccessModeFilter) {
        *matchingFilesCount = self.totalFileCount;
        return unfilteredContent;
    }

    NSMutableArray *filteredContent = [NSMutableArray array];

    // Iterate over unfiltered content, filter it
    for (NSMutableDictionary *process in self.unfilteredContent) {

        NSMutableArray *matchingFiles = [NSMutableArray array];
        
        for (NSDictionary *file in process[@"children"]) {
            
            // Let's see if it gets filtered by type
            if (showAllFileTypes == NO) {
                
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
            if (hasRegexFilter) {
                
                int matchCount = 0;
                for (NSRegularExpression *regex in regexes) {
                    if (!([file[@"name"] isMatchedByRegex:regex] ||
                          [file[@"pname"] isMatchedByRegex:regex] ||
                          [file[@"pid"] isMatchedByRegex:regex])) {
                        break;
                    }
                    matchCount += 1;
                }
                if (matchCount != [regexes count]) {
                    continue;
                }
            }
            
            [matchingFiles addObject:file];
        }
        
        // If we have matching files for the process
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

#pragma mark - Update/parse results

- (IBAction)refresh:(id)sender {
    isRefreshing = YES;
    [numItemsTextField setStringValue:@""];
    
    // Disable controls
    [filterTextField setEnabled:NO];
    [refreshButton setEnabled:NO];
    [outlineView setEnabled:NO];
    [outlineView setAlphaValue:0.5];
    
    // Center progress indicator and set it off
    CGFloat x = (NSWidth([window.contentView bounds]) - NSWidth([progressIndicator frame])) / 2;
    CGFloat y = (NSHeight([window.contentView bounds]) - NSHeight([progressIndicator frame])) / 2;
    [progressIndicator setFrameOrigin:NSMakePoint(x, y)];
    [progressIndicator setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [progressIndicator setUsesThreadedAnimation:TRUE];
    [progressIndicator startAnimation:self];

    // Update in asynchronously in the background, so interface doesn't lock up
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSString *output = [self runLsof:authenticated];
            
            int fileCount;
            self.unfilteredContent = [self parseLsofOutput:output numFiles:&fileCount];
            self.totalFileCount = fileCount;
            
            // Then update UI on main thread once task is done
            dispatch_async(dispatch_get_main_queue(), ^{
                
                // Re-enable controls
                [progressIndicator stopAnimation:self];
                [filterTextField setEnabled:YES];
                [outlineView setEnabled:YES];
                [outlineView setAlphaValue:1.0];
                [refreshButton setEnabled:YES];
                
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
        if (!_AuthExecuteWithPrivsFn) {
            NSBeep();
            NSLog(@"AuthorizationExecuteWithPrivileges function undefined");
            return nil;
        }
        
        const char *toolPath = [[self lsofPath] fileSystemRepresentation];
        NSMutableArray *arguments = [self lsofArguments];
        NSUInteger numberOfArguments = [arguments count];
        char *args[numberOfArguments + 1];
        FILE *outputFile;
        
        // First, construct an array of c strings from NSArray w. arguments
        for (int i = 0; i < numberOfArguments; i++) {
            NSString *argString = arguments[i];
            NSUInteger stringLength = [argString length];
            
            args[i] = malloc((stringLength + 1) * sizeof(char));
            snprintf(args[i], stringLength + 1, "%s", [argString fileSystemRepresentation]);
        }
        args[numberOfArguments] = NULL;
        
        // Use Authorization Reference to execute script with privileges
        _AuthExecuteWithPrivsFn(authorizationRef, toolPath, kAuthorizationFlagDefaults, args, &outputFile);
        
        // Free malloc'd argument strings
        for (int i = 0; i < numberOfArguments; i++) {
            free(args[i]);
        }

        NSFileHandle *outputFileHandle = [[NSFileHandle alloc] initWithFileDescriptor:fileno(outputFile) closeOnDealloc:YES];
        
        outputData = [outputFileHandle readDataToEndOfFile];
        
    } else {
        
        NSTask *lsof = [[NSTask alloc] init];
        [lsof setLaunchPath:[self lsofPath]];
        [lsof setArguments:[self lsofArguments]];
        
        NSPipe *pipe = [NSPipe pipe];
        [lsof setStandardOutput:pipe];
        [lsof launch];
        
        outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
    }
    
    return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
}

- (NSMutableArray *)parseLsofOutput:(NSString *)outputString numFiles:(int *)numFiles {
    NSMutableArray *processList = [NSMutableArray array];
    *numFiles = 0;
    
    if (outputString == nil || [outputString length] == 0) {
        return processList;
    }
    
    NSArray *lines = [outputString componentsSeparatedByString:@"\n"];
    
    NSMutableDictionary *processes = [NSMutableDictionary dictionary];
    
    NSString *pid = @"";
    NSString *process = @"";
    NSString *ftype = @"";
    NSString *userid = @"";
    NSString *accessmode = @"";
    NSString *protocol = @"";
    NSString *fd = @"";
    BOOL skip;
    
    // Parse each line
    for (NSString *line in lines) {
        
        if ([line length] == 0) {
            continue;
        }
        
        switch ([line characterAtIndex:0]) {
            
            // PID
            case 'p':
                pid = [line substringFromIndex:1];
                break;
            
            // Name of owning process
            case 'c':
                process = [line substringFromIndex:1];
                break;
            
            // Type
            case 't':
                ftype = [line substringFromIndex:1];
                break;
            
            // UID
            case 'u':
                userid = [line substringFromIndex:1];
                break;
            
            // Access mode
            case 'a':
                accessmode = [line substringFromIndex:1];
                break;
            
            // Protocol (IP sockets only)
            case 'P':
                protocol = [line substringFromIndex:1];
                break;
            
            // File descriptor
            case 'f':
            {
                // txt files are program code, such as the application binary itself or a shared library
                fd = [line substringFromIndex:1];
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
            
            // Name
            case 'n':
            {
                if (skip) {
                    continue;
                }
                
                // Create file info dictionary
                NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
                fileInfo[@"name"] = [line substringFromIndex:1];
                fileInfo[@"displayname"] = fileInfo[@"name"];
                fileInfo[@"pname"] = process;
                fileInfo[@"pid"] = pid;
                fileInfo[@"puserid"] = userid;
                fileInfo[@"accessmode"] = accessmode;
                fileInfo[@"protocol"] = protocol;
                fileInfo[@"fd"] = fd;
                
                if ([ftype isEqualToString:@"VREG"] || [ftype isEqualToString:@"REG"]) {
                    fileInfo[@"type"] = @"File";
                }
                else if ([ftype isEqualToString:@"VDIR"] || [ftype isEqualToString:@"DIR"]) {
                    fileInfo[@"type"] = @"Directory";
                }
                else if ([ftype isEqualToString:@"IPv6"] || [ftype isEqualToString:@"IPv4"]) {
                    fileInfo[@"type"] = @"IP Socket";
                    fileInfo[@"ipversion"] = ftype;
                }
                else  if ([ftype isEqualToString:@"unix"]) {
                    fileInfo[@"type"] = @"Unix Socket";
                }
                else if ([ftype isEqualToString:@"VCHR"] || [ftype isEqualToString:@"CHR"]) {
                    fileInfo[@"type"] = @"Character Device";
                }
                else if ([ftype isEqualToString:@"PIPE"]) {
                    fileInfo[@"type"] = @"Pipe";
                    if ([fileInfo[@"name"] isEqualToString:@""]) {
                        fileInfo[@"displayname"] = @"Unnamed Pipe";
                    }
                }
                else {
                    //NSLog(@"Unrecognized file type: %@ : %@", ftype, [fileInfo description]);
                    continue;
                }
                
                fileInfo[@"image"] = type2icon[fileInfo[@"type"]];
                
                // Create process key in dictionary if it doesn't already exist
                NSMutableDictionary *pdict = processes[pid];
                if (pdict == nil) {
                    
                    pdict = [NSMutableDictionary dictionary];
                    pdict[@"name"] = process;
                    pdict[@"pname"] = process;
                    pdict[@"displayname"] = process;
                    pdict[@"userid"] = userid;
                    pdict[@"pid"] = pid;
                    pdict[@"type"] = @"Process";
                    pdict[@"children"] = [NSMutableArray array];
                    
                    processes[pid] = pdict;
                }
                
                // Add file to process's children
                [pdict[@"children"] addObject:fileInfo];
            }
                break;
        }
    }
    
    // Create array of process dictionaries
    for (NSString *pname in [processes allKeys]) {
        NSMutableDictionary *p = processes[pname];
        [self updateProcessInfo:p];
        [processList addObject:p];
        *numFiles += [p[@"children"] count];
    }
    
    return processList;
}

- (void)updateProcessInfo:(NSMutableDictionary *)p {
    // Update display name to show number of open files for process
    NSString *procString = [NSString stringWithFormat:@"%@ (%d)", p[@"pname"], (int)[p[@"children"] count]];
    p[@"displayname"] = procString;
    
    // Get icon for process
    if (!p[@"image"]) {
        ProcessSerialNumber psn;
        GetProcessForPID([p[@"pid"] intValue], &psn);
        NSDictionary *pInfoDict = (__bridge_transfer NSDictionary *)ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);
        
        if (pInfoDict[@"BundlePath"]) { // It's a bundle
            p[@"image"] = [WORKSPACE iconForFile:pInfoDict[@"BundlePath"]];
            
            // Check if it's an app bundle
            NSString *fileType = [WORKSPACE typeOfFile:pInfoDict[@"BundlePath"] error:nil];
            if ([WORKSPACE type:fileType conformsToType:APPLICATION_UTI]) {
                p[@"app"] = @YES;
            }
            
            p[@"bundlepath"] = pInfoDict[@"BundlePath"];
        } else {
            p[@"image"] = genericExecutableIcon;
            p[@"app"] = @NO;
        }
    }
}

#pragma mark - Interface actions

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
    
    // Construct c strings array of arguments
    // /bin/kill -9 1234
    char *args[3];
    args[0] = malloc(4);
    sprintf(args[0], "%s", "-9");
    args[1] = malloc(10);
    sprintf(args[1], "%d", pid);
    args[2] = NULL;
    
    // Use Authorization Reference to execute /bin/kill with root privileges
    err = _AuthExecuteWithPrivsFn(authRef, toolPath, kAuthorizationFlagDefaults, args, NULL);
    
    // Cleanup
    free(args[0]);
    free(args[1]);
    AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
    
    // We return err if execution failed
    if (err != errAuthorizationSuccess) {
        return NO;
    }
    
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
    NSString *q = [NSString stringWithFormat:@"Are you sure you want to kill \"%@\" (%d)?", item[@"pname"], pid];
    if ([Alerts proceedAlert:q
                     subText:@"This will send the process a SIGKILL signal."
             withActionNamed:@"Kill"] == NO) {
        return;
    }

    // Find out if user owns the process
    BOOL ownsProcess = NO;
    uid_t uid = uid_for_pid(pid);
    if (uid != -1) {
        register struct passwd *pw = getpwuid(uid);
    
        NSString *pidUsername = [NSString stringWithCString:pw->pw_name encoding:NSUTF8StringEncoding];
        ownsProcess = [pidUsername isEqualToString:NSUserName()];
    }
    
    // Kill it
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

- (void)rowDoubleClicked:(id)object {
    NSInteger rowNumber = [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:rowNumber] representedObject];
    
    BOOL cmdKeyDown = (([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask) == NSCommandKeyMask);
    
    if (cmdKeyDown) {
        [self revealItemInFinder:item];
    } else {
        [self showGetInfoForItem:item];
    }
}

- (void)revealItemInFinder:(NSDictionary *)item {
    NSString *path = item[@"bundlepath"] ? item[@"bundlepath"] : item[@"name"];
    if ([self canRevealItemAtPath:path]) {
        [WORKSPACE selectFile:path inFileViewerRootedAtPath:path];
    } else {
        NSBeep();
    }
}

- (BOOL)canRevealItemAtPath:(NSString *)path {
    return path && [FILEMGR fileExistsAtPath:path] && ![path hasPrefix:@"/dev/"];
}

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

#pragma mark - Get Info

- (IBAction)getInfo:(id)sender {
    NSInteger selectedRow = [outlineView selectedRow];
    if (selectedRow >= 0) {
        [self showGetInfoForItem:[[outlineView itemAtRow:selectedRow] representedObject]];
    } else {
        NSBeep();
    }
}

- (void)showGetInfoForItem:(NSDictionary *)item {
    // Create info panel lazily
    if (infoPanelController == nil) {
        infoPanelController = [[InfoPanelController alloc] initWithWindowNibName:@"InfoPanel"];
    }
    [infoPanelController loadItem:item];
    [infoPanelController showWindow:self];
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
    NSSortDescriptor *sortDesc = [[NSSortDescriptor alloc] initWithKey:@"name"
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
    
    OSType iconID = authenticated ? kUnlockedIcon : kLockedIcon;
    NSImage *img = [WORKSPACE iconForFileType:NSFileTypeForHFSTypeCode(iconID)];
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
        BOOL canReveal = [self canRevealItemAtPath:item[@"name"]];
        BOOL hasBundlePath = [self canRevealItemAtPath:item[@"bundlepath"]];
        [revealButton setEnabled:(canReveal || hasBundlePath)];
        [getInfoButton setEnabled:YES];
        [killButton setEnabled:YES];
        [infoPanelController loadItem:item];
        
        // We make the file path red if file has been moved or deleted
        if ([item[@"type"] isEqualToString:@"File"] || [item[@"type"] isEqualToString:@"Directory"]) {
            NSColor *color = canReveal ? [NSColor blackColor] : [NSColor redColor];
            item[@"displayname"] = [[NSAttributedString alloc] initWithString:item[@"name"]
                                                                   attributes:@{NSForegroundColorAttributeName: color}];
        }
        
    } else {
        [revealButton setEnabled:NO];
        [killButton setEnabled:NO];
        [getInfoButton setEnabled:NO];
    }
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    NSString *size = [DEFAULTS stringForKey:@"interfaceSize"];
    return [size isEqualToString:@"Compact"] ? 16.f : 20.f;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard {
    NSDictionary *item = [items[0] representedObject];
    NSString *path = item[@"bundlepath"] ? item[@"bundlepath"] : item[@"name"];
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
        NSArray *items = [menu itemArray];
        for (NSMenuItem *i in items) {
            NSControlStateValue on = [[[i title] lowercaseString] hasSuffix:[DEFAULTS objectForKey:@"sortBy"]];
            [i setState:on];
        }
    }
    else if (menu == volumesMenu) {
        
        // Get currently selected volume
        NSMenuItem *selectedItem = [volumesPopupButton selectedItem];
        NSString *selectedPath = [selectedItem toolTip];
        
        // Rebuild menu
        [volumesMenu removeAllItems];
        
        NSArray *props = @[NSURLVolumeNameKey, NSURLVolumeIsRemovableKey, NSURLVolumeIsEjectableKey];
        NSArray *urls = [FILEMGR mountedVolumeURLsIncludingResourceValuesForKeys:props options:0];
        
        // All + separator
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"All"
                                                      action:@selector(updateFiltering)
                                               keyEquivalent:@""];
        [item setTarget:self];
        [item setToolTip:@""];
        [volumesMenu addItem:item];
        [volumesMenu addItem:[NSMenuItem separatorItem]];
        
        // Add all volumes as items
        for (NSURL *url in urls) {
            NSString *volumeName;
            [url getResourceValue:&volumeName forKey:NSURLVolumeNameKey error:nil];

            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:volumeName
                                                          action:@selector(updateFiltering)
                                                   keyEquivalent:@""];
            [item setTarget:self];
            [item setToolTip:[url path]];
            [volumesMenu addItem:item];
        }
        
        // Restore selection, if possible
        NSMenuItem *itemToSelect = [volumesMenu itemArray][0];
        for (NSMenuItem *item in [volumesMenu itemArray]) {
            if ([[item toolTip] isEqualToString:selectedPath]) {
                itemToSelect = item;
            }
        }
        [volumesPopupButton selectItem:itemToSelect];
    }
}

// Called when user selects Copy menu item via edit or contextual menu
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

- (BOOL)validateMenuItem:(NSMenuItem *)anItem {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];

    // Actions on items should only be enabled when something is selected
    if (( [[anItem title] isEqualToString:@"Show in Finder"] || [[anItem title] isEqualToString:@"Kill Process"] || [[anItem title] isEqualToString:@"Get Info"]) && selectedRow < 0) {
        return NO;
    }
    
    if ([[anItem title] isEqualToString:@"Show in Finder"]) {
        NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
        return [self canRevealItemAtPath:item[@"name"]] || [self canRevealItemAtPath:item[@"bundlepath"]];
    }
    
    return YES;
}

#pragma mark -

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

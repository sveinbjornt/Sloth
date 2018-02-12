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
    IBOutlet NSMenu *volumesMenu;
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
        
        type2icon = @{      @"File": [NSImage imageNamed:@"NSGenericDocument"],
                            @"Directory": [NSImage imageNamed:@"NSFolder"],
                            @"Character Device": [NSImage imageNamed:@"NSActionTemplate"],
                            @"Unix Socket": [NSImage imageNamed:@"Socket"],
                            @"IP Socket": [NSImage imageNamed:@"NSNetwork"],
                            @"Pipe": [NSImage imageNamed:@"Pipe"]
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
    
    // put application icon in window title bar
    [window setRepresentedURL:[NSURL URLWithString:@""]];
    NSButton *button = [window standardWindowButton:NSWindowDocumentIconButton];
    [button setImage:[NSApp applicationIconImage]];
    
    // Hide authenticate button if AuthorizationExecuteWithPrivileges
    // is not available in this version of OS X
    if ([self AEWPFunctionExists] == NO) {
        [authenticateButton setHidden:YES];
    }
    
    // Interface size settings
    NSString *interfaceSize = [[NSUserDefaults standardUserDefaults] objectForKey:@"interfaceSize"];
    [self checkItemWithTitle:interfaceSize inSubmenu:interfaceSizeSubmenu];
    
    // Observe defaults
    for (NSString *key in @[@"showCharacterDevices",
                            @"showDirectories",
                            @"showIPSockets",
                            @"showRegularFiles",
                            @"showUnixSockets",
                            @"showPipes",
                            @"showApplicationsOnly",
                            @"showHomeFolderOnly",
                            @"interfaceSize"]) {
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                                  forKeyPath:VALUES_KEYPATH(key)
                                                                     options:NSKeyValueObservingOptionNew
                                                                     context:NULL];
    }
    
    [outlineView setDoubleAction:@selector(rowDoubleClicked:)];
    [outlineView registerForDraggedTypes:@[NSFilenamesPboardType]];
    [outlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
    
    [self updateDiscloseControl];
    
    // Layer-backed window
    [[window contentView] setWantsLayer:YES];
    
    // If launching for the first time, center window
    if ([DEFAULTS boolForKey:@"PreviouslyLaunched"] == NO) {
        [window center];
        [DEFAULTS setBool:YES forKey:@"PreviouslyLaunched"];
    }
    [window makeKeyAndOrderFront:self];
    
    //[self updateSorting];
    
    [self performSelector:@selector(refresh:) withObject:self afterDelay:0.05];
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
    if (isRefreshing) {
        return;
    }
    //NSLog(@"Filtering");
    
    // filter content
    int matchingFilesCount = 0;
    self.content = [self filterContent:self.unfilteredContent numberOfMatchingFiles:&matchingFilesCount];
    
    // update header
    NSString *headerTitle = [NSString stringWithFormat:@"%d processes", (int)[self.content count]];
    [[[outlineView tableColumnWithIdentifier:@"children"] headerCell] setStringValue:headerTitle];
    
    // update label
    NSString *str = [NSString stringWithFormat:@"Showing %d items of %d", matchingFilesCount, self.totalFileCount];
    [numItemsTextField setStringValue:str];

    // reload
    [outlineView reloadData];
    
    if ([DEFAULTS boolForKey:@"disclosure"]) {
        [outlineView expandItem:nil expandChildren:YES];
    } else {
        [outlineView collapseItem:nil collapseChildren:YES];
    }
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if (filterTimer) {
        [filterTimer invalidate];
    }
    filterTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateFiltering) userInfo:nil repeats:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([VALUES_KEYPATH(@"interfaceSize") isEqualToString:keyPath]) {
        [outlineView reloadData];
    } else {
        [self updateFiltering];
    }
}

- (NSMutableArray *)filterContent:(NSMutableArray *)unfilteredContent numberOfMatchingFiles:(int *)matchingFilesCount {
    
    BOOL showRegularFiles = [DEFAULTS boolForKey:@"showRegularFiles"];
    BOOL showDirectories = [DEFAULTS boolForKey:@"showDirectories"];
    BOOL showIPSockets = [DEFAULTS boolForKey:@"showIPSockets"];
    BOOL showUnixSockets = [DEFAULTS boolForKey:@"showUnixSockets"];
    BOOL showCharDevices = [DEFAULTS boolForKey:@"showCharacterDevices"];
    BOOL showPipes = [DEFAULTS boolForKey:@"showPipes"];
    
    BOOL showApplicationsOnly = [DEFAULTS boolForKey:@"showApplicationsOnly"];
    BOOL showHomeFolderOnly = [DEFAULTS boolForKey:@"showHomeFolderOnly"];
    
    // Volumes filter
    NSString *volumesFilter = nil;
    BOOL hasVolumesFilter = ([[[volumesPopupButton selectedItem] title] isEqualToString:@"All"] == NO);
    if (hasVolumesFilter) {
        volumesFilter = [[volumesPopupButton selectedItem] toolTip];
    }
    
    // User home dir path prefix
    NSString *homeDirPath = [NSString stringWithFormat:@"/Users/%@", NSUserName()];
    
    // Regex search field filter
    NSMutableArray *regexes = [NSMutableArray array];
    NSString *fieldString = [[filterTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *filterStrings = [fieldString componentsSeparatedByString:@" "];
    for (NSString *fs in filterStrings) {
        NSString *s = [fs stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([s length]) {
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
    }
    
    BOOL hasRegexFilter = ([regexes count] > 0);

    BOOL showAllProcessTypes = !showApplicationsOnly;
    BOOL showAllFileTypes = (showRegularFiles && showDirectories && showIPSockets && showUnixSockets
                         && showCharDevices && showPipes && !showHomeFolderOnly);
    
    // If there is no filter, just return unfiltered content
    if (showAllFileTypes && showAllProcessTypes && !hasRegexFilter && !hasVolumesFilter) {
        *matchingFilesCount = self.totalFileCount;
        return unfilteredContent;
    }

    NSMutableArray *filteredContent = [NSMutableArray array];

    // Iterate over unfiltered content, filter it
    for (NSMutableDictionary *process in self.unfilteredContent) {

        NSMutableArray *matchingFiles = [NSMutableArray array];
        
        for (NSDictionary *file in process[@"children"]) {
            
            // let's see if it gets filtered by type
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
            
            // see if it matches regex in search field filter
            if (hasRegexFilter) {
                
                int matchCount = 0;
                for (NSRegularExpression *regex in regexes) {
                    if (!([file[@"name"] isMatchedByRegex:regex] || [file[@"pname"] isMatchedByRegex:regex])) {
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

    // update in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
    
            NSString *output = [self runLsof:authenticated];
            
            int fileCount;
            self.unfilteredContent = [self parseLsofOutput:output numFiles:&fileCount];
            self.totalFileCount = fileCount;
            
            // then update UI on main thread
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

- (NSString *)runLsof:(BOOL)isAuthenticated {
    // our command is: lsof -F pcnt +c0
    NSData *outputData;
    
    if (isAuthenticated) {
        if (!_AuthExecuteWithPrivsFn) {
            NSBeep();
            NSLog(@"AuthorizationExecuteWithPrivileges function undefined");
            return nil;
        }
        
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
        _AuthExecuteWithPrivsFn(authorizationRef, toolPath, kAuthorizationFlagDefaults, args, &outputFile);
        
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

- (NSMutableArray *)parseLsofOutput:(NSString *)outputString numFiles:(int *)numFiles {
    NSMutableArray *processList = [NSMutableArray array];
    *numFiles = 0;
    
    if (outputString == nil) {
        return processList;
    }
    
    // split into array of lines of text
    NSArray *lines = [outputString componentsSeparatedByString:@"\n"];
    
    NSMutableDictionary *processes = [NSMutableDictionary dictionary];
    
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
                //we don't report lsof process
                if (/*[process isEqualToString:PROGRAM_NAME] ||*/ [process isEqualToString:PROGRAM_LSOF_NAME]) {
                    continue;
                }
                
                // Create file info dictionary
                NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
                fileInfo[@"name"] = [line substringFromIndex:1];
                fileInfo[@"displayname"] = fileInfo[@"name"];
                fileInfo[@"pname"] = process;
                fileInfo[@"pid"] = pid;
                
                if (/*[ftype isEqualToString:@"VREG"] ||*/ [ftype isEqualToString:@"REG"]) {
                    fileInfo[@"type"] = @"File";
                }
                else if (/*[ftype isEqualToString:@"VDIR"] ||*/ [ftype isEqualToString:@"DIR"]) {
                    fileInfo[@"type"] = @"Directory";
                }
                else if ([ftype isEqualToString:@"IPv6"] || [ftype isEqualToString:@"IPv4"]) {
                    fileInfo[@"type"] = @"IP Socket";
                }
                else  if ([ftype isEqualToString:@"unix"]) {
                    fileInfo[@"type"] = @"Unix Socket";
                }
                else if (/*[ftype isEqualToString:@"VCHR"] ||*/ [ftype isEqualToString:@"CHR"]) {
                    fileInfo[@"type"] = @"Character Device";
                }
                else if ([ftype isEqualToString:@"PIPE"]) {
                    fileInfo[@"type"] = @"Pipe";
                }
                else {
//                    NSLog(@"Unrecognized file type: %@ : %@", ftype, [fileInfo description]);
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
    
//    NSMutableAttributedString *displStr = [[NSMutableAttributedString alloc] init];
//
//    NSAttributedString *pNameStr = [[NSAttributedString alloc] initWithString:p[@"name"] attributes:@{}];
//    [displStr appendAttributedString:pNameStr];
//
//    NSString *countStr = [NSString stringWithFormat:@" (%d)", (int)[p[@"children"] count]];
//    NSDictionary *attr = @{NSForegroundColorAttributeName: [NSColor grayColor]};
//    NSAttributedString *countAttrStr = [[NSAttributedString alloc] initWithString:countStr attributes:attr];
//
//    [displStr appendAttributedString:countAttrStr];

    // update display name to show number of open files for process
    NSString *procString = [NSString stringWithFormat:@"%@ (%d)", p[@"pname"], (int)[p[@"children"] count]];
    p[@"displayname"] = procString;
    
//    p[@"displayname"] = [[NSAttributedString alloc] initWithString:procString
//                                                        attributes:@{
//                                                                     NSFontAttributeName: [NSFont boldSystemFontOfSize:14],
//                                                                     NSForegroundColorAttributeName: [NSColor blackColor]}];
    
    // get icon for process
    if (!p[@"image"]) {
        ProcessSerialNumber psn;
        GetProcessForPID([p[@"pid"] intValue], &psn);
        NSDictionary *pInfoDict = (__bridge_transfer NSDictionary *)ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);
        
        if (pInfoDict[@"BundlePath"]) {
            p[@"image"] = [WORKSPACE iconForFile:pInfoDict[@"BundlePath"]];
//            if ([pInfoDict[@"BundlePath"] hasSuffix:@".app"]) {
            NSString *fileType = [WORKSPACE typeOfFile:pInfoDict[@"BundlePath"] error:nil];
            if ([WORKSPACE type:fileType conformsToType:APPLICATION_UTI]) {
                p[@"app"] = @YES;
            }
            
            //com.apple.application
            
            p[@"bundlepath"] = pInfoDict[@"BundlePath"];
        } else {
            p[@"image"] = genericExecutableIcon;
            p[@"app"] = @NO;
        }
    }
}

#pragma mark - Interface

- (BOOL)killProcess:(int)pid asRoot:(BOOL)asRoot {
    if (!asRoot) {
        return (kill(pid, SIGKILL) == 0);
    }
    
    // kill process as root
    const char *toolPath = [@"/bin/kill" fileSystemRepresentation];
    
    AuthorizationRef authRef;
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // create authorization reference
    OSStatus err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authRef);
    if (err != errAuthorizationSuccess) {
        return NO;
    }
    
    // pre-authorize the privileged operation
    err = AuthorizationCopyRights(authRef, &myRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (err != errAuthorizationSuccess) {
        return NO;
    }
    
    // construct c strings array of arguments
    // /bin/kill -9 1234
    char *args[3];
    args[0] = malloc(4);
    sprintf(args[0], "%s", "-9");
    args[1] = malloc(10);
    sprintf(args[1], "%d", pid);
    args[2] = NULL;
    
    // use Authorization Reference to execute /bin/kill with root privileges
    err = _AuthExecuteWithPrivsFn(authRef, toolPath, kAuthorizationFlagDefaults, args, NULL);
    
    // cleanup
    free(args[0]);
    free(args[1]);
    AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
    
    // we return err if execution failed
    if (err != errAuthorizationSuccess) {
        return NO;
    }
    
    return YES;
}

- (IBAction)kill:(id)sender {
    NSInteger selectedRow = ([outlineView clickedRow] == -1) ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    
    if (!item[@"pid"]) {
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
    register struct passwd *pw;
    uid_t uid = uid_for_pid(pid);
    pw = getpwuid(uid);
    
    NSString *pidUsername = [NSString stringWithCString:pw->pw_name encoding:NSUTF8StringEncoding];
    BOOL ownsProcess = [pidUsername isEqualToString:NSUserName()];
    
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
    
    BOOL commandKeyDown = (([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask) == NSCommandKeyMask);
    
    if (commandKeyDown) {
        [self revealItemInFinder:item];
    } else {
        [self showGetInfoForItem:item];
    }
}

- (void)revealItemInFinder:(NSDictionary *)item {
    NSString *path = item[@"bundlepath"];
    path = path ? path : item[@"name"];
    if ([self canRevealItemAtPath:path]) {
        [WORKSPACE selectFile:path inFileViewerRootedAtPath:path];
    } else {
        NSBeep();
    }
}

- (BOOL)canRevealItemAtPath:(NSString *)path {
    return path && [FILEMGR fileExistsAtPath:path];// && ![path hasPrefix:@"/dev/"];
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

- (IBAction)showAbout:(id)sender {
    
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
    // create info panel lazily
    if (infoPanelController == nil) {
        infoPanelController = [[InfoPanelController alloc] initWithWindowNibName:@"InfoPanel"];
    }
    // show it
    [infoPanelController setItem:item];
    [infoPanelController showWindow:self];
}

#pragma mark - Sort

- (IBAction)sortChanged:(id)sender {
    NSArray *words = [[sender title] componentsSeparatedByString:@" "];
    NSString *sortBy = [[words lastObject] lowercaseString];
    [DEFAULTS setObject:sortBy forKey:@"sortBy"];
    [self updateSorting];
}

- (void)updateSorting {
    NSString *sortBy = [DEFAULTS objectForKey:@"sortBy"];
    NSSortDescriptor *sortDesc = [[NSSortDescriptor alloc] initWithKey:sortBy
                                                             ascending:[DEFAULTS boolForKey:@"ascending"]
                                                              selector:@selector(localizedCaseInsensitiveCompare:)];
    
    if ([sortBy isEqualToString:@"count"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"children"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:^(id first, id second){
            NSUInteger cnt1 = [first count];
            NSUInteger cnt2 = [second count];
            
            if (cnt1 < cnt2) {
                return NSOrderedAscending;
            } else if (cnt1 > cnt2) {
                return NSOrderedDescending;
            } else {
                return NSOrderedSame;
            }
        }];
    }
    
    if ([sortBy isEqualToString:@"pid"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"pid"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:^(id first, id second){
            NSUInteger cnt1 = [first intValue];
            NSUInteger cnt2 = [second intValue];
            
            if (cnt1 < cnt2) {
                return NSOrderedAscending;
            } else if (cnt1 > cnt2) {
                return NSOrderedDescending;
            } else {
                return NSOrderedSame;
            }
        }];
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
            }
            return;
        }
    } else {
        [self deauthenticate];
    }
    
    NSString *imgName = authenticated ? @"UnlockedIcon" : @"LockedIcon";
    NSString *actionName = authenticated ? @"Deauthenticate" : @"Authenticate";
    NSString *ttip = authenticated ? @"Deauthenticate" : @"Authenticate to view all system processes";
    NSImage *img = [NSImage imageNamed:imgName];
    [authenticateButton setImage:img];
    [authenticateButton setToolTip:ttip];
    [authenticateMenuItem setImage:img];
    [authenticateMenuItem setTitle:actionName];
    [authenticateMenuItem setToolTip:ttip];
    
    [self refresh:self];
}

- (OSStatus)authenticate {
    OSStatus err = noErr;
    const char *toolPath = [PROGRAM_DEFAULT_LSOF_PATH fileSystemRepresentation];
    
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
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
        [infoPanelController setItem:item];
        
        // we make the file path red if file has been moved or deleted
        if ([item[@"type"] isEqualToString:@"File"]) {
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
    NSString *size = [[NSUserDefaults standardUserDefaults] stringForKey:@"interfaceSize"];
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
    
//    for (NSPasteboardItem *i in [pboard pasteboardItems]) {
//        NSLog(@"%@", [[i propertyListForType:(NSString *)kUTTypeFileURL] description]);
//    }
    
    return YES;
}

#pragma mark - Menus

- (void)menuWillOpen:(NSMenu *)menu {
    if (menu == sortMenu) {
        NSArray *items = [menu itemArray];
        for (NSMenuItem *i in items) {
            [i setState:[[[i title] lowercaseString] hasSuffix:[DEFAULTS objectForKey:@"sortBy"]]];
        }
    }
    else if (menu == volumesMenu) {
        
        // get current selection
        NSMenuItem *selectedItem = [volumesPopupButton selectedItem];
        NSString *selectedPath = [selectedItem toolTip];
        
        // rebuild menu
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

- (void)copy:(id)sender {
    NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
    [pasteBoard clearContents];
    
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];

    // Write to pasteboard
    if ([FILEMGR fileExistsAtPath:item[@"name"]]) {
        [pasteBoard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
        [pasteBoard setPropertyList:@[item[@"name"]] forType:NSFilenamesPboardType];
    }
    [pasteBoard setString:item[@"name"] forType:NSStringPboardType];
}

- (void)checkItemWithTitle:(NSString *)title inSubmenu:(NSMenu *)submenu {
    NSArray *items = [submenu itemArray];
    for (int i = 0; i < [items count]; i++) {
        NSMenuItem *item = [items objectAtIndex:i];
        [item setState:0];
    }
    [[submenu itemWithTitle:title] setState:1];
}

- (IBAction)interfaceSizeMenuItemSelected:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:[sender title] forKey:@"interfaceSize"];
    [self checkItemWithTitle:[sender title] inSubmenu:interfaceSizeSubmenu];
}

- (IBAction)find:(id)sender {
    [window makeFirstResponder:filterTextField];
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];

    //reveal in finder / kill process only enabled when something is selected
    if (( [[anItem title] isEqualToString:@"Show in Finder"] || [[anItem title] isEqualToString:@"Kill Process"] || [[anItem title] isEqualToString:@"Get Info"]) && selectedRow < 0) {
        return NO;
    }
    
    if ([[anItem title] isEqualToString:@"Show in Finder"]) {
        NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
        return [self canRevealItemAtPath:item[@"name"]] || [self canRevealItemAtPath:item[@"bundlepath"]];
    }
    
    return YES;
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

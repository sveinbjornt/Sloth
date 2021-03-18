/*
    Copyright (c) 2004-2021, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "Common.h"
#import "SlothController.h"
#import "Alerts.h"
#import "NSString+RegexConvenience.h"
#import "InfoPanelController.h"
#import "PrefsController.h"
#import "ProcessUtils.h"
#import "IconUtils.h"
#import "FSUtils.h"
#import "NSWorkspace+Additions.h"
#import "STPrivilegedTask.h"
#import "LsofTask.h"
#import "Item.h"

@interface SlothController ()
{
    IBOutlet NSWindow *window;
    
    IBOutlet NSMenu *itemContextualMenu;
    IBOutlet NSMenu *sortMenu;
    IBOutlet NSMenu *interfaceSizeSubmenu;
    IBOutlet NSMenu *accessModeSubmenu;
    IBOutlet NSMenu *filterMenu;
    IBOutlet NSMenu *openWithMenu;
    IBOutlet NSMenu *refreshIntervalMenu;
    
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
    IBOutlet NSMenuItem *refreshIntervalMenuItem;
    IBOutlet NSButton *disclosureButton;
    IBOutlet NSTextField *disclosureTextField;
    
    IBOutlet NSOutlineView *outlineView;
    
    AuthorizationRef authorizationRef;
    BOOL authenticated;
    BOOL isRefreshing;
    
    NSTimer *filterTimer;
    NSTimer *updateTimer;
    
    InfoPanelController *infoPanelController;
    PrefsController *prefsController;
}
@property int totalFileCount;
@property (strong) IBOutlet NSMutableArray *content;
@property (strong) NSMutableArray *unfilteredContent;
@property (retain, nonatomic) NSArray *sortDescriptors;

@end

@implementation SlothController

- (instancetype)init {
    if ((self = [super init])) {
        _content = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (void)initialize {
    NSString *defaultsPath = [[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"];
    [DEFAULTS registerDefaults:[NSDictionary dictionaryWithContentsOfFile:defaultsPath]];
}

#pragma mark - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Make sure lsof exists on the system
    if ([FILEMGR fileExistsAtPath:LSOF_PATH] == NO) {
        [Alerts fatalAlert:@"System corrupt" subTextFormat:@"No binary at path %@", LSOF_PATH];
        [[NSApplication sharedApplication] terminate:self];
    }
    
    // Put application icon in window title bar
    [window setRepresentedURL:[NSURL URLWithString:@""]]; // Not representing a URL
    [[window standardWindowButton:NSWindowDocumentIconButton] setImage:[NSApp applicationIconImage]];
    
    // Hide Authenticate button & menu item if AuthorizationExecuteWithPrivileges
    // function is not available in this version of Mac OS X
    if ([STPrivilegedTask authorizationFunctionAvailable]) {
        NSImage *lockIcon = [IconUtils imageNamed:@"Locked"];
        [authenticateButton setImage:lockIcon];
        [authenticateMenuItem setImage:lockIcon];
    } else {
        // Hide/disable all authentication-related controls
        [authenticateButton setHidden:YES];
        [authenticateMenuItem setAction:nil];
    }
    
    // These menus are available in both menu bar and popup button.
    // Why create two identical menus when the same one can be used?
    [volumesMenuItem setSubmenu:[volumesPopupButton menu]];
    [refreshIntervalMenuItem setSubmenu:refreshIntervalMenu];
    
    // Set reveal button icon
    NSImage *revealImg = [NSImage imageNamed:@"NSRevealFreestandingTemplate"];
    [revealImg setSize:NSMakeSize(12,12)];
    [revealButton setImage:revealImg];
    
    // For some reason, Interface Builder isn't respecting image
    // template settings so we have to do this manually... (sigh)
    [[NSImage imageNamed:@"Kill"] setTemplate:YES];
    [[NSImage imageNamed:@"Kill"] setSize:NSMakeSize(20, 20)];
    [[NSImage imageNamed:@"Info"] setTemplate:YES];
    [[NSImage imageNamed:@"Info"] setSize:NSMakeSize(20, 20)];
    
    // Manually check the appropriate menu items for these submenus
    // on launch since we (annoyingly) can't use bindings for it
    [self checkItemWithTitle:[DEFAULTS stringForKey:@"interfaceSize"] inMenu:interfaceSizeSubmenu];
    [self checkItemWithTitle:[DEFAULTS stringForKey:@"accessMode"] inMenu:accessModeSubmenu];
    
    // Set icons for items in Filter menu
    NSArray<NSMenuItem *> *items = [filterMenu itemArray];
    int idx = 0;
    for (NSMenuItem *i in items) {
        idx += 1;
        if (idx < 2) { // Skip first menu item (Show All)
            continue;
        }
        NSString *type = [i toolTip];
        if (type) {
            NSImage *img = [IconUtils imageNamed:type];
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
                            @"searchFilterRegex",
                            @"updateInterval"
                          ]) {
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
    
    if ([DEFAULTS boolForKey:@"authenticateOnLaunch"]) {
        [self toggleAuthentication:self]; // Triggers refresh
    } else {
        // Refresh immediately when app is launched
        [self refresh:self];
    }
    [self setUpdateTimerFromDefaults];
}

- (nullable NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Refresh" action:@selector(refresh:) keyEquivalent:@""];
    [item setTarget:self];
    [menu addItem:item];
    return menu;
}

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu {
    // Prevent popup menu when window icon/title is cmd-clicked
    return NO;
}

- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pasteboard {
    // Prevent dragging of title bar icon
    return NO;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [[NSApplication sharedApplication] terminate:self];
    return YES;
}

#pragma mark - Run lsof task

- (IBAction)refresh:(id)sender {
    if (isRefreshing) {
        return;
    }
    isRefreshing = YES;
    [numItemsTextField setStringValue:@"Refreshing..."];
    [outlineView deselectAll:self];
    
    // Disable controls
    [refreshButton setEnabled:NO];
    [outlineView setEnabled:NO];
    [outlineView setAlphaValue:0.5];
    [authenticateButton setEnabled:NO];
    
    // Center progress indicator and set it off
    CGFloat x = (NSWidth([window.contentView bounds]) - NSWidth([progressIndicator frame])) / 2;
    CGFloat y = (NSHeight([window.contentView bounds]) - NSHeight([progressIndicator frame])) / 2;
    [progressIndicator setFrameOrigin:NSMakePoint(x,y)];
    [progressIndicator setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin];
    [progressIndicator setUsesThreadedAnimation:TRUE];
    [progressIndicator startAnimation:self];
    
    // Run lsof asynchronously in the background, so interface doesn't lock up
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @autoreleasepool {
            int fileCount;
            LsofTask *task = [LsofTask new];
            NSMutableArray *items = [task launch:authorizationRef numFiles:&fileCount];
            self.unfilteredContent = items;
            self.totalFileCount = fileCount;
            
            // Update UI on main thread once task is done
            dispatch_async(dispatch_get_main_queue(), ^{
                isRefreshing = NO;
                // Re-enable controls
                [progressIndicator stopAnimation:self];
                [outlineView setEnabled:YES];
                [outlineView setAlphaValue:1.0];
                [refreshButton setEnabled:YES];
                [authenticateButton setEnabled:YES];
                // Filter results
                [self updateFiltering];
            });
        }
    });
}

- (void)setUpdateTimerFromDefaults {
    if (updateTimer) {
        [updateTimer invalidate];
        updateTimer = nil;
    }
    NSInteger secInterval = [DEFAULTS integerForKey:@"updateInterval"];
    if (secInterval == 0) { // Manual updates only
        return;
    }
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:secInterval
                                                   target:self
                                                 selector:@selector(refresh:)
                                                 userInfo:nil
                                                  repeats:YES];
}

#pragma mark - Filtering

- (void)updateProcessCountHeader {
    NSString *sortedBy = [DEFAULTS stringForKey:@"sortBy"];
    if ([sortedBy hasSuffix:@" id"]) {
        sortedBy = [NSString stringWithFormat:@"%@ID", [sortedBy substringToIndex:[sortedBy length]-2]];
    }
    NSString *headerTitle = [NSString stringWithFormat:@"%d processes - sorted by %@", (int)[self.content count], sortedBy];
    [[[outlineView tableColumnWithIdentifier:@"children"] headerCell] setStringValue:headerTitle];
}

- (void)updateFiltering {
    if (isRefreshing) {
        return;
    }
    
    // Filter content
    int matchingFilesCount = 0;
    self.content = [self filterContent:self.unfilteredContent numberOfMatchingFiles:&matchingFilesCount];
    
    // Update outline view header
    [self updateProcessCountHeader];
    
    // Update num items label
    NSString *str = [NSString stringWithFormat:@"Showing %d out of %d items", matchingFilesCount, self.totalFileCount];
    if (matchingFilesCount == self.totalFileCount) {
        str = [NSString stringWithFormat:@"Showing all %d items", self.totalFileCount];
    }
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
    // If can't do volume filtering on 10.15+
//    if (@available(macOS 10.15, *)) {
//        if ([[volumesPopupButton titleOfSelectedItem] isEqualToString:@"All"]) {
//            return;
//        }
//        [volumesPopupButton selectItemAtIndex:0];
//        [Alerts alert:@"Unable to filter by volume"
//        subTextFormat:@"Volume filtering is not available on this version of macOS."];
//        return;
//    }
    [self performSelector:@selector(updateFiltering) withObject:nil afterDelay:0.05];
}

// Some default changed
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([VALUES_KEYPATH(@"interfaceSize") isEqualToString:keyPath]) {
        [outlineView reloadData];
        return;
    }
    if ([VALUES_KEYPATH(@"updateInterval") isEqualToString:keyPath]) {
        [self setUpdateTimerFromDefaults];
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
    NSNumber *volumesFilter = nil; // Device ID number
    BOOL hasVolumesFilter = ([[[volumesPopupButton selectedItem] title] isEqualToString:@"All"] == NO);
    if (hasVolumesFilter) {
        volumesFilter = [[volumesPopupButton selectedItem] representedObject][@"devid"];
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
    
    // Search field filter, precompile regexes
    NSMutableArray *searchFilters = [NSMutableArray new];
    NSString *fieldString = [[filterTextField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *filterStrings = [fieldString componentsSeparatedByString:@" "];
    // Trim and create regex objects from search filter strings
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
                DLog(@"Error creating search filter regex: %@", [err localizedDescription]);
                continue;
            }
            [searchFilters addObject:regex];
        } else {
            [searchFilters addObject:s];
        }
    }
    
    // Filters set in Prefs, precompile regexes
    NSMutableArray *prefsFilters = [NSMutableArray new];
    NSArray *pfStrings = [DEFAULTS objectForKey:@"filters"];
    for (NSArray *ps in pfStrings) {
        if ([ps[0] boolValue] == NO) {
            continue;
        }
        NSString *s = [ps[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([s length] == 0) {
            continue;
        }
        NSError *err;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:s options:0 error:&err];
        if (!regex) {
            DLog(@"Error creating prefs filter regex: %@", [err localizedDescription]);
            continue;
        }
        [prefsFilters addObject:regex];
        DLog(@"Adding regex: %@", ps[1]);
    }
    
    
    BOOL hasSearchFilter = ([searchFilters count] > 0);
    BOOL hasPrefsFilter = ([prefsFilters count] > 0);
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
    if (showAllItemTypes && showAllProcessTypes && !hasSearchFilter && !hasPrefsFilter && !hasAccessModeFilter) {
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
                
                if (volumesFilter) {
//                    DLog(@"%@ cmp %@", file[@"device"][@"devid"], volumesFilter);
                    if ([file[@"device"][@"devid"] isEqualToNumber:volumesFilter] == NO) {
                        continue;
                    }
                }
                
                NSString *type = file[@"type"];
                if (([type hasPrefix:@"F"] && !showRegularFiles) ||
                    ([type hasPrefix:@"D"] && !showDirectories) ||
                    ([type hasPrefix:@"I"] && !showIPSockets) ||
                    ([type hasPrefix:@"U"] && !showUnixSockets) ||
                    ([type hasPrefix:@"C"] && !showCharDevices) ||
                    ([type hasPrefix:@"P"] && !showPipes)) {
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
            
            // See if it matches regexes in search field filter
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
            
            // Prefs filters only filter by name
            if (hasPrefsFilter) {
                // Skip any file w. name matching
                BOOL skip = NO;
                for (NSRegularExpression *regex in prefsFilters) {
                    if ([file[@"name"] isMatchedByRegex:regex]) {
                        skip = YES;
                    }
                }
                if (skip) {
                    continue;
                }
            }
            
            [matchingFiles addObject:file];
        }
        
        // If we have matching files for the process, and it's not being excluded as a non-app
        if ([matchingFiles count] && !(showApplicationsOnly && ![process[@"app"] boolValue])) {
            NSMutableDictionary *p = [process mutableCopy];
            p[@"children"] = matchingFiles;
            // Num files shown in brackets after name needs to be updated
            [LsofTask updateProcessInfo:p];
            [filteredContent addObject:p];
            *matchingFilesCount += [matchingFiles count];
        }
    }
    
    return filteredContent;
}

- (IBAction)showAll:(id)sender {
    [DEFAULTS setObject:@YES forKey:@"showRegularFiles"];
    [DEFAULTS setObject:@YES forKey:@"showDirectories"];
    [DEFAULTS setObject:@YES forKey:@"showCharacterDevices"];
    [DEFAULTS setObject:@YES forKey:@"showIPSockets"];
    [DEFAULTS setObject:@YES forKey:@"showPipes"];
    [DEFAULTS setObject:@YES forKey:@"showUnixSockets"];
    
    [DEFAULTS setObject:@NO forKey:@"showApplicationsOnly"];
    [DEFAULTS setObject:@NO forKey:@"showHomeFolderOnly"];
    
    [DEFAULTS setObject:@"Any" forKey:@"accessMode"];
    [filterTextField setStringValue:@""];
    [volumesPopupButton selectItemAtIndex:0];
    
    [DEFAULTS synchronize];
    [self updateFiltering];
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
    if ([ProcessUtils killProcess:pid asRoot:!ownsProcess] == NO) {
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

- (IBAction)showPackageContents:(id)sender {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    if (![WORKSPACE showPackageContents:path]) {
        NSBeep();
    }
}

- (IBAction)moveToTrash:(id)sender {
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    NSString *path = item[@"path"] ? item[@"path"] : item[@"name"];
    
    BOOL optionKeyDown = (([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) == NSAlternateKeyMask);
    if (!optionKeyDown) {
        // Ask user to confirm
        NSString *prompt = @"This will tell the Finder to move the specified file into your Trash folder. \
 Hold the option key (⌥) to avoid this prompt.";
        if ([Alerts proceedAlert:[NSString stringWithFormat:@"Move “%@” to the Trash?", [path lastPathComponent]]
                         subText:prompt
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

- (void)showInfoPanelForItem:(Item *)item {
    // Create info panel lazily
    if (infoPanelController == nil) {
        infoPanelController = [[InfoPanelController alloc] initWithWindowNibName:@"InfoPanel"];
    }
    [infoPanelController loadItem:item];
    [infoPanelController showWindow:self];
}

// Called when user selects Copy menu item via Edit or contextual menu
- (void)copy:(id)sender {
    
    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    if (selectedRow == -1) {
        NSBeep();
        return;
    }
    
    // Write to pasteboard
    NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
    [pasteBoard clearContents];
    
    NSMutableArray *names = [NSMutableArray new];
    NSMutableArray *filePaths = [NSMutableArray new];

    [[outlineView selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSDictionary *item = [[outlineView itemAtRow:idx] representedObject];
        if ([FILEMGR fileExistsAtPath:item[@"name"]]) {
            [filePaths addObject:item[@"name"]];
        }
        if ([item[@"type"] isEqualToString:@"Process"]) {
            [names addObject:[NSString stringWithFormat:@"%@ (%@)", item[@"name"], item[@"pid"]]];
        } else {
            [names addObject:[NSString stringWithFormat:@"\t%@", item[@"name"]]];
        }
    }];
    
    if ([filePaths count]) {
        [pasteBoard declareTypes:@[NSFilenamesPboardType] owner:nil];
        [pasteBoard setPropertyList:filePaths forType:NSFilenamesPboardType];
    }
    NSString *copyStr = [names componentsJoinedByString:@"\n"];
    [pasteBoard setString:copyStr forType:NSStringPboardType];
}

- (void)rowDoubleClicked:(id)object {
    NSInteger rowNumber = [outlineView clickedRow];
    Item *item = [[outlineView itemAtRow:rowNumber] representedObject];
    
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

- (IBAction)showPrefs:(id)sender {
    // Create info panel lazily
    if (prefsController == nil) {
        prefsController = [[PrefsController alloc] initWithWindowNibName:@"Prefs"];
    }
    [prefsController showWindow:self];
}

- (IBAction)showSelectedItem:(id)sender {
    NSInteger selectedRow = [outlineView selectedRow];
    if (selectedRow > -1) {
        [outlineView scrollRowToVisible:selectedRow];
    } else {
        NSBeep();
    }
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
    else if ([sortBy isEqualToString:@"user id"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"userid"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:integerComparisonBlock];
    }
    else if ([sortBy isEqualToString:@"file count"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"children"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:numChildrenComparisonBlock];
    }
    else if ([sortBy isEqualToString:@"process type"]) {
        // Process type sorting uses the "bundle" and "app" boolean properties
        NSMutableArray *sdesc = [NSMutableArray new];
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"bundle"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:integerComparisonBlock];
        [sdesc addObject:sortDesc];
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"app"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:integerComparisonBlock];
        [sdesc addObject:sortDesc];
        self.sortDescriptors = [sdesc copy];
        return;
    }
    else if ([sortBy isEqualToString:@"carbon psn"]) {
        sortDesc = [NSSortDescriptor sortDescriptorWithKey:@"psn"
                                                 ascending:[DEFAULTS boolForKey:@"ascending"]
                                                comparator:integerComparisonBlock];
    }
    else if ([sortBy isEqualToString:@"bundle identifier"]) {
        sortDesc = [[NSSortDescriptor alloc] initWithKey:@"identifier"
                                               ascending:[DEFAULTS boolForKey:@"ascending"]
                                                selector:@selector(caseInsensitiveCompare:)];
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
                DLog(@"Authentication failed: %d", err);
            }
            [self deauthenticate];
            return;
        }
    } else {
        [self deauthenticate];
    }
    
    NSString *iconName =  authenticated ? @"Unlocked" : @"Locked";
    NSImage *img = [IconUtils imageNamed:iconName];
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
    DLog(@"Authenticating");
    const char *toolPath = [LSOF_PATH fileSystemRepresentation];
    
    AuthorizationItem myItems = { kAuthorizationRightExecute, strlen(toolPath), &toolPath, 0 };
    AuthorizationRights myRights = { 1, &myItems };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    // Create authorization reference
    OSStatus err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
    if (err != errAuthorizationSuccess) {
        return err;
    }
    
    // Pre-authorize the privileged operation
    err = AuthorizationCopyRights(authorizationRef, &myRights, kAuthorizationEmptyEnvironment, flags, NULL);
    if (err != errAuthorizationSuccess) {
        return err;
    }
    
    return err;
}

- (void)deauthenticate {
    DLog(@"Deathenticating");
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
        Item *item = [[outlineView itemAtRow:selectedRow] representedObject];
        BOOL canReveal = [WORKSPACE canRevealFileAtPath:item[@"name"]];
        BOOL hasBundlePath = [WORKSPACE canRevealFileAtPath:item[@"path"]];
        [revealButton setEnabled:(canReveal || hasBundlePath)];
        [getInfoButton setEnabled:YES];
        [killButton setEnabled:YES];
        [infoPanelController loadItem:item];
        
        // Make the file path red if file has been moved or deleted
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
        // Bindings should really be able to do this for us! Grr...
        NSArray *items = [menu itemArray];
        for (NSMenuItem *i in items) {
            NSControlStateValue on = [[[i title] lowercaseString] hasSuffix:[DEFAULTS objectForKey:@"sortBy"]];
            [i setState:on];
        }
        return;
    }
    
    // Dynamically generate contextual menu for item
    else if (menu == itemContextualMenu) {
        NSDictionary *item = [[outlineView itemAtRow:[outlineView selectedRow]] representedObject];
        
        NSMenuItem *openItem = [itemContextualMenu itemAtIndex:0];
        NSMenuItem *copyItem = [itemContextualMenu itemAtIndex:10];
        NSMenuItem *killItem = [itemContextualMenu itemAtIndex:12];
        
        NSString *killTitle = @"Kill Process";
        if (item) {
            killTitle = [NSString stringWithFormat:@"Kill Process “%@” (%@)", item[@"pname"], item[@"pid"]];
        }
        [killItem setTitle:killTitle];
        
        if (item && [WORKSPACE canRevealFileAtPath:item[@"name"]]) {
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
    else if (menu == [[itemContextualMenu itemAtIndex:1] submenu] || menu == openWithMenu) {
        NSDictionary *item = [[outlineView itemAtRow:[outlineView selectedRow]] representedObject];
        NSString *path = nil;
        if (item && [item[@"type"] isEqualToString:@"Process"] == NO) {
            path = item[@"path"] ? item[@"path"] : item[@"name"];
        }
        [WORKSPACE openWithMenuForFile:path target:nil action:nil menu:menu];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {

    NSInteger selectedRow = [outlineView clickedRow] == -1 ? [outlineView selectedRow] : [outlineView clickedRow];
    SEL action = [menuItem action];
    
    BOOL isAction = (action == @selector(show:) ||
                     action == @selector(showInfoInFinder:) ||
                     action == @selector(showPackageContents:) ||
                     action == @selector(kill:) ||
                     action == @selector(getInfo:) ||
                     action == @selector(open:) ||
                     action == @selector(showSelectedItem:));
    
    // Actions on items should only be enabled when something is selected
    if (isAction && selectedRow < 0) {
        return NO;
    }
    
    NSDictionary *item = [[outlineView itemAtRow:selectedRow] representedObject];
    if (!item && action == @selector(copy:)) {
        return NO;
    }
    
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
    
    BOOL isPackage = (path && [WORKSPACE isFilePackageAtPath:path]);
    if (!isPackage && action == @selector(showPackageContents:)) {
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

/*
 Copyright (c) 2004-2016, Sveinbjorn Thordarson <sveinbjornt@gmail.com>
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

//#import "CoreGraphicsServices.h"
#import "SlothController.h"

#import "GetInfoPanelController.h"
#import "Common.h"
#import <pwd.h>
#import <grp.h>
#import <sys/stat.h>

@interface GetInfoPanelController ()

@property (weak) IBOutlet NSImageView *iconView;
@property (weak) IBOutlet NSTextField *nameTextField;
@property (weak) IBOutlet NSTextField *pathTextField;
@property (weak) IBOutlet NSTextField *filetypeTextField;
@property (weak) IBOutlet NSTextField *finderTypeTextField;
@property (weak) IBOutlet NSTextField *usedByTextField;
@property (weak) IBOutlet NSTextField *itemTypeTextField;
@property (weak) IBOutlet NSTextField *sizeTextField;
@property (weak) IBOutlet NSTextField *permissionsTextField;

@property (weak) IBOutlet NSButton *killButton;
@property (weak) IBOutlet NSButton *showInFinderButton;
@property (weak) IBOutlet NSButton *getFinderInfoButton;
@property (weak) IBOutlet NSButton *quickLookButton;

@property (assign, nonatomic) NSString *path;
@property (assign, nonatomic) NSDictionary *fileInfoDict;

@property (strong) QLPreviewPanel *previewPanel;

@end

@implementation GetInfoPanelController

#pragma mark - Load info

- (void)setItem:(NSDictionary *)itemDict {
    self.fileInfoDict = itemDict;
    
    NSString *type = itemDict[@"type"];
    
    BOOL isProcess = [type isEqualToString:@"Process"];
    BOOL isFileOrFolder = [type isEqualToString:@"File"] || [type isEqualToString:@"Directory"];
    
    // name
    NSString *name = isFileOrFolder ? [itemDict[@"name"] lastPathComponent] : itemDict[@"name"];
    if (name == nil || [name isEqualToString:@""]) {
        name = [NSString stringWithFormat:@"Unnamed %@", type];
    }
    if (isProcess) {
        name = itemDict[@"pname"];
    }
    [self.window setTitle:name];
    [self.nameTextField setStringValue:name];
    
    // path
    NSString *path = @"--";
    if (isFileOrFolder || isProcess) {
        path = [itemDict[@"type"] isEqualToString:@"Process"] ? itemDict[@"bundlepath"] : itemDict[@"name"];
    }
    self.path = path;
    [self.pathTextField setStringValue:path];

    // icon
    NSImage *img = isFileOrFolder ? [WORKSPACE iconForFile:path] : [itemDict[@"image"] copy];
    [img setSize:NSMakeSize(48,48)];
    [self.iconView setImage:img];
    
    NSString *sizeStr = @"";
    if ([type isEqualToString:@"File"]) {
        sizeStr = [self fileSizeStringForPath:path];
    }
    [self.sizeTextField setStringValue:sizeStr];
    
    // type
    [self.itemTypeTextField setStringValue:type];
    
    // owned by
    if (isProcess) {
        NSString *pidStr = [NSString stringWithFormat:@"PID: %@", itemDict[@"pid"]];
        [self.usedByTextField setStringValue:pidStr];
    } else {
        NSString *ownedByStr = [NSString stringWithFormat:@"%@ (%@)", itemDict[@"pname"], itemDict[@"pid"]];
        [self.usedByTextField setStringValue:ownedByStr];
    }
    
    // the other fields
    if (!isFileOrFolder && !isProcess) {
        [self.filetypeTextField setStringValue:@"--"];
        [self.finderTypeTextField setStringValue:@"--"];
        [self.permissionsTextField setStringValue:@"--"];
    } else {
        NSString *fileInfoString = [self fileInfoForPath:path];
        [self.filetypeTextField setStringValue:fileInfoString];
        
        NSString *finderInfoString = [self finderInfoForPath:path];
        [self.finderTypeTextField setStringValue:finderInfoString];
        
        NSString *permString = [self ownerInfoForPath:path];
        [self.permissionsTextField setStringValue:permString];
    }
    
    // buttons
    BOOL workablePath = isFileOrFolder || (isProcess && [FILEMGR fileExistsAtPath:path]);
    [self.showInFinderButton setEnabled:workablePath];
    [self.getFinderInfoButton setEnabled:workablePath];
    
//    [self.quickLookButton setEnabled:workablePath];
//    [[QLPreviewPanel sharedPreviewPanel] reloadData];
}

#pragma mark - Get file info

- (NSString *)ownerInfoForPath:(NSString *)filePath {
    NSString *userAndGroupStr = [self userAndGroupForPath:filePath];
    NSString *permStr = [self permissionsStringForPath:filePath];
    return [NSString stringWithFormat:@"%@ %@", permStr, userAndGroupStr];
}

- (NSString *)permissionsStringForPath:(NSString *)filePath {
    
    // The indices of the items in the permsArray correspond to the POSIX
    // permissions. Essentially each bit of the POSIX permissions represents
    // a read, write, or execute bit.
    NSArray *permsArray = [NSArray arrayWithObjects:@"---", @"--x", @"-w-", @"-wx", @"r--", @"r-x", @"rw-", @"rwx", nil];
    NSMutableString *result = [NSMutableString string];
    NSDictionary *attrs = [FILEMGR attributesOfItemAtPath:filePath error:nil];
    if (!attrs) {
        return @"";
    }
    
    NSUInteger perms = [attrs filePosixPermissions];
    
    if ([[attrs fileType] isEqualToString:NSFileTypeDirectory]) {
        [result appendString:@"d"];
    } else {
        [result appendString:@"-"];
    }
    
    // loop through POSIX permissions, starting at user, then group, then other.
    for (int i = 2; i >= 0; i--) {
        // this creates an index from 0 to 7
        unsigned long thisPart = (perms >> (i * 3)) & 0x7;
        
        // we look up this index in our permissions array and append it.
        [result appendString:[permsArray objectAtIndex:thisPart]];
    }
    
    return result;
}

- (NSString *)userAndGroupForPath:(NSString *)filePath {
    struct stat statInfo;
    stat([filePath fileSystemRepresentation], &statInfo);

    const char *u = user_from_uid(statInfo.st_uid, 0);
    const char *g = group_from_gid(statInfo.st_gid, 0);
    NSString *user = [NSString stringWithCString:u encoding:NSUTF8StringEncoding];
    NSString *group = [NSString stringWithCString:g encoding:NSUTF8StringEncoding];
    
    return [NSString stringWithFormat:@"%@:%@", user, group, nil];
}

- (NSString *)finderInfoForPath:(NSString *)filePath {
    CFStringRef kindCFStr = nil;
    NSString *kindStr = nil;
    LSCopyKindStringForURL((__bridge CFURLRef)[NSURL fileURLWithPath:filePath], &kindCFStr);
    if (kindCFStr) {
        kindStr = [NSString stringWithString:(__bridge NSString *)kindCFStr];
        CFRelease(kindCFStr);
    } else {
        kindStr = @"Unknown";
    }
    return kindStr;
}

- (NSString *)fileInfoForPath:(NSString *)filePath {
    if (![FILEMGR fileExistsAtPath:filePath]) {
        return @"";
    }
    // run file command and get output
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/file"];
    [task setArguments:@[@"-b", filePath]];
    NSPipe *outputPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    [task launch];
    [task waitUntilExit];
    
    NSFileHandle *readHandle = [outputPipe fileHandleForReading];
    NSString *outString = [[NSString alloc] initWithData:[readHandle readDataToEndOfFile]
                                                encoding:NSUTF8StringEncoding];
    return outString;
}

- (NSString *)fileSizeStringForPath:(NSString *)filePath {
    BOOL isDir;
    [FILEMGR fileExistsAtPath:filePath isDirectory:&isDir];
    if (isDir) {
        return @"---";
    }
    
    UInt64 size = [self fileOrFolderSize:filePath];
    NSString *byteSizeStr = [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
    NSString *humanSize = [self sizeAsHumanReadable:size];
    return [NSString stringWithFormat:@"%@ (%@)", humanSize, byteSizeStr];
}

#pragma mark - Interface actions

- (IBAction)showInFinder:(id)sender {
    [[NSApp delegate] performSelector:@selector(revealItemInFinder:) withObject:self.fileInfoDict];
}

- (IBAction)killProcess:(id)sender {
    [[NSApp delegate] performSelector:@selector(kill:) withObject:self];
}

//- (IBAction)quickLook:(id)sender {
////    if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible]) {
////        [[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
////    } else {
////        [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];
////    }
//    
//    if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible])
//    {
//        [[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
//    }
//    else
//    {
//        [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];
//    }
//
//    
//    [[QLPreviewPanel sharedPreviewPanel] reloadData];
//}

#pragma mark - Quick Look panel support

//- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel
//{
//    return YES;
//}
//
//- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel
//{
//    // This document is now responsible of the preview panel
//    // It is allowed to set the delegate, data source and refresh panel.
//    //
//    _previewPanel = panel;
//    panel.delegate = self;
//    panel.dataSource = self;
//}
//
//- (void)endPreviewPanelControl:(QLPreviewPanel *)panel
//{
//    // This document loses its responsisibility on the preview panel
//    // Until the next call to -beginPreviewPanelControl: it must not
//    // change the panel's delegate, data source or refresh it.
//    //
//    _previewPanel = nil;
//}

#pragma mark - QLPreviewPanelDataSource

//- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel
//{
//    return 1;
//}
//
//- (id <QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index
//{
//    return [NSURL URLWithString:[self.pathTextField stringValue]];
//}

#pragma mark - QLPreviewPanelDelegate

//- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event
//{
////    // redirect all key down events to the table view
////    if ([event type] == NSKeyDown)
////    {
////        [self.downloadsTableView keyDown:event];
////        return YES;
////    }
//    return NO;
//}
//
// This delegate method provides the rect on screen from which the panel will zoom.
//- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id <QLPreviewItem>)item
//{
//    NSInteger index = [self.downloads indexOfObject:item];
//    if (index == NSNotFound)
//    {
//        return NSZeroRect;
//    }
//    
//    NSRect iconRect = [self.downloadsTableView frameOfCellAtColumn:0 row:index];
//    
//    // check that the icon rect is visible on screen
//    NSRect visibleRect = [self.downloadsTableView visibleRect];
//    
//    if (!NSIntersectsRect(visibleRect, iconRect))
//    {
//        return NSZeroRect;
//    }
//    
//    // convert icon rect to screen coordinates
//    iconRect = [self.downloadsTableView convertRectToBacking:iconRect];
//    NSRect test = [[self.downloadsTableView window] convertRectToScreen:iconRect];
//    iconRect.origin = test.origin;
//    
//    return iconRect;
//}


#pragma mark -

- (IBAction)getInfoInFinder:(id)sender {
    BOOL isDir;
    if ([FILEMGR fileExistsAtPath:self.path isDirectory:&isDir] == NO) {
        NSBeep();
        return;
    }
    NSString *type = (isDir && ![self.path hasSuffix: @".app"]) ? @"folder" : @"file";
    NSString *osaScript = [NSString stringWithFormat:
                           @"tell application \"Finder\"\n\
                           \tactivate\n\
                           \topen the information window of %@ POSIX file \"%@\"\n\
                           end tell", type, [self path], nil];
    
    NSTask	*theTask = [[NSTask alloc] init];
    
    //initialize task -- we launch the AppleScript via the 'osascript' CLI program
    [theTask setLaunchPath: @"/usr/bin/osascript"];
    [theTask setArguments: [NSArray arrayWithObjects: @"-e", osaScript, nil]];
    [theTask launch];
}

#pragma mark - Util

- (UInt64)fileOrFolderSize:(NSString *)path {
    // returns size 0 for directories
    BOOL isDir;
    if (path == nil || ![FILEMGR fileExistsAtPath:path isDirectory:&isDir] || isDir) {
        return 0;
    }
    
    return [[FILEMGR attributesOfItemAtPath:path error:nil] fileSize];
}

- (NSString *)sizeAsHumanReadable:(UInt64)size {
    if (size < 1024ULL) {
        return [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
    } else if (size < 1048576ULL) {
        return [NSString stringWithFormat:@"%ld KB", (long)size/1024];
    } else if (size < 1073741824ULL) {
        return [NSString stringWithFormat:@"%.1f MB", size / 1048576.0];
    }
    return [NSString stringWithFormat:@"%.1f GB", size / 1073741824.0];
}

@end

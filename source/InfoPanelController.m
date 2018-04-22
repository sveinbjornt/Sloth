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
#import "InfoPanelController.h"
#import "Common.h"
#import "IPServices.h"
#import "NSString+RegexConvenience.h"
#import "ProcessUtils.h"

#import <pwd.h>
#import <grp.h>
#import <sys/stat.h>

#define EMPTY_PLACEHOLDER @"—"

@interface InfoPanelController ()

@property (weak) IBOutlet NSImageView *iconView;
@property (weak) IBOutlet NSTextField *nameTextField;
@property (weak) IBOutlet NSTextField *pathTextField;
@property (weak) IBOutlet NSTextField *pathLabelTextField;
@property (weak) IBOutlet NSTextField *filetypeTextField;
@property (weak) IBOutlet NSTextField *finderTypeTextField;
@property (weak) IBOutlet NSTextField *usedByTextField;
@property (weak) IBOutlet NSTextField *itemTypeTextField;
@property (weak) IBOutlet NSTextField *sizeTextField;
@property (weak) IBOutlet NSTextField *permissionsTextField;
@property (weak) IBOutlet NSTextField *accessModeTextField;

@property (weak) IBOutlet NSButton *killButton;
@property (weak) IBOutlet NSButton *showInFinderButton;
@property (weak) IBOutlet NSButton *getFinderInfoButton;
@property (weak) IBOutlet NSButton *quickLookButton;

@property (assign, nonatomic) NSString *path;
@property (assign, nonatomic) NSDictionary *fileInfoDict;

@end

@implementation InfoPanelController

#pragma mark - Load info

- (void)loadItem:(NSDictionary *)itemDict {
    if (!itemDict) {
        return;
    }
    // NSLog(@"%@", [itemDict description]);
    
    self.fileInfoDict = itemDict;
    
    NSString *type = itemDict[@"type"];
    
    BOOL isProcess = [type isEqualToString:@"Process"];
    BOOL isFileOrFolder = [type isEqualToString:@"File"] || [type isEqualToString:@"Directory"];
    BOOL isIPSocket = [type isEqualToString:@"IP Socket"];
    
    // Name
    NSString *name = isFileOrFolder ? [itemDict[@"name"] lastPathComponent] : itemDict[@"name"];
    if (name == nil || [name isEqualToString:@""]) {
        name = [NSString stringWithFormat:@"Unnamed %@", type];
    }
    if (isProcess) {
        name = itemDict[@"pname"];
    }
    [self.window setTitle:name];
    [self.nameTextField setStringValue:name];
    
    // Path
    NSString *path = EMPTY_PLACEHOLDER;
    if (isFileOrFolder || isProcess) {
        NSString *p = [itemDict[@"type"] isEqualToString:@"Process"] ? itemDict[@"path"] : itemDict[@"name"];
        path = p ? p : path;
    }
    self.path = path;
    if ([FILEMGR fileExistsAtPath:path] || [path isEqualToString:EMPTY_PLACEHOLDER]) {
        [self.pathTextField setStringValue:path];
    } else {
        NSAttributedString *redPath = [[NSAttributedString alloc] initWithString:path attributes:@{ NSForegroundColorAttributeName : [NSColor redColor] }];
        [self.pathTextField setAttributedStringValue:redPath];
    }
    
    
    // Resolve DNS and show details for IP sockets
    self.pathLabelTextField.stringValue = isIPSocket ? @"IP Socket Info" : @"Path";
    if (isIPSocket) {
        // Resolve DNS asynchronously
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSString *ipSockName = [self.path copy];
                NSString *descStr = [self IPSocketDescriptionForName:itemDict[@"name"]];
                // Then update UI on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Make sure loaded item hasn't changed during DNS lookup
                    if ([self.pathTextField.stringValue isEqualToString:ipSockName]) {
                        [self.pathTextField setStringValue:descStr];
                    }
                });
            }
        });
    }

    // Icon
    NSImage *img = isFileOrFolder ? [WORKSPACE iconForFile:path] : [itemDict[@"image"] copy];
    [img setSize:NSMakeSize(48,48)];
    [self.iconView setImage:img];
    
    NSString *sizeStr = @"";
    if ([type isEqualToString:@"File"]) {
        sizeStr = [self fileSizeStringForPath:path];
    }
    [self.sizeTextField setStringValue:sizeStr];
    
    // Type
    NSString *typeStr = type;
    if (isProcess) {
        pid_t pid = [itemDict[@"pid"] intValue];
        NSString *owner = [ProcessUtils ownerUserNameForPID:pid];
        if (owner) {
            typeStr = [NSString stringWithFormat:@"Process (%@)", owner];
        }
    }
    if (isIPSocket) {
        typeStr = [NSString stringWithFormat:@"%@ Socket (%@)", itemDict[@"ipversion"], itemDict[@"protocol"]];
    }
    [self.itemTypeTextField setStringValue:typeStr];
    
    // Owned by
    if (isProcess) {
        NSString *pidStr = [NSString stringWithFormat:@"PID: %@", itemDict[@"pid"]];
        [self.usedByTextField setStringValue:EMPTY_PLACEHOLDER];
        [self.sizeTextField setStringValue:pidStr];
    } else {
        NSString *ownedByStr = [NSString stringWithFormat:@"%@ (%@)", itemDict[@"pname"], itemDict[@"pid"]];
        [self.usedByTextField setStringValue:ownedByStr];
    }
    
    // Access mode
    NSString *access = [self accessModeDescriptionForItem:itemDict];
    [self.accessModeTextField setStringValue:access];
    
    // The other fields
    if ((!isFileOrFolder && (!isProcess || (isProcess && itemDict[@"path"] == nil))) ||
        (isFileOrFolder && ![FILEMGR fileExistsAtPath:itemDict[@"name"]])) {
        [self.filetypeTextField setStringValue:EMPTY_PLACEHOLDER];
        [self.finderTypeTextField setStringValue:EMPTY_PLACEHOLDER];
        [self.permissionsTextField setStringValue:EMPTY_PLACEHOLDER];
    } else {
        NSString *fileInfoString = [self fileUtilityInfoForPath:path];
        [self.filetypeTextField setStringValue:fileInfoString];
        
        NSString *finderTypeString = [self launchServicesTypeForPath:path];
        [self.finderTypeTextField setStringValue:finderTypeString];
        
        NSString *permString = [self ownerInfoForPath:path];
        [self.permissionsTextField setStringValue:permString];
    }
    
    // Buttons
    BOOL workablePath = [FILEMGR fileExistsAtPath:path] && (isFileOrFolder || isProcess);
    [self.showInFinderButton setEnabled:workablePath];
    [self.getFinderInfoButton setEnabled:workablePath];    
    [self.quickLookButton setEnabled:workablePath];
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
    NSArray *permsArray = @[@"---", @"--x", @"-w-", @"-wx", @"r--", @"r-x", @"rw-", @"rwx"];
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
    
    // Loop through POSIX permissions, starting at user, then group, then other.
    for (int i = 2; i >= 0; i--) {
        // This creates an index from 0 to 7
        unsigned long thisPart = (perms >> (i * 3)) & 0x7;
        
        // We look up this index in our permissions array and append it.
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

- (NSString *)launchServicesTypeForPath:(NSString *)filePath {
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

// Run /usr/bin/file program on path, return output
- (NSString *)fileUtilityInfoForPath:(NSString *)filePath {
    if (![FILEMGR fileExistsAtPath:filePath]) {
        return @"";
    }
    // Run 'file' command and get output
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
    outString = outString ? outString : @"";
    
    // Capitalise first letter of output
    if ([outString length]) {
        NSString *firstLetter = [[outString substringToIndex:1] uppercaseString];
        outString = [outString stringByReplacingCharactersInRange:NSMakeRange(0,1)
                                                       withString:firstLetter];
    }
    
    return outString;
}

- (NSString *)fileSizeStringForPath:(NSString *)filePath {
    BOOL isDir;
    BOOL exists = [FILEMGR fileExistsAtPath:filePath isDirectory:&isDir];
    if (isDir || !exists) {
        return EMPTY_PLACEHOLDER;
    }
    
    UInt64 size = [[FILEMGR attributesOfItemAtPath:filePath error:nil] fileSize];
    NSString *sizeString = [self fileSizeAsHumanReadableString:size];

    if ([sizeString hasSuffix:@"bytes"] == NO) {
        NSString *byteSizeStr = [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
        sizeString = [NSString stringWithFormat:@"%@ (%@)", sizeString, byteSizeStr];
    }
    
    return sizeString;
}

- (NSString *)accessModeDescriptionForItem:(NSDictionary *)itemDict {
    NSDictionary *descStrMap = @{ @"r": @"Read", @"w": @"Write", @"u": @"Read / Write" };
    
    // Parse file descriptor num
    int fd;
    BOOL hasFD = (itemDict[@"fd"] != nil) && [[NSScanner scannerWithString:itemDict[@"fd"]] scanInt:&fd];
    
    // Map access mode abbreviation to description string
    NSString *mode = itemDict[@"accessmode"];
    NSString *access = descStrMap[mode];
    
    // See if it's one of the three standard io streams
    if (access != nil && hasFD && fd < 3 && [itemDict[@"type"] isEqualToString:@"Character Device"]) {
        NSArray *standardIOs = @[@"STDIN", @"STDOUT", @"STDERR"];
        access = [NSString stringWithFormat:@"%@ (%@?)", access, standardIOs[fd]];
    }
    
    // OK, we don't have any access mode
    if (access == nil) {
        if (itemDict[@"fd"] == nil) {
            return EMPTY_PLACEHOLDER;
        } else {
            if (hasFD) {
                access = EMPTY_PLACEHOLDER;
            } else if ([itemDict[@"fd"] isEqualToString:@"txt"]) {
                access = @"N/A: Program binary, asset or shared lib";
            } else if ([itemDict[@"fd"] isEqualToString:@"cwd"]) {
                access = @"N/A: Current working directory";
            } else if ([itemDict[@"fd"] isEqualToString:@"twd"]) {
                access = @"N/A: Per-thread working directory";
            } else {
                access = [NSString stringWithFormat:@"No file descriptor. Type: %@", itemDict[@"fd"]];
            }
        }
    }
    
    return access;
}

- (NSString *)IPSocketDescriptionForName:(NSString *)name {
    NSMutableString *desc = [NSMutableString string];
    
    // Typical lsof name for IP socket has the format: 10.95.10.6:53989->31.13.90.2:443
    NSArray *components = [name componentsSeparatedByString:@"->"];
    for (NSString *c in components) {
        NSArray *addressAndPort = [c componentsSeparatedByString:@":"];
        NSString *address = addressAndPort[0];
        NSString *port = @"";
        if ([addressAndPort count] > 1) {
            port = addressAndPort[1];
        }
        
        if ([DEFAULTS boolForKey:@"dnsLookup"] == NO) {
            // It's in the format 1.2.3.4:22->4.3.2.1:22
            // Do DNS lookup
            NSString *dnsName = [IPServices dnsNameForIPAddressString:address];
            if (dnsName) {
                address = dnsName;
            }
            
            // Look up port name
            NSString *portName = [IPServices portNameForPortNumString:port];
            if (portName) {
                port = portName;
            }
        } else {
            // It's in the format myhostname:portname->anotherhost:portname
            // Resolve DNS name to IP address
            NSString *ipStr = [IPServices IPAddressStringForDNSName:address];
            if (ipStr) {
                address = ipStr;
            }
            
            // Get port number from port name
            NSString *portNum = [IPServices portNumberForPortNameString:port];
            if (portNum) {
                port = portNum;
            }
        }
        
        // If before second component
        if ([desc length]) {
            [desc appendString:@"\n–>\n"];
        }
        
        [desc appendString:[NSString stringWithFormat:@"%@:%@", address, port]];
    }
    
    
    return desc;
}

#pragma mark - Interface actions

- (IBAction)showInFinder:(id)sender {
    [[NSApp delegate] performSelector:@selector(revealItemInFinder:) withObject:self.fileInfoDict];
}

- (IBAction)killProcess:(id)sender {
    [[NSApp delegate] performSelector:@selector(kill:) withObject:self];
}

- (IBAction)getInfoInFinder:(id)sender {
    BOOL isDir;
    if ([FILEMGR fileExistsAtPath:self.path isDirectory:&isDir] == NO) {
        NSBeep();
        return;
    }
    
    NSString *type = (isDir && ![WORKSPACE isFilePackageAtPath:self.path]) ? @"folder" : @"file";
    NSString *osaScript = [NSString stringWithFormat:
                           @"tell application \"Finder\"\n\
                           \tactivate\n\
                           \topen the information window of %@ POSIX file \"%@\"\n\
                           end tell", type, [self path], nil];
    
    [self runAppleScript:osaScript];
}

- (IBAction)quickLook:(id)sender {
    if ([FILEMGR fileExistsAtPath:self.path] == NO) {
        NSBeep();
        return;
    }
    NSString *source = [NSString stringWithFormat:@"tell application \"Finder\"\n\
                        activate\n\
                        set imageFile to item (POSIX file \"%@\")\n\
                        select imageFile\n\
                        tell application \"System Events\" to keystroke \"y\" using command down\n\
                        end tell", self.path];
    
    [self runAppleScript:source];
}

#pragma mark - Util

- (BOOL)runAppleScript:(NSString *)scriptSource {
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    if (appleScript != nil) {
        [appleScript executeAndReturnError:nil];
        return YES;
    } else {
        NSLog(@"Error running AppleScript");
        return NO;
    }
}

- (NSString *)fileSizeAsHumanReadableString:(UInt64)size {
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

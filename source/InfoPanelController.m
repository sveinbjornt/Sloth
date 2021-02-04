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

#import "SlothController.h"
#import "InfoPanelController.h"
#import "Common.h"
#import "IPUtils.h"
#import "IconUtils.h"
#import "ProcessUtils.h"
#import "NSWorkspace+Additions.h"
#import "Item.h"

#import <pwd.h>
#import <grp.h>
#import <sys/stat.h>

#define EMPTY_PLACEHOLDER @"—"

@interface InfoPanelController ()

@property (weak) IBOutlet NSImageView *iconView;
@property (weak) IBOutlet NSImageView *processIconView;
@property (weak) IBOutlet NSTextField *nameTextField;
@property (weak) IBOutlet NSTextField *pathTextField;
@property (weak) IBOutlet NSTextField *pathLabelTextField;
@property (weak) IBOutlet NSTextField *filetypeTextField;
@property (weak) IBOutlet NSTextField *finderTypeTextField;
@property (weak) IBOutlet NSTextField *usedByLabelTextField;
@property (weak) IBOutlet NSTextField *usedByTextField;
@property (weak) IBOutlet NSTextField *itemTypeTextField;
@property (weak) IBOutlet NSTextField *sizeTextField;
@property (weak) IBOutlet NSTextField *permissionsTextField;
@property (weak) IBOutlet NSTextField *accessModeTextField;
@property (weak) IBOutlet NSTextField *fileSystemTextField;
@property (weak) IBOutlet NSTextField *fileSystemExtraTextField;

@property (weak) IBOutlet NSButton *killButton;
@property (weak) IBOutlet NSButton *showInFinderButton;
@property (weak) IBOutlet NSButton *getFinderInfoButton;
@property (weak) IBOutlet NSButton *showPackageContentsButton;

@property (assign, nonatomic) NSString *path;
@property (assign, nonatomic) NSDictionary *fileInfoDict;

@end

@implementation InfoPanelController

#pragma mark - Load info

- (void)loadItem:(Item *)item {
    if (!item) {
        return;
    }
    DLog(@"%@", [item description]);
    
    self.fileInfoDict = item;
    
    NSString *type = item[@"type"];
    
    BOOL isProcess = [type isEqualToString:@"Process"];
    BOOL isFileOrFolder = [type isEqualToString:@"File"] || [type isEqualToString:@"Directory"];
    BOOL isIPSocket = [type isEqualToString:@"IP Socket"];
    BOOL isPipeOrSocket = [type isEqualToString:@"Unix Domain Socket"] || [type isEqualToString:@"Pipe"];
    
    // Name
    NSString *name = isFileOrFolder ? [item[@"name"] lastPathComponent] : item[@"name"];
    if (name == nil || [name isEqualToString:@""]) {
        name = [NSString stringWithFormat:@"Unnamed %@", type];
    }
    if (isProcess) {
        name = item[@"pname"];
    }
    [self.window setTitle:name];
    [self.nameTextField setStringValue:name];
    
    // Path
    NSString *path = EMPTY_PLACEHOLDER;
    if (isFileOrFolder || isProcess) {
        NSString *p = [item[@"type"] isEqualToString:@"Process"] ? item[@"path"] : item[@"name"];
        path = p ? p : path;
    }
    self.path = path;
    if (([path hasPrefix:@"/"] && [FILEMGR fileExistsAtPath:path])
        || [path isEqualToString:EMPTY_PLACEHOLDER]) {
        [self.pathTextField setStringValue:path];
    } else {
        NSAttributedString *redPath = [[NSAttributedString alloc] initWithString:path attributes:@{ NSForegroundColorAttributeName : [NSColor redColor] }];
        [self.pathTextField setAttributedStringValue:redPath];
    }
    
    // File system
    [self.fileSystemTextField setStringValue:EMPTY_PLACEHOLDER];
    [self.fileSystemExtraTextField setStringValue:@""];
    if (isFileOrFolder) {
        [self.fileSystemTextField setStringValue:[self filesystemDescriptionForItem:item]];
        NSString *addInfo = [NSString stringWithFormat:@"%@ (inode %@)",
                  item[@"device"][@"devname"],
                  item[@"inode"]];
        [self.fileSystemExtraTextField setStringValue:addInfo];
    }
    
    // Resolve DNS and show details for IP sockets
    self.pathLabelTextField.stringValue = isIPSocket ? @"IP Socket Info" : @"Path";
    if (isIPSocket) {
        [self.pathTextField setStringValue:item[@"name"]];
        // Resolve DNS asynchronously since it is slow
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
//                NSString *ipSockName = [self.path copy];
                NSString *descStr = [self IPSocketDescriptionForItem:item];
                // Then update UI on main thread
                dispatch_async(dispatch_get_main_queue(), ^{
//                    if ([self.pathTextField.stringValue isEqualToString:ipSockName]) {
                        [self.pathTextField setStringValue:descStr];
//                    }
                });
            }
        });
    }
    
    // Show endpoints for pipes and unix domain sockets
    if (!isIPSocket) {
        self.pathLabelTextField.stringValue = isPipeOrSocket ? @"Connected to" : @"Path";
    }
    if (isPipeOrSocket && [item[@"endpoints"] count]) {
        NSString *eps = [item[@"endpoints"] componentsJoinedByString:@"\n"];
        [self.pathTextField setStringValue:eps];
    }
    
    // Icon
    NSImage *img = isFileOrFolder ? [WORKSPACE iconForFile:path] : [item[@"image"] copy];
    [img setSize:NSMakeSize(48,48)];
    [self.iconView setImage:img];
    NSImage *procImg = isProcess ? item[@"image"] : item[@"pimage"];
    [self.processIconView setImage:procImg];
    
    // Size / socket status
    NSString *sizeStr = @"";
    if ([type isEqualToString:@"File"]) {
        sizeStr = [self fileSizeStringForPath:path];
    } else if (isIPSocket && item[@"socketstate"]) {
        sizeStr = [NSString stringWithFormat:@"State: %@", item[@"socketstate"]];
    }
    [self.sizeTextField setStringValue:sizeStr];
    
    // Type
    NSString *typeStr = type;
    if (isProcess) {
        pid_t pid = [item[@"pid"] intValue];
        NSString *owner = [ProcessUtils ownerUserNameForPID:pid];
        if (owner) {
            typeStr = [NSString stringWithFormat:@"Process (%@)", owner];
        }
    }
    if (isIPSocket) {
        typeStr = [NSString stringWithFormat:@"%@ Socket (%@)", item[@"ipversion"], item[@"protocol"]];
    }
    [self.itemTypeTextField setStringValue:typeStr];
    
    // Owned by
    [self.usedByLabelTextField setStringValue:@"Used by"];
    if (isProcess) {
        NSString *pidStr = [NSString stringWithFormat:@"PID: %@", item[@"pid"]];
        if (item[@"psn"]) {
            pidStr = [pidStr stringByAppendingFormat:@"  PSN: %@", item[@"psn"]];
        }
        [self.sizeTextField setStringValue:pidStr];
        
        [self.usedByTextField setStringValue:@"None (non-bundle process)"];
        [self.usedByLabelTextField setStringValue:@"Identifier"];
        if (item[@"bundle"]) {
            NSString *usedByStr = item[@"identifier"];
            if (usedByStr) {
                 [self.usedByTextField setStringValue:usedByStr];
            }
        }
        
    } else {
        NSString *ownedByStr = [NSString stringWithFormat:@"%@ (%@)", item[@"pname"], item[@"pid"]];
        [self.usedByTextField setStringValue:ownedByStr];
    }
    
    // Access mode
    NSString *access = [self accessModeDescriptionForItem:item];
    [self.accessModeTextField setStringValue:access];
    
    // The other fields
    if (!isFileOrFolder && (!isProcess || (isProcess && item[@"path"] == nil))) {
        [self.filetypeTextField setStringValue:EMPTY_PLACEHOLDER];
        [self.finderTypeTextField setStringValue:EMPTY_PLACEHOLDER];
        [self.permissionsTextField setStringValue:EMPTY_PLACEHOLDER];
    } else {
        NSString *fileInfoString = [self fileUtilityInfoForPath:path];
        [self.filetypeTextField setStringValue:fileInfoString];
        
        NSString *finderTypeString = [WORKSPACE kindStringForFile:path];
        NSString *uti = [WORKSPACE UTIForFile:path];
        if (uti && ![uti hasPrefix:DYNAMIC_UTI_PREFIX]) {
            finderTypeString = [finderTypeString stringByAppendingFormat:@" (%@)", uti];
        }
        [self.finderTypeTextField setStringValue:finderTypeString];
        
        NSString *permString = [self ownerInfoForPath:path];
        [self.permissionsTextField setStringValue:permString];
    }
    
    // Also show 'file' info for character devices
    if ([type isEqualToString:@"Character Device"]) {
        [self.filetypeTextField setStringValue:[self fileUtilityInfoForPath:name]];
    }
    
    // Buttons
    BOOL workablePath = [FILEMGR fileExistsAtPath:path] && (isFileOrFolder || isProcess);
    [self.showInFinderButton setEnabled:workablePath];
    [self.getFinderInfoButton setEnabled:workablePath];
    [self.showPackageContentsButton setHidden:![item[@"bundle"] boolValue]];
    if ([self.showPackageContentsButton image] == nil) {
        NSImage *img = [IconUtils imageNamed:@"SmallDirectory"];
        [img setSize:NSMakeSize(10.f,10.f)];
        [self.showPackageContentsButton setImage:img];
    }
}

#pragma mark - Get file info

- (NSString *)ownerInfoForPath:(NSString *)filePath {
    if ([FILEMGR fileExistsAtPath:filePath] == NO) {
        return @"-";
    }
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
    NSString *sizeString = [WORKSPACE fileSizeAsHumanReadableString:size];

    if ([sizeString hasSuffix:@"bytes"] == NO) {
        NSString *byteSizeStr = [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
        sizeString = [NSString stringWithFormat:@"%@ (%@)", sizeString, byteSizeStr];
    }
    
    return sizeString;
}

- (NSString *)accessModeDescriptionForItem:(NSDictionary *)itemDict {
    NSDictionary *descStrMap = @{ @"r": @"Read", @"w": @"Write", @"u": @"Read / Write" };
    
    // Parse file descriptor num
    int fd = -1;
    BOOL hasFD = (itemDict[@"fd"] != nil) && [[NSScanner scannerWithString:itemDict[@"fd"]] scanInt:&fd];
    
    // Map access mode abbreviation to description string
    NSString *access = EMPTY_PLACEHOLDER;
    NSString *mode = itemDict[@"accessmode"];
    NSString *accessModeName = descStrMap[mode];
    if (accessModeName) {
        access = descStrMap[mode];
    }
    
    // See if it's one of the three standard io streams
    NSString *ioDesc = @"";
    if (accessModeName != nil && hasFD && fd < 3) {
        NSArray *standardIOs = @[@" - STDIN?", @" - STDOUT?", @" - STDERR?"];
        ioDesc = standardIOs[fd];
    }
    
    if (fd != -1) {
        access = [NSString stringWithFormat:@"%@  (fd%d%@)", access, fd, ioDesc];
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

- (NSString *)IPSocketDescriptionForItem:(Item *)item {
    NSString *name = item[@"name"];
    NSString *ipVersion = item[@"ipversion"];
    
    NSMutableString *descriptionString = [NSMutableString string];
    
    // Typical lsof name for IP socket has the format: 10.95.10.6:53989->31.13.90.2:443, or, if using IPv6,
    // like this: [2a00:23c1:4a82:8700:8877:843b:bcf4:c98b]:50865->[2a00:1450:4009:80a::200e]:80
    NSArray *components = [name componentsSeparatedByString:@"->"];
    
    for (NSString *c in components) {
        NSMutableArray *addressAndPort = [[c componentsSeparatedByString:@":"] mutableCopy];
        if ([addressAndPort count] == 1) {
            return name;
        }
        
        NSString *port = [addressAndPort lastObject];
        [addressAndPort removeLastObject];
        NSString *address = [addressAndPort componentsJoinedByString:@":"];
        
        // Chop the surrounding square brackets that lsof adds to IPv6 addresses
        if ([address characterAtIndex:[address length]-1] == ']') {
            address = [address substringToIndex:[address length]-1];
        }
        if ([address characterAtIndex:0] == '[') {
            address = [address substringFromIndex:1];
        }
        
        NSString *addrDescStr = address;
        NSString *portDescStr = port;
        
        // Is the address an IP address?
        if ([IPUtils isIPv4AddressString:address] || [IPUtils isIPv6AddressString:address]) {
            NSString *dnsName = [IPUtils dnsNameForIPAddressString:address];
            if (dnsName) {
                addrDescStr = dnsName;
            }
            
            NSString *portName = [IPUtils portNameForPortNumString:port];
            if (portName) {
                portDescStr = portName;
            }
        }
        // If not, it must be DNS name
        else {
            NSString *ipStr;
            if ([ipVersion isEqualToString:@"IPv6"]) {
                ipStr = [IPUtils IPv6AddressStringForDNSName:address];
            }
            if (!ipStr) {
                ipStr = [IPUtils IPv4AddressStringForDNSName:address];
            }
            
            if (ipStr) {
                if ([IPUtils isIPv6AddressString:ipStr]) {
                    // RFC 3986
                    // A host identified by an Internet Protocol literal address,
                    // version 6 [RFC3513] or later, is distinguished by enclosing
                    // the IP literal within square brackets ("[" and "]").
                    ipStr = [NSString stringWithFormat:@"[%@]", ipStr];
                }
                addrDescStr = ipStr;
            }
            
            NSString *portNum = [IPUtils portNumberForPortNameString:port];
            if (portNum) {
                portDescStr = portNum;
            }
        }
        
        // If before second component
        if ([descriptionString length]) {
            [descriptionString appendString:@"\n–>\n"];
        }
        
        [descriptionString appendString:[NSString stringWithFormat:@"%@:%@", addrDescStr, portDescStr]];
    }
    
    return descriptionString;
}

- (NSString *)filesystemDescriptionForItem:(Item *)item {
    if (![item objectForKey:@"device"]) {
        return EMPTY_PLACEHOLDER;
    }
    
    NSString *mountPoint = item[@"device"][@"mountpoint"];
    NSString *desc;
    NSString *type;
    [WORKSPACE getFileSystemInfoForPath:mountPoint
                            isRemovable:NULL
                             isWritable:NULL
                          isUnmountable:NULL
                            description:&desc
                                   type:&type];

    NSURL *url = [NSURL fileURLWithPath:mountPoint];
    NSError *error;
    NSString *volName;
    [url getResourceValue:&volName forKey:NSURLVolumeNameKey error:&error];
    if (!volName || error) {
        volName = @"????";
    }
    
    return [NSString stringWithFormat:@"%@ (%@)", volName, [type uppercaseString]];
}

#pragma mark - Interface actions

- (IBAction)getInfoInFinder:(id)sender {
    NSString *path = self.fileInfoDict[@"path"] ? self.fileInfoDict[@"path"] : self.fileInfoDict[@"name"];
    [WORKSPACE showFinderGetInfoForFile:path];
}

- (IBAction)showInFinder:(id)sender {
    [[NSApp delegate] performSelector:@selector(revealItemInFinder:) withObject:self.fileInfoDict];
}

- (IBAction)showPackageContents:(id)sender {
    NSString *path = self.fileInfoDict[@"path"] ? self.fileInfoDict[@"path"] : self.fileInfoDict[@"name"];
    [WORKSPACE showPackageContents:path];
}

- (IBAction)killProcess:(id)sender {
    [[NSApp delegate] performSelector:@selector(kill:) withObject:self];
}

@end

/*
    Copyright (c) 2004-2026, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "LsofTask.h"

#import "Common.h"
#import "STPrivilegedTask.h"
#import "Item.h"
#import "FSUtils.h"
#import "IconUtils.h"
#import "ProcessUtils.h"

@implementation LsofTask

- (NSMutableArray<Item *> *)launch:(AuthorizationRef __nullable)authRef numFiles:(NSInteger *)numFiles {
    return [self parse:[self run:authRef] numFiles:numFiles];
}

- (NSString *)run:(AuthorizationRef)authRef {
    DLog(@"Running lsof task");
    NSData *outputData;
    
    if (authRef) {
        STPrivilegedTask *task = [[STPrivilegedTask alloc] init];
        [task setLaunchPath:LSOF_PATH];
        [task setArguments:[self args]];
        [task launchWithAuthorization:authRef];
        
        outputData = [[task outputFileHandle] readDataToEndOfFile];
        
    } else {
        
        NSTask *lsof = [[NSTask alloc] init];
        [lsof setLaunchPath:LSOF_PATH];
        [lsof setArguments:[self args]];
        
        NSPipe *pipe = [NSPipe pipe];
        [lsof setStandardOutput:pipe];
        [lsof setStandardError:[NSFileHandle fileHandleWithNullDevice]];
        [lsof setStandardInput:[NSFileHandle fileHandleWithNullDevice]];
        [lsof launch];
        
        outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
    }
    
    return [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
}

- (NSMutableArray<Item *> *)parse:(NSString *)outputString numFiles:(NSInteger *)numFiles {
    // Parse-friendly lsof output has the following format:
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
    //    etc...
    //
    // We parse this into an array of processes, each of which has children.
    // Each child is a dictionary containing file/socket info.
    
    DLog(@"Parsing lsof output");
    NSMutableArray *processList = [NSMutableArray new];
    *numFiles = 0;
    
    if (![outputString length]) {
        DLog(@"Empty lsof output!");
        return processList;
    }
    
    // Get info about mounted filesystems
    NSDictionary *fileSystems = [FSUtils mountedFileSystems];
    
    // Maps device character codes to items. Used to find socket/pipe endpoints.
    NSMutableDictionary *devCharCodeMap = [NSMutableDictionary dictionary];
    
    Item *currentProcess;
    Item *currentFile;
    BOOL skip = NO;
    
    // Parse each line
    for (NSString *line in [outputString componentsSeparatedByString:@"\n"]) {
        if ([line length] == 0) {
            continue;
        }
        
        unichar prefix = [line characterAtIndex:0];
        NSString *value = [line substringFromIndex:1];
        
        switch (prefix) {
            
            // PID - First line of output for new process
            case 'p':
            {
                // Add last item
                if (currentProcess && currentFile && !skip) {
                    [currentProcess[@"children"] addObject:currentFile];
                    currentFile = nil;
                }
                
                // Set up new process dict
                currentProcess = [Item new];
                currentProcess[@"pid"] = value;
                currentProcess[@"type"] = @"Process";
                currentProcess[@"children"] = [NSMutableArray array];
                [processList addObject:currentProcess];
            }
                break;
                
            // Process name
            case 'c':
                value = [LsofTask unescapedString:value];
                currentProcess[@"name"] = value;
                currentProcess[@"displayname"] = value;
                break;
                
            // Process UID
            case 'u':
                currentProcess[@"userid"] = value;
                break;
            
            // Parent process ID
            case 'R':
            {
                NSString *parentProcIDStr = value;
                currentProcess[@"parentid"] = @([parentProcIDStr integerValue]);
            }
                break;
            
            // File descriptor - First line of output for a file
            case 'f':
            {
                if (currentFile && !skip) {
                    [currentProcess[@"children"] addObject:currentFile];
                    currentFile = nil;
                }
                
                // New file info starting, create new file dict
                currentFile = [Item new];
                NSString *fd = value;
                currentFile[@"fd"] = fd;
                if ([fd isEqualToString:@"err"]) {
                    currentFile[@"type"] = @"Error";
                    currentFile[@"image"] = [IconUtils imageNamed:@"Error"];
                }
                currentFile[@"pname"] = currentProcess[@"name"];
                currentFile[@"pid"] = currentProcess[@"pid"];
                currentFile[@"puserid"] = currentProcess[@"userid"];
                
                // txt files are program code, such as the application binary itself or a shared library
                if ([fd isEqualToString:@"txt"] && ![DEFAULTS boolForKey:@"showProcessBinaries"]) {
                    skip = YES;
                }
                // cwd and twd are current working directory and thread working directory, respectively
                else if (([fd isEqualToString:@"cwd"] || [fd isEqualToString:@"twd"]) && ![DEFAULTS boolForKey:@"showCurrentWorkingDirectories"]) {
                    skip = YES;
                }
                else {
                    skip = NO;
                }
            }
                break;
            
            // File access mode
            case 'a':
                currentFile[@"accessmode"] = value;
                break;
                
            // File type
            case 't':
            {
                NSString *ftype = value;
                
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
                    currentFile[@"type"] = @"Unix Domain Socket";
                }
                else if ([ftype isEqualToString:@"VCHR"] || [ftype isEqualToString:@"CHR"]) {
                    currentFile[@"type"] = @"Character Device";
                }
                else if ([ftype isEqualToString:@"PIPE"]) {
                    currentFile[@"type"] = @"Pipe";
                }
                else {
                    //DLog(@"Unrecognized file type: %@ : %@", ftype, [currentFile description]);
                    skip = YES;
                }
                
                if (currentFile[@"type"]) {
                    NSImage *img = [IconUtils imageNamed:currentFile[@"type"]];
                    if (img) {
                        currentFile[@"image"] = img;
                    }
                }
            }
                break;
            
            // File name / path
            case 'n':
            {
                value = [LsofTask unescapedString:value];
                currentFile[@"name"] = value;
                currentFile[@"displayname"] = [currentFile[@"name"] length] ? currentFile[@"name"] : @"Unnamed";
                
                // Some files when running in root mode have no type listed
                // and are only reported with the name "(revoked)". Skip those.
                if (!currentFile[@"type"] && [currentFile[@"name"] isEqualToString:@"(revoked)"]) {
                    skip = YES;
                }
                
                if ([value hasSuffix:@"Operation not permitted"]) {
                    currentFile[@"type"] = @"Error";
                    currentFile[@"image"] = [IconUtils imageNamed:@"Error"];
                }
                
                if ([currentFile[@"name"] hasPrefix:@"unknown file type:"]) {
                    currentFile[@"image"] = [IconUtils imageNamed:@"QuestionMark"];
                }
            }
                break;
            
            // Protocol (IP sockets only)
            case 'P':
                currentFile[@"protocol"] = value;
                break;
                
            // TCP socket info (IP sockets only)
            case 'T':
            {
                NSString *socketInfo = value;
                if ([socketInfo hasPrefix:@"ST="]) {
                    currentFile[@"socketstate"] = [socketInfo substringFromIndex:3];
                    currentFile[@"displayname"] = [NSString stringWithFormat:@"%@ (%@)",
                                                   currentFile[@"name"], currentFile[@"socketstate"]];
                }
            }
                break;
                
            // Device character code
            case 'd':
            {
                NSString *devCharCode = value;
                currentFile[@"devcharcode"] = devCharCode;
                if (devCharCodeMap[devCharCode] == nil) {
                    devCharCodeMap[devCharCode] = [NSMutableArray new];
                }
                [devCharCodeMap[devCharCode] addObject:currentFile];
            }
                break;
                
            // File's major/minor device number (0x<hexadecimal>)
            case 'D':
            {
                unsigned int deviceID = 0;
                NSString *deviceIDStr = value;
                NSScanner *scanner = [NSScanner scannerWithString:deviceIDStr];
                [scanner scanHexInt:&deviceID];
                // Use device number to add file system info to file
                currentFile[@"device"] = fileSystems[@(deviceID)] ? fileSystems[@(deviceID)] : @{ @"devid": @(deviceID) };
            }
                break;
            
            // File inode number
            case 'i':
            {
                NSString *inodeNumStr = value;
                currentFile[@"inode"] = @([inodeNumStr integerValue]);
            }
                break;
        }
    }
    
    // Add the one remaining output item
    if (currentProcess && currentFile && !skip) {
        [currentProcess[@"children"] addObject:currentFile];
    }
    
    // Get additional info about the processes, count total number of files
    for (NSMutableDictionary *process in processList) {
        [LsofTask updateProcessInfo:process];
        *numFiles += [process[@"children"] count];
        
        // Iterate over the process's children, map sockets and pipes to their endpoint
        for (NSMutableDictionary *f in process[@"children"]) {
            if (![f[@"type"] isEqualToString:@"Unix Domain Socket"] && ![f[@"type"] isEqualToString:@"Pipe"]) {
                continue;
            }
            // Identifiable pipes and sockets should have names in the format "->[NAME]"
            if ([f[@"name"] length] < 3) {
                continue;
            }
            
            NSString *name = [f[@"name"] substringFromIndex:2];
            
            // If we know which process owns the other end of the pipe/socket
            // Needs to run with root privileges for successful lookup of the
            // endpoints of system process pipes/sockets such as syslogd.
            if (devCharCodeMap[name]) {
                NSArray *endPoints = devCharCodeMap[name];
                NSMutableArray *epItems = [NSMutableArray new];
                NSDictionary *first = devCharCodeMap[name][0];
                f[@"displayname"] = [NSString stringWithFormat:@"%@ (%@%@)",
                                     f[@"displayname"], first[@"pname"],
                                     [endPoints count] > 1 ? @" ..." : @""];
                for (NSDictionary *e in endPoints) {
                    NSString *i = [NSString stringWithFormat:@"%@ (%@)", e[@"pname"], e[@"pid"]];
                    [epItems addObject:i];
                }
                f[@"endpoints"] = epItems;
            }
        }
    }
    
    return processList;
}

// Get additional info about process and
// add it to the process info dictionary
+ (void)updateProcessInfo:(NSMutableDictionary *)p {
    
    if (p[@"image"] == nil) {
        pid_t pid = [p[@"pid"] intValue];
        NSRunningApplication *app = [ProcessUtils appForPID:pid];
        
        if (app) {
            p[@"bundle"] = @YES;
            NSString *bundlePath = [[app bundleURL] path];
            if (bundlePath) {
                p[@"path"] = bundlePath;
            }
            p[@"image"] = [WORKSPACE iconForFile:p[@"path"]];
            p[@"app"] = @([ProcessUtils isAppProcess:p[@"path"]]);
            p[@"identifier"] = [ProcessUtils identifierForBundleAtPath:p[@"path"]];
        } else {
            p[@"image"] = [IconUtils imageNamed:@"GenericExecutable"];
            p[@"bundle"] = @NO;
            p[@"app"] = @NO;
            p[@"path"] = [ProcessUtils executablePathForPID:pid];
        }
        
//        if ([p[@"bundle"] boolValue]) {
//            p[@"identifier"] = [ProcessUtils identifierForBundleAtPath:p[@"path"]];
//        }
        p[@"psn"] = [ProcessUtils carbonProcessSerialNumberForPID:pid];
        
        // On macOS, lsof truncates process names that are longer than
        // 32 characters since it uses libproc. We can do better than that.
        if ([DEFAULTS boolForKey:@"friendlyProcessNames"]) {
            p[@"pname"] = [ProcessUtils macProcessNameForPID:pid];
        }
        if (!p[@"pname"]) {
            p[@"pname"] = [ProcessUtils fullKernelProcessNameForPID:pid];
        }
        if (!p[@"pname"]) {
            p[@"pname"] = [ProcessUtils procNameForPID:pid]; // libproc
        }
        if (!p[@"pname"]) {
            p[@"pname"] = p[@"name"];
        }
        
        // Set process icon for all children (i.e. files, sockets, etc.)
        for (NSMutableDictionary *item in p[@"children"]) {
            item[@"pimage"] = p[@"image"];
            item[@"pname"] = p[@"pname"];
        }
    }
    
    // Update display name to show number of open files for process
    p[@"displayname"] = [NSString stringWithFormat:@"%@ (%lu)", p[@"pname"], [p[@"children"] count]];
}

// Unless running with a UTF-8 locale (GUI apps get none by default), lsof
// escapes all non-ASCII bytes as \xNN, e.g. "café" becomes "caf\xc3\xa9".
// It also escapes backslashes and some control characters. Undo this so
// that names and paths are usable. Control characters shown as ^X are left
// as-is since lsof doesn't escape literal carets, making them ambiguous.
+ (NSString *)unescapedString:(NSString *)str {
    if ([str rangeOfString:@"\\"].location == NSNotFound) {
        return str;
    }

    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = [data bytes];
    NSUInteger len = [data length];
    NSMutableData *out = [NSMutableData dataWithCapacity:len];

    for (NSUInteger i = 0; i < len; i++) {
        char c = bytes[i];
        if (c == '\\' && i + 1 < len) {
            char next = bytes[i+1];
            char esc = 0;
            switch (next) {
                case '\\': esc = '\\'; break;
                case 't':  esc = '\t'; break;
                case 'n':  esc = '\n'; break;
                case 'r':  esc = '\r'; break;
                case 'b':  esc = '\b'; break;
                case 'f':  esc = '\f'; break;
                case 'x':
                    if (i + 3 < len && isxdigit(bytes[i+2]) && isxdigit(bytes[i+3])) {
                        char hex[3] = { bytes[i+2], bytes[i+3], 0 };
                        unsigned char b = (unsigned char)strtoul(hex, NULL, 16);
                        [out appendBytes:&b length:1];
                        i += 3;
                        continue;
                    }
                    break;
            }
            if (esc) {
                [out appendBytes:&esc length:1];
                i += 1;
                continue;
            }
        }
        [out appendBytes:&c length:1];
    }

    // Name may not be valid UTF-8, in which case we keep the escaped version
    NSString *unescaped = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    return unescaped ? unescaped : str;
}

- (NSMutableArray *)args {
    NSMutableArray *arguments = [LSOF_ARGS mutableCopy];
    if ([DEFAULTS boolForKey:@"dnsLookup"] == NO) {
        // Add arguments to disable dns and port name lookup
        [arguments addObjectsFromArray:LSOF_NO_DNS_ARGS];
    }
    return arguments;
}

@end

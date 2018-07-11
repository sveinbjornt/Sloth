/*
 Copyright (c) 2003-2017, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "NSWorkspace+Additions.h"

@implementation NSWorkspace (Additions)

#pragma mark - Handler apps for files

- (NSArray *)handlerApplicationsForFile:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    NSMutableArray *appPaths = [[NSMutableArray alloc] initWithCapacity:256];
    
    NSArray *applications = (NSArray *)CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)url, kLSRolesAll));
    if (applications == nil) {
        return @[];
    }
    
    for (int i = 0; i < [applications count]; i++) {
        [appPaths addObject:[applications[i] path]];
    }
    return appPaths;
}

- (NSString *)defaultHandlerApplicationForFile:(NSString *)filePath {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    CFURLRef appURL = LSCopyDefaultApplicationURLForURL((__bridge CFURLRef)fileURL, kLSRolesAll, NULL);
    if (appURL) {
        NSString *appPath = [(__bridge NSURL *)appURL path];
        CFRelease(appURL);
        return appPath;
    }
    
    return nil;
}

- (NSString *)kindStringForFile:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSString *kindStr;
    
    if (![url getResourceValue:&kindStr forKey:NSURLLocalizedTypeDescriptionKey error:nil]) {
        return @"Unknown";
    }
    
    return kindStr;
}

#pragma mark - File/folder size

- (NSString *)fileSizeAsHumanReadableString:(UInt64)size {
    if (size < 1024ULL) {
        return [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
    } else if (size < 1048576ULL) {
        return [NSString stringWithFormat:@"%llu KB", (UInt64)size / 1024];
    } else if (size < 1073741824ULL) {
        return [NSString stringWithFormat:@"%.1f MB", size / 1048576.0];
    }
    return [NSString stringWithFormat:@"%.1f GB", size / 1073741824.0];
}

#pragma mark - Finder

- (BOOL)showFinderGetInfoForFile:(NSString *)path {
    BOOL isDir;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path
                                                       isDirectory:&isDir];
    if (!exists) {
        NSLog(@"Cannot show Get Info. File does not exist: %@", path);
        return NO;
    }
    
    NSString *type = isDir && ![self isFilePackageAtPath:path] ? @"folder" : @"file";
    
    NSString *source = [NSString stringWithFormat:
@"set aFile to (POSIX file \"%@\") as text\n\
tell application \"Finder\"\n\
\tactivate\n\
\topen information window of %@ aFile\n\
end tell", path, type];
    
    return [self runAppleScript:source];
}

- (BOOL)quickLookFile:(NSString *)path {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] == NO) {
        NSBeep();
        return NO;
    }
    
    NSString *source = [NSString stringWithFormat:@"tell application \"Finder\"\n\
                        activate\n\
                        set imageFile to item (POSIX file \"%@\")\n\
                        select imageFile\n\
                        tell application \"System Events\" to keystroke \"y\" using command down\n\
                        end tell", path];
    
    return [self runAppleScript:source];
}

- (BOOL)runAppleScript:(NSString *)scriptSource {
    
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:scriptSource];
    if (appleScript != nil) {
        NSDictionary *errorInfo;
        if ([appleScript executeAndReturnError:&errorInfo] == nil) {
            NSLog(@"%@", [errorInfo description]);
            return NO;
        }
    }
    
    return YES;
}

@end

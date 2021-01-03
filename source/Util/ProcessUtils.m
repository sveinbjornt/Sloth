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

#import "ProcessUtils.h"
#import "STPrivilegedTask.h"

#import <AppKit/AppKit.h>
#import <libproc.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <pwd.h>

@implementation ProcessUtils

+ (NSRunningApplication *)appForPID:(pid_t)pid {
    return [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
}

+ (BOOL)isAppProcess:(NSString *)bundlePath {
    if (!bundlePath) {
        return NO;
    }
    NSString *fileType = [[NSWorkspace sharedWorkspace] typeOfFile:bundlePath error:nil];
    return ([[NSWorkspace sharedWorkspace] type:fileType conformsToType:@"com.apple.application"]);
}

+ (NSString *)identifierForBundleAtPath:(NSString *)path {
    return [[NSBundle bundleWithPath:path] bundleIdentifier];
}

+ (BOOL)isProcessOwnedByCurrentUser:(pid_t)pid {
    return ([ProcessUtils UIDForPID:pid] == getuid());
}

+ (uid_t)UIDForPID:(pid_t)pid {
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

+ (NSString *)ownerUserNameForPID:(pid_t)pid {
    uid_t uid = [ProcessUtils UIDForPID:pid];
    if (uid == -1) {
        return nil;
    }
    register struct passwd *pw = getpwuid(uid);
    if (pw == NULL) {
        return nil;
    }
    return [NSString stringWithCString:pw->pw_name encoding:NSUTF8StringEncoding];
}

+ (NSString *)macProcessNameForPID:(pid_t)pid {
    ProcessSerialNumber psn;
    if (GetProcessForPID(pid, &psn) == noErr) {
        CFStringRef procName = NULL;
        if (CopyProcessName(&psn, &procName) == noErr) {
            NSString *nameStr = CFBridgingRelease(procName);
            return nameStr.length > 0 ? [nameStr copy] : nil;
        }
    }
    return nil;
}

// Some processes on Mac OS X have a Carbon Process Manager
// Serial Number (PSN) in addition to a PID
+ (NSString *)carbonProcessSerialNumberForPID:(pid_t)pid {
    ProcessSerialNumber psn;
    if (GetProcessForPID(pid, &psn) == noErr) {
        return [NSString stringWithFormat:@"%d",
//                (unsigned int)psn.highLongOfPSN,
                (unsigned int)psn.lowLongOfPSN];
    }
    return nil;
}

// This function returns process name truncated to 32 characters
// This is a limitation with libproc on Mac OS X
+ (NSString *)procNameForPID:(pid_t)pid {
    char name[1024];
    if (proc_name(pid, name, sizeof(name)) > 0) {
        NSString *nameStr = @(name);
        return [nameStr length] ? nameStr : nil;
    }
    return nil;
}

// This is the method used by the Mac OS X 'ps' tool
// Adapted from getproclline() in print.c in the 'ps'
// codebase, which is part of Apple's adv_cmds package
// See: https://opensource.apple.com/tarballs/adv_cmds/
// NOTE: This doesn't work for processes not owned by
// the current user. /bin/ps gets around this with suid.

+ (NSString *)fullKernelProcessNameForPID:(pid_t)pid {
    int mib[3], argmax;
    size_t syssize;
    char *procargs, *cp;
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_ARGMAX;
    
    syssize = sizeof(argmax);
    if (sysctl(mib, 2, &argmax, &syssize, NULL, 0) == -1) {
        return nil;
    }
    
    procargs = malloc(argmax);
    if (procargs == NULL) {
        return nil;
    }
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROCARGS;
    mib[2] = pid;
    
    syssize = (size_t)argmax;
    if (sysctl(mib, 3, procargs, &syssize, NULL, 0) == -1) {
        free(procargs);
        return nil;
    }
    
    for (cp = procargs; cp < &procargs[syssize]; cp++) {
        if (*cp == '\0') {
            break;
        }
    }
    
    if (cp == &procargs[syssize]) {
        free(procargs);
        return nil;
    }
    
    for (; cp < &procargs[syssize]; cp++) {
        if (*cp != '\0') {
            break;
        }
    }
    
    if (cp == &procargs[syssize]) {
        free(procargs);
        return nil;
    }
    
    NSString *pname = [@(cp) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    free(procargs);
    return ([pname length] == 0) ? nil : [pname lastPathComponent];
}

+ (NSString *)executablePathForPID:(pid_t)pid {
    NSString *path = nil;
    char *pathbuf = calloc(PROC_PIDPATHINFO_MAXSIZE, 1);
    
    int ret = proc_pidpath(pid, pathbuf, PROC_PIDPATHINFO_MAXSIZE);
    if (ret > 0) {
        path = @(pathbuf);
    }
    
    free(pathbuf);
    return path;
}

+ (BOOL)killProcess:(int)pid asRoot:(BOOL)asRoot {
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

@end

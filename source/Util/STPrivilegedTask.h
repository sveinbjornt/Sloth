/*
    STPrivilegedTask - NSTask-like wrapper around AuthorizationExecuteWithPrivileges
    
    Copyright (C) 2008-2025 Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
   
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

#import <Cocoa/Cocoa.h>

#define STPrivilegedTaskDidTerminateNotification @"STPrivilegedTaskDidTerminateNotification"

// Defines error value for when AuthorizationExecuteWithPrivileges no longer exists
// Rather than defining a new enum, we just create a global constant
extern const OSStatus errAuthorizationFnNoLongerExists;

@interface STPrivilegedTask : NSObject

@property (nonatomic, copy) NSArray<NSString*> *arguments;
@property (nonatomic, copy) NSString *currentDirectoryPath;
@property (nonatomic, copy) NSString *launchPath;

@property (readonly) NSFileHandle *outputFileHandle;
@property (readonly) BOOL isRunning;
@property (readonly) pid_t processIdentifier;
@property (readonly) int terminationStatus;

@property (nonatomic, copy) void (^terminationHandler)(STPrivilegedTask *);

+ (BOOL)authorizationFunctionAvailable;
    
- (instancetype)initWithLaunchPath:(NSString *)path;
- (instancetype)initWithLaunchPath:(NSString *)path
                         arguments:(NSArray<NSString*> *)args;
- (instancetype)initWithLaunchPath:(NSString *)path
                         arguments:(NSArray<NSString*> *)args
                  currentDirectory:(NSString *)cwd;

+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path;
+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path
                                                 arguments:(NSArray<NSString*> *)args;
+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path
                                                 arguments:(NSArray<NSString*> *)args
                                          currentDirectory:(NSString *)cwd;
+ (STPrivilegedTask *)launchedPrivilegedTaskWithLaunchPath:(NSString *)path
                                                 arguments:(NSArray<NSString*> *)args
                                          currentDirectory:(NSString *)cwd
                                             authorization:(AuthorizationRef)authorization;

- (OSStatus)launch;
- (OSStatus)launchWithAuthorization:(AuthorizationRef)authorization;
// - (void)terminate; // doesn't work
- (void)waitUntilExit;

@end


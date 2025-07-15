/*
    Copyright (c) 2004-2025, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

@import AppKit;

NS_ASSUME_NONNULL_BEGIN

@interface ProcessUtils : NSObject

+ (NSRunningApplication * __nullable)appForPID:(pid_t)pid;
+ (BOOL)isAppProcess:(NSString *)bundlePath;
+ (NSString * __nullable)identifierForBundleAtPath:(NSString *)path;
+ (BOOL)isProcessOwnedByCurrentUser:(pid_t)pid;
+ (uid_t)UIDForPID:(pid_t)pid;
+ (NSString *)ownerUserNameForPID:(pid_t)pid;
+ (NSString *)macProcessNameForPID:(pid_t)pid;
+ (NSString *)carbonProcessSerialNumberForPID:(pid_t)pid;
+ (NSString *)procNameForPID:(pid_t)pid;
+ (NSString *)fullKernelProcessNameForPID:(pid_t)pid;
+ (NSString *)executablePathForPID:(pid_t)pid;
+ (BOOL)killProcess:(int)pid
             asRoot:(BOOL)asRoot
       usingSIGKILL:(BOOL)useSigkill;

@end

NS_ASSUME_NONNULL_END

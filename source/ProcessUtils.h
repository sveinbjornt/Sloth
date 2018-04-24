//
//  ProcessUtils.h
//  Sloth
//
//  Created by Sveinbjorn Thordarson on 19/04/2018.
//  Copyright © 2018 Sveinbjorn Thordarson. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ProcessUtils : NSObject

+ (BOOL)isAppProcess:(pid_t)pid;
+ (BOOL)isProcessOwnedByCurrentUser:(pid_t)pid;
+ (uid_t)UIDForPID:(pid_t)pid;
+ (NSString *)ownerUserNameForPID:(pid_t)pid;
+ (NSString *)macProcessNameForPID:(pid_t)pid;
+ (NSString *)carbonProcessSerialNumberForPID:(pid_t)pid;
+ (NSString *)procNameForPID:(pid_t)pid;
+ (NSString *)fullKernelProcessNameForPID:(pid_t)pid;
+ (NSString *)bundlePathForPID:(pid_t)pid;
+ (NSString *)executablePathForPID:(pid_t)pid;

@end

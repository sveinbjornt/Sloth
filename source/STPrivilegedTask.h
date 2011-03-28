/*
 
 STPrivilegedTask - NSTask-like wrapper around AuthorizationExecuteWithPrivileges
 Copyright (C) 2009 Sveinbjorn Thordarson <sveinbjornt@simnet.is>
 
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 
 */


#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Security/Authorization.h>
#import <SecurityFoundation/SFAuthorization.h>
#import <Security/Security.h>

#define STPrivilegedTaskDidTerminateNotification	@"STPrivilegedTaskDidTerminateNotification"


@interface STPrivilegedTask : NSObject 
{
	NSArray			*arguments;
	NSString		*cwd;
	NSString		*launchPath;
	BOOL			isRunning;
	int				pid;
	int				terminationStatus;
	NSFileHandle	*outputFileHandle;
	SFAuthorization *authorization;;
	
	NSTimer			*checkStatusTimer;
}
- (id)initWithLaunchPath: (NSString *)path arguments:  (NSArray *)args;
+ (STPrivilegedTask *)launchedPriviledTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;
- (NSArray *)arguments;
- (NSString *)currentDirectoryPath;
- (BOOL)isRunning;
- (int)launch;
- (NSString *)launchPath;
- (int)processIdentifier;
- (void)setArguments:(NSArray *)arguments;
- (void)setAuthorization: (SFAuthorization *)myAuthorization;
- (void)setCurrentDirectoryPath:(NSString *)path;
- (void)setLaunchPath:(NSString *)path;
- (NSFileHandle *)outputFileHandle;
- (void)terminate;  // doesn't work
- (int)terminationStatus;
- (void)_checkTaskStatus;
- (void)waitUntilExit;














@end

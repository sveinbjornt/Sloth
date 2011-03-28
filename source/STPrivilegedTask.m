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

#import "STPrivilegedTask.h"

@implementation STPrivilegedTask

- (id)init
{
	if ((self = [super init])) 
	{
		launchPath = @"";
		cwd = [[NSString alloc] initWithString: [[NSFileManager defaultManager] currentDirectoryPath]];
		arguments = [[NSArray alloc] init];
		isRunning = NO;
		outputFileHandle = NULL;
		authorization = NULL;
    }
    return self;
}

-(void)dealloc
{	
	if (arguments != NULL)
		[arguments release];

	if (cwd != NULL)
		[cwd release];
	
	if (outputFileHandle != NULL)
		[outputFileHandle release];
	
	[super dealloc];
}

+ (STPrivilegedTask *)launchedPriviledTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)args
{
	STPrivilegedTask *task = [[[STPrivilegedTask alloc] initWithLaunchPath: path arguments: args] autorelease];
	[task launch];
	[task waitUntilExit];
	return task;
}

-(id)initWithLaunchPath: (NSString *)path arguments:  (NSArray *)args
{
	self = [self init];
	if (self)
	{
		BOOL isDir = FALSE;
		
		if (![[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir] || isDir)
			return NULL;
		else
			[self setLaunchPath: path];
		if (args != NULL)
			[self setArguments: args];
	}
	return self;
}

- (NSArray *)arguments
{
		return arguments;
}

- (NSString *)currentDirectoryPath;
{
		return cwd;
}

- (BOOL)isRunning
{
		return isRunning;
}

// return 0 for success
- (int) launch
{
	OSStatus				err = noErr;
    short					i;
	AuthorizationRef		authorizationRef;
	unsigned int			argumentsCount = [arguments count];
	char					*args[argumentsCount + 1];
	FILE					*outputFile;
	
	isRunning = YES;
	
	// construct an array of c strings from NSArray w. arguments
	for (i = 0; i < argumentsCount; i++) 
	{
		NSString *theString = [arguments objectAtIndex:i];
		unsigned int stringLength = [theString length];
		
		args[i] = malloc((stringLength + 1) * sizeof(char));
		snprintf(args[i], stringLength + 1, "%s", [theString fileSystemRepresentation]);
	}
	args[argumentsCount] = NULL;
	
	// Use Apple's Authentication Manager APIs to get an Authorization Reference
	// These Apple APIs are quite possibly the most horrible of the Mac OS X APIs
	
	if (authorization == NULL)
	{
		err = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorizationRef);
		if (err != errAuthorizationSuccess)
			return err;
	}
	else
		authorizationRef = [authorization authorizationRef];
	
	// change to the current dir specified
	char *prevCwd = (char *)getcwd(nil, 0);
	chdir([cwd fileSystemRepresentation]);
		
	//use Authorization Reference to execute script with privileges
    err = AuthorizationExecuteWithPrivileges(authorizationRef, [launchPath fileSystemRepresentation], kAuthorizationFlagDefaults, args, &outputFile);
	
	// change back to old dir
	chdir(prevCwd);
	
	if (err == errAuthorizationSuccess) // authorization was successful
	{
		// dispose of the argument strings
		for (i = 0; i < argumentsCount; i++)
			free(args[i]);
		
		// get file handle for the command output
		outputFileHandle = [[NSFileHandle alloc] initWithFileDescriptor: fileno(outputFile) closeOnDealloc: YES];
		pid = fcntl(fileno(outputFile), F_GETOWN, 0);
		
		// start monitoring task
		checkStatusTimer = [NSTimer scheduledTimerWithTimeInterval: 0.20 target: self selector:@selector(_checkTaskStatus) userInfo: nil repeats: YES];
		
		// destroy the auth ref
		if (authorization == NULL)
			AuthorizationFree(authorizationRef, kAuthorizationFlagDefaults);
	}
	else
		isRunning = NO;
	
	return err;
}

- (NSString *)launchPath
{
	return launchPath;
}

- (int)processIdentifier
{
	return pid;
}

- (void)setArguments:(NSArray *)args
{
		if (arguments != NULL)
			[arguments release];
		arguments = [[NSArray alloc] initWithArray: args];
}

- (void)setAuthorization: (SFAuthorization *)myAuthorization;
{
	authorization = myAuthorization;
}

- (void)setCurrentDirectoryPath:(NSString *)path
{
		cwd = [[NSString alloc] initWithString: path];
}

- (void)setLaunchPath:(NSString *)path
{
		launchPath = path;
}

- (NSFileHandle *)outputFileHandle;
{
		return outputFileHandle;
}

- (void)terminate
{
	// This doesn't work without a PID, and we can't get one.  Stupid Security API
}

- (int)terminationStatus
{
	// this, however, actually works
	return terminationStatus;
}

// check if privileged task is still running
- (void)_checkTaskStatus
{	
	// see if task has terminated
    int mypid = waitpid([self processIdentifier], &terminationStatus, WNOHANG);
    if (mypid != 0)
	{
		isRunning = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName: STPrivilegedTaskDidTerminateNotification object:self];
		[checkStatusTimer invalidate];
	}
}

// hang until task is done
- (void)waitUntilExit
{
	int mypid;
	mypid = waitpid([self processIdentifier], &terminationStatus, 0);
	isRunning = NO;
}
@end
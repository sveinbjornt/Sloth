/*
    Copyright (c) 2004-2023, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "FSUtils.h"
#import "Common.h"

#import <sys/param.h>
#import <sys/mount.h>

#define MAX_FILESYSTEMS 1024

@implementation FSUtils

+ (NSDictionary *)mountedFileSystems {
    struct statfs buf[MAX_FILESYSTEMS];
    
    int fs_count = getfsstat(NULL, 0, MNT_NOWAIT);
    if (fs_count == -1) {
        fprintf(stderr, "Error: %d\n", errno);
        return nil;
    }

    getfsstat(buf, fs_count * sizeof(statfs), MNT_NOWAIT);
    
    NSMutableDictionary *fsdict = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < fs_count; ++i) {
        dev_t fsid = buf[i].f_fsid.val[0];
        
        fsdict[@(fsid)] = @{
            @"devid": @(fsid),
            @"devid_major": @(major(fsid)),
            @"devid_minor": @(minor(fsid)),
            @"fstype": @(buf[i].f_fstypename),
            @"devname": @(buf[i].f_mntfromname),
            @"mountpoint": @(buf[i].f_mntonname)
        };
    }
    
    DLog(@"File system info: %@", fsdict);
    
    return [fsdict copy]; // Return immutable copy
}

@end

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

#define PROGRAM_NAME                @"Sloth"
#define PROGRAM_VERSION             @"3.1"
#define PROGRAM_WEBSITE             @"https://sveinbjorn.org/sloth"
#define PROGRAM_GITHUB_WEBSITE      @"https://github.com/sveinbjornt/Sloth"
#define PROGRAM_DONATIONS           @"https://sveinbjorn.org/donations"

#define LSOF_PATH                   @"/usr/sbin/lsof"
#define LSOF_ARGS                   @[@"-F", @"fpPcntuaTdDiR", @"+c0"]
#define LSOF_NO_DNS_ARGS            @[@"-n", @"-P"]

#define DYNAMIC_UTI_PREFIX          @"dyn."

#define VALUES_KEYPATH(X)           [NSString stringWithFormat:@"values.%@", (X)]

// Let's make things a bit less verbose
#define FILEMGR                     [NSFileManager defaultManager]
#define DEFAULTS                    [NSUserDefaults standardUserDefaults]
#define WORKSPACE                   [NSWorkspace sharedWorkspace]

// Logging in debug mode only
#ifdef DEBUG
    #define DLog(...) NSLog(__VA_ARGS__)
#else
    #define DLog(...)
#endif

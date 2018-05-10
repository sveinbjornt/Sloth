/*
    Copyright (c) 2004-2018, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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
#define PROGRAM_VERSION             @"2.4"
#define PROGRAM_WEBSITE             @"https://sveinbjorn.org/sloth"
#define PROGRAM_GITHUB_WEBSITE      @"https://github.com/sveinbjornt/Sloth"
#define PROGRAM_DONATIONS           @"https://sveinbjorn.org/donations"

#define PROGRAM_LSOF_SYSTEM_PATH    @"/usr/sbin/lsof"
#define PROGRAM_LSOF_ARGS           @[@"-F", @"fpPcntuaT", @"+c0"]
#define PROGRAM_LSOF_NO_DNS_ARGS    @[@"-n", @"-P"]

#define GENERIC_EXEC_ICON_PATH \
@"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns"
#define GENERIC_DOCUMENT_ICON_PATH \
@"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns"
#define GENERIC_FOLDER_ICON_PATH \
@"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns"
#define GENERIC_NETWORK_ICON_PATH \
@"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericNetworkIcon.icns"

#define VALUES_KEYPATH(X)           [NSString stringWithFormat:@"values.%@", (X)]

// Let's make things a bit less verbose
#define FILEMGR     [NSFileManager defaultManager]
#define DEFAULTS    [NSUserDefaults standardUserDefaults]
#define WORKSPACE   [NSWorkspace sharedWorkspace]

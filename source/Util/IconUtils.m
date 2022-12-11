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

#import "Common.h"
#import "IconUtils.h"

#define CORE_TYPES_RESOURCE(X) \
[NSString stringWithFormat:@"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/%@",(X)]

#define EXEC_ICON_PATH          CORE_TYPES_RESOURCE(@"ExecutableBinaryIcon.icns")
#define NETWORK_ICON_PATH       CORE_TYPES_RESOURCE(@"SidebarNetwork.icns")
#define FILE_ICON_PATH          CORE_TYPES_RESOURCE(@"SidebarGenericFile.icns")
#define FOLDER_ICON_PATH        CORE_TYPES_RESOURCE(@"SidebarGenericFolder.icns")
#define APPL_ICON_PATH          CORE_TYPES_RESOURCE(@"SidebarApplicationsFolder.icns")
#define HOME_ICON_PATH          CORE_TYPES_RESOURCE(@"SidebarHomeFolder.icns")
#define ERR_ICON_PATH           CORE_TYPES_RESOURCE(@"AlertStopIcon.icns")
#define QUESTIONMARK_ICON_PATH  CORE_TYPES_RESOURCE(@"GenericQuestionMarkIcon.icns")

static NSMutableDictionary *iconStore;

@implementation IconUtils

+ (NSMutableDictionary *)_loadIcons {
    // We want to use the cool invertible Mojave template icons to represent
    // files, directories, IP sockets, etc. but they might not available. We
    // therefore define primary icon assets and fallbacks in case they're
    // not available on the version of macOS we're running on. This way we
    // get the best of both worlds: The old icons when running on an older
    // version of macOS, the new ones on Mojave onwards. Saves us from having
    // to bloat the application bundle with custom icon assets.
    NSMutableDictionary *icons = [NSMutableDictionary dictionary];

    NSDictionary *iconSettings = @{
        @"File": @[
            @{ @"path": FILE_ICON_PATH, @"template": @YES },
            @{ @"name": @"NSGenericDocument", @"template": @NO }
        ],
        @"Directory": @[
            @{ @"path": FOLDER_ICON_PATH, @"template": @YES },
            @{ @"name": NSImageNameFolder, @"template": @NO }
        ],
        @"SmallDirectory": @[
            @{ @"path": FOLDER_ICON_PATH, @"template": @YES },
            @{ @"name": NSImageNameFolder, @"template": @NO }
        ],
        @"Character Device": @[
            @{ @"name": @"Cog", @"template": @YES },
            @{ @"name": NSImageNameActionTemplate, @"template": @YES },
            @{ @"name": NSImageNameSmartBadgeTemplate, @"template": @YES }
        ],
        @"Pipe": @[
            @{ @"name": @"Pipe", @"template": @YES }
        ],
        @"Unix Domain Socket": @[
            @{ @"name": @"Socket", @"template": @YES }
        ],
        @"IP Socket": @[
            @{ @"path": NETWORK_ICON_PATH, @"template": @YES },
            @{ @"name": NSImageNameNetwork, @"template": @NO }
        ],
        @"Error": @[
            @{ @"path": ERR_ICON_PATH, @"template": @NO },
            @{ @"name": NSImageNameCaution, @"template": @NO }
        ],
        @"Prefs": @[
            @{ @"name": NSImageNamePreferencesGeneral, @"template": @NO }
        ],
        @"Applications": @[
            @{ @"path": APPL_ICON_PATH, @"template": @YES },
            @{ @"name": @"NSDefaultApplicationIcon", @"template": @NO }
        ],
        @"Home": @[
            @{ @"path": HOME_ICON_PATH, @"template": @YES },
            @{ @"type": NSFileTypeForHFSTypeCode(kToolbarHomeIcon), @"template": @NO }
        ],
//        @"GenericApplication": @[
//            @{ @"name": @"NSDefaultApplicationIcon", @"template": @NO }
//        ],
        @"GenericExecutable": @[
            @{ @"path": EXEC_ICON_PATH, @"template": @NO },
        ],
        @"Locked": @[
            @{ @"type": NSFileTypeForHFSTypeCode(kLockedIcon), @"template": @NO }
        ],
        @"Unlocked": @[
            @{ @"type": NSFileTypeForHFSTypeCode(kUnlockedIcon), @"template": @NO }
        ],
        @"QuestionMark": @[
            @{ @"name": @"QuestionMark", @"template": @YES },
            @{ @"path": QUESTIONMARK_ICON_PATH, @"template": @NO }
        ],
        @"Dollar": @[
            @{ @"name": @"Dollar", @"template": @YES }
        ],
        @"GitHub": @[
            @{ @"name": @"GitHub", @"template": @YES }
        ],
    };
    
    for (NSString *name in iconSettings) {
        NSArray *opts = iconSettings[name];
        NSImage *img;
        
        for (NSDictionary *o in opts) {
            if (o[@"path"] && [FILEMGR fileExistsAtPath:o[@"path"]]) {
                img = [[NSImage alloc] initWithContentsOfFile:o[@"path"]];
            }
            else if (o[@"name"] && [NSImage imageNamed:o[@"name"]]) {
                img = [NSImage imageNamed:o[@"name"]];
            }
            else if (o[@"type"]) {
                img = [WORKSPACE iconForFileType:o[@"type"]];
            }
            
            if (img) {
                [img setSize:NSMakeSize(16, 16)];
                [img setTemplate:[o[@"template"] boolValue]];
                break;
            }
        }
        
        if (img) {
            icons[name] = img;
        } else {
            DLog(@"Unable to load icon '%@'", name);
        }
    }
    
    return icons;
}

+ (NSImage *)imageNamed:(NSString *)name {
    // Lazy-load
    if (iconStore == nil) {
        iconStore = [self _loadIcons];
    }
    NSImage *img = [iconStore objectForKey:name];
    if (img == nil) {
        DLog(@"Icon '%@' not found", name);
    }
    return img;
}

@end

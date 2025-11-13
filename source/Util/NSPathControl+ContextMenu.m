/*
    Copyright (c) 2018-2025, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "NSPathControl+ContextMenu.h"
#import "NSWorkspace+Additions.h"
#import <objc/runtime.h>

static const char * kFilePathAssociatedObjectKey = "filePath";

@implementation NSPathControl (ContextMenu)

// Generate contextual menu for a Ctrl-clicked item in the Path Control
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect frame = [self bounds];
    NSPathCell *cell = (NSPathCell *)[self cell];
    
    // Find the path component cell at the clicked point
    NSPathComponentCell *componentCell = [cell pathComponentCellAtPoint:point withFrame:frame inView:self];
    if (componentCell == nil) {
        return nil;
    }
    
    NSString *path = [[componentCell URL] path];
    if (path == nil) {
        return nil;
    }
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    
    // Open (with default app)
    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open" action:@selector(openPath:) keyEquivalent:@""];
    [openItem setTarget:self];
    [openItem setRepresentedObject:path];
    
    NSString *defaultApp = [[NSWorkspace sharedWorkspace] defaultHandlerApplicationForFile:path];
    if (defaultApp) {
        NSString *appName = [[defaultApp lastPathComponent] stringByDeletingPathExtension];
        [openItem setTitle:[NSString stringWithFormat:@"Open with %@", appName]];
        NSImage *img = [[NSWorkspace sharedWorkspace] iconForFile:defaultApp];
        [img setSize:NSMakeSize(16, 16)];
        [openItem setImage:img];
    }
    [menu addItem:openItem];
    
    // Open With submenu
    NSMenuItem *openWithItem = [[NSMenuItem alloc] initWithTitle:@"Open With" action:nil keyEquivalent:@""];
    NSMenu *openWithMenu = [[NSMenu alloc] init];
    objc_setAssociatedObject(openWithMenu, kFilePathAssociatedObjectKey, path, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [openWithItem setSubmenu:openWithMenu];
    [[NSWorkspace sharedWorkspace] openWithMenuForFile:path
                                                target:self
                                                action:@selector(openPathWithApplication:)
                                                  menu:openWithMenu];
    [menu addItem:openWithItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Show in Finder
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show in Finder" action:@selector(showPathInFinder:) keyEquivalent:@""];
    [showItem setTarget:self];
    [showItem setRepresentedObject:path];
    [menu addItem:showItem];
    
    // Get Info in Finder
    NSMenuItem *getInfoItem = [[NSMenuItem alloc] initWithTitle:@"Show Info in Finder" action:@selector(showPathInfoInFinder:) keyEquivalent:@""];
    [getInfoItem setTarget:self];
    [getInfoItem setRepresentedObject:path];
    [menu addItem:getInfoItem];
    
    // Separator
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Copy Path
    NSMenuItem *copyPathItem = [[NSMenuItem alloc] initWithTitle:@"Copy Path" action:@selector(copyPath:) keyEquivalent:@""];
    [copyPathItem setTarget:self];
    [copyPathItem setRepresentedObject:path];
    [menu addItem:copyPathItem];
    
    return menu;
}

#pragma mark - Actions

- (void)openPath:(id)sender {
    NSString *path = [sender representedObject];
    [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void)openPathWithApplication:(id)sender {
    NSString *appPath = [sender toolTip];
    NSString *filePath = objc_getAssociatedObject([sender menu], kFilePathAssociatedObjectKey);
    [[NSWorkspace sharedWorkspace] openFile:filePath withApplication:appPath];
}

- (void)showPathInFinder:(id)sender {
    NSString *path = [sender representedObject];
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (void)showPathInfoInFinder:(id)sender {
    NSString *path = [sender representedObject];
    [[NSWorkspace sharedWorkspace] showFinderGetInfoForFile:path];
}

- (void)copyPath:(id)sender {
    NSString *path = [sender representedObject];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[path]];
}

@end

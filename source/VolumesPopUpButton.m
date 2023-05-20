/*
    Copyright (c) 2018-2020, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "VolumesPopUpButton.h"
#import "FSUtils.h"

@implementation VolumesPopUpButton

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    [[self menu] setDelegate:self];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(volumesChanged:)
                                                               name:NSWorkspaceDidMountNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(volumesChanged:)
                                                               name:NSWorkspaceDidUnmountNotification
                                                             object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(volumesChanged:)
                                                               name:NSWorkspaceDidRenameVolumeNotification
                                                             object:nil];
    
    [self populateMenu];
}

- (void)menuWillOpen:(NSMenu *)menu {
    for (NSMenuItem *item in [menu itemArray]) {
        NSString *volPath = [item toolTip];
        if (volPath && ![volPath isEqualToString:@""]) {
            NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:[item toolTip]];
            [icon setSize:NSMakeSize(16, 16)];
            [item setImage:icon];
        }
    }
}

- (void)menuDidClose:(NSMenu *)menu {
    for (NSMenuItem *item in [menu itemArray]) {
        [item setImage:nil];
    }
}

- (void)volumesChanged:(NSNotification *)notification {
    [self populateMenu];
}

- (void)notifyDelegateSelectionHasChanged:(id)sender {
    [[self delegate] volumeSelectionChanged:[[self selectedItem] toolTip]];
}

- (void)populateMenu {
    NSMenu *volumesMenu = [self menu];
    
    // Get currently selected volume
    NSMenuItem *selectedItem = [self selectedItem];
    NSString *selectedPath = [selectedItem toolTip];
    
    // Get info about mounted file systems
    NSDictionary *filesystems = [FSUtils mountedFileSystems];
    
    // Clear menu
    [volumesMenu removeAllItems];
    
    // All + separator
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"All"
                                                  action:@selector(notifyDelegateSelectionHasChanged:)
                                           keyEquivalent:@""];
    [item setTarget:self];
    [item setToolTip:@""];
    [volumesMenu addItem:item];
    [volumesMenu addItem:[NSMenuItem separatorItem]];
    
    // NEW METHOD: Add all filesystems (except /dev)
    for (NSNumber *fsid in [filesystems allKeys]) {
        NSDictionary *fs = filesystems[fsid];
        if ([fs[@"mountpoint"] isEqualToString:@"/dev"]) {
            continue;
        }
        NSString *menuItemName = fs[@"mountpoint"];
        
        // Get volume name, if possible
        NSURL *url = [NSURL fileURLWithPath:fs[@"mountpoint"]];
        NSString *volumeName;
        NSError *err;
        [url getResourceValue:&volumeName forKey:NSURLVolumeNameKey error:&err];
        if (volumeName != nil) {
            menuItemName = [NSString stringWithFormat:@"%@ - %@", volumeName, fs[@"mountpoint"]];
        }
        
        SEL action = @selector(notifyDelegateSelectionHasChanged:);
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:menuItemName
                                                      action:action
                                               keyEquivalent:@""];
        [item setTarget:self];
        [item setToolTip:fs[@"mountpoint"]];
        [item setRepresentedObject:fs];
        [volumesMenu addItem:item];
        
    }
    
    // Restore selection, if possible
    NSMenuItem *itemToSelect = [volumesMenu itemArray][0];
    for (NSMenuItem *item in [volumesMenu itemArray]) {
        if ([[item toolTip] isEqualToString:selectedPath]) {
            itemToSelect = item;
            break;
        }
    }
    [self selectItem:itemToSelect];
    
    if (selectedItem != itemToSelect) {
        [self notifyDelegateSelectionHasChanged:itemToSelect];
    }
}

@end

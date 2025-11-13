#import "NSPathControl+ContextMenu.h"
#import "NSWorkspace+Additions.h"
#import "IconUtils.h"

@implementation NSPathControl (ContextMenu)

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
    
    // Open
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
    
    // Open With
    NSMenuItem *openWithItem = [[NSMenuItem alloc] initWithTitle:@"Open With" action:nil keyEquivalent:@""];
    NSMenu *openWithMenu = [[NSMenu alloc] init];
    [openWithItem setSubmenu:openWithMenu];
    [[NSWorkspace sharedWorkspace] openWithMenuForFile:path target:self action:@selector(openPathWithApplication:) menu:openWithMenu];
    [menu addItem:openWithItem];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    // Show in Finder
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show in Finder" action:@selector(showPathInFinder:) keyEquivalent:@""];
    [showItem setTarget:self];
    [showItem setRepresentedObject:path];
    [menu addItem:showItem];
    
    // Get Info
    NSMenuItem *getInfoItem = [[NSMenuItem alloc] initWithTitle:@"Get Info" action:@selector(showPathInfoInFinder:) keyEquivalent:@""];
    [getInfoItem setTarget:self];
    [getInfoItem setRepresentedObject:path];
    [menu addItem:getInfoItem];
    
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
    NSString *appPath = [sender representedObject];
    NSString *filePath = [[[sender menu] supermenu] representedObject];
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

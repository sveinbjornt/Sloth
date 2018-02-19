//
//  SlothImageView.m
//  Sloth
//
//  Created by Sveinbjorn Thordarson on 12/02/2018.
//  Copyright © 2018 Sveinbjorn Thordarson. All rights reserved.
//

#import "SlothImageView.h"

@implementation SlothImageView

- (void)mouseDown:(NSEvent *)theEvent {
    // see http://www.cocoabuilder.com/archive/cocoa/115981-nsimageview-subclass-and-mouseup.html
    if (theEvent.type != NSLeftMouseDown) {
        [super mouseDown:theEvent];
    }
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.type == NSLeftMouseUp) {
        NSPoint pt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        if (NSPointInRect(pt, self.bounds)) {
            [NSApp sendAction:[self action] to:[self target] from:self];
        }
    } else {
        [super mouseUp:theEvent];
    }
}

@end

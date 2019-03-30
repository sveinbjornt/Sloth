//
//  TimeAgoTextField.h
//  Sloth
//
//  Created by Sveinbjorn Thordarson on 30/03/2019.
//  Copyright © 2019 Sveinbjorn Thordarson. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TimeAgoTextField : NSTextField

- (void)setDate:(NSDate *)date;
- (void)clear;
@end

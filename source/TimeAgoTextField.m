//
//  TimeAgoTextField.m
//  Sloth
//
//  Created by Sveinbjorn Thordarson on 30/03/2019.
//  Copyright © 2019 Sveinbjorn Thordarson. All rights reserved.
//

#import "TimeAgoTextField.h"

#define kDefaultUpdateInterval 1.0f

@interface TimeAgoTextField()
{
    NSDate *startDate;
    NSTimer *timer;
    NSTimeInterval interval;
}
@end

@implementation TimeAgoTextField

- (void)setDate:(NSDate *)date {
    interval = kDefaultUpdateInterval;
    startDate = date;
    timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(_update) userInfo:timer repeats:NO];
}

- (void)clear {
    interval = kDefaultUpdateInterval;
    startDate = nil;
    if (timer) {
        [timer invalidate];
        timer = nil;
    }
    [self setStringValue:@""];
}

- (void)_update {
    NSString *agoStr = [self timeAgoStringFromDate:startDate];
    [self setStringValue:agoStr];
    
    if ([[NSDate date] timeIntervalSinceDate:startDate] >= 60.0f) {
        interval = 60.0f;
    }
    timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(_update) userInfo:timer repeats:NO];
}

- (NSString *)timeAgoStringFromDate:(NSDate *)d {
    NSDateComponentsFormatter *formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
    
    NSDate *now = [NSDate date];
    
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitWeekOfMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond)
                                               fromDate:d
                                                 toDate:now
                                                options:0];
    
    if (components.year > 0) {
        formatter.allowedUnits = NSCalendarUnitYear;
    } else if (components.month > 0) {
        formatter.allowedUnits = NSCalendarUnitMonth;
    } else if (components.weekOfMonth > 0) {
        formatter.allowedUnits = NSCalendarUnitWeekOfMonth;
    } else if (components.day > 0) {
        formatter.allowedUnits = NSCalendarUnitDay;
    } else if (components.hour > 0) {
        formatter.allowedUnits = NSCalendarUnitHour;
    } else if (components.minute > 0) {
        formatter.allowedUnits = NSCalendarUnitMinute;
    } else {
        formatter.allowedUnits = NSCalendarUnitSecond;
    }
    
    NSString *formatString = @"Scanned %@ ago";
    
    return [NSString stringWithFormat:formatString, [formatter stringFromDateComponents:components]];
}

@end

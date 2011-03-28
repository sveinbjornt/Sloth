/*
    Sloth - Mac OS X Graphical User Interface front-end for lsof
    Copyright (C) 2004-2010 Sveinbjorn Thordarson <sveinbjornt@simnet.is>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

*/

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface STUtil : NSObject 
{

}
+ (void)alert: (NSString *)message subText: (NSString *)subtext;
+ (void)fatalAlert: (NSString *)message subText: (NSString *)subtext;
+ (BOOL) proceedWarning: (NSString *)message subText: (NSString *)subtext actionText: (NSString *)actionText;
@end

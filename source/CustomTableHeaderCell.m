/*
 Copyright (c) 2004-2016, Sveinbjorn Thordarson <sveinbjornt@gmail.com>
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

#import "CustomTableHeaderCell.h"

@implementation CustomTableHeaderCell

//- (void)awakeFromNib {
//    NSButton *discloseTriangle = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
//    [discloseTriangle setBezelStyle:NSDisclosureBezelStyle];
//    [discloseTriangle setButtonType:NSPushOnPushOffButton];
//    [discloseTriangle setTitle:nil];
//    [discloseTriangle highlight:NO];
////    [self addSubview]
//}



//- (void)drawWithFrame:(CGRect)cellFrame
//          highlighted:(BOOL)isHighlighted
//               inView:(NSView *)view
//{
//    CGRect fillRect, borderRect;
//    CGRectDivide(cellFrame, &borderRect, &fillRect, 1.0, CGRectMaxYEdge);
//    
//    NSGradient *gradient = [[NSGradient alloc]
//                            initWithStartingColor:[NSColor whiteColor]
//                            endingColor:[NSColor colorWithDeviceWhite:0.9 alpha:1.0]];
//    [gradient drawInRect:fillRect angle:90.0];
//    
//    if (isHighlighted) {
//        [[NSColor colorWithDeviceWhite:0.0 alpha:0.1] set];
//        NSRectFillUsingOperation(fillRect, NSCompositeSourceOver);
//    }
//    
//    [[NSColor colorWithDeviceWhite:0.8 alpha:1.0] set];
//    NSRectFill(borderRect);
//    
//    [self drawInteriorWithFrame:CGRectInset(fillRect, 0.0, 1.0) inView:view];
//}
//
//- (void)drawWithFrame:(CGRect)cellFrame inView:(NSView *)view
//{
//    [self drawWithFrame:cellFrame highlighted:NO inView:view];
//}
//
//- (void)highlight:(BOOL)isHighlighted
//        withFrame:(NSRect)cellFrame
//           inView:(NSView *)view
//{
//    [self drawWithFrame:cellFrame highlighted:isHighlighted inView:view];
//}

@end

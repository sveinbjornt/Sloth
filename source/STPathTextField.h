/*
    STPathTextField.h

    Created by Sveinbjorn Thordarson on 6/27/08.
    Copyright (C) 2009 Sveinbjorn Thordarson. All rights reserved.
	
	
	See STPathTextField.m for description of the functionality of
	this subclass of NSTextField.

	************************ LICENSE ***************************

	Permission is hereby granted, free of charge, to any person
	obtaining a copy of this software and associated documentation
	files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use,
	copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following
	conditions:

	The above copyright notice and this permission notice shall be
	included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
	OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
	HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	OTHER DEALINGS IN THE SOFTWARE.
	
	**************************************************************
*/


#import <Cocoa/Cocoa.h>

enum 
{
	STNoAutocomplete = 0,
	STShellAutocomplete = 1,
	STBrowserAutocomplete = 2
};

@interface STPathTextField : NSTextField 
{
	BOOL		autocompleteStyle;
	BOOL		colorInvalidPath;
	BOOL		foldersAreValid;
	BOOL		expandTildeInPath;
}
-(void)updateTextColoring;
-(int)autoComplete: (id)sender;
-(BOOL)hasValidPath;

-(void)setAutocompleteStyle: (int)style;
-(int)autocompleteStyle;

-(void)setColorInvalidPath: (BOOL)val;
-(BOOL)colorInvalidPath;

-(void)setFoldersAreValid: (BOOL)val;
-(BOOL)foldersAreValid;

-(void)setExpandTildeInPath: (BOOL)val;
-(BOOL)expandTildeInPath;
@end

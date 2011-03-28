/*
    Sloth - Mac OS X Graphical User Interface front-end for lsof
    Copyright (C) 2004-2006 Sveinbjorn Thordarson <sveinbjornt@simnet.is>
	Parts are Copyright (C) 2004-2006 Bill Bumgarner

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

#import "FilteringArrayController.h"



@implementation FilteringArrayController
- (void)dealloc
{
	if (searchString != NULL)
		[searchString release]; 
	searchString = NULL;
    [super dealloc];
}

- (NSArray *)arrangeObjects:(NSArray *)objects
{
    if ((searchString == NULL) || ([searchString isEqualToString:@""]))
		return [super arrangeObjects:objects];   
	
    NSMutableArray *matchedObjects = [NSMutableArray arrayWithCapacity:[objects count]];
    NSString *lowerSearch = [searchString lowercaseString];
    
	NSEnumerator *oEnum = [objects objectEnumerator];
    id item;	
    while (item = [oEnum nextObject]) 
	{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
        NSString *lowerName = [[item valueForKeyPath:@"name"] lowercaseString];
        if ([lowerName rangeOfString:lowerSearch].location != NSNotFound)
		{
				[matchedObjects addObject:item];
				continue;
		}
		
		lowerName = [[item valueForKeyPath:@"pid"] lowercaseString];
        if ([lowerName rangeOfString:lowerSearch].location != NSNotFound)
		{
				[matchedObjects addObject:item];
				continue;
		}
		
		lowerName = [[item valueForKeyPath:@"path"] lowercaseString];
        if ([lowerName rangeOfString:lowerSearch].location != NSNotFound)
		{
				[matchedObjects addObject:item];
				continue;
		}
		
		lowerName = [[item valueForKeyPath:@"type"] lowercaseString];
        if ([lowerName rangeOfString:lowerSearch].location != NSNotFound)
		{
				[matchedObjects addObject:item];
				continue;
		}
				
        [pool release];
    }
    return [super arrangeObjects:matchedObjects];
}

/*- (NSArray *)sortDescriptors
{
NSSortDescriptor *pidDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"pid" 
                                                    ascending:YES] autorelease];
	NSSortDescriptor *nameDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"name" 
                                                    ascending:NO] autorelease];
	NSSortDescriptor *typeDescriptor=[[[NSSortDescriptor alloc] initWithKey:@"type" 
                                                    ascending:NO] autorelease];
	return([NSArray arrayWithObjects:nameDescriptor,pidDescriptor, typeDescriptor,NULL]);

}*/

- (void) performSearch: sender;
{
    [self setValue: [sender stringValue] forKey: @"searchString"];
    [self rearrangeObjects];
}
@end

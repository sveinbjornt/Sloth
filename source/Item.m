/*
    Copyright (c) 2004-2023, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "Item.h"
#import "ProcessUtils.h"

@interface Item ()
{
    NSDictionary *lazyAttrs;
}
@end

@implementation Item

- (instancetype)init {
    self = [super init];
    if (self) {
        // Getting som item properties is expensive and therefore lazy-loaded
        lazyAttrs = @{
            //@"identifier": [NSValue valueWithPointer:@selector(bundleIdentifier)]
        };
    }
    return self;
}

- (id)objectForKey:(id)aKey {
    // See if dict has an entry for this key
    id obj = [properties objectForKey:aKey];
    if (!obj) {
        // If not, check if it's a lazy-load property
        id val = [lazyAttrs objectForKey:aKey];
        // If it is, generate the value using the appropriate selector
        if (val) {
            SEL sel = [val pointerValue];
            if (sel && [self respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                properties[aKey] = [self performSelector:sel];
#pragma clang diagnostic pop
                return properties[aKey];
            }
        }
    }
    return obj;
}

- (NSString *)bundleIdentifier {
    return [ProcessUtils identifierForBundleAtPath:self[@"path"]];
}

@end

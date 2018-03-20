/*
 Copyright (c) 2004-2018, Sveinbjorn Thordarson <sveinbjornt@gmail.com>
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

#import "IPServices.h"
#import "NSString+RegexMatching.h"

#import <sys/types.h>
#import <sys/socket.h>
#import <netdb.h>

@implementation IPServices

+ (BOOL)isIPAddressString:(NSString *)ipString {
    NSRegularExpression *regex =
    [NSRegularExpression regularExpressionWithPattern:
     @"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
                                              options:NSRegularExpressionCaseInsensitive
                                                error:nil];
    return [ipString isMatchedByRegex:regex];
}

+ (BOOL)isPortNumberString:(NSString *)portNumString {
    // Starts with, contains only, and ends with numbers
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:@"^\\d+$"
                                                                        options:0
                                                                          error:nil];
    BOOL match = [portNumString isMatchedByRegex:rx];
    int portNum = [portNumString intValue];
    BOOL validRange = portNum >= 0 && portNum < 65535;
    return match && validRange;
}

+ (NSString *)dnsNameForIPAddressString:(NSString *)ipAddrStr {
    if ([IPServices isIPAddressString:ipAddrStr] == NO) {
        return nil;
    }
    // Do DNS lookup for IP address
    return [[NSHost hostWithAddress:ipAddrStr] name];
}

// Look up port name, e.g. "http" for "80"
+ (NSString *)portNameForPortNumString:(NSString *)portNumStr {
    if ([IPServices isPortNumberString:portNumStr] == NO) {
        return nil;
    }
    // Do port name lookup
    int port = [portNumStr intValue];
    struct servent *serv;
    serv = getservbyport(htons(port), NULL);

    // Just return original port num string if port name couldn't be resolved
    if (!serv) {
        return portNumStr;
    }
    
    return [NSString stringWithCString:serv->s_name encoding:NSASCIIStringEncoding];
}

@end

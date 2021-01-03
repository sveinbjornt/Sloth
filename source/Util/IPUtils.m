/*
    Copyright (c) 2004-2021, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
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

#import "IPUtils.h"
#import "NSString+RegexConvenience.h"

#import <sys/types.h>
#import <sys/socket.h>
#import <netdb.h>

@implementation IPUtils

+ (BOOL)isIPv4AddressString:(NSString *)ipString {
    NSRegularExpression *regex =
    [NSRegularExpression regularExpressionWithPattern:
     @"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
                                              options:NSRegularExpressionCaseInsensitive
                                                error:nil];
    return [ipString isMatchedByRegex:regex];
}

// Monstrous regex from https://stackoverflow.com/questions/53497/regular-expression-that-matches-valid-ipv6-addresses
+ (BOOL)isIPv6AddressString:(NSString *)ipString {
    NSRegularExpression *regex =
    [NSRegularExpression regularExpressionWithPattern:
@"(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"
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
    BOOL validRange = (portNum >= 0 && portNum < 65535);
    return match && validRange;
}

#pragma mark -

+ (NSString *)dnsNameForIPv4AddressString:(NSString *)ipAddrStr {
    if ([IPUtils isIPv4AddressString:ipAddrStr] == NO) {
        return nil;
    }
    // Do DNS lookup for IP address
    return [[NSHost hostWithAddress:ipAddrStr] name];
}

+ (NSString *)dnsNameForIPv6AddressString:(NSString *)ipAddrStr {
    if ([IPUtils isIPv6AddressString:ipAddrStr] == NO) {
        return nil;
    }
    // Do DNS lookup for IP address
    return [[NSHost hostWithAddress:ipAddrStr] name];
}

+ (NSString *)dnsNameForIPAddressString:(NSString *)ipAddStr; {
    NSString *dns = [IPUtils dnsNameForIPv4AddressString:ipAddStr];
    if (dns) {
        return dns;
    }
    return [IPUtils dnsNameForIPv6AddressString:ipAddStr];
}

#pragma mark -

+ (NSString *)IPAddressStringForDNSName:(NSString *)dnsNameString {
    NSString *ipAddr = [IPUtils IPv4AddressStringForDNSName:dnsNameString];
    if (ipAddr) {
        return ipAddr;
    }
    return [IPUtils IPv6AddressStringForDNSName:dnsNameString];
}

+ (NSString *)IPv4AddressStringForDNSName:(NSString *)dnsNameString {
    NSHost *host = [NSHost hostWithName:dnsNameString];
    if (host) {
        for (NSString *addr in [host addresses]) {
            if ([IPUtils isIPv4AddressString:addr]) {
                return addr;
            }
        }
    }
    return nil;
}

+ (NSString *)IPv6AddressStringForDNSName:(NSString *)dnsNameString {
    NSHost *host = [NSHost hostWithName:dnsNameString];
    if (host) {
        for (NSString *addr in [host addresses]) {
            if ([IPUtils isIPv6AddressString:addr]) {
                return addr;
            }
        }
    }
    return nil;
}

#pragma mark -

// Look up port name, e.g. "http" for "80"
+ (NSString *)portNameForPortNumString:(NSString *)portNumStr {
    if ([IPUtils isPortNumberString:portNumStr] == NO) {
        return nil;
    }
    
    int port = [portNumStr intValue];
    struct servent *serv;
    serv = getservbyport(htons(port), NULL);
    
    // Just return original port num string if port name couldn't be resolved
    if (!serv) {
        return portNumStr;
    }
    
    return [NSString stringWithCString:serv->s_name encoding:NSASCIIStringEncoding];
}

// Look up port number for name, e.g. "80" for "http"
+ (NSString *)portNumberForPortNameString:(NSString *)portNameString {
    const char *portName = [portNameString cStringUsingEncoding:NSUTF8StringEncoding];
    struct servent *serv = getservbyname(portName, NULL);
    if (serv != NULL) {
        int portNum = ntohs(serv->s_port);
        return [NSString stringWithFormat:@"%d", portNum];
    }
    return nil;
}

@end

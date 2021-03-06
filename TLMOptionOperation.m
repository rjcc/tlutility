//
//  TLMOptionOperation.m
//  TeX Live Utility
//
//  Created by Adam Maxwell on 8/27/09.
/*
 This software is Copyright (c) 2009-2016
 Adam Maxwell. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 - Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 
 - Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in
 the documentation and/or other materials provided with the
 distribution.
 
 - Neither the name of Adam Maxwell nor the names of any
 contributors may be used to endorse or promote products derived
 from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "TLMOptionOperation.h"
#import "TLMEnvironment.h"
#import "TLMTask.h"
#import "TLMLogServer.h"

@implementation TLMOptionOperation

static NSString * __TLMParseStringOption(NSString *output)
{
    if (output) {
        output = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        output = [[output componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastObject];
    }
    return output;
}

+ (NSString *)stringValueOfOption:(NSString *)key
{
    NSString *cmdPath = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:cmdPath] == NO) {
        TLMLog(__func__, @"incorrect path %@ for tlmgr; can't read option %@", cmdPath, key);
        return nil;
    }
    NSArray *args = [NSArray arrayWithObjects:@"--machine-readable", @"option", key, nil];
    TLMTask *checkTask = [TLMTask launchedTaskWithLaunchPath:cmdPath arguments:args];
    [checkTask waitUntilExit];
    return ([checkTask terminationStatus] == 0) ? __TLMParseStringOption([checkTask outputString]) : nil;
}

+ (BOOL)boolValueOfOption:(NSString *)key
{
    return [[self stringValueOfOption:key] boolValue];
}

- (id)initWithKey:(NSString *)key value:(NSString *)value;
{
    NSParameterAssert(key);
    NSParameterAssert(value);
    NSString *cmd = [[TLMEnvironment currentEnvironment] tlmgrAbsolutePath];
    // insert -- in arguments to keep tlmgr from further parsing (allows passing -1 for autobackup)
    return [self initWithCommand:cmd options:[NSArray arrayWithObjects:@"option", @"--", key, value, nil]];
}

@end

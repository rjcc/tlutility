//
//  TLMOutputParser.m
//  TeX Live Manager
//
//  Created by Adam Maxwell on 12/6/08.
/*
 This software is Copyright (c) 2008-2009
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

#import "TLMOutputParser.h"
#import "TLMPackageNode.h"
#import "TLMLogServer.h"
#import "TLMPreferenceController.h"

@implementation TLMOutputParser

#pragma mark Update parsing

+ (NSString *)_statusStringForCharacter:(unichar)ch
{
    NSString *status = nil;
    switch (ch) {
        case 'd':
            status = NSLocalizedString(@"Deleted on server", @"status for package");
            break;
        case 'u':
            status = NSLocalizedString(@"Updated on server", @"status for package");
            break;
        case 'a':
            status = NSLocalizedString(@"Not installed", @"status for package");
            break;
        case 'f':
            status = NSLocalizedString(@"Forcibly removed", @"status for package");
            break;
        case 'r':
            status = NSLocalizedString(@"Local version is newer", @"status for package");
            break;
        default:
            TLMLog(__func__, @"Unknown status code \"%C\"", ch);
            break;
    }
    return status;
}

/*
 froude:tmp amaxwell$ tlmgr2 --machine-readable update --list 2>/dev/null
 ...
 casyl	f	-	-	-
 pageno	d	-	-	-
 arsclassica	a	-	11634	297310
 oberdiek	u	10278	11378	12339256
 
 */

#define MAX_COLUMNS 5

enum {
    TLMNameIndex          = 0,
    TLMStatusIndex        = 1,
    TLMLocalVersionIndex  = 2,
    TLMRemoteVersionIndex = 3,
    TLMSizeIndex          = 4
};

+ (TLMPackage *)packageWithUpdateLine:(NSString *)outputLine;
{
    TLMPackage *package = [TLMPackage package];
    
    // probably safe to use \t as separator here, but just accept any whitespace
    NSArray *components = [outputLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    // !!! early return here after a sanity check
    if ([components count] < MAX_COLUMNS) {
        TLMLog(__func__, @"Unexpected number of tokens in line \"%@\"", outputLine);
        [package setName:NSLocalizedString(@"Error parsing output line", @"error message for unreadable package")];
        [package setStatus:outputLine];
        [package setFailedToParse:YES];
        return package;
    }
    
    [package setName:[components objectAtIndex:TLMNameIndex]];
    
    unichar ch = [[components objectAtIndex:TLMStatusIndex] characterAtIndex:0];
    [package setStatus:[self _statusStringForCharacter:ch]];
    
    if ('d' == ch)
        [package setWillBeRemoved:YES];
    
    if ('a' != ch)
        [package setInstalled:YES];
    
    if ('u' == ch)
        [package setNeedsUpdate:YES];
    
    if ('f' == ch)
        [package setWasForciblyRemoved:YES];
    
    if (NO == [[components objectAtIndex:TLMLocalVersionIndex] isEqualToString:@"-"])
        [package setLocalVersion:[components objectAtIndex:TLMLocalVersionIndex]];
    
    if (NO == [[components objectAtIndex:TLMRemoteVersionIndex] isEqualToString:@"-"])
        [package setRemoteVersion:[components objectAtIndex:TLMRemoteVersionIndex]];
    
    if (NO == [[components objectAtIndex:TLMSizeIndex] isEqualToString:@"-"]) {
        NSInteger s = [[components objectAtIndex:TLMSizeIndex] integerValue];
        if (s > 0) [package setSize:[NSNumber numberWithUnsignedInteger:s]];
    }
    
    return package;
}

#pragma mark Info parsing

static bool hasKeyPrefix(NSString *line)
{
    NSScanner *scanner = [NSScanner scannerWithString:line];
    static NSCharacterSet *keySet = nil;
    if (nil == keySet) {
        NSMutableCharacterSet *cset = [NSMutableCharacterSet alphanumericCharacterSet];
        [cset addCharactersInString:@" ,-"];
        keySet = [cset copy];
    }
    [scanner setCharactersToBeSkipped:keySet];
    return ([scanner scanString:@":" intoString:NULL]);
}

#define RUN_FILE_KEY    @"run files"
#define SOURCE_FILE_KEY @"source files"
#define DOC_FILE_KEY    @"doc files"

+ (NSDictionary *)_infoDictionaryWithString:(NSString *)infoString
{
    NSArray *lines = [infoString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    NSString *key = nil;
    NSMutableString *value = nil;
    
    NSMutableArray *runfiles = [NSMutableArray array];
    NSMutableArray *sourcefiles = [NSMutableArray array];
    NSMutableArray *docfiles = [NSMutableArray array];
    int state;
    
    NSString *installPath = [[[TLMPreferenceController sharedPreferenceController] installDirectory] path];
    
    for (NSString *line in lines) {
        
        enum {
            PREAMBLE_STATE,
            RUNFILE_STATE,
            SOURCEFILE_STATE,
            DOCFILE_STATE
        };
        
        // !!! hack here; skip this line
        if ([line hasPrefix:@"Included files, by type:"])
            continue;

        if (hasKeyPrefix(line)) {
            
            // save previous key/value pair
            if (key && value) {
                CFStringTrimWhitespace((CFMutableStringRef)value);
                [dict setObject:value forKey:key];
            }
            
            value = [NSMutableString string];
            NSRange r = [line rangeOfString:@":"];
            // downcase to allow for changes from CamelCase
            key = [[line substringToIndex:r.location] lowercaseString];
            [value appendString:[line substringFromIndex:NSMaxRange(r)]];
            
            if ([key isEqualToString:RUN_FILE_KEY])
                state = RUNFILE_STATE;
            else if ([key isEqualToString:SOURCE_FILE_KEY])
                state = SOURCEFILE_STATE;
            else if ([key isEqualToString:DOC_FILE_KEY])
                state = DOCFILE_STATE;
            else
                state = PREAMBLE_STATE;
            
        }
        else {
            
            switch (state) {
                case PREAMBLE_STATE:
                    [value appendString:line];
                    break;
                case RUNFILE_STATE:
                    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([line isEqualToString:@""] == NO && installPath) {
                        NSURL *fileURL = [NSURL fileURLWithPath:[installPath stringByAppendingPathComponent:line]];
                        if (fileURL) [runfiles addObject:fileURL];
                    }
                    break;
                case SOURCEFILE_STATE:
                    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([line isEqualToString:@""] == NO && installPath) {
                        NSURL *fileURL = [NSURL fileURLWithPath:[installPath stringByAppendingPathComponent:line]];
                        if (fileURL) [sourcefiles addObject:fileURL];
                    }
                    break;
                case DOCFILE_STATE:
                    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if ([line isEqualToString:@""] == NO && installPath) {
                        NSURL *fileURL = [NSURL fileURLWithPath:[installPath stringByAppendingPathComponent:line]];
                        if (fileURL) [docfiles addObject:fileURL];
                    }
                    break;
                default:
                    break;
            }
            
        }
    }
    
    // this is whitespace; if it's ever a legitimate value, I'll have to rewrite the parser...
    if (key && value) {
        CFStringTrimWhitespace((CFMutableStringRef)value);
        [dict setObject:value forKey:key];
    }
    
    [dict setObject:runfiles forKey:RUN_FILE_KEY];
    [dict setObject:sourcefiles forKey:SOURCE_FILE_KEY];
    [dict setObject:docfiles forKey:DOC_FILE_KEY];
    
    return dict;
}

+ (NSAttributedString *)attributedStringWithInfoString:(NSString *)infoString docURLs:(NSArray *)docURLs;
{
    NSDictionary *info = [self _infoDictionaryWithString:infoString];
    
    // !!! early return here if parsing fails
    if ([info count] == 0)
        return [[[NSAttributedString alloc] initWithString:infoString] autorelease];
    
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] init];
    
    NSString *value;
    NSUInteger previousLength;
    NSFont *userFont = [NSFont userFontOfSize:0.0];
    NSFont *boldFont = [[NSFontManager sharedFontManager] convertFont:userFont toHaveTrait:NSBoldFontMask];

    // note that all keys are downcased; tlmgr 2008 used CamelCase, but Karl might switch 2009 to lowercase
    value = [info objectForKey:@"package"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Package:", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [info objectForKey:@"shortdesc"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Summary:", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [info objectForKey:@"installed"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Status:", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        if ([value caseInsensitiveCompare:@"yes"] == NSOrderedSame) {
            value = NSLocalizedString(@"Installed", @"status for package");
        }
        else {
            value = NSLocalizedString(@"Not installed", @"status for package");
        }
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@" %@\n\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    value = [info objectForKey:@"tlmgr"];
    if (value) {
        
        NSRange r = [value rangeOfString:@"installation location "];
        NSURL *linkURL = nil;

        if (r.length)
            linkURL = [NSURL URLWithString:[value substringFromIndex:NSMaxRange(r)]];
        
        if (linkURL) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:NSLocalizedString(@"Link: ", @"heading in info panel")];
            [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[linkURL absoluteString]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:linkURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }
    }
    
    value = [info objectForKey:@"longdesc"];
    if (value) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"Description:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        previousLength = [attrString length];
        [[attrString mutableString] appendFormat:@"%@\n", value];
        [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
    }
    
    // documentation from texdoc
    if ([docURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nDocumentation:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *docURL in docURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[docURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:docURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    NSArray *runURLs = [info objectForKey:RUN_FILE_KEY];
    if ([runURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nRun Files:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *aURL in runURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[aURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    NSArray *sourceURLs = [info objectForKey:SOURCE_FILE_KEY];
    if ([sourceURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nSource Files:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *aURL in sourceURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[aURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
    
    docURLs = [info objectForKey:SOURCE_FILE_KEY];
    if ([docURLs count]) {
        previousLength = [attrString length];
        [[attrString mutableString] appendString:NSLocalizedString(@"\nDoc Files:\n", @"heading in info panel")];
        [attrString addAttribute:NSFontAttributeName value:boldFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        
        for (NSURL *aURL in docURLs) {
            previousLength = [attrString length];
            [[attrString mutableString] appendString:[[aURL path] lastPathComponent]];
            [attrString addAttribute:NSFontAttributeName value:userFont range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSLinkAttributeName value:aURL range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            [attrString addAttribute:NSCursorAttributeName value:[NSCursor pointingHandCursor] range:NSMakeRange(previousLength, [attrString length] - previousLength)];
            
            previousLength = [attrString length];
            [[attrString mutableString] appendString:@"\n"];
            [attrString removeAttribute:NSLinkAttributeName range:NSMakeRange(previousLength, [attrString length] - previousLength)];
        }        
    }
        
    return [attrString autorelease];
}

#pragma mark List parsing

/*
 i Tabbing: (shortdesc missing)
 i Type1fonts: (shortdesc missing)
 i a0poster: Support for designing posters on large paper. 
   [...]
 i bin-amstex: American Mathematical Society plain TeX macros.
   bin-amstex.alpha-linux: binary files of bin-amstex for alpha-linux
   bin-amstex.amd64-freebsd: binary files of bin-amstex for amd64-freebsd
   bin-amstex.hppa-hpux: binary files of bin-amstex for hppa-hpux
   bin-amstex.i386-freebsd: binary files of bin-amstex for i386-freebsd
   bin-amstex.i386-linux: binary files of bin-amstex for i386-linux
   bin-amstex.i386-openbsd: binary files of bin-amstex for i386-openbsd
   bin-amstex.i386-solaris: binary files of bin-amstex for i386-solaris
   bin-amstex.mips-irix: binary files of bin-amstex for mips-irix
   bin-amstex.powerpc-aix: binary files of bin-amstex for powerpc-aix
   bin-amstex.powerpc-linux: binary files of bin-amstex for powerpc-linux
   bin-amstex.sparc-linux: binary files of bin-amstex for sparc-linux
   bin-amstex.sparc-solaris: binary files of bin-amstex for sparc-solaris
 i bin-amstex.universal-darwin: binary files of bin-amstex for universal-darwin
   bin-amstex.win32: binary files of bin-amstex for win32
   bin-amstex.x86_64-linux: binary files of bin-amstex for x86_64-linux
 i bin-bibtex: Process bibliographies for LaTeX, etc.
   bin-bibtex.alpha-linux: binary files of bin-bibtex for alpha-linux
   bin-bibtex.amd64-freebsd: binary files of bin-bibtex for amd64-freebsd
   [...]
*/ 

+ (TLMPackageNode *)_newPackageNodeWithOutputLine:(NSString *)line
{
    NSParameterAssert([line length]);
    
    TLMPackageNode *node = [TLMPackageNode new];
    
    if ([line characterAtIndex:0] == 'i')
        [node setInstalled:YES];
    
    NSScanner *scanner = [[NSScanner alloc] initWithString:line];
    if ([node isInstalled])
        [scanner scanString:@"i" intoString:NULL];
    
    NSString *name;
    if ([scanner scanUpToString:@":" intoString:&name]) {
        
        // e.g. bin-amstex.universal.darwin
        [node setFullName:name];
        
        NSRange r = [name rangeOfString:@"."];
        if (r.length) {
            // universal.darwin
            [node setName:[name substringFromIndex:NSMaxRange(r)]];
            [node setHasParent:YES];
        }
        else {
            // not a child node, so name and fullName are equivalent
            [node setName:name];
        }
        
        // scan past the colon
        [scanner scanString:@":" intoString:NULL];
    }
    
    if (NO == [scanner isAtEnd])
        [node setShortDescription:[line substringFromIndex:[scanner scanLocation]]];
    [scanner release];
    
    return node;
}

+ (NSArray *)nodesWithListLines:(NSArray *)listLines;
{    
    NSMutableArray *nodes = [NSMutableArray array];
    
    for (NSString *line in listLines) {
        
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (NO == [line isEqualToString:@""]) {
            TLMPackageNode *node = [self _newPackageNodeWithOutputLine:line];
            if ([node hasParent]) {
                TLMPackageNode *last = [nodes lastObject];
                if ([[node fullName] hasPrefix:[node fullName]])
                    [last addChild:node];
                else
                    TLMLog(__func__, @"Child node named \"%@\" follows node named \"%@\"", [node fullName], [node fullName]);
            }
            else {
                [nodes addObject:node];
            }
            [node release];
        }
    }
    
    return nodes;
}

@end

//
//  ViewController.m
//  TorrentParser
//
//  Created by Andrey on 2016-12-16.
//  Copyright © 2016 Andrey Paunov. All rights reserved.
//

#import "TPMainViewController.h"

// Delimiters
#define DICTIONARY_DELIMITER 'd'
#define LIST_DELIMITER 'l'
#define INTEGER_DELIMITER 'i'
#define END_DELIMITER 'e'
#define COLUMN_DELIMITER ':'

@interface TPMainViewController()

// An externtion to hold class properties

@property (weak) IBOutlet NSButton *convertButton;
@property (unsafe_unretained) IBOutlet NSTextView *parsedResultsTextView;

@property (nonatomic, assign) int lengthOfNextTagLabel;
@property (nonatomic, assign) BOOL isReadingPieces;
@property (nonatomic, assign) BOOL isReadingPlayTime;
@property (nonatomic, assign) BOOL isValue;

@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSMutableArray *stack;
@property (nonatomic, strong) NSMutableArray *fileList;
@property (nonatomic, strong) NSMutableString *jsonString;
@property (nonatomic, strong) NSRegularExpression *regex;
@property (nonatomic, strong) NSMutableDictionary *filesCollectedData;

@end

@implementation TPMainViewController

#pragma mark - Button actions

- (IBAction)browseButton:(NSButton *)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    
    [openPanel setCanChooseFiles:YES];
    [openPanel setAllowsMultipleSelection:YES];
    [openPanel setCanChooseDirectories:YES];
    
    if ([openPanel runModal] == NSModalResponseOK)
    {
        NSArray *urls = [openPanel URLs];
        [self.filesCollectedData removeAllObjects];
        
        for (int i = 0; i < [urls count]; i++)
        {
            NSURL *url = [urls objectAtIndex:i];
            
            [self.fileList addObject:url];
        }
        
        if ([urls count])
        {
            self.convertButton.enabled = YES;
        }
    }
}

- (IBAction)clear:(NSButton *)sender
{
    [[self.parsedResultsTextView textStorage] setAttributedString:[[NSMutableAttributedString alloc] initWithString:@""]];
}

- (IBAction)convertButton:(NSButton *)sender
{
    for (NSURL *url in self.fileList)
    {
        // Reset values before process a new file
        self.lengthOfNextTagLabel = 0;
        self.isReadingPieces = NO;
        self.isReadingPlayTime = NO;
        self.isValue = NO;
        self.jsonString = [NSMutableString string];
        self.stack = [NSMutableArray array];
        [self.jsonString setString:@""];

        // Parse
        [self fileParser:url];
        
        // Gather Data
//        [self.filesCollectedData setObject:[self convertToDictionaryFromJSON] forKey:url.absoluteString];
        [self.filesCollectedData setObject:self.jsonString forKey:url.absoluteString];
    }

    dispatch_async(dispatch_get_main_queue(), ^
    {
        [self.filesCollectedData enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop)
        {
//            NSString *s = [NSString stringWithFormat:@"File: %@\r%@\r\r", key, ((NSDictionary *)obj).description];
            NSString *s = [NSString stringWithFormat:@"File: %@\r%@\r\r", key, obj];
            NSMutableAttributedString * string = [[NSMutableAttributedString alloc] initWithString:s];

            [[self.parsedResultsTextView textStorage] appendAttributedString:string];
        }];
    });
}

#pragma mark - View Controller methods

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Do any additional setup after loading the view.

    self.fileManager = [NSFileManager defaultManager];
    self.fileList = [NSMutableArray array];
    self.filesCollectedData = [NSMutableDictionary dictionary];
    self.view.wantsLayer = YES;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    
    if (self.view.layer)
    {
        self.view.layer.backgroundColor = CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0);
    }
}

- (void)setRepresentedObject:(id)representedObject
{
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

#pragma mark - Torrent parsing helper methods

- (void)fileParser:(NSURL *)fileURL
{
    if ([self.fileManager fileExistsAtPath:[fileURL path]])
    {
        // The file does exist, therefore, continue with its parsing

        if ([self checkForReadPermission:[fileURL path]])
        {
            NSData *data = [self.fileManager contentsAtPath:[fileURL path]];
            NSMutableString *tagString = [NSMutableString string];
            __block int bytesRead = 0;

            [data enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop)
            {
                for (NSUInteger i = 0; i < byteRange.length; i++)
                {
                    char byte = ((const char *)bytes)[i];

                    if (self.isReadingPieces)
                    {
                        if (bytesRead++ < self.lengthOfNextTagLabel)
                        {
                            [tagString appendFormat:@"%02x", byte];
                        }
                        else
                        {
                            bytesRead = 0;
                            self.isReadingPieces = NO;
                            self.lengthOfNextTagLabel = 0;

                            [self.jsonString appendFormat:@"\"%@\"", tagString];
                            [tagString setString:@""];
                            [tagString appendFormat:@"%c", byte];
                        }
                    }
                    else if (self.isReadingPlayTime)
                    {
                        if (bytesRead++ >= self.lengthOfNextTagLabel)
                        {
                            bytesRead = 0;
                            self.isReadingPlayTime = NO;
                            self.lengthOfNextTagLabel = 0;

                            [self.jsonString appendFormat:@"\"%@\"", tagString];
                            [tagString setString:@""];
                        }

                        [tagString appendFormat:@"%c", byte];
                    }
                    else
                    {
                        [tagString appendFormat:@"%c", byte];

                        if (byte == COLUMN_DELIMITER)
                        {
                            if ([self processStringType:tagString])
                            {
                                [tagString setString:@""];
                            }
                        }
                    }
                }
            }];

            [self processStringType:tagString];
        }
    }
    else
    {
        // Log a File Not Found Error
    }
}

- (BOOL)checkForReadPermission:(NSString *)filePath
{
    if ([self.fileManager isReadableFileAtPath:filePath])
    {
        return YES;
    }
    
    return NO;
}

- (BOOL)processStringType:(NSString *)tagString
{
    // First try with a dictionary type
    if ([self isIntegerPattern:tagString])
    {
        return YES;
    }
    else if ([self isEndPattern:tagString])
    {
        return YES;
    }
    else if ([self isDicPattern:tagString])
    {
        return YES;
    }
    else if ([self isListPattern:tagString])
    {
        return YES;
    }
    else if ([self isStringPattern:tagString])
    {
        return YES;
    }

    return NO;
}

- (void)initRegEx:(NSString *)regExPattern
{
    self.regex = [NSRegularExpression regularExpressionWithPattern:regExPattern options:NSRegularExpressionCaseInsensitive error:NULL];
}

#pragma mark - Pattern methods

-(BOOL)isIntegerPattern:(NSString *)tagString
{
    NSArray *data = [self extractData:tagString delimiterPattern:@"[i]\\d+[e]"];

    if (data && [data count])
    {
        NSString *name = data.firstObject;
        NSString *pattern = data.lastObject;
        int value = [self returnIntFromString:pattern];

        [self.jsonString appendFormat:@"\"%@\":%i,", name, value];

        self.lengthOfNextTagLabel = [self returnIntFromString:[self trimIntPattern:pattern]];

        return YES;
    }
    
    return NO;
}

-(BOOL)isEndPattern:(NSString *)tagString
{
    BOOL isEndPattern = NO;
    NSString *endPattern = @"([e]+[l|d]*\\d+\\:|[e]+$)";

    NSArray *data = [self extractData:tagString delimiterPattern:endPattern];

    if (data && [data count])
    {
        NSString *name = data.firstObject;
        NSString *pattern = data.lastObject;
        
        for (int i = 0; i < [pattern length]; i++)
        {
            char iChar = [pattern characterAtIndex:i];
            
            if (iChar == 'i')
            {
                return NO;
            }
            else if (iChar == 'e')
            {
                if ([[self.stack lastObject] isEqualToString:@"l"])
                {
                    if (name)
                    {
                        if (![name isEqualToString:@""])
                        {
                            [self.jsonString appendFormat:@"\"%@\"]", name];
                            [self.stack removeLastObject];
                            name = nil;
                        }
                        else
                        {
                            [self.jsonString appendString:@"]"];
                            [self.stack removeLastObject];
                        }
                    }
                    else
                    {
                        [self.jsonString appendFormat:@"]"];
                        [self.stack removeLastObject];
                    }
                }
                else if ([[self.stack lastObject] isEqualToString:@"d"])
                {
                    if (name)
                    {
                        if (![name isEqualToString:@""])
                        {
                            [self.jsonString appendFormat:@"\"%@\"}", name];
                            [self.stack removeLastObject];
                            name = nil;
                        }
                        else
                        {
                            [self.jsonString appendString:@"}"];
                            [self.stack removeLastObject];
                        }
                    }
                    else
                    {
                        [self.jsonString appendFormat:@"}"];
                        [self.stack removeLastObject];
                    }
                }

                self.lengthOfNextTagLabel = [self returnIntFromString:pattern];

                isEndPattern = YES;
            }
            else if (iChar == 'l')
            {
                [self.jsonString appendFormat:@",["];
                
                [self.stack addObject:@"l"];
                
                isEndPattern = YES;
            }
            else if (iChar == 'd')
            {
                [self.jsonString appendFormat:@",{"];
                
                [self.stack addObject:@"d"];
                
                isEndPattern = YES;
            }
        }
    }

    return isEndPattern;
}

- (BOOL)isStringPattern:(NSString *)tagString
{
    NSArray *data = [self extractData:tagString delimiterPattern:@"\\d\\:"];

    if (data && [data count])
    {
        NSString *nameOrValue = data.firstObject;
        NSString *pattern = data.lastObject;

        if ([nameOrValue containsString:@"pieces"])
        {
            self.isReadingPieces = YES;
        }
        else if ([nameOrValue containsString:@"playtime"])
        {
            self.isReadingPlayTime = YES;
        }

        if (self.isValue)
        {
            self.isValue = NO;

            [self.jsonString appendFormat:@"\"%@\",", nameOrValue];
        }
        else
        {
            self.isValue = YES;

            char lastCharOfJsonString = [self.jsonString characterAtIndex:[self.jsonString length] - 1];
            
            if (lastCharOfJsonString == '[' || lastCharOfJsonString == '{' || lastCharOfJsonString == ',')
            {
                [self.jsonString appendFormat:@"\"%@\":", nameOrValue];
            }
            else
            {
                [self.jsonString appendFormat:@",\"%@\":", nameOrValue];
            }
        }

        self.lengthOfNextTagLabel = [self returnIntFromString:pattern];

        return YES;
    }

    return NO;
}

- (BOOL)isDicPattern:(NSString *)tagString
{
    NSArray *data = [self extractData:tagString delimiterPattern:@"[d]\\d*\\:"];

    if (data && [data count])
    {
        NSString *name = data.firstObject;
        NSString *pattern = data.lastObject;

        self.lengthOfNextTagLabel = [self returnIntFromString:pattern];
        
        for (int i = 0; i < [pattern length]; i++)
        {
            char iChar = [pattern characterAtIndex:i];
            
            if (iChar == 'd')
            {
                if (![self.jsonString length])
                {
                    [self.jsonString appendFormat:@"{"];
                }
                else
                {
                    [self.jsonString appendFormat:@"\"%@\":{", name];
                }
                
                [self.stack addObject:@"d"];
            }
        }

        return YES;
    }

    return NO;
}

- (BOOL)isListPattern:(NSString *)tagString
{
    NSArray *data = [self extractData:tagString delimiterPattern:@"[l]+\\d+\\:"];
    
    if (data && [data count])
    {
        NSString *nameOrValue = data.firstObject;
        NSString *pattern = data.lastObject;

        self.lengthOfNextTagLabel = [self returnIntFromString:pattern];
        
        [self.jsonString appendFormat:@"\"%@\":", nameOrValue];

        for (int i = 0; i < [pattern length]; i++)
        {
            char iChar = [pattern characterAtIndex:i];

            if (iChar == 'l')
            {
                [self.jsonString appendFormat:@"["];
                
                [self.stack addObject:@"l"];
            }
        }
        
        return YES;
    }

    return NO;
}

- (NSArray *)extractData:(NSString *)tagString delimiterPattern:(NSString *)pattern
{
    [self initRegEx:pattern];

    NSUInteger foundMatches = [self.regex numberOfMatchesInString:tagString options:0 range:NSMakeRange(0, [tagString length])];

    if (foundMatches)
    {
        NSString *name = nil;
        NSString *pattern = nil;

        name = [tagString substringWithRange:NSMakeRange(0, self.lengthOfNextTagLabel)];
        pattern = [tagString substringWithRange:NSMakeRange(self.lengthOfNextTagLabel, [tagString length] - self.lengthOfNextTagLabel)];

        return [NSMutableArray arrayWithObjects:name, pattern, nil];
    }

    return nil;
}

- (int)returnIntFromString:(NSString *)string
{
    if ([string containsString:@"i"])
    {
        int range = 0;

        for (int i = 0; i < [string length]; i++)
        {
            if ([string characterAtIndex:i] == 'e')
            {
                range = i;
                break;
            }
        }
        
        return [[string substringWithRange:NSMakeRange(1, range - 1)] intValue];
    }
    else
    {
        NSCharacterSet *nonDigitCharacterSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        return [[[string componentsSeparatedByCharactersInSet:nonDigitCharacterSet] componentsJoinedByString:@""] intValue];
    }
}

- (NSString *)trimIntPattern:(NSString *)pattern
{
    int endOfRange = 0;
    
    for (int i = 0; i < [pattern length]; i++)
    {
        if ([pattern characterAtIndex:i] == 'e')
        {
            endOfRange = i;
            break;
        }
    }

    return [pattern substringWithRange:NSMakeRange(endOfRange, [pattern length] - endOfRange)];
}

- (NSDictionary *)convertToDictionaryFromJSON
{
    NSStringEncoding encoding = NSUTF8StringEncoding;
    NSError *error = nil;

    NSData *jsonData = [self.jsonString dataUsingEncoding:encoding];
    
    return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
}

@end

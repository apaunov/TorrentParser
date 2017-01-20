//
//  ParsedData.m
//  TorrentParser
//
//  Created by Andrey on 2016-12-20.
//  Copyright © 2016 Andrey Paunov. All rights reserved.
//

#import "ParsedData.h"

@implementation ParsedData

- (instancetype)init:(NSString *)fileName dataDictionary:(NSDictionary *)dataDictionary
{
    if (self = [super init])
    {
        self.fileName = fileName;
        self.dataDictionary = dataDictionary;
    }

    return self;
}

@end

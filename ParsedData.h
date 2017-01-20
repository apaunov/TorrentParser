//
//  ParsedData.h
//  TorrentParser
//
//  Created by Andrey on 2016-12-20.
//  Copyright © 2016 Andrey Paunov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ParsedData : NSObject

@property (nonatomic, strong) NSString *fileName;
@property (nonatomic, strong) NSDictionary *dataDictionary;

- (instancetype)init:(NSString *)fileName dataDictionary:(NSDictionary *)dataDictionary;

@end

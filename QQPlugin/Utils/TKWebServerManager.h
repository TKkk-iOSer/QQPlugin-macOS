//
//  TKWebServerManager.h
//  QQPlugin
//
//  Created by TK on 2018/3/24.
//  Copyright © 2018年 tk. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TKWebServerManager : NSObject

+ (instancetype)shareManager;

- (void)startServer;
- (void)endServer;

@end

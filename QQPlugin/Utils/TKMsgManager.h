//
//  TKMsgManager.h
//  QQPlugin
//
//  Created by TK on 2018/3/31.
//  Copyright © 2018年 TK. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TKMsgManager : NSObject

+ (void)sendTextMessage:(NSString *)msg uin:(long long)uin sessionType:(int)type;

@end

//
//  TKQQPluginConfig.h
//  QQPlugin
//
//  Created by TK on 2018/3/19.
//  Copyright © 2018年 TK. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TKQQPluginConfig : NSObject

@property (nonatomic, assign) BOOL preventRevokeEnable;                 /**<    是否开启防撤回    */
@property (nonatomic, copy) NSMutableArray *autoReplyModels;            /**<    自动回复的数组    */

+ (instancetype)sharedConfig;
- (void)saveAutoReplyModels;

@end

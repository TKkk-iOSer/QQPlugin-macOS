//
//  TKMsgManager.m
//  QQPlugin
//
//  Created by TK on 2018/3/31.
//  Copyright © 2018年 TK. All rights reserved.
//

#import "TKMsgManager.h"
#import "QQPlugin.h"

@implementation TKMsgManager

+ (void)sendTextMessage:(NSString *)msg uin:(long long)uin sessionType:(int)type {
    BHCompoundMessagePacket *packet =  [[objc_getClass("BHCompoundMessagePacket") alloc] initWithMessageType:1024];
    [packet setValue:@[@{@"msg-type":@(0), @"text":msg}] forKey:@"array"];
    struct _BHMessageSession session = {0,0,0,0};
    session._field1 = type;
    switch (type) {
        case 1:
            session._field2 = uin;
            break;
        case 101:
            session._field3 = uin;
            break;
        case 201:
            session._field4 = uin;
            break;
        default:
            break;
    }
    BHMsgManager *manager = [objc_getClass("BHMsgManager") sharedInstance];
    packet.fontInfo  = [manager defaultFontInfo];
    [manager sendMessagePacket:packet target:session completion:nil ProgressBlock:nil];
}

@end

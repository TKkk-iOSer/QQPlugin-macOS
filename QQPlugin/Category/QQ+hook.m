//
//  QQ.m
//  QQPlugin-macOS
//
//  Created by TK on 2018/3/18.
//  Copyright © 2018年 TK. All rights reserved.
//

#import "QQPlugin.h"
#import "QQ+hook.h"
#import "fishhook.h"
#import "TKQQPluginConfig.h"
#import "TKHelper.h"
#import "TKAutoReplyWindowController.h"
#import "TKWebServerManager.h"
#import "TKMsgManager.h"

static char tkAutoReplyWindowControllerKey;         //  自动回复窗口的关联 key

@implementation  NSObject (QQ)
+ (void)hookQQ {
    tk_hookMethod(objc_getClass("MQAIOChatViewController"), @selector(revokeMessages:), [self class], @selector(hook_revokeMessages:));
    tk_hookMethod(objc_getClass("MsgDbService"), @selector(updateQQMessageModel:keyArray:), [self class], @selector(hook_updateMessageModel:keyArray:));
    tk_hookMethod(objc_getClass("BHMsgManager"), @selector(appendReceiveMessageModel:msgSource:), [self class], @selector(hook_appendReceiveMessageModel:msgSource:));
    tk_hookMethod(objc_getClass("AppController"), @selector(notifyLoginWithAccount:resultCode:userInfo:), [self class], @selector(hook_notifyLoginWithAccount:resultCode:userInfo:));
    tk_hookMethod(objc_getClass("AppController"), @selector(notifyForceLogoutWithAccount:type:tips:), [self class], @selector(hook_notifyForceLogoutWithAccount:type:tips:));

    [self setup];
    //      替换沙盒路径
    rebind_symbols((struct rebinding[2]) {
        { "NSSearchPathForDirectoriesInDomains", swizzled_NSSearchPathForDirectoriesInDomains, (void *)&original_NSSearchPathForDirectoriesInDomains },
        { "NSHomeDirectory", swizzled_NSHomeDirectory, (void *)&original_NSHomeDirectory }
    }, 2);
}

+ (void)setup {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self addAssistantMenuItem];
    });
}

- (void)hook_revokeMessages:(NSArray <BHMessageModel *>*)models {
    if ([[TKQQPluginConfig sharedConfig] preventRevokeEnable]) return;
    
    [self hook_revokeMessages:models];
}

- (void)hook_updateMessageModel:(BHMessageModel *)msgModel keyArray:(id)keyArrays {
    if (msgModel.msgType != 332 || ![[TKQQPluginConfig sharedConfig] preventRevokeEnable]) {
        [self hook_updateMessageModel:msgModel keyArray:keyArrays];
        return;
    }
    
    NSString *revokeUserName;
    if (IS_VALID_STRING(msgModel.groupCode)) {
        BHGroupManager *groupManager = [objc_getClass("BHGroupManager") sharedInstance];
        revokeUserName = [groupManager displayNameForGroupMemberWithGroupCode:msgModel.groupCode memberUin:msgModel.uin];
    } else if (IS_VALID_STRING(msgModel.discussGroupUin)) {
        BHGroupManager *groupManager = [objc_getClass("BHGroupManager") sharedInstance];
        revokeUserName = [groupManager displayNameForGroupMemberWithGroupCode:msgModel.discussGroupUin memberUin:msgModel.uin];
    } else {
        BHFriendListManager *friendManager = [objc_getClass("BHFriendListManager") sharedInstance];
        BHFriendModel *frindModel =  [friendManager getFriendModelByUin:msgModel.uin];
        if (IS_VALID_STRING(frindModel.remark)) {
            revokeUserName = frindModel.remark;
        } else {
            revokeUserName = frindModel.profileModel.nick;
        }
    }
    
    NSString *sessionUin = [self getUinByMessageModel:msgModel];
    MsgDbService *msgService = [objc_getClass("MsgDbService") sharedInstance];
    BHMessageModel *revokeMsgModel = [[msgService getMessageWithUin:[sessionUin longLongValue]
                                                           sessType:msgModel.msgSessionType
                                                             msgIds:@[@(msgModel.msgID)]] firstObject];
    
    NSString *revokeMsg = [NSString stringWithFormat:@"%@: [非文本信息]",[revokeMsgModel senderDisplayName]];

    MQSessionID *sessionID = [objc_getClass("MQSessionID") sessionIdWithChatType:revokeMsgModel.chatType andUin:[revokeMsgModel.uin longLongValue]];
    if ((revokeMsgModel != 0x0) && ([revokeMsgModel chatType] != 0x4000)) {
        if ([revokeMsgModel msgType] != 0x4) {
            if ([revokeMsgModel chatType] != 0x10000) {
                revokeMsg = [(NSMutableAttributedString *)[objc_getClass("MQRecentMsgTips") tipsOfContentMsg:revokeMsgModel sessionId:sessionID]  string];
            }
        }
    }
    NSString *revokeTipContent = [NSString stringWithFormat:@"TK 拦截到一条撤回消息:\n\t%@", revokeMsg];
    if (msgModel.isSelfSend) {
        revokeTipContent = @"你 撤回了一条消息";
    }
    
    BHTipsMsgOption *tipOpt = [[objc_getClass("BHTipsMsgOption") alloc] init];
    tipOpt.addToDb = YES;

    BHMsgManager *msgManager = [objc_getClass("BHMsgManager") sharedInstance];
    [msgManager addTipsMessage:revokeTipContent sessType:msgModel.msgSessionType uin:sessionUin option:tipOpt];
}

- (void)hook_appendReceiveMessageModel:(NSArray *)msgModels msgSource:(long long)arg2 {
    [self hook_appendReceiveMessageModel:msgModels msgSource:arg2];
    
    [msgModels enumerateObjectsUsingBlock:^(BHMessageModel *msgModel, NSUInteger idx, BOOL * _Nonnull stop) {
        [self autoReplyWithMsg:msgModel];
    }];
}

- (void)hook_notifyLoginWithAccount:(id)arg1 resultCode:(long long)arg2 userInfo:(id)arg3 {
    [self hook_notifyLoginWithAccount:arg1 resultCode:arg2 userInfo:arg3];
    
    [[TKWebServerManager shareManager] startServer];
}

- (void)hook_notifyForceLogoutWithAccount:(id)arg1 type:(long long)arg2 tips:(id)arg3 {
    [[TKWebServerManager shareManager] endServer];
    
    [self hook_notifyForceLogoutWithAccount:arg1 type:arg2 tips:arg3];
}

#pragma mark - Other
/**
 自动回复
 
 @param msgModel 接收的消息
 */
- (void)autoReplyWithMsg:(BHMessageModel *)msgModel {
    if (msgModel.msgType != 1024 || msgModel.isSelfSend) return;
    
    NSDate *now = [NSDate date];
    NSTimeInterval nowTime = [now timeIntervalSince1970];
    NSTimeInterval receiveTime = [msgModel time];
    NSTimeInterval value = nowTime - receiveTime;
    if (value > 180) { //   3 分钟前的不回复
        return;
    }
    
    NSArray *msgContentArray = [self msgContentsFromMessageModel:msgModel];
    NSMutableString *msgContent = [NSMutableString stringWithFormat:@""];
    if (msgContentArray.count > 0) {
        [msgContentArray enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (IS_VALID_STRING(obj[@"text"]) && [obj[@"msg-type"] integerValue] == 0) {
                [msgContent appendString:obj[@"text"]];
            }
        }];
    }
    
    NSArray *autoReplyModels = [[TKQQPluginConfig sharedConfig] autoReplyModels];
    [autoReplyModels enumerateObjectsUsingBlock:^(TKAutoReplyModel *model, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!model.enable) return;
        if (!model.replyContent || model.replyContent.length == 0) return;
        if ((IS_VALID_STRING(msgModel.groupCode) || IS_VALID_STRING(msgModel.discussGroupUin)) && !model.enableGroupReply) return;
        if (!(IS_VALID_STRING(msgModel.groupCode) || IS_VALID_STRING(msgModel.discussGroupUin)) && !model.enableSingleReply) return;
        
        NSArray *replyArray = [model.replyContent componentsSeparatedByString:@"|"];
        int index = arc4random() % replyArray.count;
        NSString *randomReplyContent = replyArray[index];
        
        if (model.enableRegex) {
            NSString *regex = model.keyword;
            NSError *error;
            NSRegularExpression *regular = [NSRegularExpression regularExpressionWithPattern:regex options:NSRegularExpressionCaseInsensitive error:&error];
            if (error) return;
            NSInteger count = [regular numberOfMatchesInString:msgContent options:NSMatchingReportCompletion range:NSMakeRange(0, msgContent.length)];
            if (count > 0) {
                long long uin = [[self getUinByMessageModel:msgModel] longLongValue];
                NSInteger delayTime = model.enableDelay ? model.delayTime : 0;
                [self sendTextMessage:randomReplyContent uin:uin sessionType:msgModel.msgSessionType delay:delayTime];
            }
        } else {
            NSArray * keyWordArray = [model.keyword componentsSeparatedByString:@"|"];
            [keyWordArray enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([keyword isEqualToString:@"*"] || [msgContent isEqualToString:keyword]) {
                    long long uin = [[self getUinByMessageModel:msgModel] longLongValue];
                    NSInteger delayTime = model.enableDelay ? model.delayTime : 0;
                    [self sendTextMessage:randomReplyContent uin:uin sessionType:msgModel.msgSessionType delay:delayTime];
                }
            }];
        }
    }];
}

- (void)sendTextMessage:(NSString *)msg uin:(long long)uin sessionType:(int)type delay:(NSInteger)delayTime {
    if (delayTime == 0) {
        [TKMsgManager sendTextMessage:msg
                                  uin:uin
                          sessionType:type];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [TKMsgManager sendTextMessage:msg
                                      uin:uin
                              sessionType:type];
        });
    });
}
/**
 获取当前消息的 uin

 @param msgModel 消息model
 @return 消息的 uin
 */
- (NSString *)getUinByMessageModel:(BHMessageModel *)msgModel {
    NSString *currentUin;
    if (IS_VALID_STRING(msgModel.groupCode)) {
        currentUin = msgModel.groupCode;
    } else if (IS_VALID_STRING(msgModel.discussGroupUin)) {
        currentUin = msgModel.discussGroupUin;
    } else {
        currentUin = msgModel.uin;
    }
    return currentUin;
}

/**
 获取当前消息的内容数组

 @param model 消息model
 @return 内容数组
 */
- (NSArray *)msgContentsFromMessageModel:(BHMessageModel *)model {
    NSData *jsonData = [model.smallContent dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSArray *msgContent = [NSJSONSerialization JSONObjectWithData:jsonData
                                                          options:NSJSONReadingMutableContainers
                                                            error:&error];
    
    return error ? nil : msgContent;
}

#pragma mark - 菜单栏初始化
/**
 菜单栏添加 menuItem
 */
+ (void)addAssistantMenuItem {
    //        消息防撤回
    NSMenuItem *preventRevokeItem = [[NSMenuItem alloc] initWithTitle:@"开启消息防撤回" action:@selector(onPreventRevoke:) keyEquivalent:@"T"];
    preventRevokeItem.state = [[TKQQPluginConfig sharedConfig] preventRevokeEnable];
    
    //        自动回复
    NSMenuItem *autoReplyItem = [[NSMenuItem alloc] initWithTitle:@"自动回复设置" action:@selector(onAutoReply:) keyEquivalent:@"K"];
    
    NSMenu *subMenu = [[NSMenu alloc] initWithTitle:@"QQ小助手"];
    [subMenu addItem:preventRevokeItem];
    [subMenu addItem:autoReplyItem];
    
    NSMenuItem *menuItem = [[NSMenuItem alloc] init];
    [menuItem setTitle:@"QQ小助手"];
    [menuItem setSubmenu:subMenu];
    
    [[[NSApplication sharedApplication] mainMenu] addItem:menuItem];
}

/**
 菜单栏-QQ小助手-消息防撤回 设置
 
 @param item 消息防撤回的item
 */
- (void)onPreventRevoke:(NSMenuItem *)item {
    item.state = !item.state;
    [[TKQQPluginConfig sharedConfig] setPreventRevokeEnable:item.state];
}

/**
 菜单栏-QQ小助手-自动回复 设置
 
 @param item 自动回复设置的item
 */
- (void)onAutoReply:(NSMenuItem *)item {
    MainMenuController *mainMenu = [objc_getClass("MainMenuController") sharedInstance];
    TKAutoReplyWindowController *autoReplyWC = objc_getAssociatedObject(mainMenu, &tkAutoReplyWindowControllerKey);
    
    if (!autoReplyWC) {
        autoReplyWC = [[TKAutoReplyWindowController alloc] initWithWindowNibName:@"TKAutoReplyWindowController"];
        objc_setAssociatedObject(mainMenu, &tkAutoReplyWindowControllerKey, autoReplyWC, OBJC_ASSOCIATION_RETAIN);
    }
    
    [autoReplyWC showWindow:autoReplyWC];
    [autoReplyWC.window center];
    [autoReplyWC.window makeKeyWindow];
}

#pragma mark - 替换 NSSearchPathForDirectoriesInDomains & NSHomeDirectory
static NSArray<NSString *> *(*original_NSSearchPathForDirectoriesInDomains)(NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask, BOOL expandTilde);
NSArray<NSString *> *swizzled_NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask, BOOL expandTilde) {
    NSMutableArray<NSString *> *paths = [original_NSSearchPathForDirectoriesInDomains(directory, domainMask, expandTilde) mutableCopy];
    NSString *sandBoxPath = [NSString stringWithFormat:@"%@/Library/Containers/com.tencent.qq/Data",original_NSHomeDirectory()];
    [paths enumerateObjectsUsingBlock:^(NSString *filePath, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRange range = [filePath rangeOfString:original_NSHomeDirectory()];
        if (range.length > 0) {
            NSMutableString *newFilePath = [filePath mutableCopy];
            [newFilePath replaceCharactersInRange:range withString:sandBoxPath];
            paths[idx] = newFilePath;
        }
    }];
    return paths;
}

static NSString *(*original_NSHomeDirectory)(void);
NSString *swizzled_NSHomeDirectory(void) {
    return [NSString stringWithFormat:@"%@/Library/Containers/com.tencent.qq/Data",original_NSHomeDirectory()];
}

@end


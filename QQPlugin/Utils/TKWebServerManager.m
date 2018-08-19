//
//  TKWebServerManager.m
//  QQPlugin
//
//  Created by TK on 2018/3/24.
//  Copyright © 2018年 tk. All rights reserved.
//

#import "TKWebServerManager.h"
#import "QQPlugin.h"
#import <GCDWebServer.h>
#import <GCDWebServerDataResponse.h>
#import <GCDWebServerURLEncodedFormRequest.h>
#import "TKMsgManager.h"

@interface TKWebServerManager ()
@property (nonatomic, strong) GCDWebServer *webServer;
@end

@implementation TKWebServerManager

+ (instancetype)shareManager {
    static TKWebServerManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[TKWebServerManager alloc] init];
    });
    return manager;
}

- (void)startServer {
    if (self.webServer) return;
    
    NSDictionary *options = @{GCDWebServerOption_Port: @52777,
                              GCDWebServerOption_BindToLocalhost: @YES,
                              GCDWebServerOption_ConnectedStateCoalescingInterval: @2,
                              };
    
    self.webServer = [[GCDWebServer alloc] init];
    [self addHandleForSearchUser];
    [self addHandleForOpenSession];
    [self addHandleForSearchUserChatLog];
    [self addHandleForSendMsg];
    [self.webServer startWithOptions:options error:nil];
}

- (void)endServer {
    if( [self.webServer isRunning] ) {
        [self.webServer stop];
        [self.webServer removeAllHandlers];
        self.webServer = nil;
    }
}

- (void)addHandleForSearchUser {
    __weak typeof(self) weakSelf = self;
    
    [self.webServer addHandlerForMethod:@"GET" path:@"/QQ-plugin/user" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        
        NSString *keyword = request.query ? request.query[@"keyword"] ? request.query[@"keyword"] : @"" : @"";
        NSMutableArray *sessionList = [NSMutableArray array];

        if ([keyword isEqualToString:@""]) {
            sessionList = [self getRecentSessionList];
            return [GCDWebServerDataResponse responseWithJSONObject:sessionList];
        }
        
        ContactSearcherInter *inter = [[objc_getClass("ContactSearcherInter") alloc] init];
        [inter Query:keyword];
    
        [inter.searchedBuddys enumerateObjectsUsingBlock:^(Buddy * buddy, NSUInteger idx, BOOL * _Nonnull stop) {
            [sessionList addObject:[weakSelf dictFromBuddySearchResult:buddy]];
        }];
        
        [inter.searchedDiscusses enumerateObjectsUsingBlock:^(id discuss, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([discuss isKindOfClass:objc_getClass("Discuss")]) {
                [sessionList addObject:[weakSelf dictFromDiscussSearchResult:discuss searcherInter:inter]];
            } else if([discuss isKindOfClass:objc_getClass("Group")]) {
                [sessionList addObject:[weakSelf dictFromGroupSearchResult:discuss]];
            }
        }];
        
        [inter.searchedGroups enumerateObjectsUsingBlock:^(id group, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([group isKindOfClass:objc_getClass("Discuss")]) {
                [sessionList addObject:[weakSelf dictFromDiscussSearchResult:group searcherInter:inter]];
            } else if([group isKindOfClass:objc_getClass("Group")]) {
                [sessionList addObject:[weakSelf dictFromGroupSearchResult:group]];
            }
        }];
        
        return [GCDWebServerDataResponse responseWithJSONObject:sessionList];
    }];
}

- (NSMutableArray *)getRecentSessionList {
    NSMutableArray *sessionList = [NSMutableArray array];

    MQRecentSessionManager *manager = [objc_getClass("MQRecentSessionManager") sharedLogicEngine];
    NSArray *recentList = [manager getSessionIDList];
    GroupFolderManager *groupManager = [objc_getClass("GroupFolderManager") sharedFolderManager];
    BHProfileManager *profileManager = [objc_getClass("BHProfileManager") sharedInstance];
    BHDiscussGroupManager *discussgroupManager = [objc_getClass("BHDiscussGroupManager") sharedInstance];
    UnreadMsgMgr *unreadMsgMgr = [objc_getClass("UnreadMsgMgr") sharedUnreadMsgMgr];
    
    [recentList enumerateObjectsUsingBlock:^(MQSessionID *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        BHMessageModel *msgModel = [unreadMsgMgr getRecentModelFromSessionID:obj];
        NSString *subTitle = @"";
        if ((msgModel != 0x0) && ([msgModel chatType] != 0x4000)) {
            if ([msgModel msgType] != 0x4) {
                if ([msgModel chatType] != 0x10000) {
                    subTitle = [(NSMutableAttributedString *)[objc_getClass("MQRecentMsgTips") tipsOfContentMsg:msgModel sessionId:obj]  string];
                }
            }
        }
        
        if(obj.chatType == 2) {
            BHGroupModel *model = [groupManager BHGroupModelWithUin:obj.uinString];
            if (model && [model isKindOfClass:objc_getClass("BHGroupModel")]) {
                [sessionList addObject:[self dictFromBHGroupModel:model subTitle:subTitle]];
            }
        } else if (obj.chatType == 8) {
            DiscussGroupInfo *discuss = [discussgroupManager getGroupInfo:obj.uin];
            if (discuss && [discuss isKindOfClass:objc_getClass("DiscussGroupInfo")]) {
                [sessionList addObject:[self dictFromDiscussGroupInfo:discuss subTitle:subTitle]];
            }
        } else {
            BHProfileModel *profile = [profileManager getProfileWithUIN:obj.uinString];
            if (profile && [profile isKindOfClass:objc_getClass("BHProfileModel")]) {
                [sessionList addObject:[self dictFromBHProfileModel:profile subTitle:subTitle]];
            }
        }
    }];
    
    return sessionList;
}

- (void)addHandleForSearchUserChatLog {
    __weak typeof(self) weakSelf = self;
    [self.webServer addHandlerForMethod:@"GET" path:@"/qq-plugin/chatlog" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        NSString *userId = request.query ? request.query[@"userId"] ? request.query[@"userId"] : nil : nil;
        int sessionType = request.query ? request.query[@"type"] ? [request.query[@"type"] intValue] : 0 : 0;
        if (userId && sessionType != 0) {
            int chatType = 0;
            switch (sessionType) {
                case 1:         //  好友
                    chatType = 1;
                    break;
                case 101:       //  群
                    chatType = 2;
                    break;
                case 201:      //  讨论组
                    chatType = 8;
                    break;
            }
            
            __block BOOL hasResult = NO;
            NSMutableArray *chatLogList = [NSMutableArray array];
            TChatHistoryMsgManager *chatMgr = [objc_getClass("TChatHistoryMsgManager") sharedInstance];
            TChatHistoryMsgModelWrapper * wrap = [chatMgr getHistoryMsgModel:[userId longLongValue] sessType:sessionType filter:0];
            [wrap _loadMoreMessageUpForAllMsgType:^{
                [[[wrap.msgArray reverseObjectEnumerator] allObjects] enumerateObjectsUsingBlock:^(BHMessageModel *obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [chatLogList addObject:[weakSelf dictFromMessageModel:obj]];
                }];
                hasResult = YES;
            }];
            
            while (!hasResult) {}

            GroupFolderManager *groupManager = [objc_getClass("GroupFolderManager") sharedFolderManager];
            BHProfileManager *profileManager = [objc_getClass("BHProfileManager") sharedInstance];
            BHDiscussGroupManager *discussgroupManager = [objc_getClass("BHDiscussGroupManager") sharedInstance];
            NSString *title = @"";
            if(chatType == 2) {
                BHGroupModel *groupModel = [groupManager BHGroupModelWithUin:userId];
                if (groupModel && [groupModel isKindOfClass:objc_getClass("BHGroupModel")]) {
                    title = groupModel.groupName;
                    if (IS_VALID_STRING(groupModel.groupRemark)) {
                        title = [NSString stringWithFormat:@"%@ (%@)", groupModel.groupRemark, groupModel.groupName];
                    }
                }
            } else if (chatType == 8) {
                DiscussGroupInfo *discuss = [discussgroupManager getGroupInfo:[userId longLongValue]];
                if (discuss && [discuss isKindOfClass:objc_getClass("DiscussGroupInfo")]) {
                    title = discuss.name;
                }
            } else {
                BHProfileModel *profile = [profileManager getProfileWithUIN:userId];
                if (profile && [profile isKindOfClass:objc_getClass("BHProfileModel")]) {
                    title = profile.displayName;
                }
            }
            
            NSDictionary *toUserContactDict = @{@"title": [NSString stringWithFormat:@"To: %@", title],
                                                @"subTitle": chatLogList.count > 0 ? @"以下为聊天记录👇🏻" : @"",
                                                @"icon": [weakSelf avatarPathWithUIN:userId isUser:sessionType == 1],
                                                @"userId": userId,
                                                @"qlurl": [weakSelf avatarPathWithUIN:userId isUser:sessionType == 1]
                                                };
            [chatLogList insertObject:toUserContactDict atIndex:0];
            
            return [GCDWebServerDataResponse responseWithJSONObject:chatLogList];
        }
        
        return [GCDWebServerResponse responseWithStatusCode:404];
    }];
}

- (void)addHandleForOpenSession {
    [self.webServer addHandlerForMethod:@"POST" path:@"/QQ-plugin/open-session" requestClass:[GCDWebServerURLEncodedFormRequest class] processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerURLEncodedFormRequest * _Nonnull request) {
        NSDictionary *requestBody = [request arguments];
        
        if (requestBody && requestBody[@"userId"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                long long uin = [requestBody[@"userId"] longLongValue];
                int sessionType = [requestBody[@"type"] intValue];
                int chatType = 0;
                switch (sessionType) {
                    case 1:         //  好友
                        chatType = 1;
                        break;
                    case 101:       //  群
                        chatType = 2;
                        break;
                    case 201:      //  讨论组
                        chatType = 8;
                        break;
                }
                MQAIOManager *manager = [objc_getClass("MQAIOManager") sharedInstance];
                [manager showAIOOfUin:uin chatType:chatType bringToTop:YES];
                [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
            });
            return [GCDWebServerResponse responseWithStatusCode:200];
        }
        
        return [GCDWebServerResponse responseWithStatusCode:404];
    }];
}

- (void)addHandleForSendMsg {
    [self.webServer addHandlerForMethod:@"POST" path:@"/QQ-plugin/send-message" requestClass:[GCDWebServerURLEncodedFormRequest class] processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerURLEncodedFormRequest * _Nonnull request) {
        NSDictionary *requestBody = [request arguments];
        if (requestBody && requestBody[@"userId"] && requestBody[@"content"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                long long uin = [requestBody[@"userId"] longLongValue];
                int sessionType = [requestBody[@"type"] intValue];
                [TKMsgManager sendTextMessage:requestBody[@"content"] uin:uin sessionType:sessionType];
                
            });
            return [GCDWebServerResponse responseWithStatusCode:200];
        }
        return [GCDWebServerResponse responseWithStatusCode:404];
    }];
}

#pragma mark - 返回聊天记录的 dict
- (NSDictionary *)dictFromMessageModel:(BHMessageModel *)msgModel {
    NSString *title = @"[非文本信息]";
    MQSessionID *sessionID = [objc_getClass("MQSessionID") sessionIdWithChatType:msgModel.chatType andUin:[msgModel.uin longLongValue]];
    if ((msgModel != 0x0) && ([msgModel chatType] != 0x4000)) {
        if ([msgModel msgType] != 0x4) {
            if ([msgModel chatType] != 0x10000) {
                title = [(NSMutableAttributedString *)[objc_getClass("MQRecentMsgTips") tipsOfContentMsg:msgModel sessionId:sessionID]  string];
            }
        }
    }
    NSString *subTitle = [self getDateStringWithTimeStr:msgModel.time];
    NSArray *contentPartArray = [msgModel contentPartArray];
    __block NSString *qlurl = @"";
    BHMsgManager *msgMgr = [objc_getClass("BHMsgManager") sharedInstance];
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    
    [contentPartArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:objc_getClass("QQImageMsgContentPart")]) {
            qlurl = [msgMgr getImagePathByMsg:obj imageSize:0];
            if (![fileMgr fileExistsAtPath:qlurl]) {
                [msgMgr downloadImageByMsg:msgModel content:obj completion:nil ProgressBlock:nil];
            }
            *stop = YES;
        }
    }];
    if (msgModel.msgType == 181) {
         qlurl = [msgMgr getShortVideoPathByMsg:msgModel];
        if (![fileMgr fileExistsAtPath:qlurl]) {
            [objc_getClass("VideoMsgLoadManager") requsetVideoMsgVideo:msgModel completion:nil];
        } 
    }
   
    return @{@"title": title,
             @"subTitle": subTitle,
             @"icon": [self avatarPathWithUIN:msgModel.senderUin isUser:YES],
             @"userId": msgModel.uin,
             @"qlurl": qlurl
             };
}

#pragma mark - 返回搜索用户的 dict
- (NSDictionary *)dictFromBuddySearchResult:(Buddy *)buddy {
    NSString *uin = [buddy valueForKey:@"_uinStr"];
    BHFriendListManager *friendListManager = [buddy valueForKey:@"_friendListManager"];
    
    NSMutableDictionary *friendCache = [friendListManager valueForKey:@"_friendCache"];
    NSMutableDictionary *groupCache = [friendListManager valueForKey:@"_groupCache"];
    
    BHFriendModel *friendModel = friendCache[uin];
    NSString *title = friendModel.profileModel.nick;
    if (IS_VALID_STRING(friendModel.remark)) {
        title = [NSString stringWithFormat:@"%@(%@)",friendModel.remark, friendModel.profileModel.nick];
    }
    
    NSString *subTitle = [NSString stringWithFormat:@"[%@]",friendModel.uin];
    if (IS_VALID_STRING(friendModel.groupID) && groupCache[friendModel.groupID]) {
        BHFriendGroupModel *groupModel = groupCache[friendModel.groupID];
        subTitle = [NSString stringWithFormat:@"%@-[%@]",subTitle, groupModel.groupName];
    }
    
    if (IS_VALID_STRING(friendModel.showName)) {
        subTitle = [NSString stringWithFormat:@"%@-[%@]",subTitle, friendModel.showName];
    }
    
    return @{@"title": title,
             @"subTitle": subTitle,
             @"icon": [self avatarPathWithUIN:friendModel.uin isUser:YES],
             @"userId": friendModel.uin,
             @"type": @"1",
             };
}

- (NSDictionary *)dictFromDiscussSearchResult:(Discuss *)discuss searcherInter:(ContactSearcherInter *)inter {
    if ([discuss.className isEqualToString:@"Group"]) {
        return [self dictFromGroupSearchResult:(Group *)discuss];
    }
    
    NSString *uin = [discuss valueForKey:@"_uinStr"];
    DiscussGroupInfo *discussInfo = discuss.discussInfo;

    NSString *title = discussInfo.flag == 1 ? discussInfo.name : [discuss combinDiscussName];
    
    __block NSString *subTitle = @"";
    if (discuss.discussSearchType == 2) {
        BHDiscussGroupManager *groupManager = [objc_getClass("BHDiscussGroupManager") sharedInstance];
        
        [inter.searchedBuddys enumerateObjectsUsingBlock:^(Buddy * _Nonnull buddy, NSUInteger idx, BOOL * _Nonnull stop) {
            DiscussMemberInfo *member = [groupManager getDiscussMember:[discuss valueForKey:@"_uinStr"] memberUin:[[buddy valueForKey:@"_uinStr"] longLongValue]];
            if (member) {
                subTitle = [NSString stringWithFormat:@"包含：%@",member.remarkName];
            }
        }];
    } else {
        subTitle = [NSString stringWithFormat:@"共 %d 人",discussInfo.memberNum];
    }
    
    return @{@"title": [NSString stringWithFormat:@"[讨论组]%@", title],
             @"subTitle": subTitle,
             @"icon": [self avatarPathWithUIN:uin isUser:NO],
             @"userId": uin,
             @"type": @"201",
             };
}

- (NSDictionary *)dictFromGroupSearchResult:(Group *)group {
    return [self dictFromBHGroupModel:group.troopModel subTitle:nil];
}

#pragma mark - 返回最近聊天列表的 dict

/**
 返回好友的 dict

 @param profileModel 当前好友的model
 @param subTitle 该值为subTitle设置，空的话默认为QQ号，传值的话为一般为最新的聊天记录
 */
- (NSDictionary *)dictFromBHProfileModel:(BHProfileModel *)profileModel subTitle:(NSString *)subTitle {
    NSString *title = profileModel.displayName;
    return @{@"title": title,
             @"subTitle": subTitle ?: profileModel.uin,
             @"icon": [self avatarPathWithUIN:profileModel.uin isUser:YES],
             @"userId": profileModel.uin,
             @"type": @"1",
             };
}

- (NSDictionary *)dictFromDiscussGroupInfo:(DiscussGroupInfo *)discussInfo subTitle:(NSString *)subTitle {
    NSString *title = discussInfo.name;
    NSString *subText = subTitle ?: [NSString stringWithFormat:@"共 %d 人",discussInfo.memberNum];
    NSString *uin = [NSString stringWithFormat:@"%lld",discussInfo.groupUin];
    NSString *iconPath = [self avatarPathWithUIN:uin isUser:NO];
    NSFileManager *fileMgr = [NSFileManager defaultManager];
    
    if (![fileMgr fileExistsAtPath:iconPath]) {
        //        一般讨论组的头像没有保存到本地，如果本地没有的话，就保存下
        MQSessionID *sessionID = [objc_getClass("MQSessionID") sessionIdWithChatType:8 andUin:discussInfo.groupUin];
        NSImage *image = [objc_getClass("TXImageUtils") imageOfSession:sessionID];
        NSData *imageData = [image TIFFRepresentation];
        [imageData writeToFile:iconPath atomically:YES];
    }
    
    return @{@"title": [NSString stringWithFormat:@"[讨论组]%@", title],
             @"subTitle": subText,
             @"icon": iconPath,
             @"userId": uin,
             @"type": @"201",
             };
}

- (NSDictionary *)dictFromBHGroupModel:(BHGroupModel *)groupModel subTitle:(NSString *)subTitle {
    NSDictionary *dict = @{};
    if (groupModel) {
        NSString *title = groupModel.groupName;
        if (IS_VALID_STRING(groupModel.groupRemark)) {
            title = [NSString stringWithFormat:@"%@ (%@)", groupModel.groupRemark, groupModel.groupName];
        }
        
        dict = @{@"title": [NSString stringWithFormat:@"[群聊]%@", title],
                 @"subTitle": subTitle ?: [NSString stringWithFormat:@"共 %llu 人",groupModel.groupMemberCount],
                 @"icon": [self avatarPathWithUIN:groupModel.groupCode isUser:NO],
                 @"userId": groupModel.groupCode,
                 @"type": @"101",
                 };
    }
    return dict;
}

#pragma mark - Other
- (NSString *)getDateStringWithTimeStr:(NSTimeInterval)time{
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:time];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    if ([date isToday]) {
        formatter.dateFormat = @"HH:mm:ss";
        return [formatter stringFromDate:date];
    } else {
        if ([date isYesterday]) {
            formatter.dateFormat = @"昨天 HH:mm:ss";
            return [formatter stringFromDate:date];
        } else {
            formatter.dateFormat = @"yy-MM-dd HH:mm:ss";
            return [formatter stringFromDate:date];
        }
    }
    return @"";
}

//  获取本地图片缓存路径
- (NSString *)avatarPathWithUIN:(NSString *)uin isUser:(BOOL)isUser {
    BHAvatarManager *manager = [objc_getClass("BHAvatarManager") sharedInstance];
    NSString *imgPath;
    if (isUser) {
        imgPath = [manager userAvatarPathWithUIN:uin];
    } else {
        imgPath = [manager groupAvatarPathWithGroupCode:uin];
    }
    return imgPath ?: @"";
}

@end

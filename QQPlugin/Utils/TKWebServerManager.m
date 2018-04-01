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
        
        NSDictionary *keyword = request.query ? request.query[@"keyword"] ? request.query[@"keyword"] : @"" : @"";
        NSMutableArray *sessionList = [NSMutableArray array];
        
        ContactSearcherInter *inter = [[objc_getClass("ContactSearcherInter") alloc] init];
        [inter Query:keyword];
    
        [inter.searchedBuddys enumerateObjectsUsingBlock:^(Buddy * _Nonnull buddy, NSUInteger idx, BOOL * _Nonnull stop) {
            [sessionList addObject:[weakSelf dictFromBuddySearchResult:buddy]];
        }];
        
        [inter.searchedDiscusses enumerateObjectsUsingBlock:^(Discuss * _Nonnull discuss, NSUInteger idx, BOOL * _Nonnull stop) {
            [sessionList addObject:[weakSelf dictFromDiscussSearchResult:discuss searcherInter:inter]];
        }];
        
        [inter.searchedGroups enumerateObjectsUsingBlock:^(Group * _Nonnull group, NSUInteger idx, BOOL * _Nonnull stop) {
            [sessionList addObject:[weakSelf dictFromGroupSearchResult:group]];
        }];
        
        return [GCDWebServerDataResponse responseWithJSONObject:sessionList];
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
    NSDictionary *dict = @{};
    BHGroupModel *troopModel = group.troopModel;
    if (troopModel) {
        NSString *title = troopModel.groupName;
        if (IS_VALID_STRING(troopModel.groupRemark)) {
            title = [NSString stringWithFormat:@"%@ (%@)", troopModel.groupRemark, troopModel.groupName];
        }
        
        dict = @{@"title": [NSString stringWithFormat:@"[群聊]%@", title],
                 @"subTitle": [NSString stringWithFormat:@"共 %llu 人",troopModel.groupMemberCount],
                 @"icon": [self avatarPathWithUIN:troopModel.groupCode isUser:NO],
                 @"userId": troopModel.groupCode,
                 @"type": @"101",
                 };
    }
    return dict;
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

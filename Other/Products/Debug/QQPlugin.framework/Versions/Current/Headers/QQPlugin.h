//
//  QQPlugin.h
//  QQPlugin
//
//  Created by TK on 2018/3/18.
//  Copyright © 2018年 TK. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NSView+Action.h"
#import "NSButton+Action.h"
#import "NSTextField+Action.h"
#import "Color.h"
#import <objc/runtime.h>

#define IS_VALID_STRING(STR)          ((STR) && ![(STR) isEqualToString:@""])

struct _BHMessageSession {
    int _field1;
    unsigned long long _field2;
    unsigned long long _field3;
    unsigned long long _field4;
};

@class BHFriendListManager, DiscussGroupInfo, BHGroupModel;

#pragma mark - Model

@interface MQBaseElem : NSObject
{
    NSString *_uinStr;
}
@end

@interface Buddy : MQBaseElem
{
    BHFriendListManager *_friendListManager;
}
@end

@interface Discuss : MQBaseElem
@property(retain, nonatomic) DiscussGroupInfo *discussInfo;
@property(nonatomic) unsigned long long discussSearchType;
- (id)combinDiscussName;
@end

@interface Group : MQBaseElem
@property(retain, nonatomic) BHGroupModel *troopModel;
@end

@interface DiscussGroupInfo : NSObject
@property(retain, nonatomic) NSString *name;
@property(nonatomic) int flag;
@property(nonatomic) int memberNum;
@property(nonatomic) long long groupUin;
@end

@interface DiscussMemberInfo : NSObject
@property(retain, nonatomic) NSString *remarkName;
@end

@interface BHFriendGroupModel : NSObject
@property(copy, nonatomic) NSString *groupName; 
@end

@interface BHGroupModel : NSObject
@property(readonly, nonatomic) NSString *groupCode;
@property(readonly, nonatomic) NSString *displayName;
@property(copy, nonatomic) NSString *groupName;
@property(copy, nonatomic) NSString *groupRemark;
@property(nonatomic) unsigned long long groupMemberCount;
@end

@interface BHFontInfo : NSObject
@end

@interface BHMessageModel : NSObject
@property(nonatomic) unsigned int time;
@property(nonatomic) int msgID; 
@property(retain, nonatomic) NSString *groupCode;
@property(retain, nonatomic) NSString *discussGroupUin;
@property(readonly) BOOL isSelfSend;
@property(nonatomic) int msgSessionType;
@property(nonatomic) int msgType;
@property(retain, nonatomic) NSString *nickname;
@property(copy, nonatomic) NSString *smallContent;
@property(retain, nonatomic) NSString *uin;
@end

@interface BHProfileModel : NSObject
@property(copy, nonatomic) NSString *nick;
@end

@interface BHFriendModel : NSObject
@property(copy, nonatomic) NSString *remark;
@property(copy, nonatomic) NSString *uin;
@property(retain, nonatomic) BHProfileModel *profileModel;
@property(copy, nonatomic) NSString *groupID;
@property(copy, nonatomic) NSString *showName;
@end

@interface BHTipsMsgOption : NSObject
@property(nonatomic) BOOL addToDb;
@end

#pragma mark - ViewController
@interface MQAIOChatViewController : NSObject
- (void)revokeMessages:(id)arg1;
@end

#pragma mark - Controller
@interface MainMenuController : NSObject
+ (id)sharedInstance;
@end

@interface AppController : NSObject
- (void)notifyForceLogoutWithAccount:(id)arg1 type:(long long)arg2 tips:(id)arg3;
- (void)notifyLoginWithAccount:(id)arg1 resultCode:(long long)arg2 userInfo:(id)arg3;
@end

#pragma mark - Manager
@interface BHMsgManager : NSObject
+ (id)sharedInstance;
- (id)defaultFontInfo;
- (void)appendReceiveMessageModel:(id)arg1 msgSource:(long long)arg2;
- (void)addTipsMessage:(id)arg1 sessType:(int)arg2 uin:(id)arg3 option:(id)arg4;
- (id)sendMessagePacket:(id)arg1 target:(struct _BHMessageSession)arg2 completion:(id)arg3 ProgressBlock:(id)arg4;
@end

@interface MQAIOManager : NSObject
+ (id)sharedInstance;
- (void)showAIOOfUin:(unsigned long long)arg1 chatType:(int)arg2 bringToTop:(BOOL)arg3;
@end

@interface BHAvatarManager : NSObject
+ (id)sharedInstance;
- (id)userAvatarPathWithUIN:(id)arg1;
- (id)groupAvatarPathWithGroupCode:(id)arg1;
@end

@interface BHDiscussGroupManager : NSObject
+ (id)sharedInstance;
- (id)getDiscussMember:(id)arg1 memberUin:(long long)arg2;

@end

@interface BHFriendListManager : NSObject
{
    NSMutableDictionary *_friendCache;
    NSMutableDictionary *_groupCache;
}
- (id)getFriendModelByUin:(id)arg1;
@end

@interface BHGroupManager : NSObject
- (id)displayNameForGroupMemberWithGroupCode:(id)arg1 memberUin:(id)arg2;
@end

#pragma mark - Server
@interface MsgDbService : NSObject
- (void)updateQQMessageModel:(id)arg1 keyArray:(id)arg2;
- (id)getMessageWithUin:(long long)arg1 sessType:(int)arg2 msgIds:(id)arg3;
@end

#pragma mark - Other
@interface ContactSearcherInter : NSObject
@property(retain, nonatomic) NSMutableArray <Buddy *> *searchedBuddys;
@property(retain, nonatomic) NSMutableArray <Discuss *> *searchedDiscusses;
@property(retain, nonatomic) NSMutableArray <Group *> *searchedGroups;
- (void)Query:(id)arg1;
@end

@interface BHCompoundMessagePacket : NSObject
@property(readonly, nonatomic) int msgType;
@property(retain, nonatomic) BHFontInfo *fontInfo;
- (void)addText:(id)arg1;
- (id)initWithMessageType:(int)arg1;
@end

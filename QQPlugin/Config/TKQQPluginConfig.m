//
//  TKQQPluginConfig.m
//  QQPlugin
//
//  Created by TK on 2018/3/19.
//  Copyright © 2018年 TK. All rights reserved.
//

#import "TKQQPluginConfig.h"
#import "TKHelper.h"
#import "TKAutoReplyModel.h"

static NSString * const kTKPreventRevokeEnableKey = @"kTKPreventRevokeEnableKey";
static NSString * const kTKQQResourcesPath = @"/Applications/QQ.app/Contents/MacOS/QQPlugin.framework/Resources/";

@interface TKQQPluginConfig ()
@property (nonatomic, copy) NSString *autoReplyPlistFilePath;
@end

@implementation TKQQPluginConfig

+ (instancetype)sharedConfig {
    static TKQQPluginConfig *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        config = [[TKQQPluginConfig alloc] init];
    });
    return config;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _preventRevokeEnable = [[NSUserDefaults standardUserDefaults] boolForKey:kTKPreventRevokeEnableKey];
    }
    return self;
}

- (void)setPreventRevokeEnable:(BOOL)preventRevokeEnable {
    _preventRevokeEnable = preventRevokeEnable;
    [[NSUserDefaults standardUserDefaults] setBool:preventRevokeEnable forKey:kTKPreventRevokeEnableKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


#pragma mark - 自动回复
- (NSArray *)autoReplyModels {
    if (!_autoReplyModels) {
        _autoReplyModels = [self getModelsWithClass:[TKAutoReplyModel class] filePath:self.autoReplyPlistFilePath];
    }
    return _autoReplyModels;
}

- (void)saveAutoReplyModels {
    NSMutableArray *needSaveModels = [NSMutableArray array];
    [_autoReplyModels enumerateObjectsUsingBlock:^(TKAutoReplyModel *model, NSUInteger idx, BOOL * _Nonnull stop) {
        if (model.hasEmptyKeywordOrReplyContent) {
            model.enable = NO;
            model.enableGroupReply = NO;
        }
        model.replyContent = model.replyContent == nil ? @"" : model.replyContent;
        model.keyword = model.keyword == nil ? @"" : model.keyword;
        [needSaveModels addObject:model.dictionary];
    }];
    [needSaveModels writeToFile:self.autoReplyPlistFilePath atomically:YES];
}


- (NSString *)autoReplyPlistFilePath {
    if (!_autoReplyPlistFilePath) {
        _autoReplyPlistFilePath = [self getSandboxFilePathWithPlistName:@"TKAutoReplyModels.plist"];
    }
    return _autoReplyPlistFilePath;
}

#pragma mark - common
- (NSMutableArray *)getModelsWithClass:(Class)class filePath:(NSString *)filePath {
    NSArray *originModels = [NSArray arrayWithContentsOfFile:filePath];
    NSMutableArray *newModels = [NSMutableArray array];
    
    __weak Class weakClass = class;
    [originModels enumerateObjectsUsingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        TKAutoReplyModel *model = [[weakClass alloc] initWithDict:obj];
        [newModels addObject:model];
    }];
    return newModels;
}

- (NSString *)getSandboxFilePathWithPlistName:(NSString *)plistName {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *QQPluginDirectory = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"TKQQPlugin"];
    NSString *plistFilePath = [QQPluginDirectory stringByAppendingPathComponent:plistName];
    if ([manager fileExistsAtPath:plistFilePath]) {
        return plistFilePath;
    }
    
    [manager createDirectoryAtPath:QQPluginDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *resourcesFilePath = [kTKQQResourcesPath stringByAppendingString:plistName];
    if (![manager fileExistsAtPath:resourcesFilePath]) {
        return plistFilePath;
    }
    
    NSError *error = nil;
    [manager copyItemAtPath:resourcesFilePath toPath:plistFilePath error:&error];
    if (!error) {
        return plistFilePath;
    }
    return resourcesFilePath;
}

@end

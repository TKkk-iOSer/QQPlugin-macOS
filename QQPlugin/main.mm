//
//  main.m
//  QQPlugin
//
//  Created by TK on 2018/3/18.
//  Copyright © 2018年 TK. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QQ+hook.h"

static void __attribute__((constructor)) initialize(void) {
    NSLog(@"++++++++ QQ loaded ++++++++");
    [NSObject hookQQ];
}

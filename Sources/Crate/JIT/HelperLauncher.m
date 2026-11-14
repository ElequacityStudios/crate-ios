// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#import "HelperLauncher.h"

#include <dlfcn.h>

/* No public API starts an app's own classic extension, so this uses
   NSExtension's private calls, the ones LiveContainer and other built-in JIT
   enablers use: look the extension up by bundle ID (which survives a
   sideloader renaming the app), begin a request with input items, and take the
   reply in the completion block. */
@interface NSObject (CrateNSExtension)
+ (nullable id)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *_Nullable))completion;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *_Nullable))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block;
@end

/* Each NSExtension is kept until its request ends: released mid-request, it
   drops it. */
static NSMutableArray *liveExtensions;

void crate_helper_request(NSDictionary *request,
                          void (^done)(NSDictionary *_Nullable reply, NSString *_Nullable failure)) {
    NSURL *url = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"CrateJITHelper.appex"];
    NSString *identifier = [NSBundle bundleWithURL:url].bundleIdentifier;
    if (!identifier) {
        done(nil, @"crate's JIT helper is missing from the app.");
        return;
    }
    Class extensionClass = NSClassFromString(@"NSExtension");
    if (!extensionClass) {
        dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
        extensionClass = NSClassFromString(@"NSExtension");
    }
    if (!extensionClass) {
        done(nil, @"iOS has no way to start crate's JIT helper.");
        return;
    }
    NSError *error = nil;
    id extension = [extensionClass extensionWithIdentifier:identifier error:&error];
    if (!extension) {
        done(nil, [NSString stringWithFormat:@"iOS wouldn't find crate's JIT helper (%@).",
                   error.localizedDescription ?: @"no reason given"]);
        return;
    }
    @synchronized (NSMutableArray.class) {
        if (!liveExtensions) liveExtensions = [NSMutableArray array];
        [liveExtensions addObject:extension];
    }

    // Exactly one of the blocks below answers, whichever comes first.
    NSObject *lock = [NSObject new];
    __block BOOL answered = NO;
    void (^finish)(NSDictionary *, NSString *) = ^(NSDictionary *reply, NSString *failure) {
        @synchronized (lock) {
            if (answered) return;
            answered = YES;
        }
        @synchronized (NSMutableArray.class) {
            [liveExtensions removeObject:extension];
        }
        done(reply, failure);
    };
    [extension setRequestCompletionBlock:^(NSUUID *requestID, NSArray *items) {
        NSExtensionItem *item = items.firstObject;
        NSDictionary *reply = [item isKindOfClass:NSExtensionItem.class] ? (NSDictionary *)item.userInfo : nil;
        finish(reply ?: @{}, nil);
    }];
    [extension setRequestCancellationBlock:^(NSUUID *requestID, NSError *cancelError) {
        finish(nil, [NSString stringWithFormat:@"The JIT helper was cancelled (%@).",
                     cancelError.localizedDescription ?: @"no reason given"]);
    }];
    [extension setRequestInterruptionBlock:^(NSUUID *requestID) {
        finish(nil, @"The JIT helper stopped before it answered.");
    }];

    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = request;
    [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *requestID) {
        if (!requestID) finish(nil, @"iOS wouldn't start crate's JIT helper.");
    }];
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Starts crate's JIT helper extension (PlugIns/CrateJITHelper.appex) with
   `request` as its input item's userInfo, and calls `done` once: with the
   reply item's userInfo, or with nil and why there wasn't one. `done` may run
   on any thread. See CrateJITHelper.swift for what goes in and comes out. */
void crate_helper_request(NSDictionary *request,
                          void (^done)(NSDictionary *_Nullable reply, NSString *_Nullable failure));

NS_ASSUME_NONNULL_END

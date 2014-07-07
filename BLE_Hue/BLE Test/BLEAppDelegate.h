//
//  BLEAppDelegate.h
//  Adafruit Bluefruit LE Connect
//
//  Copyright (c) 2013 Adafruit Industries. All rights reserved.
//

#define UIAppDelegate  ((BLEAppDelegate *)[[UIApplication sharedApplication] delegate])

#import <UIKit/UIKit.h>

#import "PHBridgeSelectionViewController.h"
#import "PHBridgePushLinkViewController.h"
#import <HueSDK_iOS/HueSDK.h>

@class BLEMainViewController;
@class PHHueSDK;

@interface BLEAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (strong, nonatomic) UINavigationController *navigationController;

@property (strong, nonatomic) BLEMainViewController *mainViewController;

@property (strong, nonatomic) PHHueSDK *phHueSDK;

#pragma mark - HueSDK

/**
 Starts the local heartbeat
 */
- (void)enableLocalHeartbeat;

/**
 Stops the local heartbeat
 */
- (void)disableLocalHeartbeat;

/**
 Starts a search for a bridge
 */
- (void)searchForBridgeLocal;

@end

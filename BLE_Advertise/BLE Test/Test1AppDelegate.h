//
//  Test1AppDelegate.h
//  Test
//
//  Created by LiangLi on 6/21/14.
//
//

#import <UIKit/UIKit.h>

#import <AVFoundation/AVAudioPlayer.h>

@interface Test1AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property AVAudioPlayer *appSoundPlayer;

@property NSURL *soundFileURL;

@end

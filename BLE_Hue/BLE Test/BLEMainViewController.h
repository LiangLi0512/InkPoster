//
//  BLEMainViewController.h
//  Adafruit Bluefruit LE Connect
//
//  Copyright (c) 2013 Adafruit Industries. All rights reserved.
//

#import <CoreBluetooth/CoreBluetooth.h>
#import "UARTPeripheral.h"
#import "HelpViewController.h"
#import "PinIOViewController.h"
#import "UARTViewController.h"
#import <AVFoundation/AVAudioPlayer.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVAudioSession.h>


@interface BLEMainViewController : UIViewController <UINavigationControllerDelegate, HelpViewControllerDelegate, CBCentralManagerDelegate, UARTPeripheralDelegate, UARTViewControllerDelegate, PinIOViewControllerDelegate, MPMediaPickerControllerDelegate> {
    MPMusicPlayerController *musicPlayer;
}

typedef enum {
    ConnectionModeNone  = 0,
    ConnectionModePinIO,
    ConnectionModeUART,
} ConnectionMode;

typedef enum {
    ConnectionStatusDisconnected = 0,
    ConnectionStatusScanning,
    ConnectionStatusConnected,
} ConnectionStatus;

@property (nonatomic, assign) ConnectionMode                    connectionMode;
@property (nonatomic, assign) ConnectionStatus                  connectionStatus;
@property (strong, nonatomic) UIPopoverController               *helpPopoverController;
@property (strong, nonatomic) IBOutlet PinIOViewController      *pinIoViewController;
@property (strong, nonatomic) IBOutlet UARTViewController       *uartViewController;
@property (strong, nonatomic) IBOutlet UIButton                 *pinIoButton;
@property (strong, nonatomic) IBOutlet UIButton                 *uartButton;
@property (strong, nonatomic) IBOutlet UIButton                 *infoButton;
@property (strong, nonatomic) IBOutlet UINavigationController   *navController;
@property (strong, nonatomic) IBOutlet UIViewController         *menuViewController;
@property (strong, nonatomic) IBOutlet HelpViewController       *helpViewController;
@property (strong, nonatomic) IBOutlet UIView                   *helpView;
@property (strong, nonatomic) IBOutlet UIImageView              *logo;
@property (weak, nonatomic) IBOutlet UIButton *playPauseButton;

@property (nonatomic, retain) MPMusicPlayerController *musicPlayer;

- (IBAction)showInfo:(id)sender;
- (IBAction)buttonTapped:(UIButton*)sender;
- (void)helpViewControllerDidFinish:(HelpViewController*)controller;
- (IBAction)playPause:(id)sender;
- (IBAction)previousSong:(id)sender;
- (IBAction)nextSong:(id)sender;

extern const int PLAY_MUSCI_SIGNAL;
extern const int LEFT_PICK_SIGNAL;
extern const int MIDDLE_PICK_SIGNAL;
extern const int RIGHT_PICK_SIGNAL;


@end


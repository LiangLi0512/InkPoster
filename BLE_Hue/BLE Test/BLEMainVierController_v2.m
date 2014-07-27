//
//  BLEMainVierController_v2.m
//  Adafruit Bluefruit LE Connect
//
//  Created by LiangLi on 7/23/14.
//  Copyright (c) 2014 Adafruit Industries. All rights reserved.
//

#import "BLEMainViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "NSString+hex.h"
#import "NSData+hex.h"
#import <AVFoundation/AVAudioSession.h>
#import "PHControlLightsViewController.h"
#import "BLEAppDelegate.h"

#import <HueSDK_iOS/HueSDK.h>

#define MAX_HUE 65535
#define MAX_BRIGHTNESS 254
#define CONNECTING_TEXT @"Connecting…"
#define DISCONNECTING_TEXT @"Disconnecting…"
#define DISCONNECT_TEXT @"Disconnect"
#define CONNECT_TEXT @"Connect"

#define SWITCH_MUSIC_INTERVAL 2.0
#define SWITCH_RESET_INTERVAL 2.0
const int PLAY_MUSCI_SIGNAL = 1;

const int LEFT_UPPER_SIGNAL = 100;
const int UPPER_SIGNAL = 101;
const int RIGHT_UPPER_SIGNAL = 102;
const int LEFT_SIGNAL = 103;
const int MIDDLE_SIGNAL = 104;
const int RIGHT_SIGNAL = 105;
const int LEFT_LOWER_SIGNAL = 106;
const int LOWER_SIGNAL = 107;
const int RIGHT_LOWER_SIGNAL = 108;

const int LEFT_PICK_SIGNAL = 10;
const int MIDDLE_PICK_SIGNAL = 11;
const int RIGHT_PICK_SIGNAL = 12;
const int START_HUE = 20;


@interface BLEMainViewController ()<UIAlertViewDelegate>{
    
    CBCentralManager    *cm;
    UIAlertView         *currentAlertView;
    UARTPeripheral      *currentPeripheral;
    UIBarButtonItem     *infoBarButton;
    
}

@end


@implementation BLEMainViewController

@synthesize musicPlayer;

#pragma mark - View Lifecycle


- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil{
    
    //Separate NIBs for iPhone 3.5", iPhone 4", & iPad
    
    NSString *nibName;
    
    if (IS_IPHONE_4){
        nibName = @"BLEMainViewController_iPhone";
    }
    else if (IS_IPHONE_5){
        nibName = @"BLEMainViewController_iPhone568px";
    }
    else{
        nibName = @"BLEMainViewController_iPad";
    }
    
    self = [super initWithNibName:nibName bundle:[NSBundle mainBundle]];
    if (self) {
        // Custom initialization
    }
    return self;
}


- (void)viewDidLoad{
    
    [super viewDidLoad];
    
    musicPlayer = [MPMusicPlayerController iPodMusicPlayer];
    
    //[_volumeSlider setValue:[musicPlayer volume]];
    
    
    [self.view setAutoresizesSubviews:YES];
    
    [self addChildViewController:self.navController];
    
    [self.view addSubview:self.navController.view];
	
    //disable navcontroller's swiping feature
    self.navController.interactivePopGestureRecognizer.enabled = NO;
    
    cm = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    _connectionMode = ConnectionModeNone;
    _connectionStatus = ConnectionStatusDisconnected;
    currentAlertView = nil;
    
    //add info bar button to mode controllers
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject: _infoButton];
    UIButton *buttonCopy = [NSKeyedUnarchiver unarchiveObjectWithData: archivedData];
    [buttonCopy addTarget:self action:@selector(showInfo:) forControlEvents:UIControlEventTouchUpInside];
    infoBarButton = [[UIBarButtonItem alloc]initWithCustomView:buttonCopy];
    
    touchedLeft = false;
    touchedMiddle = false;
    touchedRight = false;
    touchLeftTime = 0.0;
    touchMiddleTime = 0.0;
    touchRightTime = 0.0;
    
}


- (void)didReceiveMemoryWarning{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)viewDidUnload{
    
    [super viewDidUnload];
}


#pragma mark - Root UI


- (void)helpViewControllerDidFinish:(HelpViewController*)controller{
    
    //Called when help view's done button is tapped
    
    if (IS_IPHONE) {
        
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
    else {
        
        [self.helpPopoverController dismissPopoverAnimated:YES];
    }
    
}


- (HelpViewController*)currentHelpViewController{
    
    //Determine which help view to show based on the current view shown
    
    HelpViewController *hvc;
    
    if ([_navController.topViewController isKindOfClass:[PinIOViewController class]])
        hvc = _pinIoViewController.helpViewController;
    
    else if ([_navController.topViewController isKindOfClass:[UARTViewController class]])
        hvc = _uartViewController.helpViewController;
    
    else
        hvc = self.helpViewController;
    
    return hvc;
}


- (IBAction)showInfo:(id)sender{
    
    // Show help info view on iPhone via flip transition, called via "i" button in navbar
    
    if (IS_IPHONE) {
        
        [self presentViewController:[self currentHelpViewController] animated:YES completion:nil];
    }
    
    //iPad
    else if (IS_IPAD) {
        
        //close popover it is being shown
        if (_helpPopoverController != nil && [self.helpPopoverController isPopoverVisible]) {
            [self.helpPopoverController dismissPopoverAnimated:YES];
            self.helpPopoverController = nil;
        }
        
        //show popover if it isn't shown
        else {
            self.helpPopoverController = [[UIPopoverController alloc]initWithContentViewController:[self currentHelpViewController]];
            self.helpPopoverController.backgroundColor = [UIColor darkGrayColor];
            
            CGRect aFrame = [[[_navController.navigationBar.items lastObject] rightBarButtonItem] customView].frame;
            [self.helpPopoverController presentPopoverFromRect:aFrame
                                                        inView:[[[_navController.navigationBar.items lastObject] rightBarButtonItem] customView].superview
                                      permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        }
    }
}


- (IBAction)buttonTapped:(UIButton*)sender{
    
    //Called by Pin I/O or UART Monitor connect buttons
    
    if (currentAlertView != nil && currentAlertView.isVisible) {
        NSLog(@"ALERT VIEW ALREADY SHOWN");
        return;
    }
    
    if ([sender isEqual:self.pinIoButton]) {    //Pin I/O
        NSLog(@"Starting Pin I/O Mode …");
        _connectionMode = ConnectionModePinIO;
        
    }
    else if ([sender isEqual:self.uartButton]){ //UART
        NSLog(@"Starting UART Mode …");
        _connectionMode = ConnectionModeUART;
    }
    
    _connectionStatus = ConnectionStatusScanning;
    
    [self enableConnectionButtons:NO];
    
    [self scanForPeripherals];
    
    currentAlertView = [[UIAlertView alloc]initWithTitle:@"Scanning …"
                                                 message:nil
                                                delegate:self
                                       cancelButtonTitle:@"Cancel"
                                       otherButtonTitles:nil];
    
    [currentAlertView show];
    
}


- (void)scanForPeripherals{
    
    //Look for available Bluetooth LE devices
    
    //skip scanning if UART is already connected
    NSArray *connectedPeripherals = [cm retrieveConnectedPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]];
    if ([connectedPeripherals count] > 0) {
        //connect to first peripheral in array
        [self connectPeripheral:[connectedPeripherals objectAtIndex:0]];
    }
    
    else{
        
        [cm scanForPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]
                                   options:@{CBCentralManagerScanOptionAllowDuplicatesKey: [NSNumber numberWithBool:NO]}];
    }
    
}


- (void)connectPeripheral:(CBPeripheral*)peripheral{
    
    //Connect Bluetooth LE device
    
    //Clear off any pending connections
    [cm cancelPeripheralConnection:peripheral];
    
    //Connect
    currentPeripheral = [[UARTPeripheral alloc] initWithPeripheral:peripheral delegate:self];
    [cm connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: [NSNumber numberWithBool:YES]}];
    
}


- (void)disconnect{
    
    //Disconnect Bluetooth LE device
    
    _connectionStatus = ConnectionStatusDisconnected;
    _connectionMode = ConnectionModeNone;
    
    [cm cancelPeripheralConnection:currentPeripheral.peripheral];
    
}


- (void)enableConnectionButtons:(BOOL)enabled{
    
    _uartButton.enabled = enabled;
    _pinIoButton.enabled = enabled;
}


- (void)enableConnectionButtons{
    
    [self enableConnectionButtons:YES];
}


#pragma mark UIAlertView delegate methods


- (void)alertView:(UIAlertView*)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
    
    //the only button in our alert views is cancel, no need to check button index
    
    if (_connectionStatus == ConnectionStatusConnected) {
        [self disconnect];
    }
    else if (_connectionStatus == ConnectionStatusScanning){
        [cm stopScan];
    }
    
    _connectionStatus = ConnectionStatusDisconnected;
    _connectionMode = ConnectionModeNone;
    
    currentAlertView = nil;
    
    [self enableConnectionButtons:YES];
    
    //alert dismisses automatically @ return
    
}


#pragma mark Navigation Controller delegate methods


- (void)navigationController:(UINavigationController*)navigationController willShowViewController:(UIViewController*)viewController animated:(BOOL)animated{
    
    //disconnect when returning to main view
    if (_connectionStatus == ConnectionStatusConnected && [viewController isEqual:_menuViewController]) {
        [self disconnect];
        
        //dismiss UART keyboard
        [_uartViewController.inputField resignFirstResponder];
    }
    
}


#pragma mark CBCentralManagerDelegate


- (void) centralManagerDidUpdateState:(CBCentralManager*)central{
    
    if (central.state == CBCentralManagerStatePoweredOn){
        
        //respond to powered on
    }
    
    else if (central.state == CBCentralManagerStatePoweredOff){
        
        //respond to powered off
    }
    
}


- (void) centralManager:(CBCentralManager*)central didDiscoverPeripheral:(CBPeripheral*)peripheral advertisementData:(NSDictionary*)advertisementData RSSI:(NSNumber*)RSSI{
    
    NSLog(@"Did discover peripheral %@", peripheral.name);
    
    [cm stopScan];
    
    [self connectPeripheral:peripheral];
}


- (void) centralManager:(CBCentralManager*)central didConnectPeripheral:(CBPeripheral*)peripheral{
    
    if ([currentPeripheral.peripheral isEqual:peripheral]){
        
        if(peripheral.services){
            NSLog(@"Did connect to existing peripheral %@", peripheral.name);
            [currentPeripheral peripheral:peripheral didDiscoverServices:nil]; //already discovered services, DO NOT re-discover. Just pass along the peripheral.
        }
        
        else{
            NSLog(@"Did connect peripheral %@", peripheral.name);
            [currentPeripheral didConnect];
        }
    }
}


- (void) centralManager:(CBCentralManager*)central didDisconnectPeripheral:(CBPeripheral*)peripheral error:(NSError*)error{
    
    NSLog(@"Did disconnect peripheral %@", peripheral.name);
    
    //respond to disconnected
    [self peripheralDidDisconnect];
    
    if ([currentPeripheral.peripheral isEqual:peripheral])
    {
        [currentPeripheral didDisconnect];
    }
}


#pragma mark UARTPeripheralDelegate


- (void)didReadHardwareRevisionString:(NSString*)string{
    
    //Once hardware revision string is read, connection to Bluefruit is complete
    
    NSLog(@"HW Revision: %@", string);
    
    //Bail if we aren't in the process of connecting
    if (currentAlertView == nil){
        return;
    }
    
    _connectionStatus = ConnectionStatusConnected;
    
    //Load appropriate view controller …
    
    //Pin I/O mode
    if (_connectionMode == ConnectionModePinIO) {
        self.pinIoViewController = [[PinIOViewController alloc]initWithDelegate:self];
        _pinIoViewController.navigationItem.rightBarButtonItem = infoBarButton;
        [_pinIoViewController didConnect];
    }
    
    //UART mode
    else if (_connectionMode == ConnectionModeUART){
        self.uartViewController = [[UARTViewController alloc]initWithDelegate:self];
        _uartViewController.navigationItem.rightBarButtonItem = infoBarButton;
        [_uartViewController didConnect];
    }
    
    //Dismiss Alert view & update main view
    [currentAlertView dismissWithClickedButtonIndex:-1 animated:NO];
    
    //Push appropriate viewcontroller onto the navcontroller
    UIViewController *vc = nil;
    
    if (_connectionMode == ConnectionModePinIO)
        vc = _pinIoViewController;
    
    else if (_connectionMode == ConnectionModeUART)
        vc = _uartViewController;
    
    if (vc != nil){
        [_navController pushViewController:vc animated:YES];
    }
    
    else
        NSLog(@"CONNECTED WITH NO CONNECTION MODE SET!");
    
    currentAlertView = nil;
    
    
}


- (void)uartDidEncounterError:(NSString*)error{
    
    //Dismiss "scanning …" alert view if shown
    if (currentAlertView != nil) {
        [currentAlertView dismissWithClickedButtonIndex:0 animated:NO];
    }
    
    //Display error alert
    UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"Error"
                                                   message:error
                                                  delegate:nil
                                         cancelButtonTitle:@"OK"
                                         otherButtonTitles:nil];
    
    [alert show];
    
}

int last_value = 0;
int sig_flag = 0;
int touchCount = 0;
int bri = 0;
bool possible_next1 = false;
bool possible_next2 = false;
bool possible_previous1 = false;
bool possible_previous2 = false;

bool touchedLeft = false;
bool touchedMiddle = false;
bool touchedRight = false;
NSTimeInterval touchLeftTime = 0.0;
NSTimeInterval touchMiddleTime = 0.0;
NSTimeInterval touchRightTime = 0.0;


- (void)didReceiveData:(NSData*)newData{
    
    //Data incoming from UART peripheral, forward to current view controller
    
    //Debug
    //    NSString *hexString = [newData hexRepresentationWithSpaces:YES];
    //    NSLog(@"Received: %@", newData);
    
    if (_connectionStatus == ConnectionStatusConnected || _connectionStatus == ConnectionStatusScanning) {
        //UART
        if (_connectionMode == ConnectionModeUART) {
            //send data to UART Controller
            [_uartViewController receiveData:newData];
            /*
             //Convert NSData into int, reference UARTViewController
             NSInteger intValue;
             [newData getBytes:&intValue length:sizeof(intValue)];
             */
            //int value =(int)intValue;
            int value = *(int*)([newData bytes]);
            //int value = CFSwapInt32BigToHost(*(int*)([newData bytes]));
            NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
            NSLog(@"value = %i", value);
            
            // by Lei:   Hue
            
            if (START_HUE == value) {
                bri=MIN(touchCount,254);
                NSLog(@"bri = %i", bri);
                PHBridgeResourcesCache *cache = [PHBridgeResourcesReader readBridgeResourcesCache];
                id<PHBridgeSendAPI> bridgeSendAPI = [[[PHOverallFactory alloc] init] bridgeSendAPI];
                
                for (PHLight *light in cache.lights.allValues) {
                    
                    PHLightState *lightState = [[PHLightState alloc] init];
                    
                    //[lightState setHue:[NSNumber numberWithInt:arc4random() % MAX_HUE]];
                    //[lightState setHue:[NSNumber numberWithInt:(int)value/360.0*MAX_HUE]];
                    [lightState setHue:[NSNumber numberWithInt:(int)320/360.0*65535]];
                    [lightState setBrightness:[NSNumber numberWithInt:254-bri]];
                    [lightState setSaturation:[NSNumber numberWithInt:254]];
                    
                    // Send lightstate to light
                    [bridgeSendAPI updateLightStateForId:light.identifier withLighState:lightState completionHandler:^(NSArray *errors) {
                        if (errors != nil) {
                            NSString *message = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Errors", @""), errors != nil ? errors : NSLocalizedString(@"none", @"")];
                            
                            NSLog(@"Response: %@",message);
                        }
                        
                        //[self.randomLightsButton setEnabled:YES];
                    }];
                }
                touchCount+=20;
            }
            
            // Play / Pause
            // by Liang: Too simple, add a tool to filter out the noise.
            
            if (PLAY_MUSCI_SIGNAL == value) {
                //[musicPlayer play];
                //[self playPause];
                if ([musicPlayer playbackState] == MPMusicPlaybackStatePlaying) {
                    [musicPlayer pause];
                    
                } else {
                    [musicPlayer play];
                }
            }
            /*
             // Next song
             if (value == 825229312) {
             possible_next1 = true;
             }
             if (possible_next1 ==true && value == 825294848) {
             possible_next2 = true;
             }
             if (possible_next2 == true && value == 825360384) {
             [musicPlayer skipToNextItem];
             possible_next1 = false;
             possible_next2 = false;
             possible_previous1 = false;
             possible_previous2 = false;
             }
             
             // Previous song
             if (value == 825360384) {
             possible_previous1 = true;
             }
             if (possible_previous1 == true && value == 825294848) {
             possible_previous2 = true;
             }
             if (possible_previous2 == true && value == 825229312) {
             [musicPlayer skipToPreviousItem];
             possible_previous1 = false;
             possible_previous2 = false;
             possible_next1 = false;
             possible_next2 = false;
             }
             */
            //last_value=value;
            
            if (currentTime - touchLeftTime > SWITCH_RESET_INTERVAL) {
                touchedLeft = false;
            }
            else if (currentTime - touchMiddleTime > SWITCH_RESET_INTERVAL) {
                touchedMiddle = false;
            }
            else if (currentTime - touchRightTime > SWITCH_RESET_INTERVAL) {
                touchedRight = false;
            }
            
            if (LEFT_UPPER_SIGNAL == value || LEFT_SIGNAL == value || LEFT_LOWER_SIGNAL == value) {
                touchLeftTime = currentTime;
                touchedLeft = true;
            }
            else if (UPPER_SIGNAL == value || MIDDLE_SIGNAL == value || LOWER_SIGNAL == value) {
                touchMiddleTime = currentTime;
                touchedMiddle = true;
                /* Hue:
                 PHBridgeResourcesCache *cache = [PHBridgeResourcesReader readBridgeResourcesCache];
                 id<PHBridgeSendAPI> bridgeSendAPI = [[[PHOverallFactory alloc] init] bridgeSendAPI];
                 
                 for (PHLight *light in cache.lights.allValues) {
                 
                 PHLightState *lightState = [[PHLightState alloc] init];
                 
                 [lightState setHue:[NSNumber numberWithInt:arc4random() % MAX_HUE]];
                 [lightState setBrightness:[NSNumber numberWithInt:254]];
                 [lightState setSaturation:[NSNumber numberWithInt:254]];
                 
                 // Send lightstate to light
                 [bridgeSendAPI updateLightStateForId:light.identifier withLighState:lightState completionHandler:^(NSArray *errors) {
                 if (errors != nil) {
                 NSString *message = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Errors", @""), errors != nil ? errors : NSLocalizedString(@"none", @"")];
                 
                 NSLog(@"Response: %@",message);
                 }
                 }];
                 }
                 /////////////////////*/
            }
            else if (RIGHT_UPPER_SIGNAL == value || RIGHT_SIGNAL == value || RIGHT_LOWER_SIGNAL == value) {
                touchRightTime = currentTime;
                touchedRight = true;
            }
            //NSLog(@"touchRightTime = %f", touchRightTime);
            //NSLog(@"touchMiddleTime = %f", touchMiddleTime);
            //NSLog(@"touchLeftTime = %f", touchLeftTime);
            //NSLog(@"touchedRight = %i", touchedRight);
            //NSLog(@"touchedMiddle = %i", touchedMiddle);
            //NSLog(@"touchedLeft = %i", touchedLeft);
            if (touchedLeft && touchedMiddle && touchedRight) {
                if (touchMiddleTime - touchLeftTime > 0.0
                    &&touchMiddleTime - touchLeftTime < SWITCH_MUSIC_INTERVAL
                    //&& touchRightTime - touchMiddleTime > 0.0
                    && touchRightTime - touchMiddleTime < SWITCH_MUSIC_INTERVAL) {
                    [musicPlayer skipToNextItem];
                }
                
                else if (touchMiddleTime - touchRightTime > 0.0
                         &&touchMiddleTime - touchMiddleTime < SWITCH_MUSIC_INTERVAL
                         //&& touchLeftTime - touchMiddleTime > 0.0
                         && touchLeftTime - touchMiddleTime < SWITCH_MUSIC_INTERVAL)
                    [musicPlayer skipToPreviousItem];
                
                touchedLeft = false;
                touchedMiddle = false;
                touchedRight = false;
            }
            
        }
        
        //Pin I/O
        else if (_connectionMode == ConnectionModePinIO){
            //send data to PIN IO Controller
            [_pinIoViewController receiveData:newData];
        }
    }
}


- (void)peripheralDidDisconnect{
    
    //respond to device disconnecting
    
    //if we were in the process of scanning/connecting, dismiss alert
    if (currentAlertView != nil) {
        [self uartDidEncounterError:@"Peripheral disconnected"];
    }
    
    //if status was connected, then disconnect was unexpected by the user, show alert
    UIViewController *topVC = [_navController topViewController];
    if ((_connectionStatus == ConnectionStatusConnected) &&
        ([topVC isMemberOfClass:[PinIOViewController class]] ||
         [topVC isMemberOfClass:[UARTViewController class]])) {
            
            //return to main view
            [_navController popToRootViewControllerAnimated:YES];
            
            //display disconnect alert
            UIAlertView *alert = [[UIAlertView alloc]initWithTitle:@"Disconnected"
                                                           message:@"BLE peripheral has disconnected"
                                                          delegate:nil
                                                 cancelButtonTitle:@"OK"
                                                 otherButtonTitles: nil];
            
            [alert show];
        }
    
    _connectionStatus = ConnectionStatusDisconnected;
    _connectionMode = ConnectionModeNone;
    
    //dereference mode controllers
    self.pinIoViewController = nil;
    self.uartViewController = nil;
    
    //make reconnection available after short delay
    [self performSelector:@selector(enableConnectionButtons) withObject:nil afterDelay:1.0f];
    
}


- (void)alertBluetoothPowerOff{
    
    //Respond to system's bluetooth disabled
    
    NSString *title     = @"Bluetooth Power";
    NSString *message   = @"You must turn on Bluetooth in Settings in order to connect to a device";
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
}


- (void)alertFailedConnection{
    
    //Respond to unsuccessful connection
    
    NSString *title     = @"Unable to connect";
    NSString *message   = @"Please check power & wiring,\nthen reset your Arduino";
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
    
}


#pragma mark UartViewControllerDelegate / PinIOViewControllerDelegate


- (void)sendData:(NSData*)newData{
    
    //Output data to UART peripheral
    
    NSString *hexString = [newData hexRepresentationWithSpaces:YES];
    NSLog(@"Sending: %@", hexString);
    
    [currentPeripheral writeRawData:newData];
    
}


- (IBAction)playPause:(id)sender {
    if ([musicPlayer playbackState] == MPMusicPlaybackStatePlaying) {
        [musicPlayer pause];
        
    } else {
        [musicPlayer play];
        
    }
    
    UIView *myVolumeView = [[UIView alloc] initWithFrame:CGRectMake(30, 500, 260, 20)];
    myVolumeView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:myVolumeView];
    
    MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame: myVolumeView.bounds];
    [myVolumeView addSubview:volumeView];
}

- (IBAction)previousSong:(id)sender {
    [musicPlayer skipToPreviousItem];
}

- (IBAction)nextSong:(id)sender {
    [musicPlayer skipToNextItem];
}

@end

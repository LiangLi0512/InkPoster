//
//  BLEMainViewController.m
//  Adafruit Bluefruit LE Connect
//
//  Copyright (c) 2013 Adafruit Industries. All rights reserved.
//

#import "BLEMainViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "NSString+hex.h"
#import "NSData+hex.h"
#import <AVFoundation/AVAudioSession.h>
#import "PHControlLightsViewController.h"
#import "BLEAppDelegate.h"

#import <HueSDK_iOS/HueSDK.h>

#define MAX_HUE 65535.0
#define MAX_BRI 254.0
#define MAX_SAT 254.0
#define CONNECTING_TEXT @"Connecting…"
#define DISCONNECTING_TEXT @"Disconnecting…"
#define DISCONNECT_TEXT @"Disconnect"
#define CONNECT_TEXT @"Connect"

#define SWITCH_MUSIC_INTERVAL 2.0
#define SWITCH_RESET_INTERVAL 2.0
const int PLAY_MUSCI_SIGNAL = 1;
const int LEFT_PICK_SIGNAL = 10;
const int MIDDLE_PICK_SIGNAL = 11;
const int RIGHT_PICK_SIGNAL = 12;

@interface BLEMainViewController ()<UIAlertViewDelegate>{
    
    CBCentralManager    *cm;
    UIAlertView         *currentAlertView;
    UARTPeripheral      *currentPeripheral;
    UIBarButtonItem     *infoBarButton;
}
@property (strong, nonatomic) NSArray *lights;
@end


@implementation BLEMainViewController

@synthesize musicPlayer;
@synthesize lights = _lights;

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
        [self updateLights];
    }
    return self;
}


- (void)viewDidLoad{

    [super viewDidLoad];
    
    musicPlayer = [MPMusicPlayerController iPodMusicPlayer];
    
    
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
    
    if (_connectionStatus == ConnectionStatusConnected || _connectionStatus == ConnectionStatusScanning) {
        //UART
        if (_connectionMode == ConnectionModeUART) {
            //send data to UART Controller
            [_uartViewController receiveData:newData];

            int value = *(int*)([newData bytes]);
            NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
            NSLog(@"value = %d", value);
            
            // by Lei:   Hue
            id<PHBridgeSendAPI> bridgeSendAPI = [[[PHOverallFactory alloc] init] bridgeSendAPI];
            //PHBridgeResourcesCache *cache = [PHBridgeResourcesReader readBridgeResourcesCache];
            PHLight *light = self.lights[0];
            PHLightState *lightState = [[PHLightState alloc] init];
            [lightState setTransitionTime:[NSNumber numberWithInt:0.5]];
            //[lightState setHue:[NSNumber numberWithInt:arc4random() % MAX_HUE]];
            if (1 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(360/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.92 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(0.81 * MAX_SAT)]];
            }
            else if (2 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(25/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.71 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            else if (3 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(103/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.98 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(0.93 * MAX_SAT)]];
            }
            else if (4 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(148/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.67 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            else if (5 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(230/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.71 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            else if (6 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(240/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.71 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            else if (7 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(250/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.71 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            else if (8 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(269/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.17 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            else if (9 == value) {
                [lightState setHue:[NSNumber numberWithInt: (int)(287/360.0 * MAX_HUE)]];
                [lightState setBrightness:[NSNumber numberWithInt: (int)(0.71 * MAX_BRI)]];
                [lightState setSaturation:[NSNumber numberWithInt: (int)(1.00 * MAX_SAT)]];
            }
            // Send lightstate to light
            [bridgeSendAPI updateLightStateForId:light.identifier withLighState:lightState completionHandler:^(NSArray *errors) {
                /*if (errors != nil) {
                    NSString *message = [NSString stringWithFormat:@"%@: %@", NSLocalizedString(@"Errors", @""), errors != nil ? errors : NSLocalizedString(@"none", @"")];
                    
                    NSLog(@"Response: %@",message);
                }*/
                
            }];
                touchCount+=20;
            
            // Play / Pause
            // by Liang: Too simple, add a tool to filter out the noise.
            /*
            if (PLAY_MUSCI_SIGNAL == value) {
                //[musicPlayer play];
                //[self playPause];
                if ([musicPlayer playbackState] == MPMusicPlaybackStatePlaying) {
                    [musicPlayer pause];
                    
                } else {
                    [musicPlayer play];
                }
            }*/
            
            if (currentTime - touchLeftTime > SWITCH_RESET_INTERVAL) {
                touchedLeft = false;
            }
            else if (currentTime - touchMiddleTime > SWITCH_RESET_INTERVAL) {
                touchedMiddle = false;
            }
            else if (currentTime - touchRightTime > SWITCH_RESET_INTERVAL) {
                touchedRight = false;
            }
            
            if (LEFT_PICK_SIGNAL == value) {
                touchLeftTime = currentTime;
                touchedLeft = true;
            }
            else if (MIDDLE_PICK_SIGNAL == value) {
                touchMiddleTime = currentTime;
                touchedMiddle = true;
            }
            else if (RIGHT_PICK_SIGNAL == value) {
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
- (void)updateLights {
    PHBridgeResourcesCache *cache = [PHBridgeResourcesReader readBridgeResourcesCache];
    
    self.lights = [cache.lights.allValues sortedArrayUsingComparator:^NSComparisonResult(PHLight *light1, PHLight *light2) {
        return [light1.identifier compare:light2.identifier options:NSNumericSearch];
    }];
}

@end


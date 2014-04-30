//
//  ViewController.h
//  HopsNearby
//
//  Created by Motohiro Takayama on 4/28/14.
//  Copyright (c) 2014 mootoh.net. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <FacebookSDK/FacebookSDK.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>

@interface ViewController : UIViewController <FBLoginViewDelegate, MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate>

@property (weak, nonatomic) IBOutlet FBProfilePictureView *profilePictureView;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *peopleLabel;
@property (weak, nonatomic) IBOutlet UILabel *friendsLabel;
@property (weak, nonatomic) IBOutlet UILabel *friendsOfFriendsLabel;

@end
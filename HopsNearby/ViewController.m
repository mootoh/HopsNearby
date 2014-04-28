//
//  ViewController.m
//  HopsNearby
//
//  Created by Motohiro Takayama on 4/28/14.
//  Copyright (c) 2014 mootoh.net. All rights reserved.
//

#import "ViewController.h"
#import <FacebookSDK/FacebookSDK.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    FBLoginView *loginView = [[FBLoginView alloc] initWithReadPermissions:@[@"basic_info"]];
    [self.view addSubview:loginView];
    loginView.delegate = self;
}

- (void) friendsOf:(NSString *)person callback:(void(^)(NSError *, NSArray *friends))callback {
    NSString *path = [NSString stringWithFormat:@"%@/friends", person];
    FBRequest *req = [FBRequest requestWithGraphPath:path parameters:nil HTTPMethod:@"GET"];
    [req startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        NSArray *friends = [result objectForKey:@"data"];
        callback(error, friends);
    }];
}

- (IBAction)retrieveFriends:(id)sender {
    [self friendsOf:@"me" callback:^(NSError *error, NSArray *friends) {
        NSLog(@"found %i friends", friends.count);
        for (NSDictionary <FBGraphUser> *friend in friends) {
            NSLog(@"friend named %@ with id %@", friend.name, friend.id);
            /*
            [self friendsOf:friend.id callback:^(NSError *error2, NSArray *friends2) {
                NSLog(@"    found %i friends of %@", friends2.count, friend.name);
            }];
             */

            NSString *path = [NSString stringWithFormat:@"me/mutualfriends/%@", friend.id];
            FBRequest *req = [FBRequest requestWithGraphPath:path parameters:nil HTTPMethod:@"GET"];
            [req startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
                NSArray *mutualFriends = [result objectForKey:@"data"];
                NSLog(@"I have %d mutual friends with %@", mutualFriends.count, friend.name);
            }];
        }
    }];
}

#pragma mark - Facebook
// This method will be called when the user information has been fetched
- (void)loginViewFetchedUserInfo:(FBLoginView *)loginView
                            user:(id<FBGraphUser>)user {
    self.profilePictureView.profileID = user.id;
    self.nameLabel.text = user.name;
}

@end

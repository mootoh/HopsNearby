//
//  ViewController.m
//  HopsNearby
//
//  Created by Motohiro Takayama on 4/28/14.
//  Copyright (c) 2014 mootoh.net. All rights reserved.
//

#import "ViewController.h"
#import <FacebookSDK/FacebookSDK.h>

#define k_FB_ID @"FB_ID"

#define k_SERVICE_TYPE @"hopsnearby"
#define k_PEER_JOINED @"peer_joined"
#define k_PEER_LEFT @"peer_left"

@interface ViewController ()
@property (nonatomic) MCSession *session;
@property (nonatomic) NSString *fb_id;
@property (nonatomic) NSDate *advertiseStartedAt;
@property (nonatomic) MCNearbyServiceAdvertiser *advertiser;
@property (nonatomic) MCNearbyServiceBrowser *browser;
@property (nonatomic) MCPeerID *peerID;
@property (nonatomic) NSMutableDictionary *connectedPeers;
@property (nonatomic) NSSet *myFriends;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.connectedPeers = [NSMutableDictionary dictionary];

    FBLoginView *loginView = [[FBLoginView alloc] initWithReadPermissions:@[@"basic_info"]];
    [self.view addSubview:loginView];
    loginView.delegate = self;

    NSString *cached_fb_id = [[NSUserDefaults standardUserDefaults] stringForKey:k_FB_ID];
    if (! cached_fb_id)
        return;

    [self startFacebookSearch:cached_fb_id];
}

- (void) startFacebookSearch:(NSString *)fb_id {
    self.fb_id = fb_id;
    [self collectMyFriends:^(NSError *error) {
        if (error) {
            NSLog(@"failed in retrieving my friends from Facebook.");
            return;
        }
        [self startMultipeerNetworking];
    }];
}

- (void) collectMyFriends:(void(^)(NSError *))callback {
    FBRequest *req = [FBRequest requestForMyFriends];
    [req startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        if (error) {
            callback(error);
            return;
        }

        NSArray *friends = [result objectForKey:@"data"];
        NSMutableArray *ids = [NSMutableArray array];
        for (NSDictionary<FBGraphUser> *friend in friends) {
            [ids addObject:friend.id];
        }
        self.myFriends = [NSSet setWithArray:ids];
        callback(nil);
    }];
}

- (void) peerJoined:(MCPeerID *)peer {
    NSAssert(self.connectedPeers[peer] == nil, @"should not contain the joined peer");
    self.connectedPeers[peer] = [NSMutableDictionary dictionary];
    [self updatePeopleNearby];

    // send my friends info to the peer
    NSAssert(self.myFriends, @"friends should be retrieved beforehand");
    NSData *friendsData = [NSKeyedArchiver archivedDataWithRootObject:self.myFriends];
    NSError *error = nil;
    [self.session sendData:friendsData toPeers:@[peer] withMode:MCSessionSendDataReliable error:&error];
    if (error) {
        NSLog(@"failed in sending my friends info to peer:%@, error=%@", peer.displayName, error);
        return;
    }

    dispatch_async(dispatch_get_main_queue(),^() {
        // check if me and the peer are friends
        self.connectedPeers[peer][@"is_friend"] = [NSNumber numberWithInt:[self.myFriends containsObject:peer.displayName] ? 1 : 0];
        [self updateFriendsNearby];
    });
}

- (void) peerLeft:(MCPeerID *)peer {
//    NSAssert(self.connectedPeers[peer] != nil, @"should have the leaving peer");
    [self.connectedPeers removeObjectForKey:peer];
    [self updatePeopleNearby];
    [self updateMutualFriends];
}

- (void)updatePeopleNearby {
    dispatch_async(dispatch_get_main_queue(), ^() {
        self.peopleLabel.text = [NSString stringWithFormat:@"%d", self.connectedPeers.count];
    });
}

- (void)updateFriendsNearby {
    NSUInteger count = 0;
    for (MCPeerID *peer in self.connectedPeers) {
        count += [self.connectedPeers[peer][@"is_friend"] intValue];
    }

    dispatch_async(dispatch_get_main_queue(), ^() {
        self.friendsLabel.text = [NSString stringWithFormat:@"%d", count];
    });
}

- (void) updateMutualFriends {
    NSUInteger count = 0;
    for (MCPeerID *peer in self.connectedPeers) {
        NSArray *mutualFriends = (NSArray *)self.connectedPeers[peer][@"mutual"];
        count += mutualFriends.count;
    }

    dispatch_async(dispatch_get_main_queue(), ^() {
        self.friendsOfFriendsLabel.text = [NSString stringWithFormat:@"%d", count];
    });
}

- (NSSet *)peopleNearbyWhoAreNotMyFriend {
    NSMutableSet *people = [NSMutableSet set];

    for (MCPeerID *peer in self.connectedPeers) {
        if (! [self.myFriends containsObject:peer])
            [people addObject:peer];
    }

    return people;
}

#pragma mark - Multipeer Connectivity

- (void) startMultipeerNetworking {
    self.peerID = [[MCPeerID alloc] initWithDisplayName:self.fb_id];
    self.session = [[MCSession alloc] initWithPeer:self.peerID securityIdentity:nil encryptionPreference:MCEncryptionRequired];
    self.session.delegate = self;

    [self startAdvertise:self];
    [self startBrowse];
}

#pragma mark - Advertiser

- (void) startAdvertise:(id <MCNearbyServiceAdvertiserDelegate>)advertiserDelegate {
    self.advertiseStartedAt = [NSDate date];
    NSDictionary *discoveryInfo = @{@"timestamp": [NSString stringWithFormat:@"%lf", [self.advertiseStartedAt timeIntervalSince1970]]};

    self.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:discoveryInfo serviceType:k_SERVICE_TYPE];
    self.advertiser.delegate = advertiserDelegate;
    [self.advertiser startAdvertisingPeer];
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error {
    NSLog(@"didNotStartAdvertisingPeer: error=%@", error);
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void(^)(BOOL accept, MCSession *session))invitationHandler {
    invitationHandler(YES, self.session);
}

#pragma mark - Browser

- (void) startBrowse {
    MCNearbyServiceBrowser *browser = [[MCNearbyServiceBrowser alloc] initWithPeer:self.peerID serviceType:k_SERVICE_TYPE];
    browser.delegate = self;
    [browser startBrowsingForPeers];
    self.browser = browser;
}

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    if ([peerID.displayName isEqualToString:self.peerID.displayName]) {
        NSLog(@"skipping same device");
        return;
    }

    double me = [[NSString stringWithFormat:@"%lf", [self.advertiseStartedAt timeIntervalSince1970]] doubleValue];
    double other = [info[@"timestamp"] doubleValue];

    if (other > me) {
        NSLog(@"found peer %@ started the advertising later from this. Skip it", peerID.displayName);
        return;
    }

    for (MCPeerID *connectedPeer in self.session.connectedPeers) {
        if ([connectedPeer.displayName isEqualToString:peerID.displayName]) {
            NSLog(@"%@ already connected, skip", peerID.displayName);
            return;
        }
    }

    NSLog(@"inviting peer %@...", peerID);
    [browser invitePeer:peerID toSession:self.session withContext:nil timeout:0];
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

#pragma mark - MCSessionDelegate methods

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
//    NSLog(@"state changed: %@", [self stringForPeerConnectionState:state]);
    if (state == MCSessionStateConnected) {
        [self peerJoined:peerID];
    }
    else if (state == MCSessionStateNotConnected) {
        [self peerLeft:peerID];
    }
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    NSArray *friendsOfPeer = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    NSAssert(self.connectedPeers[peerID] != nil, @"it should have the peerID reference already");
    self.connectedPeers[peerID][@"friends"] = friendsOfPeer;

    // check if the peer has friends of mine
    for (NSString *person in friendsOfPeer) {
        if ([self.myFriends containsObject:person]) {
//            NSLog(@"peer %@ has a mutual friend of mine %@", peerID.displayName, person);
            self.connectedPeers[peerID][@"has_mutual_friends"] = [NSNumber numberWithBool:YES];
        }
    }

    int count = 0;
    for (MCPeerID *peer in self.connectedPeers) {
        if ([self.connectedPeers[peer][@"has_mutual_friends"] boolValue])
            count++;
    }

    dispatch_async(dispatch_get_main_queue(), ^() {
        self.friendsOfFriendsLabel.text = [NSString stringWithFormat:@"%d", count];
    });

}

// Helper method for human readable printing of MCSessionState.  This state is per peer.
- (NSString *)stringForPeerConnectionState:(MCSessionState)state
{
    switch (state) {
        case MCSessionStateConnected:
            return @"Connected";

        case MCSessionStateConnecting:
            return @"Connecting";

        case MCSessionStateNotConnected:
            return @"Not Connected";
    }
}

#pragma mark - Facebook

- (void) friendsOf:(NSString *)person callback:(void(^)(NSError *, NSArray *friends))callback {
    NSString *path = [NSString stringWithFormat:@"%@/friends", person];
    FBRequest *req = [FBRequest requestWithGraphPath:path parameters:nil HTTPMethod:@"GET"];
    [req startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        NSArray *friends = [result objectForKey:@"data"];
        callback(error, friends);
    }];
}

// This method will be called when the user information has been fetched
- (void)loginViewFetchedUserInfo:(FBLoginView *)loginView
                            user:(id<FBGraphUser>)user {
    self.profilePictureView.profileID = user.id;
    self.nameLabel.text = user.name;

    if (! [[NSUserDefaults standardUserDefaults] stringForKey:k_FB_ID]) {
        [[NSUserDefaults standardUserDefaults] setValue:user.id forKey:k_FB_ID];
        [self startFacebookSearch:user.id];
    }
}

- (void)loginViewShowingLoggedOutUser:(FBLoginView *)loginView {
    self.profilePictureView.profileID = nil;
    self.nameLabel.text = @"";
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:k_FB_ID];
    self.fb_id = nil;
}

- (void)loginView:(FBLoginView *)loginView
      handleError:(NSError *)error {
    NSLog(@"error? %@", error);
}

@end

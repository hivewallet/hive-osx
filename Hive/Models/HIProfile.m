//
//  HIProfile.m
//  Hive
//
//  Created by Jakub Suder on 02.10.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "BCClient.h"
#import "HIAddress.h"
#import "HINameFormatService.h"
#import "HIProfile.h"

@implementation HIProfileAddress

@end

@implementation HIProfile

+ (void)initialize {
    HIProfile *profile = [[HIProfile alloc] init];

    if (![profile profileData]) {
        // try to figure out user's name based on account data
        NSString *fullName = NSFullUserName() ?: NSUserName();

        if (fullName) {
            NSRange space = [fullName rangeOfString:@" "];

            if (space.location != NSNotFound) {
                profile.firstname = [fullName substringToIndex:space.location];
                profile.lastname = [fullName substringFromIndex:(space.location + 1)];
            } else {
                profile.firstname = fullName;
            }
        }
    }
}

- (NSDictionary *)profileData {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"Profile"];
}

- (void)updateField:(NSString *)key withValue:(id)value {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *data = [[defaults objectForKey:@"Profile"] mutableCopy] ?: [NSMutableDictionary new];

    if (value) {
        data[key] = value;
    } else {
        [data removeObjectForKey:key];
    }

    [defaults setObject:data forKey:@"Profile"];
    [defaults synchronize];
}

- (NSString *)firstname {
    return [self profileData][@"firstname"];
}

- (void)setFirstname:(NSString *)firstname {
    [self updateField:@"firstname" withValue:firstname];
}

- (NSString *)lastname {
    return [self profileData][@"lastname"];
}

- (void)setLastname:(NSString *)lastname {
    [self updateField:@"lastname" withValue:lastname];
}

- (NSString *)email {
    return [self profileData][@"email"];
}

- (void)setEmail:(NSString *)email {
    [self updateField:@"email" withValue:email];
}

- (NSString *)name {
    return [[HINameFormatService sharedService] fullNameForPerson:self];
}

- (BOOL)hasName {
    return (self.firstname.length > 0 || self.lastname.length > 0);
}

- (NSSet *)addresses {
    HIProfileAddress *address = [[HIProfileAddress alloc] init];
    address.address = [[BCClient sharedClient] walletHash];
    address.caption = NSLocalizedString(@"main", @"Main address caption");
    address.contact = self;

    return [NSSet setWithObject:address];
}

- (NSImage *)avatarImage {
    if (self.avatar) {
        return [[NSImage alloc] initWithData:self.avatar];
    } else {
        return [NSImage imageNamed:@"avatar-empty"];
    }
}

- (NSData *)avatar {
    return [self profileData][@"avatar"];
}

- (void)setAvatar:(NSData *)avatar {
    [self updateField:@"avatar" withValue:avatar];
}


- (BOOL)canBeRemoved {
    return NO;
}

- (BOOL)canEditAddresses {
    return NO;
}

- (void)addAddressesObject:(HIAddress *)value {
    NSAssert(self.canEditAddresses, @"This object's addresses cannot be edited.");
}

@end

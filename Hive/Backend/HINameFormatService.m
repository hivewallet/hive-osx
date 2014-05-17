#import "HINameFormatService.h"
#import "HIObservationHandler.h"
#import "HIPerson.h"

static NSString * const LastNameFirstDefaultsKey = @"LastNameFirst";
static int KVContext;

@interface HINameFormatService()

@property (nonatomic, strong, readonly) HIObservationHandler *observers;

@end

@implementation HINameFormatService

+ (instancetype)sharedService {
    static id sharedService = nil;
    static dispatch_once_t oncePredicate;

    dispatch_once(&oncePredicate, ^{
        sharedService = [[self class] new];
    });

    return sharedService;
}

- (id)init {
    self = [super init];
    if (self) {
        _observers = [HIObservationHandler new];

        [[NSUserDefaults standardUserDefaults] addObserver:self
                                                forKeyPath:LastNameFirstDefaultsKey
                                                   options:0
                                                   context:&KVContext];
    }
    return self;
}

- (void)dealloc {
    [[NSUserDefaults standardUserDefaults] removeObserver:self
                                               forKeyPath:LastNameFirstDefaultsKey
                                                  context:&KVContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {

    if (context == &KVContext) {
        [self notifyObservers];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - observation

- (void)addObserver:(id<HINameFormatServiceObserver>)observer {
    [self.observers addObserver:observer];
}

- (void)removeObserver:(id<HINameFormatServiceObserver>)observer {
    [self.observers removeObserver:observer];
}

- (void)notifyObservers {
    for (id<HINameFormatServiceObserver> observer in self.observers.allObservers) {
        [observer nameFormatDidChange];
    }
}

#pragma mark - format

- (NSString *)fullNameForPerson:(id<HIPerson>)person {
    if (person.firstname.length > 0 && person.lastname.length > 0) {
        BOOL lastNameFirst =
            [[NSUserDefaults standardUserDefaults] boolForKey:LastNameFirstDefaultsKey];
        NSString *first = lastNameFirst ? person.lastname : person.firstname;
        NSString *second = lastNameFirst ? person.firstname : person.lastname;
        return [NSString stringWithFormat:@"%@ %@", first, second];
    } else if (person.firstname.length > 0) {
        return person.firstname;
    } else if (person.lastname.length > 0) {
        return person.lastname;
    } else {
        return @"";
    }
}

@end
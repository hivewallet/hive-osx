//
//  HITransactionsViewController.m
//  Hive
//
//  Created by Bazyli Zygan on 28.08.2013.
//  Copyright (c) 2013 Hive Developers. All rights reserved.
//

#import "BCClient.h"
#import "HIAddress.h"
#import "HIBitcoinFormatService.h"
#import "HIContact.h"
#import "HIContactRowView.h"
#import "HIDatabaseManager.h"
#import "HITransaction.h"
#import "HITransactionCellView.h"
#import "HITransactionPopoverViewController.h"
#import "HITransactionsViewController.h"
#import "NSColor+Hive.h"

static int KVO_CONTEXT;

static NSString *const KEY_UNREAD_TRANSACTIONS = @"unreadTransactions";

@interface HITransactionsViewController ()
    <BCTransactionObserver, HITransactionPopoverDelegate, NSTableViewDataSource, NSTableViewDelegate>

// top-level objects
@property (nonatomic, strong) IBOutlet NSView *noTransactionsView;
@property (nonatomic, strong) IBOutlet NSArrayController *arrayController;

@property (nonatomic, weak) IBOutlet NSScrollView *scrollView;
@property (nonatomic, weak) IBOutlet NSTableView *tableView;

@property (nonatomic, strong) HITransactionPopoverViewController *popoverController;
@property (nonatomic, assign) NSInteger currentlySelectedRow;

@end

@implementation HITransactionsViewController {
    HIContact *_contact;
    NSDateFormatter *_transactionDateFormatter, *_fullTransactionDateFormatter;
    NSFont *_amountLabelFont;
}

- (instancetype)init {
    self = [super initWithNibName:@"HITransactionsViewController" bundle:nil];

    if (self) {
        self.title = NSLocalizedString(@"Transactions", @"Transactions view title");
        self.iconName = @"timeline";
        self.currentlySelectedRow = -1;

        _transactionDateFormatter = [NSDateFormatter new];
        _fullTransactionDateFormatter = [NSDateFormatter new];
        [self setDateFormats];

        _amountLabelFont = [NSFont boldSystemFontOfSize:13.0];
    }

    return self;
}

- (instancetype)initWithContact:(HIContact *)contact {
    self = [self init];

    if (self) {
        _contact = contact;
    }

    return self;
}

- (void)setDateFormats {
    _transactionDateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"LLL d jj:mm a"
                                                                           options:0
                                                                            locale:[NSLocale  currentLocale]];

    _fullTransactionDateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"LLL d YYYY jj:mm a"
                                                                               options:0
                                                                                locale:[NSLocale  currentLocale]];
}

- (void)loadView {
    [super loadView];

    self.arrayController.managedObjectContext = DBM;
    self.arrayController.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]];

    if (_contact) {
        self.arrayController.fetchPredicate = [NSPredicate predicateWithFormat:@"contact = %@", _contact];
    }
    [self.arrayController prepareContent];

    [self.noTransactionsView setFrame:self.view.bounds];
    [self.noTransactionsView setHidden:YES];
    [self.noTransactionsView.layer setBackgroundColor:[[NSColor hiWindowBackgroundColor] hiNativeColor]];
    [self.view addSubview:self.noTransactionsView];

    [self.arrayController addObserver:self
                           forKeyPath:@"arrangedObjects.@count"
                              options:NSKeyValueObservingOptionInitial
                              context:&KVO_CONTEXT];

    [[BCClient sharedClient] addTransactionObserver:self];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateBitcoinFormat:)
                                                 name:HIPreferredFormatChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLocaleChange)
                                                 name:NSCurrentLocaleDidChangeNotification
                                               object:nil];
    [self beginObservingUnreadCount];
}

- (void)dealloc {
    [self endObservingUnreadCount];
    [self.arrayController removeObserver:self forKeyPath:@"arrangedObjects.@count" context:&KVO_CONTEXT];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[BCClient sharedClient] removeTransactionObserver:self];

    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &KVO_CONTEXT) {
        if (object == self.arrayController) {
            [self updateNoTransactionsView];
        } else if (object == [BCClient sharedClient]) {
            [self updateBadge];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)viewWillAppear {
    [self markAllTransactionsAsRead];
}

- (void)applicationReturnedToForeground {
    [self markAllTransactionsAsRead];
}

- (void)markAllTransactionsAsRead {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:HITransactionEntity];
    request.predicate = [NSPredicate predicateWithFormat:@"read = NO"];
    for (HITransaction *transaction in [DBM executeFetchRequest:request error:NULL]) {
        transaction.read = YES;
    }

    [DBM save:nil];

    [[BCClient sharedClient] updateNotifications];
}

- (void)updateNoTransactionsView {
    // don't take count from arrangedObjects because array controller might not have fetched data yet
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:HITransactionEntity];
    NSUInteger count = [DBM countForFetchRequest:request error:NULL];

    BOOL shouldShowTransactions = _contact || count > 0;
    [self.noTransactionsView setHidden:shouldShowTransactions];
    [self.scrollView setHidden:!shouldShowTransactions];
}

- (void)onLocaleChange {
    [self setDateFormats];
    [self.tableView reloadData];
}


#pragma mark - Bitcoin format

- (void)updateBitcoinFormat:(NSNotification *)notification {
    [self.tableView reloadData];
}


#pragma mark - BCTransactionObserver

- (void)transactionChangedStatus:(HITransaction *)updatedTransaction {
    NSUInteger position = 0;
    HITransaction *originalTransaction = [self findTransactionWithHash:updatedTransaction.id position:&position];

    if (originalTransaction) {
        originalTransaction.status = updatedTransaction.status;

        [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:position]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
}

- (void)transactionMetadataWasUpdated:(HITransaction *)updatedTransaction {
    NSUInteger position = 0;
    HITransaction *originalTransaction = [self findTransactionWithHash:updatedTransaction.id position:&position];

    if (originalTransaction) {
        [DBM refreshObject:originalTransaction mergeChanges:NO];

        [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:position]
                                  columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    }
}

- (HITransaction *)findTransactionWithHash:(NSString *)transactionHash position:(NSUInteger *)returnedPosition {
    NSArray *list = self.arrayController.arrangedObjects;
    NSUInteger position = [list indexOfObjectPassingTest:^BOOL(id transaction, NSUInteger idx, BOOL *stop) {
        return [[transaction id] isEqual:transactionHash];
    }];

    if (position != NSNotFound) {
        if (returnedPosition) {
            *returnedPosition = position;
        }

        return list[position];
    } else {
        return nil;
    }
}

#pragma mark - NSTableViewDelegate

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [HIContactRowView new];
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {

    // cache some objects for optimization
    static dispatch_once_t onceToken;
    static NSImage *plusImage, *minusImage, *btcImage;
    static NSColor *pendingColor, *cancelledColor;

    dispatch_once(&onceToken, ^{
        plusImage = [NSImage imageNamed:@"icon-transactions-plus"];
        minusImage = [NSImage imageNamed:@"icon-transactions-minus"];
        btcImage = [NSImage imageNamed:@"icon-transactions-btc-symbol"];
        pendingColor = [NSColor colorWithCalibratedWhite:0.6 alpha:1.0];
        cancelledColor = [NSColor redColor];
    });

    HITransactionCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    HITransaction *transaction = self.arrayController.arrangedObjects[row];

    cell.textField.attributedStringValue = [self summaryTextForTransaction:transaction];
    cell.dateLabel.stringValue = [self dateTextForTransaction:transaction];
    cell.directionMark.image = transaction.isIncoming ? plusImage : minusImage;

    if (transaction.contact && transaction.contact.avatarImage) {
        cell.imageView.image = transaction.contact.avatarImage;
        cell.imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    } else {
        cell.imageView.image = btcImage;
        cell.imageView.imageScaling = NSImageScaleProportionallyDown;
    }

    switch (transaction.status) {
        case HITransactionStatusBuilding:
            [cell.pendingLabel setHidden:YES];
            break;

        case HITransactionStatusDead:
            [cell.pendingLabel setHidden:NO];
            cell.pendingLabel.stringValue = NSLocalizedString(@"CANCELLED", @"Dead transaction label");
            cell.pendingLabel.textColor = cancelledColor;
            break;

        default:
            [cell.pendingLabel setHidden:NO];
            cell.pendingLabel.stringValue = NSLocalizedString(@"PENDING", @"Pending transaction label");
            cell.pendingLabel.textColor = pendingColor;
            break;
    }

    return cell;
}

- (NSAttributedString *)summaryTextForTransaction:(HITransaction *)transaction {
    NSString *text;

    // not using standard localized string variables on purpose because we need to mark the fragments with bold
    if (transaction.isIncoming) {
        if (transaction.contact) {
            text = NSLocalizedString(@"Received &a from &c", @"Received amount of BTC from contact");
        } else {
            text = NSLocalizedString(@"Received &a", @"Received amount of BTC from unknown source");
        }
    } else {
        text = NSLocalizedString(@"Sent &a to &c", @"Sent amount of BTC to a contact/address");
    }

    // The attribute in IB does not work for attributed strings.
    NSMutableParagraphStyle *truncatingStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    truncatingStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    // paragraph style is determined for the whole line by the first fragment, so all fragments must specify it
    NSDictionary *attributes = @{NSParagraphStyleAttributeName: truncatingStyle};
    NSDictionary *boldAttributes = @{NSFontAttributeName: _amountLabelFont,
                                     NSParagraphStyleAttributeName: truncatingStyle};

    NSMutableAttributedString *summary = [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];

    NSRange amountRange = [summary.string rangeOfString:@"&a"];
    if (amountRange.location != NSNotFound) {
        satoshi_t satoshi = transaction.absoluteAmount;
        NSString *value = [[HIBitcoinFormatService sharedService] stringWithUnitForBitcoin:satoshi];
        NSAttributedString *fragment = [[NSAttributedString alloc] initWithString:value attributes:boldAttributes];
        [summary replaceCharactersInRange:amountRange withAttributedString:fragment];
    }

    NSRange contactRange = [summary.string rangeOfString:@"&c"];
    if (contactRange.location != NSNotFound) {
        NSString *value;

        if (transaction.contact.firstname.length > 0) {
            value = transaction.contact.firstname;
        } else if (transaction.contact.lastname.length > 0) {
            value = transaction.contact.lastname;
        } else if (transaction.label) {
            value = transaction.label;
        } else if (contactRange.location == summary.string.length - 2) {
            value = transaction.targetAddress;
        } else {
            // we can't tail-truncate if the address is not at the end, so we'll truncate it manually
            value = [NSString stringWithFormat:@"%@…%@",
                     [transaction.targetAddress substringToIndex:8],
                     [transaction.targetAddress substringFromIndex:(transaction.targetAddress.length - 8)]];
        }

        if (!value) {
            HILogWarn(@"Transaction has no targetAddress: %@", transaction);
            value = @"?";
        }

        NSAttributedString *fragment = [[NSAttributedString alloc] initWithString:value attributes:boldAttributes];
        [summary replaceCharactersInRange:contactRange withAttributedString:fragment];
    }

    return summary;
}

- (NSString *)dateTextForTransaction:(HITransaction *)transaction {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger currentYear = [[calendar components:NSYearCalendarUnit fromDate:[NSDate date]] year];
    NSInteger transactionYear = [[calendar components:NSYearCalendarUnit fromDate:transaction.date] year];

    if (currentYear == transactionYear) {
        return [_transactionDateFormatter stringFromDate:transaction.date];
    } else {
        return [_fullTransactionDateFormatter stringFromDate:transaction.date];
    }
}

- (IBAction)tableViewWasClicked:(id)sender {
    NSInteger previousRow = self.currentlySelectedRow;

    if (previousRow != -1) {
        [self.tableView deselectRow:previousRow];

        [self.popoverController closePopover];
        self.popoverController.delegate = nil;
        self.popoverController = nil;
        self.currentlySelectedRow = -1;
    }

    NSInteger clickedRow = self.tableView.clickedRow;

    if (clickedRow != -1 && clickedRow != previousRow) {
        HITransaction *transaction = self.arrayController.arrangedObjects[clickedRow];

        if (transaction) {
            [self showPopoverForTransaction:transaction inRow:clickedRow];
        }

        self.currentlySelectedRow = clickedRow;
    }
}

- (void)showPopoverForTransaction:(HITransaction *)transaction inRow:(NSInteger)row {
    NSTableCellView *cell = [self.tableView viewAtColumn:0 row:row makeIfNecessary:NO];
    if (!cell) {
        return;
    }

    self.popoverController = [[HITransactionPopoverViewController alloc] initWithTransaction:transaction];
    self.popoverController.delegate = self;

    [[self.popoverController createPopover] showRelativeToRect:cell.bounds ofView:cell preferredEdge:NSMinYEdge];
}

- (void)transactionPopoverDidClose:(HITransactionPopoverViewController *)controller {
    if (controller == self.popoverController) {
        [self.tableView deselectAll:self];
        self.currentlySelectedRow = -1;
        self.popoverController.delegate = nil;
        self.popoverController = nil;
    }
}


#pragma mark - badge

- (void)beginObservingUnreadCount {
    [[BCClient sharedClient] addObserver:self
                              forKeyPath:KEY_UNREAD_TRANSACTIONS
                                 options:NSKeyValueObservingOptionInitial
                                 context:&KVO_CONTEXT];
}

- (void)updateBadge {
    self.badgeNumber = [BCClient sharedClient].unreadTransactions;
}

- (void)endObservingUnreadCount {
    [[BCClient sharedClient] removeObserver:self forKeyPath:KEY_UNREAD_TRANSACTIONS context:&KVO_CONTEXT];
}

@end

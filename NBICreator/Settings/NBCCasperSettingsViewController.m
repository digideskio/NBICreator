//
//  NBCCasperSettingsViewController.m
//  NBICreator
//
//  Created by Erik Berglund.
//  Copyright (c) 2015 NBICreator. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "NBCCasperRAMDiskPathCellView.h"
#import "NBCCasperRAMDiskSizeCellView.h"
#import "NBCCasperSettingsViewController.h"
#import "NBCCasperTrustedNetBootServerCellView.h"
#import "NBCCertificateTableCellView.h"
#import "NBCConstants.h"
#import "NBCController.h"
#import "NBCDDReader.h"
#import "NBCDesktopEntity.h"
#import "NBCDiskArbitrator.h"
#import "NBCHelperAuthorization.h"
#import "NBCHelperConnection.h"
#import "NBCHelperProtocol.h"
#import "NBCLogging.h"
#import "NBCOverlayViewController.h"
#import "NBCPackageTableCellView.h"
#import "NBCSettingsController.h"
#import "NBCTableViewCells.h"
#import "NBCVariables.h"
#import "NBCWorkflowItem.h"
#import "NSString+validIP.h"
#import "Reachability.h"
#import "TFHpple.h"
#import <Carbon/Carbon.h>

DDLogLevel ddLogLevel;

@interface NBCCasperSettingsViewController () {
    Reachability *_internetReachableFoo;
}

@end

@implementation NBCCasperSettingsViewController

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Initialization
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (id)init {
    self = [super initWithNibName:@"NBCCasperSettingsViewController" bundle:nil];
    if (self != nil) {
        _templates = [[NBCTemplatesController alloc] initWithSettingsViewController:self templateType:NBCSettingsTypeCasper delegate:self];
    }
    return self;
} // init

- (void)awakeFromNib {
    [_tableViewCertificates registerForDraggedTypes:@[ NSURLPboardType ]];
    [_tableViewPackages registerForDraggedTypes:@[ NSURLPboardType ]];
} // awakeFromNib

- (void)dealloc {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSControlTextDidEndEditingNotification object:nil];
    [nc removeObserver:self name:DADiskDidAppearNotification object:nil];
    [nc removeObserver:self name:DADiskDidDisappearNotification object:nil];
    [nc removeObserver:self name:DADiskDidChangeNotification object:nil];
} // dealloc

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setConnectedToInternet:NO];

    [self setKeyboardLayoutDict:[[NSMutableDictionary alloc] init]];
    [self setCertificateTableViewContents:[[NSMutableArray alloc] init]];
    [self setPackagesTableViewContents:[[NSMutableArray alloc] init]];
    [self setTrustedServers:[[NSMutableArray alloc] init]];
    [self setRamDisks:[[NSMutableArray alloc] init]];
    [self setPostWorkflowScripts:[[NSMutableArray alloc] init]];

    // --------------------------------------------------------------
    //  Add Notification Observers
    // --------------------------------------------------------------
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(editingDidEnd:) name:NSControlTextDidEndEditingNotification object:nil];
    [nc addObserver:self selector:@selector(updatePopUpButtonUSBDevices) name:DADiskDidAppearNotification object:nil];
    [nc addObserver:self selector:@selector(updatePopUpButtonUSBDevices) name:DADiskDidDisappearNotification object:nil];
    [nc addObserver:self selector:@selector(updatePopUpButtonUSBDevices) name:DADiskDidChangeNotification object:nil];

    // --------------------------------------------------------------
    //  Add KVO Observers
    // --------------------------------------------------------------
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:NBCUserDefaultsIndexCounter options:NSKeyValueObservingOptionNew context:nil];

    // --------------------------------------------------------------
    //  Initialize Properties
    // --------------------------------------------------------------
    NSError *error;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *userApplicationSupport = [fm URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error];
    if ([userApplicationSupport checkResourceIsReachableAndReturnError:&error]) {
        _templatesFolderURL = [userApplicationSupport URLByAppendingPathComponent:NBCFolderTemplatesCasper isDirectory:YES];
    } else {
        DDLogError(@"[ERROR] %@", [error localizedDescription]);
    }

    [_imageViewIcon setDelegate:self];
    [_imageViewBackgroundImage setDelegate:self];
    [self setSiuSource:[[NBCApplicationSourceSystemImageUtility alloc] init]];
    [self setTemplatesDict:[[NSMutableDictionary alloc] init]];
    [self setShowARDPassword:NO];
    [self initializeTableViewOverlays];

    // --------------------------------------------------------------
    //  Test Internet Connectivity
    // --------------------------------------------------------------
    [self testInternetConnection];

    [self populatePopUpButtonTimeZone];
    [self populatePopUpButtonLanguage];
    [self populatePopUpButtonKeyboardLayout];
    [self updatePopUpButtonUSBDevices];

    // ------------------------------------------------------------------------------
    //  Add contextual menu to NBI Icon image view to allow to restore original icon.
    // -------------------------------------------------------------------------------
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *restoreView = [[NSMenuItem alloc] initWithTitle:NBCMenuItemRestoreOriginalIcon action:@selector(restoreNBIIcon:) keyEquivalent:@""];
    [restoreView setTarget:self];
    [menu addItem:restoreView];
    [_imageViewIcon setMenu:menu];

    // --------------------------------------------------------------
    //  Load saved templates and create the template menu
    // --------------------------------------------------------------
    [self updatePopUpButtonTemplates];

    // ------------------------------------------------------------------------------------------
    //  Add contextual menu to NBI background image view to allow to restore original background.
    // ------------------------------------------------------------------------------------------
    NSMenu *backgroundImageMenu = [[NSMenu alloc] init];
    NSMenuItem *restoreViewBackground = [[NSMenuItem alloc] initWithTitle:NBCMenuItemRestoreOriginalBackground action:@selector(restoreNBIBackground:) keyEquivalent:@""];
    [backgroundImageMenu addItem:restoreViewBackground];
    [_imageViewBackgroundImage setMenu:backgroundImageMenu];

    // ------------------------------------------------------------------------------
    //
    // -------------------------------------------------------------------------------
    [self updateSettingVisibility];

    // ------------------------------------------------------------------------------
    //  Verify build button so It's not enabled by mistake
    // -------------------------------------------------------------------------------
    [self verifyBuildButton];

} // viewDidLoad

- (void)initializeTableViewOverlays {
    if (!_viewOverlayPackages) {
        NBCOverlayViewController *vc = [[NBCOverlayViewController alloc] initWithContentType:kContentTypePackages];
        _viewOverlayPackages = [vc view];
    }
    [self addOverlayViewToView:_superViewPackages overlayView:_viewOverlayPackages];

    if (!_viewOverlayCertificates) {
        NBCOverlayViewController *vc = [[NBCOverlayViewController alloc] initWithContentType:kContentTypeCertificates];
        _viewOverlayCertificates = [vc view];
    }
    [self addOverlayViewToView:_superViewCertificates overlayView:_viewOverlayCertificates];
    /* Will be added next release
    if ( ! _viewOverlayPostWorkflowScripts ) {
        NBCOverlayViewController *vc = [[NBCOverlayViewController alloc] initWithContentType:kContentTypeScripts];
        _viewOverlayPostWorkflowScripts = [vc view];
    }
    [self addOverlayViewToView:_superViewPostWorkflowScripts overlayView:_viewOverlayPostWorkflowScripts];
     */
} // initializeTableViewOverlays

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NSTableView DataSource Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCertificates]) {
        return (NSInteger)[_certificateTableViewContents count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        return (NSInteger)[_packagesTableViewContents count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCasperTrustedServers]) {
        return (NSInteger)[_trustedServers count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCasperRAMDisks]) {
        return (NSInteger)[_ramDisks count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPostWorkflowScripts]) {
        return (NSInteger)[_postWorkflowScripts count];
    } else {
        return 0;
    }
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
#pragma unused(row)
    if (dropOperation == NSTableViewDropAbove) {
        if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCertificates]) {
            if ([self containsAcceptableCertificateURLsFromPasteboard:[info draggingPasteboard]]) {
                [info setAnimatesToDestination:YES];
                return NSDragOperationCopy;
            }
        } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
            if ([self containsAcceptablePackageURLsFromPasteboard:[info draggingPasteboard]]) {
                [info setAnimatesToDestination:YES];
                return NSDragOperationCopy;
            }
        }
    }
    return NSDragOperationNone;
}

- (void)tableView:(NSTableView *)tableView updateDraggingItemsForDrag:(id<NSDraggingInfo>)draggingInfo {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCertificates]) {
        NSArray *classes = @[ [NBCDesktopCertificateEntity class], [NSPasteboardItem class] ];
        __block NBCCertificateTableCellView *certCellView = [tableView makeViewWithIdentifier:@"CertificateCellView" owner:self];
        __block NSInteger validCount = 0;
        [draggingInfo enumerateDraggingItemsWithOptions:0
            forView:tableView
            classes:classes
            searchOptions:@{}
            usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
              if ([[draggingItem item] isKindOfClass:[NBCDesktopCertificateEntity class]]) {
                  NBCDesktopCertificateEntity *entity = (NBCDesktopCertificateEntity *)[draggingItem item];
                  [draggingItem setDraggingFrame:[certCellView frame]];
                  [draggingItem setImageComponentsProvider:^NSArray * {
                    if ([entity isKindOfClass:[NBCDesktopCertificateEntity class]]) {
                        NSData *certificateData = [entity certificate];
                        NSDictionary *certificateDict = [self examineCertificate:certificateData];
                        if ([certificateDict count] != 0) {
                            certCellView = [self populateCertificateCellView:certCellView certificateDict:certificateDict];
                        }
                    }
                    [[certCellView textFieldCertificateName] setStringValue:[entity name]];
                    return [certCellView draggingImageComponents];
                  }];
                  validCount++;
              } else {
                  [draggingItem setImageComponentsProvider:nil];
              }
            }];
        [draggingInfo setNumberOfValidItemsForDrop:validCount];
        [draggingInfo setDraggingFormation:NSDraggingFormationList];

    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        NSArray *classes = @[ [NBCDesktopPackageEntity class], [NSPasteboardItem class] ];
        __block NBCPackageTableCellView *packageCellView = [tableView makeViewWithIdentifier:@"PackageCellView" owner:self];
        __block NSInteger validCount = 0;
        [draggingInfo enumerateDraggingItemsWithOptions:0
            forView:tableView
            classes:classes
            searchOptions:@{}
            usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
              if ([[draggingItem item] isKindOfClass:[NBCDesktopPackageEntity class]]) {
                  NBCDesktopPackageEntity *entity = (NBCDesktopPackageEntity *)[draggingItem item];
                  [draggingItem setDraggingFrame:[packageCellView frame]];
                  [draggingItem setImageComponentsProvider:^NSArray * {
                    if ([entity isKindOfClass:[NBCDesktopPackageEntity class]]) {
                        NSDictionary *packageDict = [self examinePackageAtURL:[entity fileURL]];
                        if ([packageDict count] != 0) {
                            packageCellView = [self populatePackageCellView:packageCellView packageDict:packageDict];
                        }
                    }
                    [[packageCellView textFieldPackageName] setStringValue:[entity name]];
                    return [packageCellView draggingImageComponents];
                  }];
                  validCount++;
              } else {
                  [draggingItem setImageComponentsProvider:nil];
              }
            }];
        [draggingInfo setNumberOfValidItemsForDrop:validCount];
        [draggingInfo setDraggingFormation:NSDraggingFormationList];
    }
}

- (void)insertCertificatesInTableView:(NSTableView *)tableView draggingInfo:(id<NSDraggingInfo>)info row:(NSInteger)row {
    NSArray *classes = @[ [NBCDesktopCertificateEntity class] ];
    __block NSInteger insertionIndex = row;
    [info enumerateDraggingItemsWithOptions:0
        forView:tableView
        classes:classes
        searchOptions:@{}
        usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
          NBCDesktopCertificateEntity *entity = (NBCDesktopCertificateEntity *)[draggingItem item];
          if ([entity isKindOfClass:[NBCDesktopCertificateEntity class]]) {
              NSData *certificateData = [entity certificate];
              NSDictionary *certificateDict = [self examineCertificate:certificateData];
              if ([certificateDict count] != 0) {

                  for (NSDictionary *certDict in self->_certificateTableViewContents) {
                      if ([certificateDict[NBCDictionaryKeyCertificateSignature] isEqualToData:certDict[NBCDictionaryKeyCertificateSignature]]) {
                          if ([certificateDict[NBCDictionaryKeyCertificateSerialNumber] isEqualToString:certDict[NBCDictionaryKeyCertificateSerialNumber]]) {
                              DDLogWarn(@"Certificate %@ is already added!", certificateDict[NBCDictionaryKeyCertificateName]);
                              return;
                          }
                      }
                  }

                  [self->_certificateTableViewContents insertObject:certificateDict atIndex:(NSUInteger)insertionIndex];
                  [tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)insertionIndex] withAnimation:NSTableViewAnimationEffectGap];
                  [draggingItem setDraggingFrame:[tableView frameOfCellAtColumn:0 row:insertionIndex]];
                  insertionIndex++;
                  [self->_viewOverlayCertificates setHidden:YES];
              }
          }
        }];
}

- (void)insertPackagesInTableView:(NSTableView *)tableView draggingInfo:(id<NSDraggingInfo>)info row:(NSInteger)row {
    NSArray *classes = @[ [NBCDesktopPackageEntity class] ];
    __block NSInteger insertionIndex = row;
    [info enumerateDraggingItemsWithOptions:0
        forView:tableView
        classes:classes
        searchOptions:@{}
        usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
          NBCDesktopPackageEntity *entity = (NBCDesktopPackageEntity *)[draggingItem item];
          if ([entity isKindOfClass:[NBCDesktopPackageEntity class]]) {
              NSDictionary *packageDict = [self examinePackageAtURL:[entity fileURL]];
              if ([packageDict count] != 0) {

                  NSString *packagePath = packageDict[NBCDictionaryKeyPackagePath];
                  for (NSDictionary *pkgDict in self->_packagesTableViewContents) {
                      if ([packagePath isEqualToString:pkgDict[NBCDictionaryKeyPackagePath]]) {
                          DDLogWarn(@"Package %@ is already added!", [packagePath lastPathComponent]);
                          return;
                      }
                  }

                  [self->_packagesTableViewContents insertObject:packageDict atIndex:(NSUInteger)insertionIndex];
                  [tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)insertionIndex] withAnimation:NSTableViewAnimationEffectGap];
                  [draggingItem setDraggingFrame:[tableView frameOfCellAtColumn:0 row:insertionIndex]];
                  insertionIndex++;
                  [self->_viewOverlayPackages setHidden:YES];
              }
          }
        }];
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
#pragma unused(dropOperation)
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCertificates]) {
        [self insertCertificatesInTableView:_tableViewCertificates draggingInfo:info row:row];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        [self insertPackagesInTableView:_tableViewPackages draggingInfo:info row:row];
    }
    return NO;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NSTableView Delegate Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NBCCertificateTableCellView *)populateCertificateCellView:(NBCCertificateTableCellView *)cellView certificateDict:(NSDictionary *)certificateDict {
    NSMutableAttributedString *certificateName;
    NSMutableAttributedString *certificateExpirationString;
    if ([certificateDict[NBCDictionaryKeyCertificateExpired] boolValue]) {
        certificateName = [[NSMutableAttributedString alloc] initWithString:certificateDict[NBCDictionaryKeyCertificateName]];
        [certificateName addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[certificateName length])];

        certificateExpirationString = [[NSMutableAttributedString alloc] initWithString:certificateDict[NBCDictionaryKeyCertificateExpirationString]];
        [certificateExpirationString addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[certificateExpirationString length])];
    }

    // --------------------------------------------
    //  Certificate Icon
    // --------------------------------------------
    NSImage *certificateIcon;
    NSURL *certificateIconURL;

    if ([certificateDict[NBCDictionaryKeyCertificateSelfSigned] boolValue]) {
        certificateIconURL = [[NSBundle mainBundle] URLForResource:@"IconCertRoot" withExtension:@"png"];
    } else {
        certificateIconURL = [[NSBundle mainBundle] URLForResource:@"IconCertStandard" withExtension:@"png"];
    }

    if ([certificateIconURL checkResourceIsReachableAndReturnError:nil]) {
        certificateIcon = [[NSImage alloc] initWithContentsOfURL:certificateIconURL];
        [[cellView imageViewCertificateIcon] setImage:certificateIcon];
    }

    // --------------------------------------------
    //  Certificate Name
    // --------------------------------------------
    if ([certificateName length] != 0) {
        [[cellView textFieldCertificateName] setAttributedStringValue:certificateName];
    } else {
        [[cellView textFieldCertificateName] setStringValue:certificateDict[NBCDictionaryKeyCertificateName]];
    }

    // --------------------------------------------
    //  Certificate Expiration String
    // --------------------------------------------
    if ([certificateExpirationString length] != 0) {
        [[cellView textFieldCertificateExpiration] setAttributedStringValue:certificateExpirationString];
    } else {
        [[cellView textFieldCertificateExpiration] setStringValue:certificateDict[NBCDictionaryKeyCertificateExpirationString]];
    }

    return cellView;
}

- (NBCCasperTrustedNetBootServerCellView *)populateTrustedNetBootServerCellView:(NBCCasperTrustedNetBootServerCellView *)cellView netBootServerIP:(NSString *)netBootServerIP {
    NSMutableAttributedString *netBootServerIPMutable;
    if ([netBootServerIP isValidIPAddress]) {
        [[cellView textFieldTrustedNetBootServer] setStringValue:netBootServerIP];
    } else {
        netBootServerIPMutable = [[NSMutableAttributedString alloc] initWithString:netBootServerIP];
        [netBootServerIPMutable addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[netBootServerIPMutable length])];
        [[cellView textFieldTrustedNetBootServer] setAttributedStringValue:netBootServerIPMutable];
    }

    return cellView;
}

- (NBCPackageTableCellView *)populatePackageCellView:(NBCPackageTableCellView *)cellView packageDict:(NSDictionary *)packageDict {
    NSMutableAttributedString *packageName;
    NSImage *packageIcon;
    NSURL *packageURL = [NSURL fileURLWithPath:packageDict[NBCDictionaryKeyPackagePath]];
    if ([packageURL checkResourceIsReachableAndReturnError:nil]) {
        [[cellView textFieldPackageName] setStringValue:packageDict[NBCDictionaryKeyPackageName]];
        packageIcon = [[NSWorkspace sharedWorkspace] iconForFile:[packageURL path]];
        [[cellView imageViewPackageIcon] setImage:packageIcon];
    } else {
        packageName = [[NSMutableAttributedString alloc] initWithString:packageDict[NBCDictionaryKeyPackageName]];
        [packageName addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[packageName length])];
        [[cellView textFieldPackageName] setAttributedStringValue:packageName];
    }

    return cellView;
}

- (NBCCasperRAMDiskPathCellView *)populateRAMDiskPathCellView:(NBCCasperRAMDiskPathCellView *)cellView ramDiskDict:(NSDictionary *)ramDiskDict row:(NSInteger)row {
    NSString *ramDiskPath = ramDiskDict[@"path"] ?: @"";
    [[cellView textFieldRAMDiskPath] setStringValue:ramDiskPath];
    [[cellView textFieldRAMDiskPath] setTag:row];
    /*
     NSMutableAttributedString *ramDiskMutable;
     if ( [netBootServerIP isValidIPAddress] ) {
     [[cellView textFieldTrustedNetBootServer] setStringValue:netBootServerIP];
     } else {
     netBootServerIPMutable = [[NSMutableAttributedString alloc] initWithString:netBootServerIP];
     [netBootServerIPMutable addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0,(NSUInteger)[netBootServerIPMutable length])];
     [[cellView textFieldTrustedNetBootServer] setAttributedStringValue:netBootServerIPMutable];
     }
     */
    return cellView;
}

- (NBCCasperRAMDiskSizeCellView *)populateRAMDiskSizeCellView:(NBCCasperRAMDiskSizeCellView *)cellView ramDiskDict:(NSDictionary *)ramDiskDict row:(NSInteger)row {
    NSString *ramDiskSize = ramDiskDict[@"size"] ?: @"1";
    [[cellView textFieldRAMDiskSize] setStringValue:ramDiskSize];
    [[cellView textFieldRAMDiskSize] setTag:row];
    /*
     NSMutableAttributedString *ramDiskMutable;
     if ( [netBootServerIP isValidIPAddress] ) {
     [[cellView textFieldTrustedNetBootServer] setStringValue:netBootServerIP];
     } else {
     netBootServerIPMutable = [[NSMutableAttributedString alloc] initWithString:netBootServerIP];
     [netBootServerIPMutable addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0,(NSUInteger)[netBootServerIPMutable length])];
     [[cellView textFieldTrustedNetBootServer] setAttributedStringValue:netBootServerIPMutable];
     }
     */
    return cellView;
}

- (NBCCellViewPostWorkflowScript *)populateCellViewPostWorkflowScript:(NBCCellViewPostWorkflowScript *)cellView packageDict:(NSDictionary *)packageDict {
    NSMutableAttributedString *packageName;
    NSImage *packageIcon;
    NSURL *packageURL = [NSURL fileURLWithPath:packageDict[NBCDictionaryKeyPath]];
    if ([packageURL checkResourceIsReachableAndReturnError:nil]) {
        [[cellView textField] setStringValue:packageDict[NBCDictionaryKeyName] ?: @"Unknown"];
        packageIcon = [[NSWorkspace sharedWorkspace] iconForFile:[packageURL path]];
        [[cellView imageView] setImage:packageIcon];
    } else {
        packageName = [[NSMutableAttributedString alloc] initWithString:packageDict[NBCDictionaryKeyName]];
        [packageName addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[packageName length])];
        [[cellView textField] setAttributedStringValue:packageName];
    }

    return cellView;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCertificates]) {
        NSDictionary *certificateDict = _certificateTableViewContents[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"CertificateTableColumn"]) {
            NBCCertificateTableCellView *cellView = [tableView makeViewWithIdentifier:@"CertificateCellView" owner:self];
            return [self populateCertificateCellView:cellView certificateDict:certificateDict];
        }
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        NSDictionary *packageDict = _packagesTableViewContents[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"PackageTableColumn"]) {
            NBCPackageTableCellView *cellView = [tableView makeViewWithIdentifier:@"PackageCellView" owner:self];
            return [self populatePackageCellView:cellView packageDict:packageDict];
        }
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCasperTrustedServers]) {
        [self updateTrustedNetBootServersCount];
        NSString *trustedServer = _trustedServers[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"CasperTrustedNetBootTableColumn"]) {
            NBCCasperTrustedNetBootServerCellView *cellView = [tableView makeViewWithIdentifier:@"CasperNetBootServerCellView" owner:self];
            return [self populateTrustedNetBootServerCellView:cellView netBootServerIP:trustedServer];
        }
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierCasperRAMDisks]) {
        [self updateRAMDisksCount];
        NSDictionary *ramDiskDict = _ramDisks[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"CasperRAMDiskPathTableColumn"]) {
            NBCCasperRAMDiskPathCellView *cellView = [tableView makeViewWithIdentifier:@"CasperRAMDiskPathCellView" owner:self];
            return [self populateRAMDiskPathCellView:cellView ramDiskDict:ramDiskDict row:row];
        } else if ([[tableColumn identifier] isEqualToString:@"CasperRAMDiskSizeTableColumn"]) {
            NBCCasperRAMDiskSizeCellView *cellView = [tableView makeViewWithIdentifier:@"CasperRAMDiskSizeCellView" owner:self];
            return [self populateRAMDiskSizeCellView:cellView ramDiskDict:ramDiskDict row:row];
        }
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPostWorkflowScripts]) {
        NSDictionary *scriptDict = _postWorkflowScripts[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"ScriptTableColumn"]) {
            NBCCellViewPostWorkflowScript *cellView = [tableView makeViewWithIdentifier:@"CellViewPostWorkflowScript" owner:self];
            return [self populateCellViewPostWorkflowScript:cellView packageDict:scriptDict];
        }
    }
    return nil;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NSTableView Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NSDictionary *)pasteboardReadingOptionsCertificates {
    return @{ NSPasteboardURLReadingFileURLsOnlyKey : @YES, NSPasteboardURLReadingContentsConformToTypesKey : @[ @"public.x509-certificate" ] };
}

- (NSDictionary *)pasteboardReadingOptionsPackages {
    return @{ NSPasteboardURLReadingFileURLsOnlyKey : @YES, NSPasteboardURLReadingContentsConformToTypesKey : @[ @"com.apple.installer-package-archive" ] };
}

- (BOOL)containsAcceptableCertificateURLsFromPasteboard:(NSPasteboard *)pasteboard {
    return [pasteboard canReadObjectForClasses:@[ [NSURL class] ] options:[self pasteboardReadingOptionsCertificates]];
}

- (BOOL)containsAcceptablePackageURLsFromPasteboard:(NSPasteboard *)pasteboard {
    return [pasteboard canReadObjectForClasses:@[ [NSURL class] ] options:[self pasteboardReadingOptionsPackages]];
}

- (NSDictionary *)examinePackageAtURL:(NSURL *)packageURL {

    DDLogDebug(@"[DEBUG] Examine installer package...");

    NSMutableDictionary *newPackageDict = [[NSMutableDictionary alloc] init];

    newPackageDict[NBCDictionaryKeyPackagePath] = [packageURL path] ?: @"Unknown";
    DDLogDebug(@"[DEBUG] Package path: %@", newPackageDict[NBCDictionaryKeyPackagePath]);

    newPackageDict[NBCDictionaryKeyPackageName] = [packageURL lastPathComponent] ?: @"Unknown";
    DDLogDebug(@"[DEBUG] Package pame: %@", newPackageDict[NBCDictionaryKeyPackageName]);

    return newPackageDict;
}

- (NSDictionary *)examineCertificate:(NSData *)certificateData {

    NSMutableDictionary *newCertificateDict = [[NSMutableDictionary alloc] init];

    SecCertificateRef certificate = nil;
    NSString *certificateName;
    NSString *certificateExpirationString;
    NSString *certificateSerialNumber;
    NSDate *certificateNotValidBeforeDate;
    NSDate *certificateNotValidAfterDate;
    BOOL isSelfSigned = NO;
    BOOL certificateExpired = NO;

    certificate = SecCertificateCreateWithData(NULL, CFBridgingRetain(certificateData));

    if (!certificate) {
        DDLogError(@"[ERROR] Could not get certificate from data!");
        return nil;
    }

    CFErrorRef *error = nil;
    NSDictionary *certificateValues = (__bridge NSDictionary *)(SecCertificateCopyValues(certificate,
                                                                                         (__bridge CFArrayRef) @[
                                                                                             (__bridge id)kSecOIDX509V1ValidityNotBefore,
                                                                                             (__bridge id)kSecOIDX509V1ValidityNotAfter,
                                                                                             (__bridge id)kSecOIDX509V1Signature,
                                                                                             (__bridge id)kSecOIDX509V1SerialNumber,
                                                                                             (__bridge id)kSecOIDTitle
                                                                                         ],
                                                                                         error));

    if ([certificateValues count] != 0) {
        // --------------------------------------------
        //  Certificate IsSelfSigned
        // --------------------------------------------
        CFDataRef issuerData = SecCertificateCopyNormalizedIssuerContent(certificate, error);
        CFDataRef subjectData = SecCertificateCopyNormalizedSubjectContent(certificate, error);

        if ([(__bridge NSData *)issuerData isEqualToData:(__bridge NSData *)subjectData]) {
            isSelfSigned = YES;
        }
        newCertificateDict[NBCDictionaryKeyCertificateSelfSigned] = @(isSelfSigned);

        // --------------------------------------------
        //  Certificate Name
        // --------------------------------------------
        certificateName = (__bridge NSString *)(SecCertificateCopySubjectSummary(certificate));
        if ([certificateName length] != 0) {
            newCertificateDict[NBCDictionaryKeyCertificateName] = certificateName ?: @"";
        } else {
            DDLogError(@"[ERROR] Could not get certificateName!");
            return nil;
        }

        // --------------------------------------------
        //  Certificate NotValidBefore
        // --------------------------------------------
        if (certificateValues[(__bridge id)kSecOIDX509V1ValidityNotBefore]) {
            NSDictionary *notValidBeforeDict = certificateValues[(__bridge id)kSecOIDX509V1ValidityNotBefore];
            NSNumber *notValidBefore = notValidBeforeDict[@"value"];
            certificateNotValidBeforeDate = CFBridgingRelease(CFDateCreate(kCFAllocatorDefault, [notValidBefore doubleValue]));

            if ([certificateNotValidBeforeDate compare:[NSDate date]] == NSOrderedDescending) {
                certificateExpired = YES;
                certificateExpirationString = [NSString stringWithFormat:@"Not valid before %@", certificateNotValidBeforeDate];
            }

            newCertificateDict[NBCDictionaryKeyCertificateNotValidBeforeDate] = certificateNotValidBeforeDate;
        }

        // --------------------------------------------
        //  Certificate NotValidAfter
        // --------------------------------------------
        if (certificateValues[(__bridge id)kSecOIDX509V1ValidityNotAfter]) {
            NSDictionary *notValidAfterDict = certificateValues[(__bridge id)kSecOIDX509V1ValidityNotAfter];
            NSNumber *notValidAfter = notValidAfterDict[@"value"];
            certificateNotValidAfterDate = CFBridgingRelease(CFDateCreate(kCFAllocatorDefault, [notValidAfter doubleValue]));

            if ([certificateNotValidAfterDate compare:[NSDate date]] == NSOrderedAscending && !certificateExpired) {
                certificateExpired = YES;
                certificateExpirationString = [NSString stringWithFormat:@"Expired %@", certificateNotValidAfterDate];
            } else {
                certificateExpirationString = [NSString stringWithFormat:@"Expires %@", certificateNotValidAfterDate];
            }

            newCertificateDict[NBCDictionaryKeyCertificateNotValidAfterDate] = certificateNotValidAfterDate;
        }

        // --------------------------------------------
        //  Certificate Expiration String
        // --------------------------------------------
        newCertificateDict[NBCDictionaryKeyCertificateExpirationString] = certificateExpirationString;

        // --------------------------------------------
        //  Certificate Expired
        // --------------------------------------------
        newCertificateDict[NBCDictionaryKeyCertificateExpired] = @(certificateExpired);

        // --------------------------------------------
        //  Certificate Serial Number
        // --------------------------------------------
        if (certificateValues[(__bridge id)kSecOIDX509V1SerialNumber]) {
            NSDictionary *serialNumber = certificateValues[(__bridge id)kSecOIDX509V1SerialNumber];
            certificateSerialNumber = serialNumber[@"value"];

            newCertificateDict[NBCDictionaryKeyCertificateSerialNumber] = certificateSerialNumber;
        }

        // --------------------------------------------
        //  Certificate Signature
        // --------------------------------------------
        if (certificateValues[(__bridge id)kSecOIDX509V1Signature]) {
            NSDictionary *signatureDict = certificateValues[(__bridge id)kSecOIDX509V1Signature];
            newCertificateDict[NBCDictionaryKeyCertificateSignature] = signatureDict[@"value"];
        }

        // --------------------------------------------
        //  Add Certificate
        // --------------------------------------------
        newCertificateDict[NBCDictionaryKeyCertificate] = certificateData;

        return [newCertificateDict copy];
    } else {
        DDLogError(@"[ERROR] SecCertificateCopyValues returned nil, possibly PEM-encoded?");
        return nil;
    }
}

- (BOOL)insertCertificateInTableView:(NSDictionary *)certificateDict {
    for (NSDictionary *certDict in _certificateTableViewContents) {
        if ([certificateDict[NBCDictionaryKeyCertificateSignature] isEqualToData:certDict[NBCDictionaryKeyCertificateSignature]]) {
            if ([certificateDict[NBCDictionaryKeyCertificateSerialNumber] isEqualToString:certDict[NBCDictionaryKeyCertificateSerialNumber]]) {
                DDLogWarn(@"Certificate %@ is already added!", certificateDict[NBCDictionaryKeyCertificateName]);
                return NO;
            }
        }
    }

    NSInteger index = [_tableViewCertificates selectedRow];
    index++;
    [_tableViewCertificates beginUpdates];
    [_tableViewCertificates insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewCertificates scrollRowToVisible:index];
    [_certificateTableViewContents insertObject:certificateDict atIndex:(NSUInteger)index];
    [_viewOverlayCertificates setHidden:YES];
    [_tableViewCertificates endUpdates];
    return YES;
}

- (void)insertPackageInTableView:(NSDictionary *)packageDict {
    NSString *packagePath = packageDict[NBCDictionaryKeyPackagePath];
    for (NSDictionary *pkgDict in _packagesTableViewContents) {
        if ([packagePath isEqualToString:pkgDict[NBCDictionaryKeyPackagePath]]) {
            DDLogWarn(@"Package %@ is already added!", [packagePath lastPathComponent]);
            return;
        }
    }

    NSInteger index = [_tableViewPackages selectedRow];
    index++;
    [_tableViewPackages beginUpdates];
    [_tableViewPackages insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewPackages scrollRowToVisible:index];
    [_packagesTableViewContents insertObject:packageDict atIndex:(NSUInteger)index];
    [_viewOverlayPackages setHidden:YES];
    [_tableViewPackages endUpdates];
}

- (NSInteger)insertNetBootServerIPInTableView:(NSString *)netBootServerIP {
    NSInteger index = [_tableViewTrustedServers selectedRow];
    index++;
    [_tableViewTrustedServers beginUpdates];
    [_tableViewTrustedServers insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewTrustedServers scrollRowToVisible:index];
    [_trustedServers insertObject:netBootServerIP atIndex:(NSUInteger)index];
    [_tableViewTrustedServers endUpdates];
    return index;
}

- (NSInteger)insertRAMDiskInTableView:(NSDictionary *)ramDiskDict {
    NSInteger index = [_tableViewRAMDisks selectedRow];
    index++;
    [_tableViewRAMDisks beginUpdates];
    [_tableViewRAMDisks insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewRAMDisks scrollRowToVisible:index];
    [_ramDisks insertObject:ramDiskDict atIndex:(NSUInteger)index];
    [_tableViewRAMDisks endUpdates];
    return index;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Reachability
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)testInternetConnection {

    _internetReachableFoo = [Reachability reachabilityWithHostname:@"github.com"];
    __unsafe_unretained typeof(self) weakSelf = self;

    // Internet is reachable
    _internetReachableFoo.reachableBlock = ^(Reachability *reach) {
#pragma unused(reach)
      // Update the UI on the main thread
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf setConnectedToInternet:YES];
        if (weakSelf->_verifyJSSWhenConnected) {
            [weakSelf setVerifyJSSWhenConnected:NO];
            [weakSelf buttonVerifyJSS:nil];
        }
      });
    };

    // Internet is not reachable
    _internetReachableFoo.unreachableBlock = ^(Reachability *reach) {
#pragma unused(reach)
      // Update the UI on the main thread
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf setConnectedToInternet:NO];
      });
    };

    [_internetReachableFoo startNotifier];
} // testInternetConnection

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods ImageDropView
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateIconFromURL:(NSURL *)iconURL {
    if (iconURL != nil) {
        // To get the view to update I have to first set the nbiIcon property to @""
        // It only happens when it recieves a dropped image, not when setting in code.
        [self setNbiIcon:@""];
        [self setNbiIconPath:[iconURL path]];
    }
}

- (void)updateBackgroundFromURL:(NSURL *)backgroundURL {
    if (backgroundURL != nil) {
        // To get the view to update I have to first set the nbiIcon property to @""
        // It only happens when it recieves a dropped image, not when setting in code.
        [self setImageBackground:@""];
        [self setImageBackgroundURL:[backgroundURL path]];
    }
} // updateBackgroundFromURL

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods PopUpButton
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {

    BOOL retval = YES;

    if ([[menuItem title] isEqualToString:NBCMenuItemRestoreOriginalIcon]) {

        // -------------------------------------------------------------
        //  No need to restore original icon if it's already being used
        // -------------------------------------------------------------
        if ([_nbiIconPath isEqualToString:NBCFilePathNBIIconCasper]) {
            retval = NO;
        }
        return retval;
    } else if ([[menuItem title] isEqualToString:NBCMenuItemRestoreOriginalBackground]) {
        // -------------------------------------------------------------------
        //  No need to restore original background if it's already being used
        // -------------------------------------------------------------------
        if ([_imageBackgroundURL isEqualToString:NBCBackgroundImageDefaultPath]) {
            retval = NO;
        }
        return retval;
    }

    return YES;
} // validateMenuItem

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods TextField
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)controlTextDidChange:(NSNotification *)sender {
    if ([[[sender object] class] isSubclassOfClass:[NSTextField class]]) {
        NSTextField *textField = [sender object];
        if ([[[textField superview] class] isSubclassOfClass:[NBCCasperTrustedNetBootServerCellView class]]) {
            NSNumber *textFieldTag = @([textField tag]);
            if (textFieldTag != nil) {
                if ([sender object] ==
                    [[_tableViewTrustedServers viewAtColumn:[_tableViewTrustedServers selectedColumn] row:[textFieldTag integerValue] makeIfNecessary:NO] textFieldTrustedNetBootServer]) {
                    NSDictionary *userInfo = [sender userInfo];
                    NSString *inputText = [[userInfo valueForKey:@"NSFieldEditor"] string];

                    // Only allow numers and periods
                    NSCharacterSet *allowedCharacters = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
                    if ([[inputText stringByTrimmingCharactersInSet:allowedCharacters] length] != 0) {
                        [textField setStringValue:[inputText stringByTrimmingCharactersInSet:[allowedCharacters invertedSet]]];
                        return;
                    }

                    [_trustedServers replaceObjectAtIndex:(NSUInteger)[textFieldTag integerValue] withObject:[inputText copy]];
                }
            }
        }

        // --------------------------------------------------------------------
        //  Expand variables for the NBI preview text fields
        // --------------------------------------------------------------------
        if (textField == _textFieldNBIName) {
            if ([_nbiName length] == 0) {
                [_textFieldNBINamePreview setStringValue:@""];
            } else {
                NSString *nbiName = [NBCVariables expandVariables:_nbiName source:_source applicationSource:_siuSource];
                [_textFieldNBINamePreview setStringValue:[NSString stringWithFormat:@"%@.nbi", nbiName]];
            }
        } else if (textField == _textFieldIndex) {
            if ([_nbiIndex length] == 0) {
                [_textFieldIndexPreview setStringValue:@""];
            } else {
                NSString *nbiIndex = [NBCVariables expandVariables:_nbiIndex source:_source applicationSource:_siuSource];
                [_textFieldIndexPreview setStringValue:[NSString stringWithFormat:@"Index: %@", nbiIndex]];
            }
        } else if (textField == _textFieldNBIDescription) {
            if ([_nbiDescription length] == 0) {
                [_textFieldNBIDescriptionPreview setStringValue:@""];
            } else {
                NSString *nbiDescription = [NBCVariables expandVariables:_nbiDescription source:_source applicationSource:_siuSource];
                [_textFieldNBIDescriptionPreview setStringValue:nbiDescription];
            }
        } else if (textField == _textFieldJSSURL) {
            NSURL *stringAsURL = [NSURL URLWithString:[_textFieldJSSURL stringValue]];
            if (stringAsURL && [stringAsURL scheme] && [stringAsURL host]) {
                [self jssURLIsValid];
            } else {
                [self jssURLIsInvalid];
            }

            [_imageViewVerifyJSSStatus setHidden:YES];
            [_textFieldVerifyJSSStatus setHidden:YES];
            [_imageViewDownloadJSSCertificateStatus setHidden:YES];
            [_textFieldDownloadJSSCertificateStatus setHidden:YES];
            [_buttonShowJSSCertificate setHidden:YES];
        } else if (textField == _textFieldDestinationFolder) {
            // --------------------------------------------------------------------
            //  Expand tilde for destination folder if tilde is used in settings
            // --------------------------------------------------------------------
            if ([_destinationFolder length] == 0) {
                [self setDestinationFolder:@""];
            } else if ([_destinationFolder hasPrefix:@"~"]) {
                NSString *destinationFolder = [_destinationFolder stringByExpandingTildeInPath];
                [self setDestinationFolder:destinationFolder];
            }
        }

        // --------------------------------------------------------------------
        //  Continuously verify build button
        // --------------------------------------------------------------------
        [self verifyBuildButton];
    }

} // controlTextDidChange

- (void)downloadCanceled:(NSDictionary *)downloadInfo {
    NSString *downloadTag = downloadInfo[NBCDownloaderTag];
    if ([downloadTag isEqualToString:NBCDownloaderTagJSSCertificate]) {
        DDLogError(@"Download with tag %@ canceled!", downloadTag);
    }
}

- (void)jssURLIsValid {
    [self setJssURLValid:YES];
    if (!_verifyingJSS) {
        [_buttonVerifyJSS setEnabled:YES];
    }
    [_buttonDownloadJSSCertificate setEnabled:YES];
    [_buttonShowJSSCertificate setEnabled:YES];
}

- (void)jssURLIsInvalid {
    [self setJssURLValid:NO];
    [_buttonVerifyJSS setEnabled:NO];
    [_buttonDownloadJSSCertificate setEnabled:NO];
    [_buttonShowJSSCertificate setEnabled:NO];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods NBCAlert
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)alertReturnCode:(NSInteger)returnCode alertInfo:(NSDictionary *)alertInfo {

    NSString *alertTag = alertInfo[NBCAlertTagKey];
    if ([alertTag isEqualToString:NBCAlertTagSettingsWarning]) {
        if (returnCode == NSAlertSecondButtonReturn) { // Continue
            NBCWorkflowItem *workflowItem = alertInfo[NBCAlertWorkflowItemKey];
            [self prepareWorkflowItem:workflowItem];
        }
    }

    if ([alertTag isEqualToString:NBCAlertTagSettingsUnsaved]) {
        NSString *selectedTemplate = alertInfo[NBCAlertUserInfoSelectedTemplate];
        if (returnCode == NSAlertFirstButtonReturn) { // Save
            [self saveUISettingsWithName:_selectedTemplate atUrl:_templatesDict[_selectedTemplate]];
            [self setSelectedTemplate:selectedTemplate];
            [self updateUISettingsFromURL:_templatesDict[_selectedTemplate]];
            [self expandVariablesForCurrentSettings];
            return;
        } else if (returnCode == NSAlertSecondButtonReturn) { // Discard
            [self setSelectedTemplate:selectedTemplate];
            [self updateUISettingsFromURL:_templatesDict[_selectedTemplate]];
            [self expandVariablesForCurrentSettings];
            return;
        } else { // Cancel
            [_popUpButtonTemplates selectItemWithTitle:_selectedTemplate];
            return;
        }
    }

    if ([alertTag isEqualToString:NBCAlertTagSettingsUnsavedBuild]) {
        NSString *selectedTemplate = alertInfo[NBCAlertUserInfoSelectedTemplate];
        NSDictionary *preWorkflowTasks = alertInfo[NBCAlertUserInfoPreWorkflowTasks];
        if (returnCode == NSAlertFirstButtonReturn) { // Save and Continue
            if ([_selectedTemplate isEqualToString:NBCMenuItemUntitled]) {
                [_templates showSheetSaveUntitled:selectedTemplate buildNBI:YES preWorkflowTasks:preWorkflowTasks];
                return;
            } else {
                [self saveUISettingsWithName:_selectedTemplate atUrl:_templatesDict[_selectedTemplate]];
                [self setSelectedTemplate:selectedTemplate];
                [self updateUISettingsFromURL:_templatesDict[_selectedTemplate]];
                [self expandVariablesForCurrentSettings];
                [self verifySettings:preWorkflowTasks];
                return;
            }
        } else if (returnCode == NSAlertSecondButtonReturn) { // Continue
            [self verifySettings:preWorkflowTasks];
            return;
        } else { // Cancel
            [_popUpButtonTemplates selectItemWithTitle:_selectedTemplate];
            return;
        }
    }
} // alertReturnCode:alertInfo

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Notification Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateSettingVisibility {
    if (_source != nil) {
        int sourceVersionMinor = (int)[[_source expandVariables:@"%OSMINOR%"] integerValue];
        if (_source != nil && 11 <= sourceVersionMinor) {
            [self setSettingTrustedNetBootServersVisible:YES];
        } else {
            [self setSettingTrustedNetBootServersVisible:NO];
        }
    } else {
        [self setSettingTrustedNetBootServersVisible:NO];
    }
}

- (void)updateSource:(NBCSource *)source target:(NBCTarget *)target {
    if (source != nil) {
        [self setSource:source];
    }

    [self updateSettingVisibility];

    NSString *currentBackgroundImageURL = _imageBackgroundURL;
    if ([currentBackgroundImageURL isEqualToString:NBCBackgroundImageDefaultPath]) {
        [self setImageBackground:@""];
        [self setImageBackground:NBCBackgroundImageDefaultPath];
        [self setImageBackgroundURL:NBCBackgroundImageDefaultPath];
    }

    if (target != nil) {
        DDLogDebug(@"[DEBUG] Updating target...");
        [self setTarget:target];
    }

    if ([[source sourceType] isEqualToString:NBCSourceTypeNBI]) {

        // If current source is NBI, remove current template.
        if (_isNBI) {
            NSURL *selectedTemplate = _templatesDict[_selectedTemplate];
            if ([selectedTemplate checkResourceIsReachableAndReturnError:nil]) {
                [_templates deleteTemplateAtURL:selectedTemplate updateTemplateList:NO];
            }
        }

        [self setIsNBI:YES];

        NSURL *nbiURL = [source sourceURL];
        [self createSettingsFromNBI:nbiURL];
    } else {
        if (_isNBI) {
            NSURL *selectedTemplate = _templatesDict[_selectedTemplate];
            if ([selectedTemplate checkResourceIsReachableAndReturnError:nil]) {
                [_templates deleteTemplateAtURL:selectedTemplate updateTemplateList:YES];
            }
        }

        [self setNbiSourceSettings:nil];
        [self setIsNBI:NO];
        [self updateUIForSourceType:[source sourceType] settings:nil];
        [self expandVariablesForCurrentSettings];
        [self verifyBuildButton];
    }

    [self updatePopOver];
}

- (void)removedSource {
    if (_source) {
        [self setSource:nil];
    }

    [self updateSettingVisibility];

    NSString *currentBackgroundImageURL = _imageBackgroundURL;
    if ([currentBackgroundImageURL isEqualToString:NBCBackgroundImageDefaultPath]) {
        [self setImageBackground:@""];
        [self setImageBackground:NBCBackgroundImageDefaultPath];
        [self setImageBackgroundURL:NBCBackgroundImageDefaultPath];
    }

    if (_isNBI) {
        NSURL *selectedTemplate = _templatesDict[_selectedTemplate];
        if ([selectedTemplate checkResourceIsReachableAndReturnError:nil]) {
            [_templates deleteTemplateAtURL:selectedTemplate updateTemplateList:YES];
        }
    }

    [self setIsNBI:NO];
    [self setNbiSourceSettings:nil];
    //[self updateUIForSourceType:NBCSourceTypeInstallerApplication settings:nil];
    [self expandVariablesForCurrentSettings];
    [self verifyBuildButton];
    [self updatePopOver];
}

/*
 - (void)removedSource:(NSNotification *)notification {
 #pragma unused(notification)

 if ( _source ) {
 [self setSource:nil];
 }

 [self updateSettingVisibility];

 NSString *currentBackgroundImageURL = _imageBackgroundURL;
 if ( [currentBackgroundImageURL isEqualToString:NBCBackgroundImageDefaultPath] ) {
 [self setImageBackground:@""];
 [self setImageBackground:NBCBackgroundImageDefaultPath];
 [self setImageBackgroundURL:NBCBackgroundImageDefaultPath];
 }

 [self setIsNBI:NO];
 [_textFieldDestinationFolder setEnabled:YES];
 [_buttonChooseDestinationFolder setEnabled:YES];
 [_popUpButtonTool setEnabled:YES];
 [self expandVariablesForCurrentSettings];
 [self verifyBuildButton];
 [self updatePopOver];
 } // removedSource
 */

- (void)refreshCreationTool {
    [self setNbiCreationTool:_nbiCreationTool ?: NBCMenuItemNBICreator];
}

- (void)restoreNBIIcon:(NSNotification *)notification {
#pragma unused(notification)

    [self setNbiIconPath:NBCFilePathNBIIconCasper];
    [self expandVariablesForCurrentSettings];
} // restoreNBIIcon

- (void)restoreNBIBackground:(NSNotification *)notification {
#pragma unused(notification)

    [self setImageBackground:@""];
    [self setImageBackgroundURL:NBCBackgroundImageDefaultPath];
    [self expandVariablesForCurrentSettings];
} // restoreNBIBackground

- (void)editingDidEnd:(NSNotification *)notification {
    if ([[[notification object] class] isSubclassOfClass:[NSTextField class]]) {
        NSTextField *textField = [notification object];
        if ([[[textField superview] class] isSubclassOfClass:[NBCCasperTrustedNetBootServerCellView class]]) {
            [self updateTrustedNetBootServersCount];
        } else if ([[[textField superview] class] isSubclassOfClass:[NBCCasperRAMDiskPathCellView class]]) {
            NSString *newPath = [textField stringValue];
            NSNumber *textFieldTag = @([textField tag]);
            if (textFieldTag != nil) {
                NSMutableDictionary *ramDiskDict = [NSMutableDictionary dictionaryWithDictionary:[_ramDisks objectAtIndex:(NSUInteger)[textFieldTag integerValue]]];
                ramDiskDict[@"path"] = newPath ?: @"";
                [_ramDisks replaceObjectAtIndex:(NSUInteger)[textFieldTag integerValue] withObject:[ramDiskDict copy]];
                [self updateRAMDisksCount];
            }
        } else if ([[[textField superview] class] isSubclassOfClass:[NBCCasperRAMDiskSizeCellView class]]) {
            NSString *newSize = [[notification object] stringValue];
            NSNumber *textFieldTag = @([textField tag]);
            if (textFieldTag != nil) {
                NSMutableDictionary *ramDiskDict = [NSMutableDictionary dictionaryWithDictionary:[_ramDisks objectAtIndex:(NSUInteger)[textFieldTag integerValue]]];
                ramDiskDict[@"size"] = newSize ?: @"";
                [_ramDisks replaceObjectAtIndex:(NSUInteger)[textFieldTag integerValue] withObject:[ramDiskDict copy]];
                [self updateRAMDisksCount];
            }
        }
    }
} // editingDidEnd

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Key/Value Observing
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
#pragma unused(object, change, context)

    if ([keyPath isEqualToString:NBCUserDefaultsIndexCounter]) {
        NSString *nbiIndex = [NBCVariables expandVariables:_nbiIndex source:_source applicationSource:_siuSource];
        [_textFieldIndexPreview setStringValue:[NSString stringWithFormat:@"Index: %@", nbiIndex]];
    }
} // observeValueForKeyPath:ofObject:change:context

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Settings
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateUISettingsFromDict:(NSDictionary *)settingsDict {

    [self setCasperImagingVersion:@""];
    [self setJssCACertificateExpirationString:@""];
    [self setJssVersion:@""];

    [self setNbiCreationTool:settingsDict[NBCSettingsNBICreationToolKey]];
    [self setNbiName:settingsDict[NBCSettingsNameKey]];
    [self setNbiIndex:settingsDict[NBCSettingsIndexKey]];
    [self setNbiProtocol:settingsDict[NBCSettingsProtocolKey]];
    [self setNbiEnabled:[settingsDict[NBCSettingsEnabledKey] boolValue]];
    [self setNbiDefault:[settingsDict[NBCSettingsDefaultKey] boolValue]];
    [self setNbiLanguage:settingsDict[NBCSettingsLanguageKey]];
    [self setNbiKeyboardLayout:settingsDict[NBCSettingsKeyboardLayoutKey]];
    [self setNbiDescription:settingsDict[NBCSettingsDescriptionKey]];
    [self setDestinationFolder:settingsDict[NBCSettingsDestinationFolderKey]];
    [self setNbiIconPath:settingsDict[NBCSettingsIconKey]];
    [self setDisableWiFi:[settingsDict[NBCSettingsDisableWiFiKey] boolValue]];
    [self setDisableBluetooth:[settingsDict[NBCSettingsDisableBluetoothKey] boolValue]];
    [self setIncludeSystemUIServer:[settingsDict[NBCSettingsIncludeSystemUIServerKey] boolValue]];
    [self setArdLogin:settingsDict[NBCSettingsARDLoginKey]];
    [self setArdPassword:settingsDict[NBCSettingsARDPasswordKey]];
    [self setUseNetworkTimeServer:[settingsDict[NBCSettingsUseNetworkTimeServerKey] boolValue]];
    [self setNetworkTimeServer:settingsDict[NBCSettingsNetworkTimeServerKey]];
    [self setCasperImagingPath:settingsDict[NBCSettingsCasperImagingPathKey]];
    [self setCasperJSSURL:settingsDict[NBCSettingsCasperJSSURLKey]];
    //[self setIsNBI:[settingsDict[NBCSettingsCasperSourceIsNBI] boolValue]];
    [self setUseBackgroundImage:[settingsDict[NBCSettingsUseBackgroundImageKey] boolValue]];
    [self setImageBackgroundURL:settingsDict[NBCSettingsBackgroundImageKey]];
    [self setUseVerboseBoot:[settingsDict[NBCSettingsUseVerboseBootKey] boolValue]];
    [self setDiskImageReadWrite:[settingsDict[NBCSettingsDiskImageReadWriteKey] boolValue]];
    [self setDiskImageReadWriteRename:[settingsDict[NBCSettingsDiskImageReadWriteRenameKey] boolValue]];
    [self setBaseSystemDiskImageSize:settingsDict[NBCSettingsBaseSystemDiskImageSizeKey] ?: @10];
    [self setIncludeConsoleApp:[settingsDict[NBCSettingsIncludeConsoleAppKey] boolValue]];
    [self setAllowInvalidCertificate:[settingsDict[NBCSettingsCasperAllowInvalidCertificateKey] boolValue]];
    [self setJssCACertificate:settingsDict[NBCSettingsCasperJSSCACertificateKey]];
    [self setEnableCasperImagingDebugMode:[settingsDict[NBCSettingsCasperImagingDebugModeKey] boolValue]];
    [self setEnableLaunchdLogging:[settingsDict[NBCSettingsEnableLaunchdLoggingKey] boolValue]];
    [self setLaunchConsoleApp:[settingsDict[NBCSettingsLaunchConsoleAppKey] boolValue]];
    [self setIncludeRuby:[settingsDict[NBCSettingsIncludeRubyKey] boolValue]];
    [self setAddTrustedNetBootServers:[settingsDict[NBCSettingsAddTrustedNetBootServersKey] boolValue]];
    [self setAddCustomRAMDisks:[settingsDict[NBCSettingsAddCustomRAMDisksKey] boolValue]];
    [self setIncludePython:[settingsDict[NBCSettingsIncludePythonKey] boolValue]];
    [self setUsbLabel:settingsDict[NBCSettingsUSBLabelKey] ?: @"%OSVERSION%_%OSBUILD%_Casper"];

    NSNumber *displaySleepMinutes = settingsDict[NBCSettingsDisplaySleepMinutesKey];
    int displaySleepMinutesInteger = 20;
    if (displaySleepMinutes != nil) {
        displaySleepMinutesInteger = [displaySleepMinutes intValue];
        [self setDisplaySleepMinutes:displaySleepMinutesInteger];
    } else {
        [self setDisplaySleepMinutes:displaySleepMinutesInteger];
    }

    [_sliderDisplaySleep setIntegerValue:displaySleepMinutesInteger];
    [self updateSliderPreview:displaySleepMinutesInteger];
    if (displaySleepMinutesInteger < 120) {
        [self setDisplaySleep:NO];
    } else {
        [self setDisplaySleep:YES];
    }

    [self uppdatePopUpButtonTool];

    if (_isNBI) {
        [_popUpButtonTool setEnabled:NO];
        [_textFieldDestinationFolder setEnabled:NO];
        [_buttonChooseDestinationFolder setEnabled:NO];
        if ([settingsDict[NBCSettingsDisableWiFiKey] boolValue]) {
            [_checkboxDisableWiFi setEnabled:NO];
        } else {
            [_checkboxDisableWiFi setEnabled:YES];
        }
    } else {
        [_popUpButtonTool setEnabled:YES];
        [_textFieldDestinationFolder setEnabled:YES];
        [_buttonChooseDestinationFolder setEnabled:YES];
    }

    if (_nbiCreationTool == nil || [_nbiCreationTool isEqualToString:NBCMenuItemNBICreator]) {
        [self hideSystemImageUtilityVersion];
    } else {
        [self showSystemImageUtilityVersion];
    }

    [_certificateTableViewContents removeAllObjects];
    [_tableViewCertificates reloadData];
    if ([settingsDict[NBCSettingsCertificatesKey] count] != 0) {
        NSArray *certificatesArray = settingsDict[NBCSettingsCertificatesKey];
        for (NSData *certificate in certificatesArray) {
            NSDictionary *certificateDict = [self examineCertificate:certificate];
            if ([certificateDict count] != 0) {
                [self insertCertificateInTableView:certificateDict];
            }
        }
    } else {
        [_viewOverlayCertificates setHidden:NO];
    }

    [_packagesTableViewContents removeAllObjects];
    [_tableViewPackages reloadData];
    if ([settingsDict[NBCSettingsPackagesKey] count] != 0) {
        NSArray *packagesArray = settingsDict[NBCSettingsPackagesKey];
        for (NSString *packagePath in packagesArray) {
            NSURL *packageURL = [NSURL fileURLWithPath:packagePath];
            NSDictionary *packageDict = [self examinePackageAtURL:packageURL];
            if ([packageDict count] != 0) {
                [self insertPackageInTableView:packageDict];
            }
        }
    } else {
        [_viewOverlayPackages setHidden:NO];
    }

    [_trustedServers removeAllObjects];
    [_tableViewTrustedServers reloadData];
    if ([settingsDict[NBCSettingsTrustedNetBootServersKey] count] != 0) {
        NSArray *trustedServersArray = settingsDict[NBCSettingsTrustedNetBootServersKey];
        if ([trustedServersArray count] != 0) {
            for (NSString *trustedServer in trustedServersArray) {
                [self insertNetBootServerIPInTableView:trustedServer];
            }
        } else {
            [self updateTrustedNetBootServersCount];
        }
    } else {
        [self updateTrustedNetBootServersCount];
    }

    [_ramDisks removeAllObjects];
    [_tableViewRAMDisks reloadData];
    if ([settingsDict[NBCSettingsRAMDisksKey] count] != 0) {
        NSArray *ramDisksArray = settingsDict[NBCSettingsRAMDisksKey];
        for (NSDictionary *ramDiskDict in ramDisksArray) {
            if ([ramDiskDict count] != 0) {
                [self insertRAMDiskInTableView:ramDiskDict];
            }
        }
    }

    if ([_jssCACertificate count] != 0) {
        if (_jssCACertificate[_casperJSSURL]) {
            NSImage *imageSuccess = [[NSImage alloc] initWithContentsOfFile:IconSuccessPath];
            [_imageViewDownloadJSSCertificateStatus setImage:imageSuccess];
            [_buttonShowJSSCertificate setHidden:NO];
            [_textFieldDownloadJSSCertificateStatus setStringValue:@"Downloaded"];
            [_imageViewDownloadJSSCertificateStatus setHidden:NO];
            [_textFieldDownloadJSSCertificateStatus setHidden:NO];
            for (NSDictionary *certDict in _certificateTableViewContents) {
                if ([certDict[@"CertificateSignature"] isEqualToData:_jssCACertificate[_casperJSSURL]]) {
                    [self updateJSSCACertificateExpirationFromDateNotValidAfter:certDict[@"CertificateNotValidAfterDate"] dateNotValidBefore:certDict[@"CertificateNotValidBeforeDate"]];
                }
            }
        } else {
            [_buttonShowJSSCertificate setHidden:YES];
            [_textFieldDownloadJSSCertificateStatus setStringValue:@""];
            [_imageViewDownloadJSSCertificateStatus setHidden:YES];
            [_textFieldDownloadJSSCertificateStatus setHidden:YES];
        }
    } else {
        [_buttonShowJSSCertificate setHidden:YES];
        [_textFieldDownloadJSSCertificateStatus setStringValue:@""];
        [_imageViewDownloadJSSCertificateStatus setHidden:YES];
        [_textFieldDownloadJSSCertificateStatus setHidden:YES];
    }

    [_imageViewVerifyJSSStatus setHidden:YES];
    [_textFieldVerifyJSSStatus setHidden:YES];
    [_textFieldVerifyJSSStatus setStringValue:@""];
    NSURL *stringAsURL = [NSURL URLWithString:_casperJSSURL];
    if (stringAsURL && [stringAsURL scheme] && [stringAsURL host]) {
        [self jssURLIsValid];
        if (_connectedToInternet) {
            [self buttonVerifyJSS:nil];
        } else {
            [self setVerifyJSSWhenConnected:YES];
        }
    } else {
        [self jssURLIsInvalid];
    }

    if ([_casperImagingPath length] != 0) {
        NSBundle *bundle = [NSBundle bundleWithPath:_casperImagingPath];
        if (bundle != nil) {
            NSString *bundleIdentifier = [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
            if ([bundleIdentifier isEqualToString:NBCCasperImagingBundleIdentifier]) {
                NSString *bundleVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                if ([bundleVersion length] != 0) {
                    [self setCasperImagingVersion:bundleVersion];
                }
            }
        }
    }

    NSString *selectedTimeZone = settingsDict[NBCSettingsTimeZoneKey];
    if ([selectedTimeZone length] == 0 || [selectedTimeZone isEqualToString:NBCMenuItemCurrent]) {
        [self selectTimeZone:[_popUpButtonTimeZone itemWithTitle:NBCMenuItemCurrent]];
    } else {
        NSString *selectedTimeZoneRegion = [selectedTimeZone componentsSeparatedByString:@"/"][0];
        DDLogDebug(@"[DEBUG] TimeZone Region: %@", selectedTimeZoneRegion);
        NSString *selectedTimeZoneCity = [selectedTimeZone componentsSeparatedByString:@"/"][1];
        DDLogDebug(@"[DEBUG] TimeZone City: %@", selectedTimeZoneCity);
        NSArray *regionArray = [[[_popUpButtonTimeZone itemWithTitle:selectedTimeZoneRegion] submenu] itemArray];
        for (NSMenuItem *menuItem in regionArray) {
            if ([[menuItem title] isEqualToString:selectedTimeZoneCity]) {
                DDLogDebug(@"[DEBUG] Selecting menu item: %@", [menuItem title]);
                [self selectTimeZone:menuItem];
                break;
            }
        }
    }

    [self expandVariablesForCurrentSettings];

    if (_isNBI) {
        [self updateUIForSourceType:NBCSourceTypeNBI settings:settingsDict];
    } else {
        [self updateUIForSourceType:NBCSourceTypeInstallerApplication settings:settingsDict]; // Doesn't matter as long as it's not NBI
    }

    /*/////////////////////////////////////////////////////////////////////////
     /// TEMPORARY FIX WHEN CHANGING KEY FOR KEYBOARD_LAYOUT IN TEMPLATE    ///
     ////////////////////////////////////////////////////////////////////////*/
    if ([settingsDict[NBCSettingsKeyboardLayoutKey] length] == 0) {
        NSString *valueFromOldKeyboardLayoutKey = settingsDict[@"KeyboardLayoutName"];
        if ([valueFromOldKeyboardLayoutKey length] != 0) {
            [self setNbiKeyboardLayout:valueFromOldKeyboardLayoutKey];
        }
    }
    /* --------------------------------------------------------------------- */
} // updateUISettingsFromDict

- (void)updateUIForSourceType:(NSString *)sourceType settings:(NSDictionary *)settingsDict {

    // -------------------------------------------------------------------------------
    //  If source is NBI, disable all settings that require extraction from OS Source.
    // -------------------------------------------------------------------------------
    if ([sourceType isEqualToString:NBCSourceTypeNBI]) {

        [_popUpButtonTool setEnabled:NO];
        [_popUpButtonTemplates setEnabled:NO];

        // Tab Bar: General
        [_textFieldDestinationFolder setEnabled:NO];
        [_buttonChooseDestinationFolder setEnabled:NO];

        // Tab Bar: Options
        if ([settingsDict[NBCSettingsDisableWiFiKey] boolValue]) {
            [_checkboxDisableWiFi setEnabled:NO];
        } else {
            [_checkboxDisableWiFi setEnabled:YES];
        }

        if ([settingsDict[NBCSettingsDisableBluetoothKey] boolValue]) {
            [_checkboxDisableBluetooth setEnabled:NO];
        } else {
            [_checkboxDisableBluetooth setEnabled:YES];
        }

        [_checkboxIncludeRuby setEnabled:NO];
        [_checkboxIncludePython setEnabled:NO];
        [_checkboxIncludeSystemUIServer setEnabled:NO];

        if ([settingsDict[NBCSettingsARDLoginKey] length] != 0) {
            [_textFieldARDLogin setEnabled:YES];
            [_textFieldARDPassword setEnabled:YES];
            [_secureTextFieldARDPassword setEnabled:YES];
            [_checkboxARDPasswordShow setEnabled:YES];
        } else {
            [_textFieldARDLogin setEnabled:NO];
            [_textFieldARDPassword setEnabled:NO];
            [_secureTextFieldARDPassword setEnabled:NO];
            [_checkboxARDPasswordShow setEnabled:NO];
        }

        if ([settingsDict[NBCSettingsUseNetworkTimeServerKey] boolValue]) {
            [_checkboxUseNetworkTimeServer setEnabled:YES];
        } else {
            [_checkboxUseNetworkTimeServer setEnabled:NO];
        }

        // Tab Bar: Advanced
        [_checkboxAddBackground setEnabled:NO];

        // Tab Bar: Debug
        [_checkboxIncludeConsole setEnabled:NO];
        if ([settingsDict[NBCSettingsIncludeConsoleAppKey] boolValue]) {
            [_checkboxConsoleLaunchBehindApp setEnabled:YES];
        } else {
            [_checkboxConsoleLaunchBehindApp setEnabled:NO];
        }
    } else {
        [_popUpButtonTool setEnabled:YES];
        [_popUpButtonTemplates setEnabled:YES];

        // Tab Bar: General
        [_textFieldDestinationFolder setEnabled:YES];
        [_buttonChooseDestinationFolder setEnabled:YES];

        // Tab Bar: Options
        [_checkboxDisableWiFi setEnabled:YES];
        [_checkboxDisableBluetooth setEnabled:YES];
        [_checkboxIncludeRuby setEnabled:YES];
        [_checkboxIncludePython setEnabled:YES];
        [_checkboxIncludeSystemUIServer setEnabled:YES];
        [_textFieldARDLogin setEnabled:YES];
        [_textFieldARDPassword setEnabled:YES];
        [_secureTextFieldARDPassword setEnabled:YES];
        [_checkboxARDPasswordShow setEnabled:YES];
        [_checkboxUseNetworkTimeServer setEnabled:YES];

        // Tab Bar: Advanced
        [_checkboxAddBackground setEnabled:YES];

        // Tab Bar: Debug
        [_checkboxIncludeConsole setEnabled:YES];
        [_checkboxConsoleLaunchBehindApp setEnabled:YES];
    }
}

- (void)updateJSSCACertificateExpirationFromDateNotValidAfter:(NSDate *)dateAfter dateNotValidBefore:(NSDate *)dateBefore {
#pragma unused(dateBefore)
    NSDate *dateNow = [NSDate date];

    BOOL certificateExpired = NO;
    if ([dateBefore compare:dateNow] == NSOrderedDescending) {
        // Not valid before...
    }

    if ([dateAfter compare:dateNow] == NSOrderedAscending && !certificateExpired) {
        // Expired...
    } else {
        // Expires...
    }

    NSTimeInterval secondsBetween = [dateAfter timeIntervalSinceDate:dateNow];
    NSDateComponentsFormatter *dateComponentsFormatter = [[NSDateComponentsFormatter alloc] init];
    NSCalendar *calendarUS = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    [calendarUS setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    [dateComponentsFormatter setCalendar:calendarUS];
    [dateComponentsFormatter setUnitsStyle:NSDateComponentsFormatterUnitsStyleFull];
    [dateComponentsFormatter setMaximumUnitCount:3];
    NSString *expirationString = [dateComponentsFormatter stringFromTimeInterval:secondsBetween];
    if ([expirationString length] != 0) {
        [self setJssCACertificateExpirationString:expirationString];
    }
}

- (void)updateUISettingsFromURL:(NSURL *)url {

    NSDictionary *mainDict = [[NSDictionary alloc] initWithContentsOfURL:url];
    if (mainDict) {
        NSDictionary *settingsDict = mainDict[NBCSettingsSettingsKey];
        if (settingsDict) {
            [self updateUISettingsFromDict:settingsDict];
        } else {
            DDLogError(@"[ERROR] No key named 'Settings' i plist at URL: %@", url);
        }
    } else {
        DDLogError(@"[ERROR] Could not read plist at URL: %@", url);
    }
} // updateUISettingsFromURL

- (NSDictionary *)returnSettingsFromUI {

    NSMutableDictionary *settingsDict = [[NSMutableDictionary alloc] init];

    settingsDict[NBCSettingsNBICreationToolKey] = _nbiCreationTool ?: NBCMenuItemNBICreator;
    settingsDict[NBCSettingsNameKey] = _nbiName ?: @"";
    settingsDict[NBCSettingsIndexKey] = _nbiIndex ?: @"1";
    settingsDict[NBCSettingsProtocolKey] = _nbiProtocol ?: @"NFS";
    settingsDict[NBCSettingsLanguageKey] = _nbiLanguage ?: NBCMenuItemCurrent;
    settingsDict[NBCSettingsKeyboardLayoutKey] = _nbiKeyboardLayout ?: NBCMenuItemCurrent;
    settingsDict[NBCSettingsEnabledKey] = @(_nbiEnabled) ?: @NO;
    settingsDict[NBCSettingsDefaultKey] = @(_nbiDefault) ?: @NO;
    settingsDict[NBCSettingsDescriptionKey] = _nbiDescription ?: @"";
    if (_destinationFolder != nil) {
        NSString *currentUserHome = NSHomeDirectory();
        if ([_destinationFolder hasPrefix:currentUserHome]) {
            NSString *destinationFolderPath = [_destinationFolder stringByReplacingOccurrencesOfString:currentUserHome withString:@"~"];
            settingsDict[NBCSettingsDestinationFolderKey] = destinationFolderPath ?: @"~/Desktop";
        } else {
            settingsDict[NBCSettingsDestinationFolderKey] = _destinationFolder ?: @"~/Desktop";
        }
    }
    settingsDict[NBCSettingsIconKey] = _nbiIconPath ?: @"%APPLICATIONRESOURCESURL%/IconCasperImaging.icns";
    settingsDict[NBCSettingsDisableWiFiKey] = @(_disableWiFi) ?: @NO;
    settingsDict[NBCSettingsDisableBluetoothKey] = @(_disableBluetooth) ?: @NO;
    settingsDict[NBCSettingsDisplaySleepMinutesKey] = @(_displaySleepMinutes) ?: @30;
    settingsDict[NBCSettingsDisplaySleepKey] = (_displaySleepMinutes == 120) ? @NO : @YES;
    settingsDict[NBCSettingsIncludeSystemUIServerKey] = @(_includeSystemUIServer) ?: @NO;
    settingsDict[NBCSettingsCasperImagingPathKey] = _casperImagingPath ?: @"";
    settingsDict[NBCSettingsCasperJSSURLKey] = _casperJSSURL ?: @"";
    settingsDict[NBCSettingsARDLoginKey] = _ardLogin ?: @"";
    settingsDict[NBCSettingsARDPasswordKey] = _ardPassword ?: @"";
    settingsDict[NBCSettingsUseNetworkTimeServerKey] = @(_useNetworkTimeServer) ?: @NO;
    settingsDict[NBCSettingsNetworkTimeServerKey] = _networkTimeServer ?: @"time.apple.com";
    settingsDict[NBCSettingsSourceIsNBI] = @(_isNBI) ?: @NO;
    settingsDict[NBCSettingsUseBackgroundImageKey] = @(_useBackgroundImage) ?: @NO;
    settingsDict[NBCSettingsBackgroundImageKey] = _imageBackgroundURL ?: @"%SOURCEURL%/System/Library/CoreServices/DefaultDesktop.jpg";
    settingsDict[NBCSettingsUseVerboseBootKey] = @(_useVerboseBoot) ?: @NO;
    settingsDict[NBCSettingsDiskImageReadWriteKey] = @(_diskImageReadWrite) ?: @NO;
    settingsDict[NBCSettingsDiskImageReadWriteRenameKey] = @(_diskImageReadWriteRename) ?: @NO;
    settingsDict[NBCSettingsBaseSystemDiskImageSizeKey] = @([_baseSystemDiskImageSize integerValue]) ?: @10;
    settingsDict[NBCSettingsIncludeConsoleAppKey] = @(_includeConsoleApp) ?: @NO;
    settingsDict[NBCSettingsCasperAllowInvalidCertificateKey] = @(_allowInvalidCertificate) ?: @NO;
    settingsDict[NBCSettingsCasperJSSCACertificateKey] = _jssCACertificate ?: @{};
    settingsDict[NBCSettingsCasperImagingDebugModeKey] = @(_enableCasperImagingDebugMode) ?: @NO;
    settingsDict[NBCSettingsEnableLaunchdLoggingKey] = @(_enableLaunchdLogging) ?: @NO;
    settingsDict[NBCSettingsLaunchConsoleAppKey] = @(_launchConsoleApp) ?: @NO;
    settingsDict[NBCSettingsIncludeRubyKey] = @(_includeRuby) ?: @NO;
    settingsDict[NBCSettingsAddTrustedNetBootServersKey] = @(_addTrustedNetBootServers) ?: @NO;
    settingsDict[NBCSettingsAddCustomRAMDisksKey] = @(_addCustomRAMDisks) ?: @NO;
    settingsDict[NBCSettingsIncludePythonKey] = @(_includePython) ?: @NO;
    settingsDict[NBCSettingsUSBLabelKey] = _usbLabel ?: @"";

    NSMutableArray *certificateArray = [[NSMutableArray alloc] init];
    for (NSDictionary *certificateDict in _certificateTableViewContents) {
        NSData *certificateData = certificateDict[NBCDictionaryKeyCertificate];
        if (certificateData != nil) {
            [certificateArray insertObject:certificateData atIndex:0];
        }
    }
    settingsDict[NBCSettingsCertificatesKey] = certificateArray ?: @[];

    NSMutableArray *packageArray = [[NSMutableArray alloc] init];
    for (NSDictionary *packageDict in _packagesTableViewContents) {
        NSString *packagePath = packageDict[NBCDictionaryKeyPackagePath];
        if ([packagePath length] != 0) {
            [packageArray insertObject:packagePath atIndex:0];
        }
    }
    settingsDict[NBCSettingsPackagesKey] = packageArray ?: @[];

    NSMutableArray *ramDisksArray = [[NSMutableArray alloc] init];
    for (NSDictionary *ramDiskDict in _ramDisks) {
        if ([ramDiskDict count] != 0) {
            [ramDisksArray insertObject:ramDiskDict atIndex:0];
        }
    }
    settingsDict[NBCSettingsRAMDisksKey] = ramDisksArray ?: @[];

    NSMutableArray *trustedNetBootServersArray = [[NSMutableArray alloc] init];
    for (NSString *trustedNetBootServer in _trustedServers) {
        if ([trustedNetBootServer length] != 0) {
            [trustedNetBootServersArray insertObject:trustedNetBootServer atIndex:0];
        }
    }
    settingsDict[NBCSettingsTrustedNetBootServersKey] = trustedNetBootServersArray ?: @[];

    NSString *selectedTimeZone;
    NSString *selectedTimeZoneCity = [_selectedMenuItem title];
    if ([selectedTimeZoneCity isEqualToString:NBCMenuItemCurrent]) {
        selectedTimeZone = selectedTimeZoneCity;
    } else {
        NSString *selectedTimeZoneRegion = [[_selectedMenuItem menu] title];
        selectedTimeZone = [NSString stringWithFormat:@"%@/%@", selectedTimeZoneRegion, selectedTimeZoneCity];
    }
    settingsDict[NBCSettingsTimeZoneKey] = selectedTimeZone ?: NBCMenuItemCurrent;

    return [settingsDict copy];
} // haveettingsFromUI

- (void)createSettingsFromNBI:(NSURL *)nbiURL {
#pragma unused(nbiURL)
} // returnSettingsFromUI

- (NSDictionary *)returnSettingsFromURL:(NSURL *)url {

    NSDictionary *mainDict = [[NSDictionary alloc] initWithContentsOfURL:url];
    NSDictionary *settingsDict;
    if (mainDict) {
        settingsDict = mainDict[NBCSettingsSettingsKey];
    }

    return settingsDict;
} // returnSettingsFromURL

- (void)saveUISettingsWithName:(NSString *)name atUrl:(NSURL *)url {

    NSURL *settingsURL = url;
    // -------------------------------------------------------------
    //  Create an empty dict and add template type, name and version
    // -------------------------------------------------------------
    NSMutableDictionary *mainDict = [[NSMutableDictionary alloc] init];
    mainDict[NBCSettingsTitleKey] = name;
    mainDict[NBCSettingsTypeKey] = NBCSettingsTypeCasper;
    mainDict[NBCSettingsVersionKey] = NBCSettingsFileVersion;

    // ----------------------------------------------------------------
    //  Get current UI settings and add to settings sub-dict
    // ----------------------------------------------------------------
    NSDictionary *settingsDict = [self returnSettingsFromUI];
    mainDict[NBCSettingsSettingsKey] = settingsDict;

    // -------------------------------------------------------------
    //  If no url was passed it means it's never been saved before.
    //  Create a new UUID and set 'settingsURL' to the new settings file
    // -------------------------------------------------------------
    if (settingsURL == nil) {
        NSString *uuid = [[NSUUID UUID] UUIDString];
        settingsURL = [_templatesFolderURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.nbictemplate", uuid]];
    }

    // -------------------------------------------------------------
    //  Create the template folder if it doesn't exist.
    // -------------------------------------------------------------
    NSError *error;
    NSFileManager *fm = [[NSFileManager alloc] init];

    if (![_templatesFolderURL checkResourceIsReachableAndReturnError:&error]) {
        if (![fm createDirectoryAtURL:_templatesFolderURL withIntermediateDirectories:YES attributes:nil error:&error]) {
            DDLogError(@"[ERROR] Casper template folder create failed!");
            DDLogError(@"[ERROR] %@", error);
        }
    }

    // -------------------------------------------------------------
    //  Write settings to url and update _templatesDict
    // -------------------------------------------------------------
    if ([mainDict writeToURL:settingsURL atomically:NO]) {
        _templatesDict[name] = settingsURL;
    } else {
        DDLogError(@"[ERROR] Writing Casper template to disk failed!");
    }
} // saveUISettingsWithName:atUrl

- (BOOL)haveSettingsChanged {

    BOOL retval = YES;

    NSURL *defaultSettingsURL = [[NSBundle mainBundle] URLForResource:NBCFileNameCasperDefaults withExtension:@"plist"];
    if ([defaultSettingsURL checkResourceIsReachableAndReturnError:nil]) {
        NSDictionary *currentSettings = [self returnSettingsFromUI];
        NSDictionary *defaultSettings = [NSDictionary dictionaryWithContentsOfURL:defaultSettingsURL];
        if ([currentSettings count] != 0 && [defaultSettings count] != 0) {
            if ([currentSettings isEqualToDictionary:defaultSettings]) {
                return NO;
            } else {
                /*
                 NSArray *keys = [currentSettings allKeys];
                 for ( NSString *key in keys ) {
                 id currentValue = currentSettings[key];
                 id defaultValue = defaultSettings[key];
                 if ( ! [currentValue isEqualTo:defaultValue] || ! [[currentValue class] isEqualTo:[defaultValue class]]) {
                 DDLogDebug(@"[DEBUG] Key \"%@\" has changed", key);
                 DDLogDebug(@"[DEBUG] Value from current UI settings: %@ (%@)", currentValue, [currentValue class]);
                 DDLogDebug(@"[DEBUG] Value from default settings: %@ (%@)", defaultValue, [defaultValue class]);
                 }
                 }

                keys = [defaultSettings allKeys];
                for ( NSString *key in keys ) {
                    id currentValue = currentSettings[key];
                    id defaultValue = defaultSettings[key];
                    if ( ! [currentValue isEqualTo:defaultValue] || ! [[currentValue class] isEqualTo:[defaultValue class]]) {
                        DDLogDebug(@"[DEBUG] Key \"%@\" has changed", key);
                        DDLogDebug(@"[DEBUG] Value from current UI settings: %@ (%@)", currentValue, [currentValue class]);
                        DDLogDebug(@"[DEBUG] Value from default settings: %@ (%@)", defaultValue, [defaultValue class]);
                    }
                }
                 */
            }
        }
    }

    if ([_selectedTemplate isEqualToString:NBCMenuItemUntitled]) {
        return retval;
    }

    NSError *error = nil;
    NSURL *savedSettingsURL = _templatesDict[_selectedTemplate];
    if ([savedSettingsURL checkResourceIsReachableAndReturnError:&error]) {
        NSDictionary *currentSettings = [self returnSettingsFromUI];
        NSDictionary *savedSettings = [self returnSettingsFromURL:savedSettingsURL];
        if ([currentSettings count] != 0 && [savedSettings count] != 0) {
            if ([currentSettings isEqualToDictionary:savedSettings]) {
                retval = NO;
            }
        } else {
            DDLogError(@"[ERROR] Could not compare UI settings to saved template settings, one of them was empty!");
        }
    } else {
        DDLogError(@"[ERROR] %@", [error localizedDescription]);
    }

    return retval;
} // haveSettingsChanged

- (void)expandVariablesForCurrentSettings {

    // -------------------------------------------------------------
    //  Expand tilde in destination folder path
    // -------------------------------------------------------------
    if ([_destinationFolder hasPrefix:@"~"]) {
        NSString *destinationFolderPath = [_destinationFolder stringByExpandingTildeInPath];
        [self setDestinationFolder:destinationFolderPath];
    }

    // -------------------------------------------------------------
    //  Expand variables in NBI Index
    // -------------------------------------------------------------
    NSString *nbiIndex = [NBCVariables expandVariables:_nbiIndex source:_source applicationSource:_siuSource];
    [_textFieldIndexPreview setStringValue:[NSString stringWithFormat:@"Index: %@", nbiIndex]];

    // -------------------------------------------------------------
    //  Expand variables in NBI Name
    // -------------------------------------------------------------
    NSString *nbiName = [NBCVariables expandVariables:_nbiName source:_source applicationSource:_siuSource];
    [_textFieldNBINamePreview setStringValue:[NSString stringWithFormat:@"%@.nbi", nbiName]];

    // -------------------------------------------------------------
    //  Expand variables in NBI Description
    // -------------------------------------------------------------
    NSString *nbiDescription = [NBCVariables expandVariables:_nbiDescription source:_source applicationSource:_siuSource];
    [_textFieldNBIDescriptionPreview setStringValue:nbiDescription];

    // -------------------------------------------------------------
    //  Expand variables in NBI Icon Path
    // -------------------------------------------------------------
    NSString *nbiIconPath = [NBCVariables expandVariables:_nbiIconPath source:_source applicationSource:_siuSource];
    [self setNbiIcon:nbiIconPath];

    // -------------------------------------------------------------
    //  Expand variables in Image Background Path
    // -------------------------------------------------------------
    NSString *customBackgroundPath = [NBCVariables expandVariables:_imageBackgroundURL source:_source applicationSource:_siuSource];
    [self setImageBackground:customBackgroundPath];

} // expandVariablesForCurrentSettings

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark IBAction Buttons
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (IBAction)buttonChooseDestinationFolder:(id)sender {
#pragma unused(sender)

    NSOpenPanel *chooseDestionation = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [chooseDestionation setTitle:@"Choose Destination Folder"];
    [chooseDestionation setPrompt:@"Choose"];
    [chooseDestionation setCanChooseFiles:NO];
    [chooseDestionation setCanChooseDirectories:YES];
    [chooseDestionation setCanCreateDirectories:YES];
    [chooseDestionation setAllowsMultipleSelection:NO];

    if ([chooseDestionation runModal] == NSModalResponseOK) {
        // -------------------------------------------------------------------------
        //  Get first item in URL array returned (should only be one) and update UI
        // -------------------------------------------------------------------------
        NSArray *selectedURLs = [chooseDestionation URLs];
        NSURL *selectedURL = [selectedURLs firstObject];
        [self setDestinationFolder:[selectedURL path]];
    }
} // buttonChooseDestinationFolder

- (IBAction)buttonPopOver:(id)sender {

    [self updatePopOver];
    [_popOverVariables showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSMaxXEdge];
} // buttonPopOver

- (void)updatePopOver {
    NSString *separator = @";";
    NSString *variableString = [NSString stringWithFormat:@"%%OSVERSION%%%@"
                                                           "%%OSMAJOR%%%@"
                                                           "%%OSMINOR%%%@"
                                                           "%%OSPATCH%%%@"
                                                           "%%OSBUILD%%%@"
                                                           "%%DATE%%%@"
                                                           "%%OSINDEX%%%@"
                                                           "%%NBCVERSION%%%@",
                                                          separator, separator, separator, separator, separator, separator, separator, separator];
    NSString *expandedVariables = [NBCVariables expandVariables:variableString source:_source applicationSource:_siuSource];
    NSArray *expandedVariablesArray = [expandedVariables componentsSeparatedByString:separator];

    // %OSVERSION%
    if (1 <= [expandedVariablesArray count]) {
        NSString *osVersion = expandedVariablesArray[0];
        if ([osVersion length] != 0) {
            [self setPopOverOSVersion:osVersion];
        }
    }
    // %OSMAJOR%
    if (2 <= [expandedVariablesArray count]) {
        NSString *osMajor = expandedVariablesArray[1];
        if ([osMajor length] != 0) {
            [self setPopOverOSMajor:osMajor];
        }
    }
    // %OSMINOR%
    if (3 <= [expandedVariablesArray count]) {
        NSString *osMinor = expandedVariablesArray[2];
        if ([osMinor length] != 0) {
            [self setPopOverOSMinor:osMinor];
        }
    }
    // %OSPATCH%
    if (4 <= [expandedVariablesArray count]) {
        NSString *osPatch = expandedVariablesArray[3];
        if ([osPatch length] != 0) {
            [self setPopOverOSPatch:osPatch];
        }
    }
    // %OSBUILD%
    if (5 <= [expandedVariablesArray count]) {
        NSString *osBuild = expandedVariablesArray[4];
        if ([osBuild length] != 0) {
            [self setPopOverOSBuild:osBuild];
        }
    }
    // %DATE%
    if (6 <= [expandedVariablesArray count]) {
        NSString *date = expandedVariablesArray[5];
        if ([date length] != 0) {
            [self setPopOverDate:date];
        }
    }
    // %OSINDEX%
    if (7 <= [expandedVariablesArray count]) {
        NSString *osIndex = expandedVariablesArray[6];
        if ([osIndex length] != 0) {
            [self setPopOverOSIndex:osIndex];
        }
    }
    // %NBCVERSION%
    if (8 <= [expandedVariablesArray count]) {
        NSString *nbcVersion = expandedVariablesArray[7];
        if ([nbcVersion length] != 0) {
            [self setNbcVersion:nbcVersion];
        }
    }
    // %COUNTER%
    [self setPopOverIndexCounter:[[[NSUserDefaults standardUserDefaults] objectForKey:NBCUserDefaultsIndexCounter] stringValue]];
    // %SIUVERSION%
    [self setSiuVersion:[_siuSource systemImageUtilityVersion]];
} // updatePopOver

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark IBAction PopUpButtons
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)importTemplateAtURL:(NSURL *)url templateInfo:(NSDictionary *)templateInfo {
#pragma unused(templateInfo)
    DDLogInfo(@"Importing template at path: %@", [url path]);
} // importTemplateAtURL

- (void)updatePopUpButtonTemplates {
    [_templates updateTemplateListForPopUpButton:_popUpButtonTemplates title:nil];
} // updatePopUpButtonTemplates

- (IBAction)popUpButtonTemplates:(id)sender {

    NSString *selectedTemplate = [[sender selectedItem] title];
    BOOL settingsChanged = [self haveSettingsChanged];

    if ([_selectedTemplate isEqualToString:NBCMenuItemUntitled]) {
        [_templates showSheetSaveUntitled:selectedTemplate buildNBI:NO preWorkflowTasks:@{}];
        return;
    } else if (settingsChanged) {
        NSDictionary *alertInfo = @{NBCAlertTagKey : NBCAlertTagSettingsUnsaved, NBCAlertUserInfoSelectedTemplate : selectedTemplate};

        NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
        [alert showAlertSettingsUnsaved:@"You have unsaved settings, do you want to discard changes and continue?" alertInfo:alertInfo];
    } else {
        [self setSelectedTemplate:[[sender selectedItem] title]];
        [self updateUISettingsFromURL:_templatesDict[_selectedTemplate]];
    }
} // popUpButtonTemplates

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark PopUpButton NBI Creation Tool
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)uppdatePopUpButtonTool {

    NSString *systemUtilityVersion = [_siuSource systemImageUtilityVersion];
    if ([systemUtilityVersion length] != 0) {
        [_textFieldSIUVersionString setStringValue:systemUtilityVersion];
    } else {
        [_textFieldSIUVersionString setStringValue:@"Not Installed"];
    }

    if (_popUpButtonTool) {
        [_popUpButtonTool removeAllItems];
        [_popUpButtonTool addItemWithTitle:NBCMenuItemNBICreator];
        [_popUpButtonTool addItemWithTitle:NBCMenuItemSystemImageUtility];
        [_popUpButtonTool selectItemWithTitle:_nbiCreationTool];
        [self setNbiCreationTool:[_popUpButtonTool titleOfSelectedItem]];
    }
} // uppdatePopUpButtonTool

- (IBAction)popUpButtonTool:(id)sender {

    NSString *selectedVersion = [[sender selectedItem] title];
    if ([selectedVersion isEqualToString:NBCMenuItemSystemImageUtility]) {
        [self showSystemImageUtilityVersion];
        if ([_nbiDescription isEqualToString:NBCNBIDescriptionNBC]) {
            [self setNbiDescription:NBCNBIDescriptionSIU];
        }

        [self expandVariablesForCurrentSettings];
    } else {
        [self hideSystemImageUtilityVersion];
        if ([_nbiDescription isEqualToString:NBCNBIDescriptionSIU]) {
            [self setNbiDescription:NBCNBIDescriptionNBC];
        }

        [self expandVariablesForCurrentSettings];
    }
} // popUpButtonTool

- (void)showSystemImageUtilityVersion {

    [self setUseSystemImageUtility:YES];
    [_constraintTemplatesBoxHeight setConstant:93];
    [_constraintSavedTemplatesToTool setConstant:32];
} // showCasperLocalVersionInput

- (void)hideSystemImageUtilityVersion {

    [self setUseSystemImageUtility:NO];
    [_constraintTemplatesBoxHeight setConstant:70];
    [_constraintSavedTemplatesToTool setConstant:8];
} // hideCasperLocalVersionInput

- (IBAction)buttonChooseCasperImagingPath:(id)sender {
#pragma unused(sender)

    NSOpenPanel *chooseDestionation = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [chooseDestionation setTitle:@"Select Casper Imaging Application"];
    [chooseDestionation setPrompt:@"Choose"];
    [chooseDestionation setCanChooseFiles:YES];
    [chooseDestionation setAllowedFileTypes:@[ @"com.apple.application-bundle" ]];
    [chooseDestionation setCanChooseDirectories:NO];
    [chooseDestionation setCanCreateDirectories:NO];
    [chooseDestionation setAllowsMultipleSelection:NO];

    if ([chooseDestionation runModal] == NSModalResponseOK) {
        // -------------------------------------------------------------------------
        //  Get first item in URL array returned (should only be one) and update UI
        // -------------------------------------------------------------------------
        NSArray *selectedURLs = [chooseDestionation URLs];
        NSURL *selectedURL = [selectedURLs firstObject];
        NSBundle *bundle = [NSBundle bundleWithURL:selectedURL];
        if (bundle != nil) {
            NSString *bundleIdentifier = [bundle objectForInfoDictionaryKey:@"CFBundleIdentifier"];
            if ([bundleIdentifier isEqualToString:NBCCasperImagingBundleIdentifier]) {
                [self setCasperImagingPath:[selectedURL path]];
                NSString *bundleVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
                if ([bundleVersion length] != 0) {
                    [self setCasperImagingVersion:bundleVersion];
                }
                return;
            }
        }
        [NBCAlerts showAlertUnrecognizedCasperImagingApplication];
    }
} // buttonChooseCasperLocalPath

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Verify Build Button
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)verifyBuildButton {

    BOOL buildEnabled = YES;

    // -------------------------------------------------------------
    //  Verify that the current source is not nil.
    // -------------------------------------------------------------
    if (_source == nil) {
        buildEnabled = NO;
    }

    // -------------------------------------------------------------
    //  Verify that the destination folder is not empty
    // -------------------------------------------------------------
    if ([_destinationFolder length] == 0) {
        buildEnabled = NO;
    }

    // --------------------------------------------------------------------------------
    //  Post a notification that sets the button state to value of bool 'buildEnabled'
    // --------------------------------------------------------------------------------
    NSDictionary *userInfo = @{ NBCNotificationUpdateButtonBuildUserInfoButtonState : @(buildEnabled) };
    [[NSNotificationCenter defaultCenter] postNotificationName:NBCNotificationUpdateButtonBuild object:self userInfo:userInfo];

} // verifyBuildButton

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Build NBI
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)buildNBI:(NSDictionary *)preWorkflowTasks {

    if (!_isNBI && [self haveSettingsChanged]) {
        NSDictionary *alertInfo =
            @{ NBCAlertTagKey : NBCAlertTagSettingsUnsavedBuild,
               NBCAlertUserInfoSelectedTemplate : _selectedTemplate,
               NBCAlertUserInfoPreWorkflowTasks : preWorkflowTasks ?: @{} };

        NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
        [alert showAlertSettingsUnsavedBuild:@"You have unsaved settings, do you want to save current template and continue?" alertInfo:alertInfo];
    } else if (_isNBI && ![self haveSettingsChanged]) {
        [NBCAlerts showAlertSettingsUnchangedNBI];
        return;
    } else {
        [self verifySettings:preWorkflowTasks];
    }
} // buildNBI

- (void)verifySettings:(NSDictionary *)preWorkflowTasks {

    DDLogInfo(@"Verifying settings...");

    NBCWorkflowItem *workflowItem = [[NBCWorkflowItem alloc] initWithWorkflowType:kWorkflowTypeCasper workflowSessionType:kWorkflowSessionTypeGUI];
    [workflowItem setSource:_source];
    [workflowItem setApplicationSource:_siuSource];
    [workflowItem setSettingsViewController:self];
    [workflowItem setPreWorkflowTasks:preWorkflowTasks];

    // ----------------------------------------------------------------
    //  Collect current UI settings and pass them through verification
    // ----------------------------------------------------------------
    NSMutableDictionary *userSettings = [[self returnSettingsFromUI] mutableCopy];
    if ([userSettings count] != 0) {

        // Add create usb device here as this settings only is avalable to this session
        userSettings[NBCSettingsCreateUSBDeviceKey] = @(_createUSBDevice);
        userSettings[NBCSettingsUSBBSDNameKey] = _usbDevicesDict[[_popUpButtonUSBDevices titleOfSelectedItem]] ?: @"";

        // Add userSettings dict to workflowItem
        [workflowItem setUserSettings:[userSettings copy]];

        // Instantiate settingsController and run verification
        NBCSettingsController *sc = [[NBCSettingsController alloc] init];
        NSDictionary *errorInfoDict = [sc verifySettingsForWorkflowItem:workflowItem];

        if ([errorInfoDict count] != 0) {
            BOOL configurationError = NO;
            BOOL configurationWarning = NO;
            NSMutableString *alertInformativeText = [[NSMutableString alloc] init];
            NSArray *error = errorInfoDict[NBCSettingsError];
            NSArray *warning = errorInfoDict[NBCSettingsWarning];

            if ([error count] != 0) {
                configurationError = YES;
                for (NSString *errorString in error) {
                    [alertInformativeText appendString:[NSString stringWithFormat:@"\n\n• %@", errorString]];
                }
            }

            if ([warning count] != 0) {
                configurationWarning = YES;
                for (NSString *warningString in warning) {
                    [alertInformativeText appendString:[NSString stringWithFormat:@"\n\n• %@", warningString]];
                }
            }

            // ----------------------------------------------------------------
            //  If any errors are found, display alert and stop NBI creation
            // ----------------------------------------------------------------
            if (configurationError) {
                [NBCAlerts showAlertSettingsError:alertInformativeText];
            }

            // --------------------------------------------------------------------------------
            //  If only warnings are found, display alert and allow user to continue or cancel
            // --------------------------------------------------------------------------------
            if (!configurationError && configurationWarning) {
                NSDictionary *alertInfo = @{NBCAlertTagKey : NBCAlertTagSettingsWarning, NBCAlertWorkflowItemKey : workflowItem};

                NBCAlerts *alerts = [[NBCAlerts alloc] initWithDelegate:self];
                [alerts showAlertSettingsWarning:alertInformativeText alertInfo:alertInfo];
            }
        } else {
            [self prepareWorkflowItem:workflowItem];
        }
    } else {
        [NBCAlerts showAlertErrorWithTitle:@"Configuration Error"
                           informativeText:@"Settings in UI could not be read.\n\nTry saving your template and restart the application.\n\nIf this problem persists, consider turning on debug logging "
                                           @"in preferences and open an issue on GitHub."];
    }
} // verifySettings

- (void)prepareWorkflowItem:(NBCWorkflowItem *)workflowItem {
    NSDictionary *userSettings = [workflowItem userSettings];
    NSMutableDictionary *resourcesSettings = [[NSMutableDictionary alloc] init];
    NSError *err = nil;
    NSString *selectedLanguage = userSettings[NBCSettingsLanguageKey];
    if ([selectedLanguage isEqualToString:NBCMenuItemCurrent]) {
        NSLocale *currentLocale = [NSLocale currentLocale];
        NSString *currentLanguageID = [NSLocale preferredLanguages][0];
        if ([currentLanguageID length] != 0) {
            resourcesSettings[NBCSettingsLanguageKey] = currentLanguageID;
        } else {
            [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"Could not get current language ID"];
            DDLogError(@"[ERROR] Could not get current language ID!");
            return;
        }

        NSString *currentLocaleIdentifier = [currentLocale localeIdentifier];
        if ([currentLocaleIdentifier length] != 0) {
            resourcesSettings[NBCSettingsLocale] = currentLocaleIdentifier;
        }

        NSString *currentCountry = [currentLocale objectForKey:NSLocaleCountryCode];
        if ([currentCountry length] != 0) {
            resourcesSettings[NBCSettingsCountry] = currentCountry;
        }
    } else {
        NSArray *allKeys = [_languageDict allKeysForObject:selectedLanguage];
        if ([allKeys count] != 0) {
            NSString *languageID = [allKeys firstObject];
            if ([languageID length] != 0) {
                resourcesSettings[NBCSettingsLanguageKey] = languageID;
            } else {
                [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"Could not get language ID"];
                DDLogError(@"[ERROR] Could not get language ID!");
                return;
            }

            if ([languageID containsString:@"-"]) {
                NSString *localeFromLanguage = [languageID stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
                if ([localeFromLanguage length] != 0) {
                    resourcesSettings[NBCSettingsLocale] = localeFromLanguage;

                    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:localeFromLanguage];
                    NSString *country = [locale objectForKey:NSLocaleCountryCode];
                    if ([country length] != 0) {
                        resourcesSettings[NBCSettingsCountry] = country;
                    }
                }
            }
        } else {
            [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:[NSString stringWithFormat:@"No objects in language dict for %@", selectedLanguage]];
            DDLogError(@"[ERROR] No objects in language dict for %@", selectedLanguage);
            return;
        }
    }

    // -------------------------------------------------------------------------
    //  Keyboard Layout Name
    // -------------------------------------------------------------------------
    DDLogDebug(@"[DEBUG] Preparing selected keyboard layout name...");
    NSDictionary *hiToolboxDict;
    NSURL *userLibraryURL = [[NSFileManager defaultManager] URLForDirectory:NSLibraryDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    DDLogDebug(@"[DEBUG] User library path: %@", [userLibraryURL path]);
    NSURL *hiToolboxURL = [userLibraryURL URLByAppendingPathComponent:@"Preferences/com.apple.HIToolbox.plist"];
    NSString *selectedKeyboardLayoutName = userSettings[NBCSettingsKeyboardLayoutKey];
    DDLogDebug(@"[DEBUG] Selected keyboard layout name: %@", selectedKeyboardLayoutName);
    if ([selectedKeyboardLayoutName isEqualToString:NBCMenuItemCurrent]) {
        DDLogDebug(@"[DEBUG] Checking HiToolbox URL...");
        if (![hiToolboxURL checkResourceIsReachableAndReturnError:&err]) {
            DDLogError(@"[ERROR] %@", err);
            [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"Could not find hiToolboxPlist!"];
            return;
        }

        hiToolboxDict = [NSDictionary dictionaryWithContentsOfURL:hiToolboxURL];
        if ([hiToolboxDict isKindOfClass:[NSDictionary class]]) {

            if ([hiToolboxDict count] == 0) {
                DDLogError(@"[ERROR] HIToolbox.plist was empty!");
                [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"HIToolbox.plist was empty"];
                return;
            }

            NSArray *appleSelectedInputSources = hiToolboxDict[@"AppleSelectedInputSources"] ?: @[];
            if ([appleSelectedInputSources count] == 0) {
                DDLogError(@"[ERROR] AppleSelectedInputSources in HIToolbox.plist was empty!");
                [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"AppleSelectedInputSources in HIToolbox.plist was empty"];
                return;
            }

            NSDictionary *currentInputSource = [appleSelectedInputSources firstObject] ?: @{};
            if ([currentInputSource count] == 0) {
                DDLogError(@"[ERROR] First object in AppleSelectedInputSources in HIToolbox.plist was empty!");
                [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"First object in AppleSelectedInputSources in HIToolbox.plist was empty"];
                return;
            }

            selectedKeyboardLayoutName = currentInputSource[@"KeyboardLayout Name"];
            DDLogDebug(@"[DEBUG] Current keyboard layout name: %@", selectedKeyboardLayoutName);
            if ([selectedKeyboardLayoutName length] != 0) {
                resourcesSettings[NBCSettingsKeyboardLayoutKey] = selectedKeyboardLayoutName;
            } else {
                DDLogError(@"[ERROR] Selected keyboard layout name was empty");
                [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"Could not get current keyboard layout name"];
                return;
            }
        } else {
            DDLogError(@"[ERROR] hiToolboxDict is NOT a dict, it's of class: %@", [hiToolboxDict class]);
            return;
        }
    } else {
        resourcesSettings[NBCSettingsKeyboardLayoutKey] = selectedKeyboardLayoutName;
    }

    NSString *selectedKeyboardLayout = _keyboardLayoutDict[selectedKeyboardLayoutName];
    if ([selectedKeyboardLayout length] == 0) {
        NSString *currentKeyboardLayout = hiToolboxDict[@"AppleCurrentKeyboardLayoutInputSourceID"];
        if ([currentKeyboardLayout length] != 0) {
            resourcesSettings[NBCSettingsKeyboardLayoutID] = currentKeyboardLayout;
        } else {
            [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"Could not get current keyboard layout"];
            DDLogError(@"[ERROR] Could not get current keyboard layout!");
            return;
        }
    } else {
        resourcesSettings[NBCSettingsKeyboardLayoutID] = selectedKeyboardLayout;
    }

    NSString *selectedTimeZone = [self timeZoneFromMenuItem:_selectedMenuItem];
    if ([selectedTimeZone length] != 0) {
        if ([selectedTimeZone isEqualToString:NBCMenuItemCurrent]) {
            NSTimeZone *currentTimeZone = [NSTimeZone defaultTimeZone];
            NSString *currentTimeZoneName = [currentTimeZone name];
            resourcesSettings[NBCSettingsTimeZoneKey] = currentTimeZoneName;
        } else {
            resourcesSettings[NBCSettingsTimeZoneKey] = selectedTimeZone;
        }
    } else {
        [NBCAlerts showAlertErrorWithTitle:@"Preparing build failed" informativeText:@"Selected TimeZone was empty"];
        DDLogError(@"[ERROR] Selected TimeZone was empty!");
        return;
    }

    NSMutableArray *certificates = [[NSMutableArray alloc] init];
    for (NSDictionary *certificateDict in _certificateTableViewContents) {
        NSData *certificate = certificateDict[NBCDictionaryKeyCertificate];
        [certificates addObject:certificate];
    }
    resourcesSettings[NBCSettingsCertificatesKey] = certificates;

    NSMutableArray *packages = [[NSMutableArray alloc] init];
    for (NSDictionary *packageDict in _packagesTableViewContents) {
        NSString *packagePath = packageDict[NBCDictionaryKeyPackagePath];
        [packages addObject:packagePath];
    }

    resourcesSettings[NBCSettingsPackagesKey] = packages;
    [workflowItem setResourcesSettings:[resourcesSettings copy]];

    // --------------------------------
    //  Get Authorization
    // --------------------------------
    NSData *authData = [workflowItem authData];
    if (!authData) {
        authData = [NBCHelperAuthorization authorizeHelper:&err];
        if (err) {
            DDLogError(@"[ERROR] %@", [err localizedDescription]);
        }
        [workflowItem setAuthData:authData];
    }

    // ------------------------------------------------------
    //  Authorize the workflow before adding it to the queue
    // ------------------------------------------------------
    dispatch_queue_t taskQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(taskQueue, ^{

      NBCHelperConnection *helperConnector = [[NBCHelperConnection alloc] init];
      [helperConnector connectToHelper];
      [[[helperConnector connection] remoteObjectProxyWithErrorHandler:^(NSError *proxyError) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [NBCAlerts showAlertErrorWithTitle:@"Helper Connection Error"
                             informativeText:[NSString stringWithFormat:@"%@\n\nPlease try re-launching NBICreator and try installing the helper again.\n\nIf that doesn't work, consult the FAQ on "
                                                                        @"the NBICreator GitHub wiki page under the title:\n\n\"Can't connect to helper\".",
                                                                        [proxyError localizedDescription]]];
          DDLogError(@"[ERROR] %@", [proxyError localizedDescription]);
        });
      }] authorizeWorkflowCasper:authData
                        withReply:^(NSError *error) {
                          if (!error) {
                              dispatch_async(dispatch_get_main_queue(), ^{

                                // -------------------------------------------------------------
                                //  Post notification to add workflow item to queue
                                // -------------------------------------------------------------
                                NSDictionary *userInfo = @{NBCNotificationAddWorkflowItemToQueueUserInfoWorkflowItem : workflowItem};
                                [[NSNotificationCenter defaultCenter] postNotificationName:NBCNotificationAddWorkflowItemToQueue object:self userInfo:userInfo];
                              });
                          } else {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                DDLogError(@"[ERROR] %@", [error localizedDescription]);
                              });
                          }
                        }];
    });

} // prepareWorkflowItem

- (NSString *)timeZoneFromMenuItem:(NSMenuItem *)menuItem {
    NSString *timeZone;

    NSString *selectedTimeZoneCity = [menuItem title];
    if ([selectedTimeZoneCity isEqualToString:NBCMenuItemCurrent]) {
        timeZone = selectedTimeZoneCity;
    } else {
        NSString *selectedTimeZoneRegion = [[menuItem menu] title];
        timeZone = [NSString stringWithFormat:@"%@/%@", selectedTimeZoneRegion, selectedTimeZoneCity];
    }

    return timeZone;
}

- (void)populatePopUpButtonTimeZone {
    [self setTimeZoneArray:[NSTimeZone knownTimeZoneNames]];
    if ([_timeZoneArray count] != 0) {
        NSMenu *menuAfrica = [[NSMenu alloc] initWithTitle:@"Africa"];
        [menuAfrica setAutoenablesItems:NO];
        NSMenu *menuAmerica = [[NSMenu alloc] initWithTitle:@"America"];
        [menuAmerica setAutoenablesItems:NO];
        NSMenu *menuAntarctica = [[NSMenu alloc] initWithTitle:@"Antarctica"];
        [menuAntarctica setAutoenablesItems:NO];
        NSMenu *menuArctic = [[NSMenu alloc] initWithTitle:@"Arctic"];
        [menuArctic setAutoenablesItems:NO];
        NSMenu *menuAsia = [[NSMenu alloc] initWithTitle:@"Asia"];
        [menuAsia setAutoenablesItems:NO];
        NSMenu *menuAtlantic = [[NSMenu alloc] initWithTitle:@"Atlantic"];
        [menuAtlantic setAutoenablesItems:NO];
        NSMenu *menuAustralia = [[NSMenu alloc] initWithTitle:@"Australia"];
        [menuAustralia setAutoenablesItems:NO];
        NSMenu *menuEurope = [[NSMenu alloc] initWithTitle:@"Europe"];
        [menuEurope setAutoenablesItems:NO];
        NSMenu *menuIndian = [[NSMenu alloc] initWithTitle:@"Indian"];
        [menuIndian setAutoenablesItems:NO];
        NSMenu *menuPacific = [[NSMenu alloc] initWithTitle:@"Pacific"];
        [menuPacific setAutoenablesItems:NO];
        for (NSString *timeZoneName in _timeZoneArray) {
            if ([timeZoneName isEqualToString:@"GMT"]) {
                continue;
            }

            NSArray *timeZone = [timeZoneName componentsSeparatedByString:@"/"];
            NSString *timeZoneRegion = timeZone[0];
            __block NSString *timeZoneCity = @"";
            if (2 < [timeZone count]) {
                NSRange range;
                range.location = 1;
                range.length = ([timeZone count] - 1);
                [timeZone enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range]
                                            options:0
                                         usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
                                           if ([timeZoneCity length] == 0) {
                                               timeZoneCity = obj;
                                           } else {
                                               timeZoneCity = [NSString stringWithFormat:@"%@/%@", timeZoneCity, obj];
                                           }
                                         }];
            } else {
                timeZoneCity = timeZone[1];
            }

            NSMenuItem *cityMenuItem = [[NSMenuItem alloc] initWithTitle:timeZoneCity action:@selector(selectTimeZone:) keyEquivalent:@""];
            [cityMenuItem setEnabled:YES];
            [cityMenuItem setTarget:self];

            if ([timeZoneRegion isEqualToString:@"Africa"]) {
                [menuAfrica addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"America"]) {
                [menuAmerica addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Antarctica"]) {
                [menuAntarctica addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Arctic"]) {
                [menuArctic addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Asia"]) {
                [menuAsia addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Atlantic"]) {
                [menuAtlantic addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Australia"]) {
                [menuAustralia addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Europe"]) {
                [menuEurope addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Indian"]) {
                [menuIndian addItem:cityMenuItem];
            } else if ([timeZoneRegion isEqualToString:@"Pacific"]) {
                [menuPacific addItem:cityMenuItem];
            }
        }

        [_popUpButtonTimeZone removeAllItems];
        [_popUpButtonTimeZone setAutoenablesItems:NO];
        [_popUpButtonTimeZone addItemWithTitle:NBCMenuItemCurrent];
        [[_popUpButtonTimeZone menu] addItem:[NSMenuItem separatorItem]];

        NSMenuItem *menuItemAfrica = [[NSMenuItem alloc] initWithTitle:@"Africa" action:nil keyEquivalent:@""];
        [menuItemAfrica setSubmenu:menuAfrica];
        [menuItemAfrica setTarget:self];
        [menuItemAfrica setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemAfrica];

        NSMenuItem *menuItemAmerica = [[NSMenuItem alloc] initWithTitle:@"America" action:nil keyEquivalent:@""];
        [menuItemAmerica setSubmenu:menuAmerica];
        [menuItemAmerica setTarget:self];
        [menuItemAmerica setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemAmerica];

        NSMenuItem *menuItemAntarctica = [[NSMenuItem alloc] initWithTitle:@"Antarctica" action:nil keyEquivalent:@""];
        [menuItemAntarctica setSubmenu:menuAntarctica];
        [menuItemAntarctica setTarget:self];
        [menuItemAntarctica setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemAntarctica];

        NSMenuItem *menuItemArctic = [[NSMenuItem alloc] initWithTitle:@"Arctic" action:nil keyEquivalent:@""];
        [menuItemArctic setSubmenu:menuArctic];
        [menuItemArctic setTarget:self];
        [menuItemArctic setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemArctic];

        NSMenuItem *menuItemAsia = [[NSMenuItem alloc] initWithTitle:@"Asia" action:nil keyEquivalent:@""];
        [menuItemAsia setSubmenu:menuAsia];
        [menuItemAsia setTarget:self];
        [menuItemAsia setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemAsia];

        NSMenuItem *menuItemAtlantic = [[NSMenuItem alloc] initWithTitle:@"Atlantic" action:nil keyEquivalent:@""];
        [menuItemAtlantic setSubmenu:menuAtlantic];
        [menuItemAtlantic setTarget:self];
        [menuItemAtlantic setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemAtlantic];

        NSMenuItem *menuItemAustralia = [[NSMenuItem alloc] initWithTitle:@"Australia" action:nil keyEquivalent:@""];
        [menuItemAustralia setSubmenu:menuAustralia];
        [menuItemAustralia setTarget:self];
        [menuItemAustralia setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemAustralia];

        NSMenuItem *menuItemEurope = [[NSMenuItem alloc] initWithTitle:@"Europe" action:nil keyEquivalent:@""];
        [menuItemEurope setSubmenu:menuEurope];
        [menuItemEurope setTarget:self];
        [menuItemEurope setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemEurope];

        NSMenuItem *menuItemIndian = [[NSMenuItem alloc] initWithTitle:@"Indian" action:nil keyEquivalent:@""];
        [menuItemIndian setSubmenu:menuIndian];
        [menuItemIndian setTarget:self];
        [menuItemIndian setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemIndian];

        NSMenuItem *menuItemPacific = [[NSMenuItem alloc] initWithTitle:@"Pacific" action:nil keyEquivalent:@""];
        [menuItemPacific setSubmenu:menuPacific];
        [menuItemPacific setTarget:self];
        [menuItemPacific setEnabled:YES];
        [[_popUpButtonTimeZone menu] addItem:menuItemPacific];

        [self setSelectedMenuItem:[_popUpButtonTimeZone selectedItem]];
    } else {
        DDLogError(@"[ERROR] Could not find language strings file!");
    }
}

- (void)selectTimeZone:(id)sender {
    if (![sender isKindOfClass:[NSMenuItem class]]) {
        return;
    }

    [_selectedMenuItem setState:NSOffState];

    _selectedMenuItem = (NSMenuItem *)sender;
    [_selectedMenuItem setState:NSOnState];

    NSMenuItem *newMenuItem = [_selectedMenuItem copy];

    NSInteger selectedMenuItemIndex = [_popUpButtonTimeZone indexOfSelectedItem];

    if (selectedMenuItemIndex == 0) {
        if (![[_popUpButtonTimeZone itemAtIndex:1] isSeparatorItem]) {
            [_popUpButtonTimeZone removeItemAtIndex:1];
        }
    } else {
        [_popUpButtonTimeZone removeItemAtIndex:selectedMenuItemIndex];
    }

    for (NSMenuItem *menuItem in [[_popUpButtonTimeZone menu] itemArray]) {
        if ([[menuItem title] isEqualToString:NBCMenuItemCurrent]) {
            [_popUpButtonTimeZone removeItemWithTitle:NBCMenuItemCurrent];
            break;
        }
    }
    [[_popUpButtonTimeZone menu] insertItem:newMenuItem atIndex:0];

    if (![[_selectedMenuItem title] isEqualToString:NBCMenuItemCurrent]) {
        [[_popUpButtonTimeZone menu] insertItemWithTitle:NBCMenuItemCurrent action:@selector(selectTimeZone:) keyEquivalent:@"" atIndex:0];
    }
    [_popUpButtonTimeZone selectItem:newMenuItem];
}

- (void)populatePopUpButtonLanguage {
    NSError *error;
    NSURL *languageStringsFile = [NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/IntlPreferences.framework/Versions/A/Resources/Language.strings"];
    if ([languageStringsFile checkResourceIsReachableAndReturnError:&error]) {
        _languageDict = [[NSDictionary dictionaryWithContentsOfURL:languageStringsFile] mutableCopy];
        NSArray *languageArray = [[_languageDict allValues] sortedArrayUsingSelector:@selector(compare:)];
        [_popUpButtonLanguage removeAllItems];
        [_popUpButtonLanguage addItemWithTitle:NBCMenuItemCurrent];
        [[_popUpButtonLanguage menu] addItem:[NSMenuItem separatorItem]];
        [_popUpButtonLanguage addItemsWithTitles:languageArray];
    } else {
        DDLogError(@"[ERROR] Could not find language strings file!");
        DDLogError(@"%@", error);
    }
}

- (void)populatePopUpButtonKeyboardLayout {
    NSDictionary *ref = @{(NSString *)kTISPropertyInputSourceType : (NSString *)kTISTypeKeyboardLayout};

    CFArrayRef sourceList = TISCreateInputSourceList((__bridge CFDictionaryRef)(ref), true);
    for (int i = 0; i < CFArrayGetCount(sourceList); ++i) {
        TISInputSourceRef source = (TISInputSourceRef)(CFArrayGetValueAtIndex(sourceList, i));
        if (!source)
            continue;

        NSString *sourceID = (__bridge NSString *)(TISGetInputSourceProperty(source, kTISPropertyInputSourceID));
        NSString *localizedName = (__bridge NSString *)(TISGetInputSourceProperty(source, kTISPropertyLocalizedName));

        _keyboardLayoutDict[localizedName] = sourceID;
    }

    NSArray *keyboardLayoutArray = [[_keyboardLayoutDict allKeys] sortedArrayUsingSelector:@selector(compare:)];
    [_popUpButtonKeyboardLayout removeAllItems];
    [_popUpButtonKeyboardLayout addItemWithTitle:NBCMenuItemCurrent];
    [[_popUpButtonKeyboardLayout menu] addItem:[NSMenuItem separatorItem]];
    [_popUpButtonKeyboardLayout addItemsWithTitles:keyboardLayoutArray];
}

- (IBAction)buttonAddCertificate:(id)sender {
#pragma unused(sender)
    NSOpenPanel *addCertificates = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [addCertificates setTitle:@"Add Certificates"];
    [addCertificates setPrompt:@"Add"];
    [addCertificates setCanChooseFiles:YES];
    [addCertificates setAllowedFileTypes:@[ @"public.x509-certificate" ]];
    [addCertificates setCanChooseDirectories:NO];
    [addCertificates setCanCreateDirectories:YES];
    [addCertificates setAllowsMultipleSelection:YES];

    if ([addCertificates runModal] == NSModalResponseOK) {
        NSArray *selectedURLs = [addCertificates URLs];
        for (NSURL *certificateURL in selectedURLs) {
            NSData *certificateData = [[NSData alloc] initWithContentsOfURL:certificateURL];
            NSDictionary *certificateDict = [self examineCertificate:certificateData];
            if ([certificateDict count] != 0) {
                [self insertCertificateInTableView:certificateDict];
            }
        }
    }
}

- (IBAction)buttonRemoveCertificate:(id)sender {
#pragma unused(sender)
    NSIndexSet *indexes = [_tableViewCertificates selectedRowIndexes];
    [_certificateTableViewContents removeObjectsAtIndexes:indexes];
    [_tableViewCertificates removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    if ([_certificateTableViewContents count] == 0) {
        [_viewOverlayCertificates setHidden:NO];
    }
}

- (IBAction)buttonAddPackage:(id)sender {
#pragma unused(sender)
    NSOpenPanel *addPackages = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [addPackages setTitle:@"Add Packages"];
    [addPackages setPrompt:@"Add"];
    [addPackages setCanChooseFiles:YES];
    [addPackages setAllowedFileTypes:@[ @"com.apple.installer-package-archive" ]];
    [addPackages setCanChooseDirectories:NO];
    [addPackages setCanCreateDirectories:YES];
    [addPackages setAllowsMultipleSelection:YES];

    if ([addPackages runModal] == NSModalResponseOK) {
        NSArray *selectedURLs = [addPackages URLs];
        for (NSURL *packageURL in selectedURLs) {
            NSDictionary *packageDict = [self examinePackageAtURL:packageURL];
            if ([packageDict count] != 0) {
                [self insertPackageInTableView:packageDict];
            }
        }
    }
}

- (IBAction)buttonRemovePackage:(id)sender {
#pragma unused(sender)
    NSIndexSet *indexes = [_tableViewPackages selectedRowIndexes];
    [_packagesTableViewContents removeObjectsAtIndexes:indexes];
    [_tableViewPackages removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    if ([_packagesTableViewContents count] == 0) {
        [_viewOverlayPackages setHidden:NO];
    }
}

- (NSString *)jssVersionFromDownloadData:(NSData *)data {
    NSString *jssVersion;

    TFHpple *parser = [TFHpple hppleWithHTMLData:data];

    NSString *xpathQueryString = @"/html/head/meta[@name='version']/@content";
    NSArray *nodes = [parser searchWithXPathQuery:xpathQueryString];

    if (!nodes) {
        NSString *downloadString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        DDLogDebug(@"[DEBUG] Download String: %@", downloadString);
    }

    for (TFHppleElement *element in nodes) {
        NSArray *children = [element children];
        for (TFHppleElement *childElement in children) {
            jssVersion = [childElement content];
        }
    }

    return [jssVersion copy];
}

- (IBAction)buttonVerifyJSS:(id)sender {
#pragma unused(sender)
    [self setVerifyingJSS:YES];
    [_imageViewVerifyJSSStatus setHidden:YES];
    [_textFieldVerifyJSSStatus setStringValue:@"Contacting JSS..."];
    [_textFieldVerifyJSSStatus setHidden:NO];

    NSString *jssURLString = _casperJSSURL;
    NSURL *jssURL;
    if ([jssURLString length] == 0) {
        [_imageViewVerifyJSSStatus setHidden:NO];
        [_textFieldVerifyJSSStatus setHidden:NO];
        [_textFieldVerifyJSSStatus setStringValue:@"No URL was passed!"];
        // Show Alert
        return;
    } else {
        jssURL = [NSURL URLWithString:jssURLString];
    }

    if (!_jssVersionDownloader) {
        _jssVersionDownloader = [[NBCDownloader alloc] initWithDelegate:self];
    }

    NSDictionary *downloadInfo = @{NBCDownloaderTag : NBCDownloaderTagJSSVerify};
    [_jssVersionDownloader downloadPageAsData:jssURL downloadInfo:downloadInfo];
}

- (void)downloadFailed:(NSDictionary *)downloadInfo withError:(NSError *)error {
    NSString *downloadTag = downloadInfo[NBCDownloaderTag];
    if ([downloadTag isEqualToString:NBCDownloaderTagJSSCertificate]) {
        NSString *errorMessage = @"";
        if (error) {
            errorMessage = [error localizedDescription];
        }

        [self setDownloadingJSSCertificate:NO];
        NSImage *imageWarning = [NSImage imageNamed:@"NSCaution"];
        [_imageViewDownloadJSSCertificateStatus setImage:imageWarning];
        [_imageViewDownloadJSSCertificateStatus setHidden:NO];
        [_textFieldDownloadJSSCertificateStatus setStringValue:errorMessage];
        [_textFieldDownloadJSSCertificateStatus setHidden:NO];
    } else if ([downloadTag isEqualToString:NBCDownloaderTagJSSVerify]) {
        NSString *errorMessage = @"";
        if (error) {
            errorMessage = [error localizedDescription];
        }

        [self setVerifyingJSS:NO];
        NSImage *imageWarning = [NSImage imageNamed:@"NSCaution"];
        [_imageViewVerifyJSSStatus setImage:imageWarning];
        [_imageViewVerifyJSSStatus setHidden:NO];
        [_textFieldVerifyJSSStatus setStringValue:errorMessage];
        [_textFieldVerifyJSSStatus setHidden:NO];
    }
}

- (void)dataDownloadCompleted:(NSData *)data downloadInfo:(NSDictionary *)downloadInfo {
    NSString *downloadTag = downloadInfo[NBCDownloaderTag];
    if ([downloadTag isEqualToString:NBCDownloaderTagJSSCertificate]) {
        [self setDownloadingJSSCertificate:NO];
        NSDictionary *certificateDict = [self examineCertificate:data];
        if ([certificateDict count] != 0) {
            if ([_casperJSSURL length] != 0) {
                [self setJssCACertificate:@{ _casperJSSURL : certificateDict[@"CertificateSignature"] }];
            }

            NSString *status;
            NSImage *image;

            if ([self insertCertificateInTableView:certificateDict]) {
                status = @"Downloaded";
            } else {
                status = @"Already Exist";
            }

            if ([certificateDict[@"CertificateExpired"] boolValue]) {
                image = [NSImage imageNamed:@"NSCaution"];
                NSMutableAttributedString *certificateExpired = [[NSMutableAttributedString alloc] initWithString:@"Certificate Expired"];
                [certificateExpired addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[certificateExpired length])];
                [_textFieldDownloadJSSCertificateStatus setAttributedStringValue:certificateExpired];
            } else {
                image = [[NSImage alloc] initWithContentsOfFile:IconSuccessPath];
                [_textFieldDownloadJSSCertificateStatus setStringValue:status];
            }

            [self updateJSSCACertificateExpirationFromDateNotValidAfter:certificateDict[@"CertificateNotValidAfterDate"] dateNotValidBefore:certificateDict[@"CertificateNotValidBeforeDate"]];

            [_imageViewDownloadJSSCertificateStatus setImage:image];
            [_textFieldDownloadJSSCertificateStatus setHidden:NO];
            [_imageViewDownloadJSSCertificateStatus setHidden:NO];
            [_buttonShowJSSCertificate setHidden:NO];
        } else {
        }
    } else if ([downloadTag isEqualToString:NBCDownloaderTagJSSVerify]) {
        NSString *jssVersion = [self jssVersionFromDownloadData:data];
        if ([jssVersion length] != 0) {
            [self setJssVersion:jssVersion];
            [self setVerifyingJSS:NO];
            NSImage *imageSuccess = [[NSImage alloc] initWithContentsOfFile:IconSuccessPath];
            [_imageViewVerifyJSSStatus setImage:imageSuccess];
            [_imageViewVerifyJSSStatus setHidden:NO];
            [_textFieldVerifyJSSStatus setHidden:NO];
            [_textFieldVerifyJSSStatus setStringValue:[NSString stringWithFormat:@"Verified JSS Version: %@", jssVersion]];
        } else {
            [self setVerifyingJSS:NO];
            NSImage *imageCaution = [NSImage imageNamed:@"NSCaution"];
            [_imageViewVerifyJSSStatus setImage:imageCaution];
            [_imageViewVerifyJSSStatus setHidden:NO];
            [_textFieldVerifyJSSStatus setHidden:NO];
            [_textFieldVerifyJSSStatus setStringValue:@"Unable to determine JSS version"];
        }
    }
}

- (IBAction)buttonDownloadJSSCertificate:(id)sender {
#pragma unused(sender)
    [_buttonShowJSSCertificate setHidden:YES];
    [self setDownloadingJSSCertificate:YES];
    [_imageViewDownloadJSSCertificateStatus setHidden:YES];
    [_textFieldDownloadJSSCertificateStatus setHidden:NO];
    [_textFieldDownloadJSSCertificateStatus setStringValue:@"Contacting JSS..."];

    NSString *jssURLString = _casperJSSURL;
    NSURL *jssCertificateURL;
    if ([jssURLString length] != 0) {
        jssCertificateURL = [[NSURL URLWithString:jssURLString] URLByAppendingPathComponent:NBCCasperJSSCertificateURLPath];
        NSURLComponents *components = [[NSURLComponents alloc] initWithURL:jssCertificateURL resolvingAgainstBaseURL:NO];
        NSURLQueryItem *queryItems = [NSURLQueryItem queryItemWithName:@"operation" value:@"getcacert"];
        [components setQueryItems:@[ queryItems ]];
        jssCertificateURL = [components URL];
    } else {
        [_imageViewDownloadJSSCertificateStatus setHidden:NO];
        [_textFieldDownloadJSSCertificateStatus setHidden:NO];
        [_textFieldDownloadJSSCertificateStatus setStringValue:@"No URL was passed!"];
        // Show Alert
        return;
    }

    if (!_jssCertificateDownloader) {
        _jssCertificateDownloader = [[NBCDownloader alloc] initWithDelegate:self];
    }
    NSDictionary *downloadInfo = @{NBCDownloaderTag : NBCDownloaderTagJSSCertificate};
    [_jssCertificateDownloader downloadPageAsData:jssCertificateURL downloadInfo:downloadInfo];
}

- (IBAction)buttonShowJSSCertificate:(id)sender {
#pragma unused(sender)
    [_tabViewCasperSettings selectTabViewItemWithIdentifier:NBCTabViewItemExtra];
    if ([_casperJSSURL length] != 0) {
        __block NSData *jssCACertificateSignature = _jssCACertificate[_casperJSSURL];
        if (jssCACertificateSignature) {
            [_certificateTableViewContents enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
              if ([jssCACertificateSignature isEqualToData:obj[@"CertificateSignature"]]) {
                  [self->_tableViewCertificates selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
                  *stop = YES;
              }
            }];
        }
    }
}

- (void)addOverlayViewToView:(NSView *)view overlayView:(NSView *)overlayView {
    [view addSubview:overlayView positioned:NSWindowAbove relativeTo:nil];
    [overlayView setTranslatesAutoresizingMaskIntoConstraints:NO];
    NSArray *constraintsArray;
    constraintsArray = [NSLayoutConstraint constraintsWithVisualFormat:@"|-1-[overlayView]-1-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(overlayView)];
    [view addConstraints:constraintsArray];
    constraintsArray = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-1-[overlayView]-1-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(overlayView)];
    [view addConstraints:constraintsArray];
    [view setHidden:NO];
} // addOverlayViewToView:overlayView

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Trusted NetBoot Servers
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (IBAction)buttonManageTrustedServers:(id)sender {
    [_popOverManageTrustedServers showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSMaxXEdge];
}

- (IBAction)buttonAddTrustedServer:(id)sender {
#pragma unused(sender)
    // Insert new view
    NSInteger index = [self insertNetBootServerIPInTableView:@""];
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:(NSUInteger)index];

    // Select the newly created text field in the new view
    [_tableViewTrustedServers selectRowIndexes:indexSet byExtendingSelection:NO];
    [[[_tableViewTrustedServers viewAtColumn:[_tableViewTrustedServers selectedColumn] row:index makeIfNecessary:NO] textFieldTrustedNetBootServer] selectText:self];
    [self updateTrustedNetBootServersCount];
}

- (IBAction)buttonRemoveTrustedServer:(id)sender {
#pragma unused(sender)
    NSIndexSet *indexes = [_tableViewTrustedServers selectedRowIndexes];
    [_trustedServers removeObjectsAtIndexes:indexes];
    [_tableViewTrustedServers removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    [self updateTrustedNetBootServersCount];
}

- (void)updateTrustedNetBootServersCount {
    __block int validNetBootServersCounter = 0;
    __block BOOL containsInvalidNetBootServer = NO;

    [_trustedServers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
#pragma unused(stop)
      NBCCasperTrustedNetBootServerCellView *cellView = [self->_tableViewTrustedServers viewAtColumn:0 row:(NSInteger)idx makeIfNecessary:NO];

      if ([obj isValidIPAddress]) {
          validNetBootServersCounter++;
          [[cellView textFieldTrustedNetBootServer] setStringValue:obj];
      } else {
          NSMutableAttributedString *trustedNetBootServerAttributed = [[NSMutableAttributedString alloc] initWithString:obj];
          [trustedNetBootServerAttributed addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[trustedNetBootServerAttributed length])];
          [[cellView textFieldTrustedNetBootServer] setAttributedStringValue:trustedNetBootServerAttributed];
          containsInvalidNetBootServer = YES;
      }
    }];

    NSString *trustedNetBootServerCount = [@(validNetBootServersCounter) stringValue];
    if (containsInvalidNetBootServer) {
        NSMutableAttributedString *trustedNetBootServerCountMutable = [[NSMutableAttributedString alloc] initWithString:trustedNetBootServerCount];
        [trustedNetBootServerCountMutable addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[trustedNetBootServerCountMutable length])];
        [_textFieldTrustedServersCount setAttributedStringValue:trustedNetBootServerCountMutable];
    } else {
        [_textFieldTrustedServersCount setStringValue:trustedNetBootServerCount];
    }
}

- (IBAction)sliderDisplaySleep:(id)sender {
#pragma unused(sender)
    [self setDisplaySleepMinutes:(int)[_sliderDisplaySleep integerValue]];
    [self updateSliderPreview:(int)[_sliderDisplaySleep integerValue]];
}

- (void)updateSliderPreview:(int)sliderValue {
    NSString *sliderPreviewString;
    if (120 <= sliderValue) {
        sliderPreviewString = @"Never";
    } else {
        NSCalendar *calendarUS = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        calendarUS.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        NSDateComponentsFormatter *dateComponentsFormatter = [[NSDateComponentsFormatter alloc] init];
        dateComponentsFormatter.maximumUnitCount = 2;
        dateComponentsFormatter.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
        dateComponentsFormatter.calendar = calendarUS;

        sliderPreviewString = [dateComponentsFormatter stringFromTimeInterval:(sliderValue * 60)];
    }

    [_textFieldDisplaySleepPreview setStringValue:sliderPreviewString];
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark RAM Disks
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (IBAction)buttonRamDisks:(id)sender {
    [_popOverRAMDisks showRelativeToRect:[sender bounds] ofView:sender preferredEdge:NSMaxXEdge];
}

- (IBAction)buttonAddRAMDisk:(id)sender {
#pragma unused(sender)

    // Check if empty view already exist
    __block NSNumber *index;
    [_ramDisks enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      if ([obj[@"path"] length] == 0 && [obj[@"size"] isEqualToString:@"1"]) {
          index = @((NSInteger)idx);
          *stop = YES;
      }
    }];

    if (index == nil) {
        // Insert new view
        NSDictionary *newRamDiskDict = @{
            @"path" : @"",
            @"size" : @"1",
        };
        index = @([self insertRAMDiskInTableView:newRamDiskDict]);
    }

    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:(NSUInteger)index];

    // Select the newly created text field in the new view
    [_tableViewRAMDisks selectRowIndexes:indexSet byExtendingSelection:NO];
    [[[_tableViewRAMDisks viewAtColumn:[_tableViewRAMDisks selectedColumn] row:[index integerValue] makeIfNecessary:NO] textFieldRAMDiskPath] selectText:self];
    [self updateRAMDisksCount];
}

- (IBAction)buttonRemoveRAMDisk:(id)sender {
#pragma unused(sender)
    NSIndexSet *indexes = [_tableViewRAMDisks selectedRowIndexes];
    [_ramDisks removeObjectsAtIndexes:indexes];
    [_tableViewRAMDisks removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    [self updateRAMDisksCount];
}

- (void)updateRAMDisksCount {
    __block BOOL containsInvalidRAMDisk = NO;
    __block int validRAMDisksCounter = 0;
    __block int sumRAMDiskSize = 0;
    [_ramDisks enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
#pragma unused(stop, idx, obj)
      BOOL validPath = NO;
      BOOL validSize = NO;
      NSString *path = obj[@"path"];
      NSString *size = obj[@"size"];
      if ([path length] == 0 && [size isEqualToString:@"1"]) {
          return;
      }

      NBCCasperRAMDiskPathCellView *cellView = [self->_tableViewRAMDisks viewAtColumn:0 row:(NSInteger)idx makeIfNecessary:NO];
      if ([path length] != 0) {
          [[cellView textFieldRAMDiskPath] setStringValue:path];
          validPath = YES;
      } else {
          /*
           NSMutableAttributedString *pathathAttributed = [[NSMutableAttributedString alloc] initWithString:path];
           [pathathAttributed addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0,(NSUInteger)[pathathAttributed length])];
           [[cellView textFieldRAMDiskPath] setAttributedStringValue:pathathAttributed];
           */
      }

      if ([size length] != 0) {
          sumRAMDiskSize = (sumRAMDiskSize + [size intValue]);
          validSize = YES;
      }

      if (validPath && validSize) {
          validRAMDisksCounter++;
      } else {
          containsInvalidRAMDisk = YES;
      }
    }];

    NSString *ramDisksCount = [@(validRAMDisksCounter) stringValue];
    NSString *ramDiskSize = [NSByteCountFormatter stringFromByteCount:(long long)(sumRAMDiskSize * 1000000) countStyle:NSByteCountFormatterCountStyleDecimal];
    [_textFieldRAMDiskSize setStringValue:ramDiskSize];

    if (containsInvalidRAMDisk) {
        NSMutableAttributedString *ramDisksCountMutable = [[NSMutableAttributedString alloc] initWithString:ramDisksCount];
        [ramDisksCountMutable addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[ramDisksCountMutable length])];
        [_textFieldRAMDiskCount setAttributedStringValue:ramDisksCountMutable];
    } else {
        [_textFieldRAMDiskCount setStringValue:ramDisksCount];
    }
}

- (BOOL)validateRAMDisk:(NSDictionary *)ramDiskDict {
    BOOL retval = YES;
    NSString *path = ramDiskDict[@"path"];
    NSString *size = ramDiskDict[@"size"];
    if ([path length] == 0 || [size length] == 0) {
        return NO;
    }

    return retval;
}

- (IBAction)buttonAddPostWorkflowScript:(id)__unused sender {

    NSOpenPanel *addPackages = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [addPackages setTitle:@"Add Scripts"];
    [addPackages setPrompt:@"Add"];
    [addPackages setCanChooseFiles:YES];
    [addPackages setAllowedFileTypes:@[ @"public.shell-script" ]];
    [addPackages setCanChooseDirectories:NO];
    [addPackages setCanCreateDirectories:YES];
    [addPackages setAllowsMultipleSelection:YES];

    if ([addPackages runModal] == NSModalResponseOK) {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSArray *selectedURLs = [addPackages URLs];
        for (NSURL *url in selectedURLs) {
            NSString *fileType = [[NSWorkspace sharedWorkspace] typeOfFile:[url path] error:nil];
            if ([workspace type:fileType conformsToType:@"public.shell-script"]) {
                NSDictionary *scriptDict = [self examineScriptAtURL:url];
                if ([scriptDict count] != 0) {
                    [self insertItemInPostWorkflowScriptsTableView:scriptDict];
                    return;
                }
            }
        }
    }
}

- (void)insertItemInPostWorkflowScriptsTableView:(NSDictionary *)itemDict {
    NSString *packagePath = itemDict[NBCDictionaryKeyPath];
    for (NSDictionary *scriptDict in _postWorkflowScripts) {
        if ([packagePath isEqualToString:scriptDict[NBCDictionaryKeyPath]]) {
            DDLogWarn(@"Script %@ is already added!", [packagePath lastPathComponent]);
            return;
        }
    }

    NSInteger index = [_tableViewPostWorkflowScripts selectedRow];
    index++;
    [_tableViewPostWorkflowScripts beginUpdates];
    [_tableViewPostWorkflowScripts insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewPostWorkflowScripts scrollRowToVisible:index];
    [_postWorkflowScripts insertObject:itemDict atIndex:(NSUInteger)index];
    [_tableViewPostWorkflowScripts endUpdates];
    [_viewOverlayPostWorkflowScripts setHidden:YES];
}

- (NSDictionary *)examineScriptAtURL:(NSURL *)url {

    DDLogDebug(@"[DEBUG] Examine script...");

    NSMutableDictionary *newScriptDict = [[NSMutableDictionary alloc] init];
    NBCDDReader *reader = [[NBCDDReader alloc] initWithFilePath:[url path]];
    [reader enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
      if ([line hasPrefix:@"#!/bin/bash"] | [line hasPrefix:@"#!/bin/sh"]) {
          newScriptDict[NBCDictionaryKeyScriptType] = @"Shell Script";
          *stop = YES;
      }
    }];

    DDLogDebug(@"[DEBUG] Script type: %@", newScriptDict[NBCDictionaryKeyScriptType] ?: @"Unknown");

    if ([newScriptDict[NBCDictionaryKeyScriptType] length] != 0) {
        newScriptDict[NBCDictionaryKeyPath] = [url path] ?: @"Unknown";
        DDLogDebug(@"[DEBUG] Script path: %@", newScriptDict[NBCDictionaryKeyPath]);

        newScriptDict[NBCDictionaryKeyName] = [url lastPathComponent] ?: @"Unknown";
        DDLogDebug(@"[DEBUG] Script name: %@", newScriptDict[NBCDictionaryKeyName]);

        return newScriptDict;
    } else {
        return nil;
    }
}

- (IBAction)buttonRemovePostWorkflowScript:(id)__unused sender {
    NSIndexSet *indexes = [_tableViewPostWorkflowScripts selectedRowIndexes];
    [_postWorkflowScripts removeObjectsAtIndexes:indexes];
    [_tableViewPostWorkflowScripts removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    if ([_postWorkflowScripts count] == 0) {
        [_viewOverlayPostWorkflowScripts setHidden:NO];
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark PopUpButton USB Devices
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updatePopUpButtonUSBDevices {

    NSString *currentSelection = [_popUpButtonUSBDevices titleOfSelectedItem];

    [_popUpButtonUSBDevices removeAllItems];
    _usbDevicesDict = [NSMutableDictionary dictionary];
    [_popUpButtonUSBDevices addItemWithTitle:NBCMenuItemNoSelection];
    [[_popUpButtonUSBDevices menu] setAutoenablesItems:NO];

    // ------------------------------------------------------
    //  Add menu title: System Volumes
    // ------------------------------------------------------
    [[_popUpButtonUSBDevices menu] addItem:[NSMenuItem separatorItem]];
    NSMenuItem *titleMenuItem = [[NSMenuItem alloc] initWithTitle:@"USB Devices" action:nil keyEquivalent:@""];
    [titleMenuItem setTarget:nil];
    [titleMenuItem setEnabled:NO];
    [[_popUpButtonUSBDevices menu] addItem:titleMenuItem];
    [[_popUpButtonUSBDevices menu] addItem:[NSMenuItem separatorItem]];

    // --------------------------------------------------------------
    //  Add all mounted OS X disks to source popUpButton
    // --------------------------------------------------------------
    NSMutableArray *addedDisks = [[NSMutableArray alloc] init];
    NSSet *currentDisks = [[[NBCDiskArbitrator sharedArbitrator] disks] copy];
    for (NBCDisk *disk in currentDisks) {
        if (!disk) {
            continue;
        }

        NSString *deviceProtocol = [disk deviceProtocol];
        if ([deviceProtocol isEqualToString:@"USB"]) {
            NBCDisk *usbDisk = [disk parent];

            if (usbDisk != nil && ![addedDisks containsObject:[usbDisk BSDName]]) {
                NSString *diskMenuItemTitle = [usbDisk mediaName] ?: @"Unknown";
                NSImage *icon = [[usbDisk icon] copy];
                NSMenuItem *diskMenuItem = [[NSMenuItem alloc] initWithTitle:diskMenuItemTitle action:nil keyEquivalent:@""];
                [icon setSize:NSMakeSize(16, 16)];
                [diskMenuItem setImage:icon];
                [diskMenuItem setEnabled:YES];
                [[_popUpButtonUSBDevices menu] addItem:diskMenuItem];

                _usbDevicesDict[diskMenuItemTitle] = [usbDisk BSDName];
                [addedDisks addObject:[usbDisk BSDName]];

                for (NBCDisk *childDisk in [usbDisk children]) {
                    NSString *childDiskItemTitle = [childDisk volumeName] ?: @"Unknown";
                    NSImage *childIcon = [[childDisk icon] copy];
                    NSMenuItem *childDiskMenuItem = [[NSMenuItem alloc] initWithTitle:childDiskItemTitle action:nil keyEquivalent:@""];
                    [childIcon setSize:NSMakeSize(16, 16)];
                    [childDiskMenuItem setImage:childIcon];
                    [childDiskMenuItem setIndentationLevel:1];
                    [childDiskMenuItem setEnabled:NO];
                    [[_popUpButtonUSBDevices menu] addItem:childDiskMenuItem];
                }
            }
        }
    }

    if ([[_popUpButtonUSBDevices itemTitles] containsObject:currentSelection]) {
        [_popUpButtonUSBDevices selectItemWithTitle:currentSelection ?: NBCMenuItemNoSelection];
    } else {
        [_popUpButtonUSBDevices selectItemWithTitle:NBCMenuItemNoSelection];
    }
}

@end

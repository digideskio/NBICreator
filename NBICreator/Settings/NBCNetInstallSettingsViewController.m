//
//  NBCNISettingsController.m
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

#import "NBCConfigurationProfileTableCellView.h"
#import "NBCConstants.h"
#import "NBCDDReader.h"
#import "NBCDesktopEntity.h"
#import "NBCDiskArbitrator.h"
#import "NBCError.h"
#import "NBCHelperAuthorization.h"
#import "NBCHelperConnection.h"
#import "NBCHelperProtocol.h"
#import "NBCInstallerPackageController.h"
#import "NBCLogging.h"
#import "NBCNetInstallSettingsViewController.h"
#import "NBCNetInstallTrustedNetBootServerCellView.h"
#import "NBCOverlayViewController.h"
#import "NBCPackageTableCellView.h"
#import "NBCSettingsController.h"
#import "NBCTableViewCells.h"
#import "NBCVariables.h"
#import "NBCWorkflowItem.h"
#import "NSString+validIP.h"

DDLogLevel ddLogLevel;

@implementation NBCNetInstallSettingsViewController

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Initialization
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (id)init {
    self = [super initWithNibName:@"NBCNetInstallSettingsViewController" bundle:nil];
    if (self != nil) {
        _templates = [[NBCTemplatesController alloc] initWithSettingsViewController:self templateType:NBCSettingsTypeNetInstall delegate:self];
    }
    return self;
} // init

- (void)awakeFromNib {
    [_tableViewConfigurationProfiles registerForDraggedTypes:@[ NSURLPboardType ]];
    [_tableViewPackagesNetInstall registerForDraggedTypes:@[ NSURLPboardType ]];
} // awakeFromNib

- (void)dealloc {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSControlTextDidEndEditingNotification object:nil];
    //[nc removeObserver:self name:DADiskDidAppearNotification object:nil];
    //[nc removeObserver:self name:DADiskDidDisappearNotification object:nil];
    //[nc removeObserver:self name:DADiskDidChangeNotification object:nil];
} // dealloc

- (void)viewDidLoad {
    [super viewDidLoad];

    [self setPackagesNetInstallTableViewContents:[[NSMutableArray alloc] init]];
    [self setConfigurationProfilesTableViewContents:[[NSMutableArray alloc] init]];
    [self setTrustedServers:[[NSMutableArray alloc] init]];
    [self setPostWorkflowScripts:[[NSMutableArray alloc] init]];
    NSTabViewItem *tabViewPostWorkflow = [[self tabViewSettings] tabViewItemAtIndex:3];
    [[self tabViewSettings] removeTabViewItem:tabViewPostWorkflow];
    //[self updatePopUpButtonUSBDevices];

    // --------------------------------------------------------------
    //  Add Notification Observers
    // --------------------------------------------------------------
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(editingDidEnd:) name:NSControlTextDidEndEditingNotification object:nil];
    //[nc addObserver:self selector:@selector(updatePopUpButtonUSBDevices) name:DADiskDidAppearNotification object:nil];
    //[nc addObserver:self selector:@selector(updatePopUpButtonUSBDevices) name:DADiskDidDisappearNotification object:nil];
    //[nc addObserver:self selector:@selector(updatePopUpButtonUSBDevices) name:DADiskDidChangeNotification object:nil];

    // --------------------------------------------------------------
    //  Add KVO Observers
    // --------------------------------------------------------------
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud addObserver:self forKeyPath:NBCUserDefaultsIndexCounter options:NSKeyValueObservingOptionNew context:nil];

    // --------------------------------------------------------------
    //  Initialize Properties
    // --------------------------------------------------------------
    NSError *error;
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSURL *userApplicationSupport = [fm URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error];
    if ([userApplicationSupport checkResourceIsReachableAndReturnError:&error]) {
        _templatesFolderURL = [userApplicationSupport URLByAppendingPathComponent:NBCFolderTemplatesNetInstall isDirectory:YES];
    } else {
        DDLogError(@"[ERROR] %@", [error localizedDescription]);
    }

    [_imageViewIcon setDelegate:self];
    [self setSiuSource:[[NBCApplicationSourceSystemImageUtility alloc] init]];
    [self setTemplatesDict:[[NSMutableDictionary alloc] init]];
    [self initializeTableViewOverlays];

    // --------------------------------------------------------------
    //  Load saved templates and create the template menu
    // --------------------------------------------------------------
    [self updatePopUpButtonTemplates];

    // --------------------------------------------------------------
    //  Update default System Image Utility Version in UI.
    // --------------------------------------------------------------
    NSString *systemUtilityVersion = [_siuSource systemImageUtilityVersion];
    if ([systemUtilityVersion length] != 0) {
        [_textFieldSystemImageUtilityVersion setStringValue:systemUtilityVersion];
    } else {
        [_textFieldSystemImageUtilityVersion setStringValue:@"Not Installed"];
    }

    // ------------------------------------------------------------------------------
    //  Add contextual menu to NBI Icon image view to allow to restore original icon.
    // -------------------------------------------------------------------------------
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *restoreView = [[NSMenuItem alloc] initWithTitle:NBCMenuItemRestoreOriginalIcon action:@selector(restoreNBIIcon:) keyEquivalent:@""];
    [menu addItem:restoreView];
    [_imageViewIcon setMenu:menu];

    [self updateSettingVisibility];

    // ------------------------------------------------------------------------------
    //  Verify build button so It's not enabled by mistake
    // -------------------------------------------------------------------------------
    [self verifyBuildButton];

} // viewDidLoad

- (void)initializeTableViewOverlays {
    if (!_viewOverlayPackagesNetInstall) {
        NBCOverlayViewController *vc = [[NBCOverlayViewController alloc] initWithContentType:kContentTypeNetInstallPackages];
        _viewOverlayPackagesNetInstall = [vc view];
    }
    [self addOverlayViewToView:_superViewPackagesNetInstall overlayView:_viewOverlayPackagesNetInstall];

    if (!_viewOverlayConfigurationProfiles) {
        NBCOverlayViewController *vc = [[NBCOverlayViewController alloc] initWithContentType:kContentTypeConfigurationProfiles];
        _viewOverlayConfigurationProfiles = [vc view];
    }
    [self addOverlayViewToView:_superViewConfigurationProfiles overlayView:_viewOverlayConfigurationProfiles];
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
#pragma mark Delegate Methods PopUpButton
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    BOOL retval = YES;

    if ([[menuItem title] isEqualToString:NBCMenuItemRestoreOriginalIcon]) {
        // -------------------------------------------------------------
        //  No need to restore original icon if it's already being used
        // -------------------------------------------------------------
        if ([_nbiIconPath isEqualToString:NBCFilePathNBIIconNetInstall]) {
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
        if ([[[textField superview] class] isSubclassOfClass:[NBCNetInstallTrustedNetBootServerCellView class]]) {
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
        if ([sender object] == _textFieldNBIName) {
            if ([_nbiName length] == 0) {
                [_textFieldNBINamePreview setStringValue:@""];
            } else {
                NSString *nbiName = [NBCVariables expandVariables:_nbiName source:_source applicationSource:_siuSource];
                [_textFieldNBINamePreview setStringValue:[NSString stringWithFormat:@"%@.nbi", nbiName]];
            }
        } else if ([sender object] == _textFieldIndex) {
            if ([_nbiIndex length] == 0) {
                [_textFieldIndexPreview setStringValue:@""];
            } else {
                NSString *nbiIndex = [NBCVariables expandVariables:_nbiIndex source:_source applicationSource:_siuSource];
                [_textFieldIndexPreview setStringValue:[NSString stringWithFormat:@"Index: %@", nbiIndex]];
            }
        } else if ([sender object] == _textFieldNBIDescription) {
            if ([_nbiDescription length] == 0) {
                [_textFieldNBIDescriptionPreview setStringValue:@""];
            } else {
                NSString *nbiDescription = [NBCVariables expandVariables:_nbiDescription source:_source applicationSource:_siuSource];
                [_textFieldNBIDescriptionPreview setStringValue:nbiDescription];
            }
        }

        // --------------------------------------------------------------------
        //  Expand tilde for destination folder if tilde is used in settings
        // --------------------------------------------------------------------
        if ([sender object] == _textFieldDestinationFolder) {
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
    } else if ([alertTag isEqualToString:NBCAlertTagSettingsUnsaved]) {
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
    } else if ([alertTag isEqualToString:NBCAlertTagIncorrectPackageType]) {
        if (returnCode == NSAlertFirstButtonReturn) { // Cancel
            DDLogDebug(@"[DEBUG] Canceled package update");
        } else if (returnCode == NSAlertSecondButtonReturn) { // Update Package
            NSArray *productArchivePackageURLs = [NBCInstallerPackageController convertPackagesToProductArchivePackages:alertInfo[NBCAlertResourceKey] ?: @[]];
            NSMutableArray *incorrectPackageTypes = [[NSMutableArray alloc] init];
            for (NSURL *packageURL in productArchivePackageURLs) {
                NSDictionary *packageDict = [self examinePackageAtURL:packageURL];
                if ([packageDict count] != 0) {
                    if ([packageDict[NBCDictionaryKeyPackageFormat] length] != 0 &&
                        (![packageDict[NBCDictionaryKeyPackageFormat] isEqualToString:@"Flat"] || ![packageDict[NBCDictionaryKeyPackageType] isEqualToString:@"Product Archive"])) {
                        [incorrectPackageTypes addObject:packageDict];
                    } else {
                        [self insertItemInPackagesNetInstallTableView:packageDict];
                    }
                }
            }

            if ([incorrectPackageTypes count] != 0) {
                NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
                [alert showAlertIncorrectPackageType:incorrectPackageTypes alertInfo:@{}];
            }
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

- (void)updateSource:(NBCSource *)source target:(NBCTarget *)__unused target {
    if (source != nil) {
        [self setSource:source];
    }

    [self updateSettingVisibility];
    [self expandVariablesForCurrentSettings];
    [self verifyBuildButton];
    [self updatePopOver];
} // updateSource

- (void)removedSource {
    if (_source) {
        [self setSource:nil];
    }

    [self updateSettingVisibility];
    [self expandVariablesForCurrentSettings];
    [self verifyBuildButton];
    [self updatePopOver];
} // removedSource

- (void)refreshCreationTool {
    [self setNbiCreationTool:_nbiCreationTool ?: NBCMenuItemSystemImageUtility];
    [self setNbiType:_nbiType ?: @"NetInstall"];
} // refreshCreationTool

- (void)restoreNBIIcon:(NSNotification *)__unused notification {
    [self setNbiIconPath:NBCFilePathNBIIconNetInstall];
    [self expandVariablesForCurrentSettings];
} // restoreNBIIcon

- (void)editingDidEnd:(NSNotification *)notification {
    if ([[[notification object] class] isSubclassOfClass:[NSTextField class]]) {
        NSTextField *textField = [notification object];
        if ([[[textField superview] class] isSubclassOfClass:[NBCNetInstallTrustedNetBootServerCellView class]]) {
            [self updateTrustedNetBootServersCount];
        }
    }
} // editingDidEnd

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Key/Value Observing
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)__unused object change:(NSDictionary *)__unused change context:(void *)__unused context {
    if ([keyPath isEqualToString:NBCUserDefaultsIndexCounter]) {
        NSString *nbiIndex = [NBCVariables expandVariables:_nbiIndex source:_source applicationSource:_siuSource];
        [_textFieldIndexPreview setStringValue:[NSString stringWithFormat:@"Index: %@", nbiIndex]];
        [self setPopOverIndexCounter:nbiIndex];
    }
} // observeValueForKeyPath:ofObject:change:context

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Settings
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updateUISettingsFromDict:(NSDictionary *)settingsDict {
    [self setNbiName:settingsDict[NBCSettingsNameKey]];
    [self setNbiIndex:settingsDict[NBCSettingsIndexKey]];
    [self setNbiProtocol:settingsDict[NBCSettingsProtocolKey]];
    [self setNbiEnabled:[settingsDict[NBCSettingsEnabledKey] boolValue]];
    [self setNbiDefault:[settingsDict[NBCSettingsDefaultKey] boolValue]];
    [self setNbiLanguage:settingsDict[NBCSettingsLanguageKey]];
    [self setNbiDescription:settingsDict[NBCSettingsDescriptionKey]];
    [self setDestinationFolder:settingsDict[NBCSettingsDestinationFolderKey]];
    [self setNbiIconPath:settingsDict[NBCSettingsIconKey]];
    [self setAddTrustedNetBootServers:[settingsDict[NBCSettingsAddTrustedNetBootServersKey] boolValue]];
    [self setNetInstallPackageOnly:[settingsDict[NBCSettingsNetInstallPackageOnlyKey] boolValue]];
    [self setUsbLabel:settingsDict[NBCSettingsUSBLabelKey] ?: @"%OSVERSION%_%OSBUILD%_NetInstall"];

    [_packagesNetInstallTableViewContents removeAllObjects];
    [_tableViewPackagesNetInstall reloadData];
    if ([settingsDict[NBCSettingsNetInstallPackagesKey] count] != 0) {
        NSArray *packagesArray = settingsDict[NBCSettingsNetInstallPackagesKey];
        NSMutableArray *incorrectPackageTypes = [[NSMutableArray alloc] init];
        NSMutableArray *packageWarning = [[NSMutableArray alloc] init];
        for (NSString *packagePath in packagesArray) {
            NSURL *packageURL = [NSURL fileURLWithPath:packagePath];
            NSDictionary *packageDict = [self examinePackageAtURL:packageURL];
            if ([packageDict count] != 0) {
                NSString *packageName = packageDict[NBCDictionaryKeyName];
                for (NSDictionary *pkgDict in self->_packagesNetInstallTableViewContents) {
                    if ([packagePath isEqualToString:pkgDict[NBCDictionaryKeyPath]]) {
                        [packageWarning addObject:packageDict];
                        DDLogWarn(@"Package %@ is already added!", [packagePath lastPathComponent]);
                        return;
                    }

                    if ([packageName isEqualToString:pkgDict[NBCDictionaryKeyName]]) {
                        [packageWarning addObject:packageDict];
                        DDLogWarn(@"A package with the name: \"%@\" has already been added!", [packagePath lastPathComponent]);
                        return;
                    }
                }

                if ([packageDict[NBCDictionaryKeyPackageFormat] length] != 0 &&
                    (![packageDict[NBCDictionaryKeyPackageFormat] isEqualToString:@"Flat"] || ![packageDict[NBCDictionaryKeyPackageType] isEqualToString:@"Product Archive"])) {
                    [incorrectPackageTypes addObject:packageDict];
                } else {
                    [self insertItemInPackagesNetInstallTableView:packageDict];
                }
            }
        }

        if ([packageWarning count] != 0) {
            [NBCAlerts showAlertPackageAlreadyAdded:packageWarning];
        }

        if ([incorrectPackageTypes count] != 0) {
            NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
            [alert showAlertIncorrectPackageType:incorrectPackageTypes alertInfo:@{}];
        }
    } else {
        [_viewOverlayPackagesNetInstall setHidden:NO];
    }

    [_configurationProfilesTableViewContents removeAllObjects];
    [_tableViewConfigurationProfiles reloadData];
    if ([settingsDict[NBCSettingsConfigurationProfilesKey] count] != 0) {
        NSArray *configurationProfilesArray = settingsDict[NBCSettingsConfigurationProfilesKey];
        for (NSString *path in configurationProfilesArray) {
            NSURL *url = [NSURL fileURLWithPath:path];
            NSDictionary *configurationProfileDict = [self examineConfigurationProfileAtURL:url];
            if ([configurationProfileDict count] != 0) {
                [self insertConfigurationProfileInTableView:configurationProfileDict];
            }
        }
    } else {
        [_viewOverlayConfigurationProfiles setHidden:NO];
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

    [self updatePopUpButtonNBIType];

    [self expandVariablesForCurrentSettings];
} // updateUISettingsFromDict

- (void)updateUISettingsFromURL:(NSURL *)url {
    NSDictionary *mainDict = [[NSDictionary alloc] initWithContentsOfURL:url];
    if ([mainDict count] != 0) {
        NSDictionary *settingsDict = mainDict[NBCSettingsSettingsKey];
        if ([settingsDict count] != 0) {
            [self updateUISettingsFromDict:settingsDict];
        } else {
            DDLogError(@"[ERROR] No key named Settings i plist at path: %@", [url path]);
        }
    } else {
        DDLogError(@"[ERROR] Could not read plist at path: %@", [url path]);
    }
} // updateUISettingsFromURL

- (NSDictionary *)returnSettingsFromUI {
    NSMutableDictionary *settingsDict = [[NSMutableDictionary alloc] init];

    settingsDict[NBCSettingsNameKey] = _nbiName ?: @"";
    settingsDict[NBCSettingsIndexKey] = _nbiIndex ?: @"";
    settingsDict[NBCSettingsProtocolKey] = _nbiProtocol ?: @"";
    settingsDict[NBCSettingsLanguageKey] = _nbiLanguage ?: @"";
    settingsDict[NBCSettingsEnabledKey] = @(_nbiEnabled) ?: @NO;
    settingsDict[NBCSettingsDefaultKey] = @(_nbiDefault) ?: @NO;
    settingsDict[NBCSettingsDescriptionKey] = _nbiDescription ?: @"";
    settingsDict[NBCSettingsAddTrustedNetBootServersKey] = @(_addTrustedNetBootServers) ?: @NO;
    settingsDict[NBCSettingsNetInstallPackageOnlyKey] = @(_netInstallPackageOnly) ?: @NO;
    settingsDict[NBCSettingsUSBLabelKey] = _usbLabel ?: @"";

    if (_destinationFolder != nil) {
        NSString *currentUserHome = NSHomeDirectory();
        if ([_destinationFolder hasPrefix:currentUserHome]) {
            NSString *destinationFolderPath = [_destinationFolder stringByReplacingOccurrencesOfString:currentUserHome withString:@"~"];
            settingsDict[NBCSettingsDestinationFolderKey] = destinationFolderPath ?: @"";
        } else {
            settingsDict[NBCSettingsDestinationFolderKey] = _destinationFolder ?: @"";
        }
    }
    settingsDict[NBCSettingsIconKey] = _nbiIconPath ?: @"";

    NSMutableArray *trustedNetBootServersArray = [[NSMutableArray alloc] init];
    for (NSString *trustedNetBootServer in _trustedServers) {
        if ([trustedNetBootServer length] != 0) {
            [trustedNetBootServersArray insertObject:trustedNetBootServer atIndex:0];
        }
    }
    settingsDict[NBCSettingsTrustedNetBootServersKey] = trustedNetBootServersArray ?: @[];

    NSMutableArray *packageArray = [[NSMutableArray alloc] init];
    for (NSDictionary *packageDict in _packagesNetInstallTableViewContents) {
        NSString *packagePath = packageDict[NBCDictionaryKeyPath];
        if ([packagePath length] != 0) {
            [packageArray insertObject:packagePath atIndex:0];
        }
    }
    settingsDict[NBCSettingsNetInstallPackagesKey] = packageArray ?: @[];

    NSMutableArray *configurationProfilesArray = [[NSMutableArray alloc] init];
    for (NSDictionary *configurationProfileDict in _configurationProfilesTableViewContents) {
        NSString *configurationProfilePath = configurationProfileDict[NBCDictionaryKeyConfigurationProfilePath];
        if ([configurationProfilePath length] != 0) {
            [configurationProfilesArray insertObject:configurationProfilePath atIndex:0];
        }
    }
    settingsDict[NBCSettingsConfigurationProfilesKey] = configurationProfilesArray ?: @[];

    return [settingsDict copy];
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
    mainDict[NBCSettingsTypeKey] = NBCSettingsTypeNetInstall;
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
            [NBCAlerts showAlertError:error];
            return;
        }
    }

    // -------------------------------------------------------------
    //  Write settings to url and update _templatesDict
    // -------------------------------------------------------------
    if ([mainDict writeToURL:settingsURL atomically:NO]) {
        _templatesDict[name] = settingsURL;
    } else {
        [NBCAlerts showAlertErrorWithTitle:@"Saving Template Failed!" informativeText:@"Writing NetInstall template to disk failed"];
    }
} // saveUISettingsWithName:atUrl

- (BOOL)haveSettingsChanged {

    BOOL retval = YES;

    NSURL *defaultSettingsURL = [[NSBundle mainBundle] URLForResource:NBCFileNameNetInstallDefaults withExtension:@"plist"];
    if ([defaultSettingsURL checkResourceIsReachableAndReturnError:nil]) {
        NSDictionary *currentSettings = [self returnSettingsFromUI];
        NSDictionary *defaultSettings = [NSDictionary dictionaryWithContentsOfURL:defaultSettingsURL];
        if ([currentSettings count] != 0 && [defaultSettings count] != 0) {
            if ([currentSettings isEqualToDictionary:defaultSettings]) {
                return NO;
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

- (IBAction)buttonAddConfigurationProfile:(id)sender {
#pragma unused(sender)
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [openPanel setTitle:@"Add Configuration Profiles"];
    [openPanel setPrompt:@"Add"];
    [openPanel setCanChooseFiles:YES];
    [openPanel setAllowedFileTypes:@[ @"com.apple.mobileconfig" ]];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setCanCreateDirectories:YES];
    [openPanel setAllowsMultipleSelection:YES];

    if ([openPanel runModal] == NSModalResponseOK) {
        NSArray *selectedURLs = [openPanel URLs];
        for (NSURL *packageURL in selectedURLs) {
            NSDictionary *configurationProfileDict = [self examineConfigurationProfileAtURL:packageURL];
            if ([configurationProfileDict count] != 0) {
                [self insertConfigurationProfileInTableView:configurationProfileDict];
            }
        }
    }
}

- (IBAction)buttonRemoveConfigurationProfile:(id)sender {
#pragma unused(sender)
    NSIndexSet *indexes = [_tableViewConfigurationProfiles selectedRowIndexes];
    [_configurationProfilesTableViewContents removeObjectsAtIndexes:indexes];
    [_tableViewConfigurationProfiles removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    if ([_configurationProfilesTableViewContents count] == 0) {
        [_viewOverlayConfigurationProfiles setHidden:NO];
    }
}

- (IBAction)buttonAddPackageNetInstall:(id)sender {
#pragma unused(sender)
    NSOpenPanel *addPackages = [NSOpenPanel openPanel];

    // --------------------------------------------------------------
    //  Setup open dialog to only allow one folder to be chosen.
    // --------------------------------------------------------------
    [addPackages setTitle:@"Add Packages and/or Scripts"];
    [addPackages setPrompt:@"Add"];
    [addPackages setCanChooseFiles:YES];
    [addPackages setAllowedFileTypes:@[ @"com.apple.installer-package-archive", @"public.shell-script" ]];
    [addPackages setCanChooseDirectories:NO];
    [addPackages setCanCreateDirectories:YES];
    [addPackages setAllowsMultipleSelection:YES];

    if ([addPackages runModal] == NSModalResponseOK) {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSArray *selectedURLs = [addPackages URLs];
        NSMutableArray *incorrectPackageTypes = [[NSMutableArray alloc] init];
        NSMutableArray *packageWarning = [[NSMutableArray alloc] init];
        for (NSURL *url in selectedURLs) {
            NSString *fileType = [[NSWorkspace sharedWorkspace] typeOfFile:[url path] error:nil];
            if ([workspace type:fileType conformsToType:@"com.apple.installer-package-archive"]) {
                NSDictionary *packageDict = [self examinePackageAtURL:url];
                if ([packageDict count] != 0) {
                    NSString *packagePath = packageDict[NBCDictionaryKeyPath];
                    NSString *packageName = packageDict[NBCDictionaryKeyName];
                    for (NSDictionary *pkgDict in self->_packagesNetInstallTableViewContents) {
                        if ([packagePath isEqualToString:pkgDict[NBCDictionaryKeyPath]]) {
                            [packageWarning addObject:packageDict];
                            DDLogWarn(@"Package %@ is already added!", [packagePath lastPathComponent]);
                            return;
                        }

                        if ([packageName isEqualToString:pkgDict[NBCDictionaryKeyName]]) {
                            [packageWarning addObject:packageDict];
                            DDLogWarn(@"A package with the name: \"%@\" has already been added!", [packagePath lastPathComponent]);
                            return;
                        }
                    }

                    if ([packageDict[NBCDictionaryKeyPackageFormat] length] != 0 &&
                        (![packageDict[NBCDictionaryKeyPackageFormat] isEqualToString:@"Flat"] || ![packageDict[NBCDictionaryKeyPackageType] isEqualToString:@"Product Archive"])) {
                        [incorrectPackageTypes addObject:packageDict];
                    } else {
                        [self insertItemInPackagesNetInstallTableView:packageDict];
                    }
                    return;
                }
            } else if ([workspace type:fileType conformsToType:@"public.shell-script"]) {
                NSDictionary *scriptDict = [self examineScriptAtURL:url];
                if ([scriptDict count] != 0) {
                    [self insertItemInPackagesNetInstallTableView:scriptDict];
                    return;
                }
            }
        }

        if ([packageWarning count] != 0) {
            [NBCAlerts showAlertPackageAlreadyAdded:packageWarning];
        }

        if ([incorrectPackageTypes count] != 0) {
            NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
            [alert showAlertIncorrectPackageType:incorrectPackageTypes alertInfo:@{}];
        }
    }
}

- (IBAction)buttonRemovePackageNetInstall:(id)sender {
#pragma unused(sender)
    NSIndexSet *indexes = [_tableViewPackagesNetInstall selectedRowIndexes];
    [_packagesNetInstallTableViewContents removeObjectsAtIndexes:indexes];
    [_tableViewPackagesNetInstall removeRowsAtIndexes:indexes withAnimation:NSTableViewAnimationSlideDown];
    if ([_packagesNetInstallTableViewContents count] == 0) {
        [_viewOverlayPackagesNetInstall setHidden:NO];
    }
}

// PopOver

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
#pragma mark PopUpButton NBI Type
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)updatePopUpButtonNBIType {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_netInstallPackageOnly) {
        [self setNbiType:NBCMenuItemNBITypePackageOnly];
        NSDictionary *userInfo = @{ NBCSettingsNetInstallPackageOnlyKey : @YES };
        [nc postNotificationName:NBCNotificationNetInstallUpdateNBIType object:self userInfo:userInfo];
    } else {
        [self setNbiType:NBCMenuItemNBITypeNetInstall];
        NSDictionary *userInfo = @{ NBCSettingsNetInstallPackageOnlyKey : @NO };
        [nc postNotificationName:NBCNotificationNetInstallUpdateNBIType object:self userInfo:userInfo];
    }

    if (_popUpButtonNBIType) {
        [_popUpButtonNBIType removeAllItems];
        [_popUpButtonNBIType addItemWithTitle:NBCMenuItemNBITypeNetInstall];
        [_popUpButtonNBIType addItemWithTitle:NBCMenuItemNBITypePackageOnly];
        [_popUpButtonNBIType selectItemWithTitle:_nbiType];
        [self setNbiType:[_popUpButtonNBIType titleOfSelectedItem]];
    }
} // uppdatePopUpButtonTool

- (IBAction)popUpButtonNBIType:(id)sender {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSString *selectedType = [[sender selectedItem] title];
    if ([selectedType isEqualToString:NBCMenuItemNBITypePackageOnly]) {
        [self setNbiType:NBCMenuItemNBITypePackageOnly];
        [self setNetInstallPackageOnly:YES];
        NSDictionary *userInfo = @{ NBCSettingsNetInstallPackageOnlyKey : @YES };
        [nc postNotificationName:NBCNotificationNetInstallUpdateNBIType object:self userInfo:userInfo];
    } else if ([selectedType isEqualToString:NBCMenuItemNBITypeNetInstall]) {
        [self setNbiType:NBCMenuItemNBITypeNetInstall];
        [self setNetInstallPackageOnly:NO];
        NSDictionary *userInfo = @{ NBCSettingsNetInstallPackageOnlyKey : @NO };
        [nc postNotificationName:NBCNotificationNetInstallUpdateNBIType object:self userInfo:userInfo];
    }
} // popUpButtonTool

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark IBAction PopUpButtons
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)importTemplateAtURL:(NSURL *)url templateInfo:(NSDictionary *)templateInfo {
#pragma unused(templateInfo)
    DDLogInfo(@"Importing template at path: %@", [url path]);

    BOOL settingsChanged = [self haveSettingsChanged];

    if (settingsChanged) {
        NSDictionary *alertInfo = @{NBCAlertTagKey : NBCAlertTagSettingsUnsaved, NBCAlertUserInfoSelectedTemplate : _selectedTemplate};

        NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
        [alert showAlertSettingsUnsaved:@"You have unsaved settings, do you want to discard changes and continue?" alertInfo:alertInfo];
    }
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
#pragma mark Build NBI
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)buildNBI:(NSDictionary *)preWorkflowTasks {
    NBCWorkflowItem *workflowItem = [[NBCWorkflowItem alloc] initWithWorkflowType:kWorkflowTypeNetInstall workflowSessionType:kWorkflowSessionTypeGUI];
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

        userSettings[NBCSettingsNBICreationToolKey] = NBCMenuItemSystemImageUtility;
        [workflowItem setUserSettings:[userSettings copy]];

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
                    [alertInformativeText appendString:[NSString stringWithFormat:@"\n• %@", errorString]];
                }
            }

            if ([warning count] != 0) {
                configurationWarning = YES;
                for (NSString *warningString in warning) {
                    [alertInformativeText appendString:[NSString stringWithFormat:@"\n• %@", warningString]];
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
} // buildNBI

- (void)prepareWorkflowItem:(NBCWorkflowItem *)workflowItem {
    NSMutableDictionary *resourcesSettings = [[NSMutableDictionary alloc] init];

    NSMutableArray *validatedTrustedNetBootServers = [[NSMutableArray alloc] init];
    for (NSString *netBootServerIP in _trustedServers) {
        if ([netBootServerIP isValidIPAddress]) {
            [validatedTrustedNetBootServers addObject:netBootServerIP];
        }
    }

    if ([validatedTrustedNetBootServers count] != 0) {
        resourcesSettings[NBCSettingsTrustedNetBootServersKey] = [validatedTrustedNetBootServers copy];
    }

    NSMutableArray *packages = [[NSMutableArray alloc] init];
    for (NSDictionary *packageDict in _packagesNetInstallTableViewContents) {
        NSString *packagePath = packageDict[NBCDictionaryKeyPath];
        [packages addObject:packagePath];
    }
    resourcesSettings[NBCSettingsNetInstallPackagesKey] = [packages copy];

    NSMutableArray *configurationProfiles = [[NSMutableArray alloc] init];
    for (NSDictionary *configurationProfileDict in _configurationProfilesTableViewContents) {
        NSString *configurationProfilePath = configurationProfileDict[NBCDictionaryKeyConfigurationProfilePath];
        [configurationProfiles addObject:configurationProfilePath];
    }
    resourcesSettings[NBCSettingsConfigurationProfilesNetInstallKey] = [configurationProfiles copy];

    [workflowItem setResourcesSettings:[resourcesSettings copy]];

    // --------------------------------
    //  Get Authorization
    // --------------------------------
    NSError *err = nil;
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
      }] authorizeWorkflowNetInstall:authData
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
} // prepareWorkflow

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark TableView Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)insertItemInPackagesNetInstallTableView:(NSDictionary *)itemDict {
    NSString *packagePath = itemDict[NBCDictionaryKeyPath];
    for (NSDictionary *pkgDict in _packagesNetInstallTableViewContents) {
        if ([packagePath isEqualToString:pkgDict[NBCDictionaryKeyPath]]) {
            DDLogWarn(@"Package %@ is already added!", [packagePath lastPathComponent]);
            return;
        }
    }

    NSInteger index = [_tableViewPackagesNetInstall selectedRow];
    index++;
    [_tableViewPackagesNetInstall beginUpdates];
    [_tableViewPackagesNetInstall insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewPackagesNetInstall scrollRowToVisible:index];
    [_packagesNetInstallTableViewContents insertObject:itemDict atIndex:(NSUInteger)index];
    [_tableViewPackagesNetInstall endUpdates];
    [_viewOverlayPackagesNetInstall setHidden:YES];
}

- (void)insertConfigurationProfileInTableView:(NSDictionary *)configurationProfileDict {
    NSString *path = configurationProfileDict[NBCDictionaryKeyConfigurationProfilePath];
    for (NSDictionary *dict in _configurationProfilesTableViewContents) {
        if ([path isEqualToString:dict[NBCDictionaryKeyConfigurationProfilePath]]) {
            DDLogWarn(@"Configuration Profile %@ is already added!", [path lastPathComponent]);
            return;
        }
    }

    NSInteger index = [_tableViewConfigurationProfiles selectedRow];
    index++;
    [_tableViewConfigurationProfiles beginUpdates];
    [_tableViewConfigurationProfiles insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] withAnimation:NSTableViewAnimationSlideDown];
    [_tableViewConfigurationProfiles scrollRowToVisible:index];
    [_configurationProfilesTableViewContents insertObject:configurationProfileDict atIndex:(NSUInteger)index];
    [_tableViewConfigurationProfiles endUpdates];
    [_viewOverlayConfigurationProfiles setHidden:YES];
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

- (NSDictionary *)examinePackageAtURL:(NSURL *)url {

    DDLogDebug(@"[DEBUG] Examine installer package...");

    NSError *error = nil;
    NSMutableDictionary *newPackageDict = [[NSMutableDictionary alloc] init];

    // -------------------------------------------------------------
    //  Package Path
    // -------------------------------------------------------------
    newPackageDict[NBCDictionaryKeyPath] = [url path] ?: @"Unknown";
    DDLogDebug(@"[DEBUG] Package path: %@", newPackageDict[NBCDictionaryKeyPath]);

    // -------------------------------------------------------------
    //  Package Name
    // -------------------------------------------------------------
    newPackageDict[NBCDictionaryKeyName] = [url lastPathComponent] ?: @"Unknown";
    DDLogDebug(@"[DEBUG] Package name: %@", newPackageDict[NBCDictionaryKeyName]);

    if ([url checkResourceIsReachableAndReturnError:nil]) {

        // -------------------------------------------------------------
        //  Package Format ( Bundle or Flat )
        // -------------------------------------------------------------
        NSNumber *isDirectory;
        BOOL success = [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error];
        if (success) {
            if ([isDirectory boolValue]) {
                newPackageDict[NBCDictionaryKeyPackageFormat] = @"Bundle";
            } else {
                newPackageDict[NBCDictionaryKeyPackageFormat] = @"Flat";
            }
        } else {
            DDLogError(@"[ERROR] %@", [error localizedDescription]);
            newPackageDict[NBCDictionaryKeyPackageFormat] = @"Unknown";
        }
        DDLogDebug(@"[DEBUG] Package format: %@", newPackageDict[NBCDictionaryKeyPackageFormat]);

        // -----------------------------------------------------------------------
        //  Package Type ( Component or Product Archive ) (only if package exist)
        // -----------------------------------------------------------------------
        NSTask *hdiutilTask = [[NSTask alloc] init];
        [hdiutilTask setLaunchPath:@"/usr/bin/xar"];
        NSArray *args = @[ @"-tf", [url path] ];
        [hdiutilTask setArguments:args];
        [hdiutilTask setStandardOutput:[NSPipe pipe]];
        [hdiutilTask setStandardError:[NSPipe pipe]];
        [hdiutilTask launch];
        [hdiutilTask waitUntilExit];

        NSData *stdOutData = [[[hdiutilTask standardOutput] fileHandleForReading] readDataToEndOfFile];
        NSString *stdOut = [[NSString alloc] initWithData:stdOutData encoding:NSUTF8StringEncoding];

        NSData *stdErrData = [[[hdiutilTask standardError] fileHandleForReading] readDataToEndOfFile];
        NSString *stdErr = [[NSString alloc] initWithData:stdErrData encoding:NSUTF8StringEncoding];

        if ([hdiutilTask terminationStatus] == 0) {
            if ([stdOut containsString:@"Distribution"] || [stdOut containsString:@"distribution"]) {
                newPackageDict[NBCDictionaryKeyPackageType] = @"Product Archive";
            } else {
                newPackageDict[NBCDictionaryKeyPackageType] = @"Component";
            }
        } else {
            DDLogError(@"[xar][stdout] %@", stdOut);
            DDLogError(@"[xar][stderr] %@", stdErr);
            DDLogError(@"[ERROR] xar command failed with exit status: %d", [hdiutilTask terminationStatus]);
            newPackageDict[NBCDictionaryKeyPackageType] = @"Unknown";
        }
        DDLogDebug(@"[DEBUG] Package type: %@", newPackageDict[NBCDictionaryKeyPackageType]);
    } else {
        DDLogWarn(@"[WARN] The package \"%@\" couldn’t be opened because there is no such file", newPackageDict[NBCDictionaryKeyName]);
    }

    return newPackageDict;
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

- (NSDictionary *)examineConfigurationProfileAtURL:(NSURL *)url {

    DDLogDebug(@"[DEBUG] Examine configuration profile...");

    NSMutableDictionary *newConfigurationProfileDict = [[NSMutableDictionary alloc] init];

    newConfigurationProfileDict[NBCDictionaryKeyConfigurationProfilePath] = [url path];
    DDLogDebug(@"[DEBUG] Configuration profile path: %@", newConfigurationProfileDict[NBCDictionaryKeyConfigurationProfilePath] ?: @"Unknown");

    NSDictionary *configurationProfileDict = [NSDictionary dictionaryWithContentsOfURL:url];
    NSString *payloadName = configurationProfileDict[@"PayloadDisplayName"] ?: [[url lastPathComponent] stringByDeletingPathExtension];
    newConfigurationProfileDict[NBCDictionaryKeyConfigurationProfilePayloadDisplayName] = payloadName ?: @"Unknown";
    DDLogDebug(@"[DEBUG] Configuration profile name: %@", newConfigurationProfileDict[NBCDictionaryKeyConfigurationProfilePayloadDisplayName]);

    NSString *payloadDescription = configurationProfileDict[@"PayloadDescription"] ?: [[url lastPathComponent] stringByDeletingPathExtension];
    newConfigurationProfileDict[NBCDictionaryKeyConfigurationProfilePayloadDisplayName] = payloadDescription ?: @"";
    DDLogDebug(@"[DEBUG] Configuration profile description: %@", newConfigurationProfileDict[NBCDictionaryKeyConfigurationProfilePayloadDisplayName]);

    return newConfigurationProfileDict;
}

- (BOOL)containsAcceptablePackageURLsFromPasteboard:(NSPasteboard *)pasteboard {
    return [pasteboard canReadObjectForClasses:@[ [NSURL class] ] options:[self pasteboardReadingOptionsPackagesNetInstall]];
}

- (BOOL)containsAcceptableConfigurationProfileURLsFromPasteboard:(NSPasteboard *)pasteboard {
    return [pasteboard canReadObjectForClasses:@[ [NSURL class] ] options:[self pasteboardReadingOptionsConfigurationProfiles]];
}

- (NSDictionary *)pasteboardReadingOptionsPackagesNetInstall {
    return @{ NSPasteboardURLReadingFileURLsOnlyKey : @YES, NSPasteboardURLReadingContentsConformToTypesKey : @[ @"com.apple.installer-package-archive", @"public.shell-script" ] };
}

- (NSDictionary *)pasteboardReadingOptionsConfigurationProfiles {
    return @{ NSPasteboardURLReadingFileURLsOnlyKey : @YES, NSPasteboardURLReadingContentsConformToTypesKey : @[ @"com.apple.mobileconfig" ] };
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods TableView Data Source
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes {
#pragma unused(session, screenPoint)
    NSUInteger len = ([rowIndexes lastIndex] + 1) - [rowIndexes firstIndex];
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        [self setObjectRange:NSMakeRange([rowIndexes firstIndex], len)];
        [self setCurrentlyDraggedObjects:[_packagesNetInstallTableViewContents objectsAtIndexes:rowIndexes]];
    }
}

- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
#pragma unused(session, screenPoint, operation)
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        [self setObjectRange:NSMakeRange(0, 0)];
        [self setCurrentlyDraggedObjects:nil];
    }
}

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        NSDictionary *itemDict = _packagesNetInstallTableViewContents[(NSUInteger)row];
        return [NSURL fileURLWithPath:itemDict[NBCDictionaryKeyPath]];
    }
    return nil;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        NSDictionary *packageDict = _packagesNetInstallTableViewContents[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"PackageTableColumn"]) {
            NBCPackageTableCellView *cellView = [tableView makeViewWithIdentifier:@"PackageCellView" owner:self];
            return [self populatePackageCellView:cellView packageDict:packageDict];
        }
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierConfigurationProfiles]) {
        NSDictionary *configurationProfileDict = _configurationProfilesTableViewContents[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"ConfigurationProfileTableColumn"]) {
            NBCConfigurationProfileTableCellView *cellView = [tableView makeViewWithIdentifier:@"ConfigurationProfileCellView" owner:self];
            return [self populateConfigurationProfileCellView:cellView configurationProfileDict:configurationProfileDict];
        }
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierNetInstallTrustedServers]) {
        [self updateTrustedNetBootServersCount];
        NSString *trustedServer = _trustedServers[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"NetInstallTrustedNetBootTableColumn"]) {
            NBCNetInstallTrustedNetBootServerCellView *cellView = [tableView makeViewWithIdentifier:@"NetInstallNetBootServerCellView" owner:self];
            return [self populateTrustedNetBootServerCellView:cellView netBootServerIP:trustedServer row:row];
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

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation {
#pragma unused(row)
    if (dropOperation == NSTableViewDropAbove) {
        if ([info draggingSource] == tableView && (row < (NSInteger)_objectRange.location || (NSInteger)_objectRange.location + (NSInteger)_objectRange.length < row)) {
            return NSDragOperationMove;
        } else {
            if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
                if ([self containsAcceptablePackageURLsFromPasteboard:[info draggingPasteboard]]) {
                    [info setAnimatesToDestination:YES];
                    return NSDragOperationCopy;
                }
            } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierConfigurationProfiles]) {
                if ([self containsAcceptableConfigurationProfileURLsFromPasteboard:[info draggingPasteboard]]) {
                    [info setAnimatesToDestination:YES];
                    return NSDragOperationCopy;
                }
            }
        }
    }
    return NSDragOperationNone;
}

- (void)tableView:(NSTableView *)tableView updateDraggingItemsForDrag:(id<NSDraggingInfo>)draggingInfo {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        NSArray *classes = @[ [NBCDesktopPackageEntity class], [NBCDesktopScriptEntity class], [NSPasteboardItem class] ];
        __block NSInteger validCount = 0;
        [draggingInfo enumerateDraggingItemsWithOptions:0
            forView:tableView
            classes:classes
            searchOptions:@{}
            usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
              if ([[draggingItem item] isKindOfClass:[NBCDesktopPackageEntity class]] || [[draggingItem item] isKindOfClass:[NBCDesktopScriptEntity class]]) {
                  validCount++;
              }
            }];
        [draggingInfo setNumberOfValidItemsForDrop:validCount];
        [draggingInfo setDraggingFormation:NSDraggingFormationList];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierConfigurationProfiles]) {
        NSArray *classes = @[ [NBCDesktopConfigurationProfileEntity class], [NSPasteboardItem class] ];
        __block NSInteger validCount = 0;
        [draggingInfo enumerateDraggingItemsWithOptions:0
            forView:tableView
            classes:classes
            searchOptions:@{}
            usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
              if ([[draggingItem item] isKindOfClass:[NBCDesktopConfigurationProfileEntity class]]) {
                  validCount++;
              }
            }];
        [draggingInfo setNumberOfValidItemsForDrop:validCount];
        [draggingInfo setDraggingFormation:NSDraggingFormationList];
    }
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation {
#pragma unused(dropOperation)
    if (_currentlyDraggedObjects == nil) {
        if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
            [self insertItemInPackagesNetInstallTableView:_tableViewPackagesNetInstall draggingInfo:info row:row];
        } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierConfigurationProfiles]) {
            [self insertConfigurationProfilesInTableView:_tableViewConfigurationProfiles draggingInfo:info row:row];
        }
    } else {
        if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
            [tableView beginUpdates];
            [self reorderItemsInPackagesNetInstallTableView:_tableViewPackagesNetInstall draggingInfo:info row:row];
            [tableView endUpdates];
        } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierConfigurationProfiles]) {
            //[tableView beginUpdates];
            //[self reorderConfigurationProfilesInTableView:_tableViewConfigurationProfiles draggingInfo:info row:row];
            //[tableView endUpdates];
        }
    }
    return NO;
}

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
    // Check if empty view already exist
    __block NSNumber *index;
    [_trustedServers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      if ([obj length] == 0) {
          index = @((NSInteger)idx);
          *stop = YES;
      }
    }];

    if (index == nil) {
        // Insert new view
        index = @([self insertNetBootServerIPInTableView:@""]);
    }

    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:(NSUInteger)index];
    // Select the newly created text field in the new view
    [_tableViewTrustedServers selectRowIndexes:indexSet byExtendingSelection:NO];
    [[[_tableViewTrustedServers viewAtColumn:[_tableViewTrustedServers selectedColumn] row:[index integerValue] makeIfNecessary:NO] textFieldTrustedNetBootServer] selectText:self];
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
      // Skip empty lines
      if ([obj length] == 0) {
          return;
      }

      NBCNetInstallTrustedNetBootServerCellView *cellView = [self->_tableViewTrustedServers viewAtColumn:0 row:(NSInteger)idx makeIfNecessary:NO];

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

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Delegate Methods TableView
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPackages]) {
        return (NSInteger)[_packagesNetInstallTableViewContents count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierConfigurationProfiles]) {
        return (NSInteger)[_configurationProfilesTableViewContents count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierNetInstallTrustedServers]) {
        return (NSInteger)[_trustedServers count];
    } else if ([[tableView identifier] isEqualToString:NBCTableViewIdentifierPostWorkflowScripts]) {
        return (NSInteger)[_postWorkflowScripts count];
    } else {
        return 0;
    }
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark TableView Methods
#pragma mark -
////////////////////////////////////////////////////////////////////////////////

- (NBCConfigurationProfileTableCellView *)populateConfigurationProfileCellView:(NBCConfigurationProfileTableCellView *)cellView configurationProfileDict:(NSDictionary *)configurationProfileDict {
    NSMutableAttributedString *configurationProfilePath;
    NSImage *icon;
    NSURL *url = [NSURL fileURLWithPath:configurationProfileDict[NBCDictionaryKeyConfigurationProfilePath]];
    if ([url checkResourceIsReachableAndReturnError:nil]) {
        [[cellView textFieldConfigurationProfileName] setStringValue:configurationProfileDict[NBCDictionaryKeyConfigurationProfilePayloadDisplayName]];
        icon = [[NSWorkspace sharedWorkspace] iconForFile:[url path]];
        [[cellView imageViewConfigurationProfileIcon] setImage:icon];
    } else {
        configurationProfilePath = [[NSMutableAttributedString alloc] initWithString:configurationProfileDict[NBCDictionaryKeyConfigurationProfilePath]];
        [configurationProfilePath addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[configurationProfilePath length])];
        [[cellView textFieldConfigurationProfileName] setAttributedStringValue:configurationProfilePath];
    }

    return cellView;
}

- (NBCPackageTableCellView *)populatePackageCellView:(NBCPackageTableCellView *)cellView packageDict:(NSDictionary *)packageDict {
    NSMutableAttributedString *packageName;
    NSImage *packageIcon;
    NSURL *packageURL = [NSURL fileURLWithPath:packageDict[NBCDictionaryKeyPath]];
    if ([packageURL checkResourceIsReachableAndReturnError:nil]) {
        [[cellView textFieldPackageName] setStringValue:packageDict[NBCDictionaryKeyName]];
        packageIcon = [[NSWorkspace sharedWorkspace] iconForFile:[packageURL path]];
        [[cellView imageViewPackageIcon] setImage:packageIcon];
    } else {
        packageName = [[NSMutableAttributedString alloc] initWithString:packageDict[NBCDictionaryKeyName]];
        [packageName addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[packageName length])];
        [[cellView textFieldPackageName] setAttributedStringValue:packageName];
    }

    return cellView;
}

- (NBCNetInstallTrustedNetBootServerCellView *)populateTrustedNetBootServerCellView:(NBCNetInstallTrustedNetBootServerCellView *)cellView
                                                                    netBootServerIP:(NSString *)netBootServerIP
                                                                                row:(NSInteger)row {
    NSMutableAttributedString *netBootServerIPMutable;
    [[cellView textFieldTrustedNetBootServer] setTag:row];
    if ([netBootServerIP isValidIPAddress]) {
        [[cellView textFieldTrustedNetBootServer] setStringValue:netBootServerIP];
    } else {
        netBootServerIPMutable = [[NSMutableAttributedString alloc] initWithString:netBootServerIP];
        [netBootServerIPMutable addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, (NSUInteger)[netBootServerIPMutable length])];
        [[cellView textFieldTrustedNetBootServer] setAttributedStringValue:netBootServerIPMutable];
    }

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

- (void)insertConfigurationProfilesInTableView:(NSTableView *)tableView draggingInfo:(id<NSDraggingInfo>)info row:(NSInteger)row {
    NSArray *classes = @[ [NBCDesktopConfigurationProfileEntity class] ];
    __block NSInteger insertionIndex = row;
    [info enumerateDraggingItemsWithOptions:0
        forView:tableView
        classes:classes
        searchOptions:@{}
        usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
          NBCDesktopConfigurationProfileEntity *entity = (NBCDesktopConfigurationProfileEntity *)[draggingItem item];
          if ([entity isKindOfClass:[NBCDesktopConfigurationProfileEntity class]]) {
              NSDictionary *configurationProfileDict = [self examineConfigurationProfileAtURL:[entity fileURL]];
              if ([configurationProfileDict count] != 0) {

                  NSString *path = configurationProfileDict[NBCDictionaryKeyConfigurationProfilePath];
                  for (NSDictionary *dict in self->_configurationProfilesTableViewContents) {
                      if ([path isEqualToString:dict[NBCDictionaryKeyConfigurationProfilePath]]) {
                          DDLogWarn(@"Configuration Profile %@ is already added!", [path lastPathComponent]);
                          return;
                      }
                  }

                  [self->_configurationProfilesTableViewContents insertObject:configurationProfileDict atIndex:(NSUInteger)insertionIndex];
                  [tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)insertionIndex] withAnimation:NSTableViewAnimationEffectGap];
                  [draggingItem setDraggingFrame:[tableView frameOfCellAtColumn:0 row:insertionIndex]];
                  insertionIndex++;
                  [self->_viewOverlayConfigurationProfiles setHidden:YES];
              }
          }
        }];
}

- (void)reorderItemsInPackagesNetInstallTableView:(NSTableView *)tableView draggingInfo:(id<NSDraggingInfo>)info row:(NSInteger)row {
    NSArray *classes = @[ [NBCDesktopPackageEntity class], [NBCDesktopScriptEntity class] ];
    [info enumerateDraggingItemsWithOptions:0
        forView:tableView
        classes:classes
        searchOptions:@{}
        usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop, draggingItem)
          NSInteger newIndex = (row + idx);
          NBCDesktopEntity *entity = self->_currentlyDraggedObjects[(NSUInteger)idx];
          NSInteger oldIndex = (NSInteger)[self->_packagesNetInstallTableViewContents indexOfObject:entity];
          if (oldIndex < newIndex) {
              newIndex -= (idx + 1);
          }
          [self->_packagesNetInstallTableViewContents removeObjectAtIndex:(NSUInteger)oldIndex];
          [self->_packagesNetInstallTableViewContents insertObject:entity atIndex:(NSUInteger)newIndex];
          [self->_tableViewPackagesNetInstall moveRowAtIndex:oldIndex toIndex:newIndex];
        }];
}

- (void)insertItemInPackagesNetInstallTableView:(NSTableView *)tableView draggingInfo:(id<NSDraggingInfo>)info row:(NSInteger)row {
    NSArray *classes = @[ [NBCDesktopPackageEntity class], [NBCDesktopScriptEntity class] ];
    __block NSInteger insertionIndex = row;
    __block NSMutableArray *incorrectPackageTypes = [[NSMutableArray alloc] init];
    __block NSMutableArray *packageWarning = [[NSMutableArray alloc] init];
    [info enumerateDraggingItemsWithOptions:0
        forView:tableView
        classes:classes
        searchOptions:@{}
        usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
#pragma unused(idx, stop)
          if ([[draggingItem item] isKindOfClass:[NBCDesktopPackageEntity class]]) {
              NBCDesktopPackageEntity *entity = (NBCDesktopPackageEntity *)[draggingItem item];
              if ([entity isKindOfClass:[NBCDesktopPackageEntity class]]) {
                  NSDictionary *packageDict = [self examinePackageAtURL:[entity fileURL]];
                  if ([packageDict count] != 0) {
                      NSString *packagePath = packageDict[NBCDictionaryKeyPath];
                      NSString *packageName = packageDict[NBCDictionaryKeyName];
                      for (NSDictionary *pkgDict in self->_packagesNetInstallTableViewContents) {
                          if ([packagePath isEqualToString:pkgDict[NBCDictionaryKeyPath]]) {
                              [packageWarning addObject:packageDict];
                              DDLogWarn(@"Package %@ is already added!", [packagePath lastPathComponent]);
                              return;
                          }

                          if ([packageName isEqualToString:pkgDict[NBCDictionaryKeyName]]) {
                              [packageWarning addObject:packageDict];
                              DDLogWarn(@"A package with the name: \"%@\" has already been added!", [packagePath lastPathComponent]);
                              return;
                          }
                      }

                      if ([packageDict[NBCDictionaryKeyPackageFormat] length] != 0 &&
                          (![packageDict[NBCDictionaryKeyPackageFormat] isEqualToString:@"Flat"] || ![packageDict[NBCDictionaryKeyPackageType] isEqualToString:@"Product Archive"])) {
                          [incorrectPackageTypes addObject:packageDict];
                      } else {
                          [self->_packagesNetInstallTableViewContents insertObject:packageDict atIndex:(NSUInteger)insertionIndex];
                          [tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)insertionIndex] withAnimation:NSTableViewAnimationEffectGap];
                          [draggingItem setDraggingFrame:[tableView frameOfCellAtColumn:0 row:insertionIndex]];
                          insertionIndex++;
                          [self->_viewOverlayPackagesNetInstall setHidden:YES];
                      }
                  }
              }
          } else if ([[draggingItem item] isKindOfClass:[NBCDesktopScriptEntity class]]) {
              NBCDesktopScriptEntity *entity = (NBCDesktopScriptEntity *)[draggingItem item];
              if ([entity isKindOfClass:[NBCDesktopScriptEntity class]]) {
                  NSDictionary *scriptDict = [self examineScriptAtURL:[entity fileURL]];
                  if ([scriptDict count] != 0) {

                      NSString *scriptPath = scriptDict[NBCDictionaryKeyPath];
                      for (NSDictionary *dict in self->_packagesNetInstallTableViewContents) {
                          if ([scriptPath isEqualToString:dict[NBCDictionaryKeyPath]]) {
                              DDLogWarn(@"Script %@ is already added!", [scriptPath lastPathComponent]);
                              return;
                          }
                      }

                      [self->_packagesNetInstallTableViewContents insertObject:scriptDict atIndex:(NSUInteger)insertionIndex];
                      [tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)insertionIndex] withAnimation:NSTableViewAnimationEffectGap];
                      [draggingItem setDraggingFrame:[tableView frameOfCellAtColumn:0 row:insertionIndex]];
                      insertionIndex++;
                      [self->_viewOverlayPackagesNetInstall setHidden:YES];
                  }
              }
          }
        }];
    if ([packageWarning count] != 0) {
        [NBCAlerts showAlertPackageAlreadyAdded:packageWarning];
    }

    if ([incorrectPackageTypes count] != 0) {
        NBCAlerts *alert = [[NBCAlerts alloc] initWithDelegate:self];
        [alert showAlertIncorrectPackageType:incorrectPackageTypes alertInfo:@{NBCAlertTagKey : NBCAlertTagIncorrectPackageType, NBCAlertResourceKey : incorrectPackageTypes}];
    }
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

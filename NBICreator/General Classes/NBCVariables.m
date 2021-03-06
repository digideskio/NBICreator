//
//  NBCVariables.m
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

#import "NBCConstants.h"
#import "NBCVariables.h"

#import "NBCApplicationSourceDeployStudio.h"
#import "NBCApplicationSourceSystemImageUtility.h"
#import "NBCLogging.h"
#import "NBCSource.h"

DDLogLevel ddLogLevel;

@implementation NBCVariables

+ (NSString *)expandVariables:(NSString *)string source:(NBCSource *)source applicationSource:(id)applicationSource {

    NSString *newString = string;

    // -------------------------------------------------------------
    //  Expand variables for current application version
    // -------------------------------------------------------------
    NSDictionary *nbiCreatorInfoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *nbiCreatorVersion = nbiCreatorInfoDict[@"CFBundleShortVersionString"];
    NSString *nbiCreatorBuild = nbiCreatorInfoDict[@"CFBundleVersion"];
    NSString *nbiCreatorVersionString = [NSString stringWithFormat:@"%@-%@", nbiCreatorVersion, nbiCreatorBuild];
    newString = [newString stringByReplacingOccurrencesOfString:NBCVariableNBICreatorVersion withString:nbiCreatorVersionString];

    // -------------------------------------------------------------
    //  Expand variables for current Source
    // -------------------------------------------------------------
    if (source != nil) {
        newString = [source expandVariables:newString];
    } else {
        NBCSource *tmpSource = [[NBCSource alloc] init];
        newString = [tmpSource expandVariables:newString];
    }

    // -------------------------------------------------------------
    //  Expand variables for current external application
    // -------------------------------------------------------------
    if (applicationSource) {
        newString = [applicationSource expandVariables:newString];
    }

    // --------------------------------------------------------------
    //  Expand %COUNTER%
    // --------------------------------------------------------------
    NSString *indexCounter;
    NSNumber *defaultsCounter = [[NSUserDefaults standardUserDefaults] objectForKey:NBCUserDefaultsIndexCounter];
    if (defaultsCounter) {
        indexCounter = [NSString stringWithFormat:@"%@", defaultsCounter];
    } else {
        indexCounter = @"1024";
    }

    newString = [newString stringByReplacingOccurrencesOfString:NBCVariableIndexCounter withString:indexCounter];

    // --------------------------------------------------------------
    //  Expand %APPLICATIONRESOURCESURL%
    // --------------------------------------------------------------
    NSString *applicationResourcesURL;
    applicationResourcesURL = [[NSBundle mainBundle] resourcePath];

    newString = [newString stringByReplacingOccurrencesOfString:NBCVariableApplicationResourcesURL withString:applicationResourcesURL];

    // --------------------------------------------------------------
    //  Expand %DATE%
    // --------------------------------------------------------------
    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSString *dateFormatString = [[NSUserDefaults standardUserDefaults] objectForKey:NBCUserDefaultsDateFormatString];
    NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setDateFormat:dateFormatString];
    NSString *formattedDate = [dateFormatter stringFromDate:date];

    newString = [newString stringByReplacingOccurrencesOfString:NBCVariableDate withString:formattedDate];
    return newString;
} // expandVariables

@end

//
//  NBCDownloaderGitHub.m
//  NBICreator
//
//  Created by Erik Berglund on 2015-05-06.
//  Copyright (c) 2015 NBICreator. All rights reserved.
//

#import "NBCDownloaderGitHub.h"
#import "NBCConstants.h"
#import "NBCLogging.h"

DDLogLevel ddLogLevel;

@implementation NBCDownloaderGitHub

- (id)initWithDelegate:(id<NBCDownloaderGitHubDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (void)getReleaseVersionsAndURLsFromGithubRepository:(NSString *)repository downloadInfo:(NSDictionary *)downloadInfo {
    DDLogDebug(@"%@", NSStringFromSelector(_cmd));
    NSString *githubURL = [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases", repository];
    
    NBCDownloader *downloader = [[NBCDownloader alloc] initWithDelegate:self];
    [downloader downloadPageAsData:[NSURL URLWithString:githubURL] downloadInfo:downloadInfo];
}

- (void)dataDownloadCompleted:(NSData *)data downloadInfo:(NSDictionary *)downloadInfo {
    DDLogDebug(@"%@", NSStringFromSelector(_cmd));
    NSMutableArray *releaseVersions = [[NSMutableArray alloc] init];
    NSMutableDictionary *releaseVersionsURLsDict = [[NSMutableDictionary alloc] init];
    
    NSArray *allReleases = [self convertJSONDataToArray:data];
    
    for ( NSDictionary *dict in allReleases ) {
        NSString *versionNumber = [dict[@"tag_name"] stringByReplacingOccurrencesOfString:@"v" withString:@""];
        [releaseVersions addObject:versionNumber];
        
        NSArray *assets = dict[@"assets"];
        NSDictionary *assetsDict = [assets firstObject];
        NSString *downloadURL = assetsDict[@"browser_download_url"];
        releaseVersionsURLsDict[versionNumber] = downloadURL;
    }

    [_delegate githubReleaseVersionsArray:[releaseVersions copy] downloadDict:[releaseVersionsURLsDict copy] downloadInfo:downloadInfo];
}

- (NSArray *)convertJSONDataToArray:(NSData *)data {
    DDLogDebug(@"%@", NSStringFromSelector(_cmd));
    if ( data != nil ) {
        NSError *error;
        
        id jsonDataArray = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
        
        if ( [jsonDataArray isKindOfClass:[NSArray class]] ) {
            return jsonDataArray;
        } else if ( jsonDataArray == nil ) {
            NSLog(@"Error when serializing JSONData: %@.", error);
        }
    }
    return nil;
}

@end
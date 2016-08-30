#import "CodePush.h"
#include <CommonCrypto/CommonDigest.h>

@implementation CodePushUpdateUtils

NSString * const AssetsFolderName = @"assets";
NSString * const BinaryHashKey = @"CodePushBinaryHash";
NSString * const ManifestFolderPrefix = @"CodePush";

+ (BOOL)addContentsOfFolderToManifest:(NSString *)folderPath
                           pathPrefix:(NSString *)pathPrefix
                             manifest:(NSMutableArray *)manifest
                                error:(NSError **)error
{
    NSError *localError;
    NSArray *folderFiles = [[NSFileManager defaultManager]
                            contentsOfDirectoryAtPath:folderPath
                            error:&localError];
    if (!folderFiles) {
        if (localError && error) {
            *error = localError;
        }
        return NO;
    }
    
    for (NSString *fileName in folderFiles) {
        // We must skip the macOS generated files.
        if ([fileName isEqualToString:@".DS_Store"] || [fileName isEqualToString:@"__MACOSX"]) {
            continue;
        }

        NSString *fullFilePath = [folderPath stringByAppendingPathComponent:fileName];
        NSString *relativePath = [pathPrefix stringByAppendingPathComponent:fileName];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullFilePath
                                                 isDirectory:&isDir] && isDir) {
            BOOL result = [self addContentsOfFolderToManifest:fullFilePath
                                                   pathPrefix:relativePath
                                                     manifest:manifest
                                                        error:&localError];
            if (!result) {
                if (error) {
                    *error = localError;
                }
                return NO;
            }
        } else {
            NSData *fileContents = [NSData dataWithContentsOfFile:fullFilePath];
            NSString *fileContentsHash = [self computeHashForData:fileContents];
            [manifest addObject:[[relativePath stringByAppendingString:@":"] stringByAppendingString:fileContentsHash]];
        }
    }
    return YES;
}

+ (void)addFileToManifest:(NSURL *)fileURL
                 manifest:(NSMutableArray *)manifest
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        NSData *fileContents = [NSData dataWithContentsOfURL:fileURL];
        NSString *fileContentsHash = [self computeHashForData:fileContents];
        [manifest addObject:[NSString stringWithFormat:@"%@/%@:%@", [self manifestFolderPrefix], [fileURL lastPathComponent], fileContentsHash]];
    }
}

+ (NSString *)computeFinalHashFromManifest:(NSMutableArray *)manifest
                                     error:(NSError **)error
{
    NSError *localError;
    NSArray *sortedManifest = [manifest sortedArrayUsingSelector:@selector(compare:)];
    NSData *manifestData = [NSJSONSerialization dataWithJSONObject:sortedManifest
                                                           options:kNilOptions
                                                             error:&localError];
    if (!manifestData) {
        if (localError && error) {
            *error = localError;
        }
        return nil;
    }
    
    NSString *manifestString = [[NSString alloc] initWithData:manifestData
                                                     encoding:NSUTF8StringEncoding];
    // The JSON serialization turns path separators into "\/", e.g. "CodePush\/assets\/image.png"
    manifestString = [manifestString stringByReplacingOccurrencesOfString:@"\\/"
                                                               withString:@"/"];
    return [self computeHashForData:[NSData dataWithBytes:manifestString.UTF8String length:manifestString.length]];
}

+ (NSString *)computeHashForData:(NSData *)inputData
{
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(inputData.bytes, inputData.length, digest);
    NSMutableString* inputHash = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [inputHash appendFormat:@"%02x", digest[i]];
    }
    
    return inputHash;
}

+ (void)copyEntriesInFolder:(NSString *)sourceFolder
                 destFolder:(NSString *)destFolder
                      error:(NSError **)error
{
    NSError *localError;
    NSArray* files = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtPath:sourceFolder
                      error:&localError];
    if (!files) {
        if (localError && error) {
            *error = localError;
        }
        return;
    }
    
    for (NSString *fileName in files) {
        NSString * fullFilePath = [sourceFolder stringByAppendingPathComponent:fileName];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullFilePath
                                                 isDirectory:&isDir] && isDir) {
            NSString *nestedDestFolder = [destFolder stringByAppendingPathComponent:fileName];
            [self copyEntriesInFolder:fullFilePath
                           destFolder:nestedDestFolder
                                error:&localError];
        } else {
            NSString *destFileName = [destFolder stringByAppendingPathComponent:fileName];
            if ([[NSFileManager defaultManager] fileExistsAtPath:destFileName]) {
                BOOL result = [[NSFileManager defaultManager] removeItemAtPath:destFileName error:&localError];
                if (!result) {
                    if (localError && error) {
                        *error = localError;
                    }
                    return;
                }
            }
            if (![[NSFileManager defaultManager] fileExistsAtPath:destFolder]) {
                BOOL result = [[NSFileManager defaultManager] createDirectoryAtPath:destFolder
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:&localError];
                if (!result) {
                    if (localError && error) {
                        *error = localError;
                    }
                    return;
                }
            }
            
            BOOL result = [[NSFileManager defaultManager] copyItemAtPath:fullFilePath toPath:destFileName error:&localError];
            if (!result) {
                if (localError && error) {
                    *error = localError;
                }
                return;
            }
        }
    }
}

+ (NSString *)findMainBundleInFolder:(NSString *)folderPath
                    expectedFileName:(NSString *)expectedFileName
                               error:(NSError **)error
{
    NSError *localError;
    NSArray* folderFiles = [[NSFileManager defaultManager]
                            contentsOfDirectoryAtPath:folderPath
                            error:&localError];
    if (!folderFiles) {
        if (localError && error) {
            *error = localError;
        }
        return nil;
    }
    
    for (NSString *fileName in folderFiles) {
        NSString *fullFilePath = [folderPath stringByAppendingPathComponent:fileName];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullFilePath
                                                 isDirectory:&isDir] && isDir) {
            NSString *mainBundlePathInFolder = [self findMainBundleInFolder:fullFilePath
                                                           expectedFileName:expectedFileName
                                                                      error:&localError];
            if (!mainBundlePathInFolder) {
                if (localError && error) {
                    *error = localError;
                }
                return nil;
            }
            
            if (mainBundlePathInFolder) {
                return [fileName stringByAppendingPathComponent:mainBundlePathInFolder];
            }
        } else if ([fileName isEqualToString:expectedFileName]) {
            return fileName;
        }
    }
    
    return nil;
}

+ (NSString *)assetsFolderName
{
    return AssetsFolderName;
}

+ (NSString *)getHashForBinaryContents:(NSURL *)binaryBundleUrl
                                 error:(NSError **)error
{
    // Get the cached hash from user preferences if it exists.
    NSError *localError;
    NSString *binaryModifiedDate = [self modifiedDateStringOfFileAtURL:binaryBundleUrl];
    NSUserDefaults *preferences = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *binaryHashDictionary = [preferences objectForKey:BinaryHashKey];
    NSString *binaryHash = nil;
    if (binaryHashDictionary != nil) {
        binaryHash = [binaryHashDictionary objectForKey:binaryModifiedDate];
        if (binaryHash == nil) {
            [preferences removeObjectForKey:BinaryHashKey];
            [preferences synchronize];
        } else {
            return binaryHash;
        }
    }
    
    binaryHashDictionary = [NSMutableDictionary dictionary];
    NSMutableArray *manifest = [NSMutableArray array];
    
    // If the app is using assets, then add
    // them to the generated content manifest.
    NSString *assetsPath = [CodePush bundleAssetsPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:assetsPath]) {
        BOOL result = [self addContentsOfFolderToManifest:assetsPath
                                               pathPrefix:[NSString stringWithFormat:@"%@/%@", [self manifestFolderPrefix], @"assets"]
                                                 manifest:manifest
                                                    error:&localError];
        if (!result) {
            if (error) {
                *error = localError;
            }
            return nil;
        }
    }
    
    [self addFileToManifest:binaryBundleUrl manifest:manifest];
    [self addFileToManifest:[binaryBundleUrl URLByAppendingPathExtension:@"meta"] manifest:manifest];

    binaryHash = [self computeFinalHashFromManifest:manifest error:&localError];
    
    // Cache the hash in user preferences. This assumes that the modified date for the
    // JS bundle changes every time a new bundle is generated by the packager.
    [binaryHashDictionary setObject:binaryHash forKey:binaryModifiedDate];
    [preferences setObject:binaryHashDictionary forKey:BinaryHashKey];
    [preferences synchronize];
    return binaryHash;
}

+ (NSString *)manifestFolderPrefix
{
    return ManifestFolderPrefix;
}

+ (NSString *)modifiedDateStringOfFileAtURL:(NSURL *)fileURL
{
    if (fileURL != nil) {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:nil];
        NSDate *modifiedDate = [fileAttributes objectForKey:NSFileModificationDate];
        return [NSString stringWithFormat:@"%f", [modifiedDate timeIntervalSince1970]];
    } else {
        return nil;
    }
}

+ (BOOL)verifyHashForDiffUpdate:(NSString *)finalUpdateFolder
                   expectedHash:(NSString *)expectedHash
                          error:(NSError **)error
{
    NSError *localError;
    NSMutableArray *updateContentsManifest = [NSMutableArray array];
    BOOL result = [self addContentsOfFolderToManifest:finalUpdateFolder
                                           pathPrefix:@""
                                             manifest:updateContentsManifest
                                                error:&localError];
    if (!result) {
        if (error) {
            *error = localError;
        }
        return NO;
    }

    NSString *updateContentsManifestHash = [self computeFinalHashFromManifest:updateContentsManifest
                                                                        error:&localError];
    if (updateContentsManifestHash == nil) {
        if (error) {
            *error = localError;
        }
        return NO;
    }
    
    return [updateContentsManifestHash isEqualToString:expectedHash];
}

@end
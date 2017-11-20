//
//  PVEmulatorCore.m
//  Provenance
//
//  Created by James Addyman on 31/08/2013.
//  Copyright (c) 2013 James Addyman. All rights reserved.
//

#import "PVEmulatorCore.h"
#import <CloudKit/CloudKit.h>
#import "NSObject+PVAbstractAdditions.h"
#import "OERingBuffer.h"
#import "RealTimeThread.h"

static Class PVEmulatorCoreClass = Nil;
static NSTimeInterval defaultFrameInterval = 60.0;

NSString *const PVEmulatorCoreErrorDomain = @"com.jamsoftonline.EmulatorCore.ErrorDomain";

@interface PVEmulatorCore()
@property (nonatomic, assign) CGFloat  framerateMultiplier;
@end

@implementation PVEmulatorCore

+ (void)initialize
{
    if (self == [PVEmulatorCore class])
    {
        PVEmulatorCoreClass = [PVEmulatorCore class];
    }
}

- (id)init
{
	if ((self = [super init]))
	{
		NSUInteger count = [self audioBufferCount];
        ringBuffers = (__strong OERingBuffer **)calloc(count, sizeof(OERingBuffer *));
        self.emulationLoopThreadLock = [NSLock new];
	}
	
	return self;
}

- (void)dealloc
{
    [self stopEmulation];

	for (NSUInteger i = 0, count = [self audioBufferCount]; i < count; i++)
	{
		ringBuffers[i] = nil;
	}
	
    free(ringBuffers);
}

#pragma mark - Execution

- (void)startEmulation
{
	if ([self class] != PVEmulatorCoreClass)
    {
		if (!isRunning)
		{
			isRunning  = YES;
			shouldStop = NO;
            self.gameSpeed = GameSpeedNormal;
            [NSThread detachNewThreadSelector:@selector(emulationLoopThread) toTarget:self withObject:nil];

		}
	}
}

- (void)resetEmulation
{
	[self doesNotImplementSelector:_cmd];
}

- (void)setPauseEmulation:(BOOL)flag
{
    if (flag)
	{
		isRunning = NO;
	}
    else
	{
		isRunning = YES;
	}
}

- (BOOL)isEmulationPaused
{
    return !isRunning;
}

- (void)stopEmulation
{
	shouldStop = YES;
    isRunning  = NO;

    [self.emulationLoopThreadLock lock]; // make sure emulator loop has ended
    [self.emulationLoopThreadLock unlock];
}

- (void)updateControllers
{
    //subclasses may implement for polling
}

- (void) emulationLoopThread {

    // For FPS computation
    int frameCount = 0;
    NSDate *fpsCounter = [NSDate date];
    
    //Setup Initial timing
    NSDate *origin = [NSDate date];
    NSTimeInterval sleepTime;
    NSTimeInterval nextEmuTick = GetSecondsSince(origin);
    
    [self.emulationLoopThreadLock lock];

    //Become a real-time thread:
    MakeCurrentThreadRealTime();

    //Emulation loop
    while (!shouldStop) {

        [self updateControllers];
        
        @synchronized (self) {
            if (isRunning) {
                [self executeFrame];
            }
        }
        frameCount += 1;

        nextEmuTick += gameInterval;
        sleepTime = nextEmuTick - GetSecondsSince(origin);
        if(sleepTime >= 0) {
            [NSThread sleepForTimeInterval:sleepTime];
        }
        else if (sleepTime < -0.1) {
            // We're behind, we need to reset emulation time,
            // otherwise emulation will "catch up" to real time
            origin = [NSDate date];
            nextEmuTick = GetSecondsSince(origin);
        }

        // Compute FPS
        NSTimeInterval timeSinceLastFPS = GetSecondsSince(fpsCounter);
        if (timeSinceLastFPS >= 0.5) {
            self.emulationFPS = (double)frameCount / timeSinceLastFPS;
            frameCount = 0;
            fpsCounter = [NSDate date];
        }
        
    }
    
    [self.emulationLoopThreadLock unlock];
}

- (void)setGameSpeed:(GameSpeed)gameSpeed
{
    _gameSpeed = gameSpeed;
    
    switch (gameSpeed) {
        case GameSpeedSlow:
            self.framerateMultiplier = 0.2;
            break;
        case GameSpeedNormal:
            self.framerateMultiplier = 1.0;
            break;
        case GameSpeedFast:
            self.framerateMultiplier = 5.0;
            break;
    }
}

- (BOOL)isSpeedModified
{
	return self.gameSpeed != GameSpeedNormal;
}

- (void)setFramerateMultiplier:(CGFloat)framerateMultiplier
{
	_framerateMultiplier = framerateMultiplier;

    NSLog(@"multiplier: %.1f", framerateMultiplier);
    gameInterval = 1.0 / ([self frameInterval] * framerateMultiplier);
}

- (void)executeFrame
{
	[self doesNotImplementOptionalSelector:_cmd];
}

- (BOOL)loadFileAtPath:(NSString*)path
{
	[self doesNotImplementSelector:_cmd];
	return NO;
}

- (BOOL)supportsDiskSwapping
{
    return NO;
}

- (void)swapDisk
{
    [self doesNotImplementOptionalSelector:_cmd];
}

#pragma mark - Video

- (const void *)videoBuffer
{
	[self doesNotImplementSelector:_cmd];
	return NULL;
}

- (CGRect)screenRect
{
	[self doesNotImplementSelector:_cmd];
	return CGRectZero;
}

- (CGSize)aspectSize
{
	[self doesNotImplementSelector:_cmd];
	return CGSizeZero;
}

- (CGSize)bufferSize
{
	[self doesNotImplementSelector:_cmd];
	return CGSizeZero;
}

- (GLenum)pixelFormat
{
	[self doesNotImplementSelector:_cmd];
	return 0;
}

- (GLenum)pixelType
{
	[self doesNotImplementSelector:_cmd];
	return 0;
}

- (GLenum)internalPixelFormat
{
	[self doesNotImplementSelector:_cmd];
	return 0;
}

- (NSTimeInterval)frameInterval
{
	return defaultFrameInterval;
}

#pragma mark - Audio

- (double)audioSampleRate
{
	[self doesNotImplementSelector:_cmd];
	return 0;
}

- (NSUInteger)channelCount
{
	[self doesNotImplementSelector:_cmd];
	return 0;
}

- (NSUInteger)audioBufferCount
{
	return 1;
}

- (void)getAudioBuffer:(void *)buffer frameCount:(NSUInteger)frameCount bufferIndex:(NSUInteger)index
{
	[[self ringBufferAtIndex:index] read:buffer maxLength:frameCount * [self channelCountForBuffer:index] * sizeof(UInt16)];
}

- (NSUInteger)audioBitDepth
{
	return 16;
}

- (NSUInteger)channelCountForBuffer:(NSUInteger)buffer
{
	if (buffer == 0)
	{
		return [self channelCount];
	}
	
	DLog(@"Buffer counts greater than 1 must implement %@", NSStringFromSelector(_cmd));
	[self doesNotImplementSelector:_cmd];
	
	return 0;
}

- (NSUInteger)audioBufferSizeForBuffer:(NSUInteger)buffer
{
	// 4 frames is a complete guess
    double frameSampleCount = [self audioSampleRateForBuffer:buffer] / [self frameInterval];
    NSUInteger channelCount = [self channelCountForBuffer:buffer];
    NSUInteger bytesPerSample = [self audioBitDepth] / 8;
    NSAssert(frameSampleCount, @"frameSampleCount is 0");
    return channelCount*bytesPerSample * frameSampleCount;
}

- (double)audioSampleRateForBuffer:(NSUInteger)buffer
{
	if(buffer == 0)
	{
		return [self audioSampleRate];
	}
	
    DLog(@"Buffer count is greater than 1, must implement %@", NSStringFromSelector(_cmd));
    [self doesNotImplementSelector:_cmd];
    return 0;
}

- (OERingBuffer *)ringBufferAtIndex:(NSUInteger)index
{
	if (ringBuffers[index] == nil)
	{
        ringBuffers[index] = [[OERingBuffer alloc] initWithLength:[self audioBufferSizeForBuffer:index] * 16];
	}
	
    return ringBuffers[index];
}

#pragma mark - Save States

- (BOOL)autoSaveState
{
    NSString *autoSavePath = [[self saveStatesPath] stringByAppendingPathComponent:@"auto.svs"];
    BOOL saveResult = [self saveStateToFileAtPath:autoSavePath];
    if ( saveResult )
    {
        [self syncCloudFile:[[self romMD5] stringByAppendingPathExtension:@"svs"] toURL:[NSURL fileURLWithPath:autoSavePath]];
    }
    return saveResult;
}

- (BOOL)saveStateToFileAtPath:(NSString *)path
{
	[self doesNotImplementSelector:_cmd];
	return NO;
}

- (BOOL)loadStateFromFileAtPath:(NSString *)path
{
	[self doesNotImplementSelector:_cmd];
	return NO;
}

- (void)loadSaveFile:(NSString *)path forType:(int)type
{
	[self doesNotImplementSelector:_cmd];
}

- (void)writeSaveFile:(NSString *)path forType:(int)type
{
	[self doesNotImplementSelector:_cmd];
}

- (void)syncCloudFile:(NSString *)filename toURL:(NSURL *)fileURL
{
    NSLog( @"Syncing cloud file: %@", filename );
    
    bool fileExists = [fileURL checkResourceIsReachableAndReturnError:NULL];
    NSDate* fileDate = NULL;
    if ( fileExists )
    {
        NSLog( @"File exists." );
        [fileURL getResourceValue:&fileDate forKey:NSURLContentModificationDateKey error:NULL];
    }
    else
    {
        NSLog( @"File does not exist." );
    }
    
    if ( fileDate != NULL )
    {
        NSLog( @"File date: %@", fileDate );
    }
    
    NSString* containerIdentifier = [[[CKContainer defaultContainer] containerIdentifier] stringByReplacingOccurrencesOfString:@"provenancetv" withString:@"provenance"];
    CKDatabase* privateCloudDatabase = [[CKContainer containerWithIdentifier:containerIdentifier] privateCloudDatabase];
    CKRecordID* saveRecordID = [[CKRecordID alloc] initWithRecordName:filename];
    
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter( group );
    
    [privateCloudDatabase fetchRecordWithID:saveRecordID completionHandler:^(CKRecord * _Nullable record, NSError * _Nullable error)
    {
        bool iCloudRecordIsNewer = false;
        bool iCloudRecordIsOlder = true;
        if ( error == NULL && record != NULL )
        {
            NSLog( @"Successfully retrieved cloud save." );
            NSDate* recordDate = record[@"date"];
            NSLog( @"Record Date: %@", recordDate );
            if ( fileDate == NULL || [recordDate compare:fileDate] == NSOrderedDescending )
            {
                NSLog( @"iCloud record is newer." );
                iCloudRecordIsNewer = true;
                iCloudRecordIsOlder = false;
                CKAsset* asset = record[@"asset"];
                [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
                [[NSFileManager defaultManager] copyItemAtURL:[asset fileURL] toURL:fileURL error:NULL];
            }
            else if ( fileDate != NULL && [recordDate compare:fileDate] == NSOrderedSame )
            {
                iCloudRecordIsOlder = false;
            }
            else
            {
                NSLog( @"Record date: %@", recordDate );
            }
        }
        else if ( error != NULL )
        {
            NSLog( @"Error retrieving cloud save: %@", error.localizedDescription );
        }
        
        if ( iCloudRecordIsOlder && fileDate != NULL && fileExists )
        {
            NSLog( @"Uploading cloud save." );
            record = [[CKRecord alloc] initWithRecordType:@"CloudSave" recordID:saveRecordID];
            record[@"date"] = fileDate;
            record[@"asset"] = [[CKAsset alloc] initWithFileURL:fileURL];
            CKModifyRecordsOperation* modifyRecordsOperation = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:[NSArray arrayWithObject:record] recordIDsToDelete:nil];
            modifyRecordsOperation.savePolicy = CKRecordSaveAllKeys;
            modifyRecordsOperation.qualityOfService = NSQualityOfServiceUserInitiated;
            modifyRecordsOperation.modifyRecordsCompletionBlock = ^(NSArray<CKRecord *> * _Nullable savedRecords, NSArray<CKRecordID *> * _Nullable deletedRecordIDs, NSError * _Nullable operationError)
            {
                if ( operationError != NULL )
                {
                    NSLog( @"Error while uploading cloud save: %@", operationError.localizedDescription );
                }
                dispatch_group_leave( group );
            };
            [privateCloudDatabase addOperation:modifyRecordsOperation];
        }
        else
        {
            dispatch_group_leave( group );
        }
    }];
    
    dispatch_group_wait( group, DISPATCH_TIME_FOREVER );
}

@end

// Private CoreGraphics virtual display API (same one BetterDisplay / DeskPad use).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class CGVirtualDisplay;

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) unsigned int hiDPI;
@property (nonatomic, copy) NSArray<CGVirtualDisplayMode *> *modes;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) NSUInteger maxPixelsWide;
@property (nonatomic) NSUInteger maxPixelsHigh;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings NS_SWIFT_NAME(applySettings(_:));
@property (readonly, nonatomic) CGDirectDisplayID displayID;
@end

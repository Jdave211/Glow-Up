#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.glowup.app";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "welcomebg1" asset catalog image resource.
static NSString * const ACImageNameWelcomebg1 AC_SWIFT_PRIVATE = @"welcomebg1";

/// The "welcomebg2" asset catalog image resource.
static NSString * const ACImageNameWelcomebg2 AC_SWIFT_PRIVATE = @"welcomebg2";

/// The "welcomebg3" asset catalog image resource.
static NSString * const ACImageNameWelcomebg3 AC_SWIFT_PRIVATE = @"welcomebg3";

#undef AC_SWIFT_PRIVATE

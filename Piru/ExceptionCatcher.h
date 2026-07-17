#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, converting any Objective-C `NSException` it raises into a
/// returned `NSError` so Swift can handle it — Swift's `do/catch` cannot catch
/// ObjC exceptions, only Swift `Error`s, so a raised `NSException` would
/// otherwise reach `std::terminate` and crash the process.
///
/// Returns `YES` if `block` ran to completion, `NO` if it raised (in which case
/// `outError`, when non-NULL, is populated in the `PiruObjCException` domain
/// with the exception name as the code-adjacent info and its reason as the
/// localized description).
///
/// `block` is non-escaping and runs synchronously, so it may capture and mutate
/// local state exactly like an inline call.
BOOL PiruCatchNSException(void (NS_NOESCAPE ^block)(void),
                          NSError *_Nullable *_Nullable outError);

NS_ASSUME_NONNULL_END

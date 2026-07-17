#import "ExceptionCatcher.h"

BOOL PiruCatchNSException(void (NS_NOESCAPE ^block)(void),
                          NSError *_Nullable *_Nullable outError) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outError != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            if (exception.reason != nil) {
                info[NSLocalizedDescriptionKey] = exception.reason;
            }
            if (exception.name != nil) {
                info[@"PiruExceptionName"] = exception.name;
            }
            if (exception.userInfo != nil) {
                info[@"PiruExceptionUserInfo"] = exception.userInfo;
            }
            *outError = [NSError errorWithDomain:@"PiruObjCException"
                                            code:0
                                        userInfo:info];
        }
        return NO;
    }
}

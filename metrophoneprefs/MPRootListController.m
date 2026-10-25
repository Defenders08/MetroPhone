#import "MPRootListController.h"
#import "../MetroPhoneCommon.h"

@implementation MPRootListController

- (id)specifiers {
	if (_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

// Кнопка перезапуска: новые обои/плитки в SpringBoard применяются только после respring
- (void)respring {
	// пауза, чтобы Preferences успел записать настройки
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		system("/usr/bin/killall SpringBoard");
	});
}

@end

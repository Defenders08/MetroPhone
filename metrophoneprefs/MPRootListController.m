#import "MPRootListController.h"
#import "../MetroPhoneCommon.h"

@implementation MPRootListController

// Имя страницы для крупной шапки WP: ставим до того, как контроллер начнёт
// появляться (стилизация идёт в viewWillAppear базового класса)
- (void)viewWillAppear:(BOOL)animated {
	if (self.title.length == 0) self.title = @"MetroPhone";
	[super viewWillAppear:animated];
}

- (id)specifiers {
	if (_specifiers == nil) {
		// Крупная шапка WP берёт имя страницы из title; без этого она
		// показывает имя приложения («настройки») вместо «metrophone»
		if (self.title.length == 0) self.title = @"MetroPhone";
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

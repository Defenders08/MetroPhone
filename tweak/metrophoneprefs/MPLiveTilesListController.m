#import "MPLiveTilesListController.h"
#import "MPLiveTileSizeView.h"

@implementation MPLiveTilesListController

- (id)specifiers {
	if (_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"LiveTiles" target:self];
	}
	return _specifiers;
}

// Таблица PSListController собирается лениво — футер с размерами ставим в viewDidAppear
// (тот же приём, что и сетка цветов в MPColorsListController)
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	UITableView *t = [self table];
	if (t == nil) return;
	if (![t.tableFooterView isKindOfClass:[MPLiveTileSizeView class]]) {
		CGFloat w = t.bounds.size.width;
		if (w < 100.0f) w = 320.0f;
		MPLiveTileSizeView *sizeView = [[MPLiveTileSizeView alloc]
			initWithFrame:CGRectMake(0.0f, 0.0f, w, [MPLiveTileSizeView heightForWidth:w])];
		t.tableFooterView = sizeView;
	}
	[(MPLiveTileSizeView *)t.tableFooterView refreshValues];
}

@end

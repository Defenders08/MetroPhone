#import "MPColorsListController.h"

@implementation MPColorsListController

- (id)specifiers {
	if (_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Colors" target:self];
	}
	return _specifiers;
}

// Таблица PSListController собирается лениво (к viewDidAppear она точно есть) —
// ставим сетку как tableFooterView; reloadData её не сбрасывает
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];   // общий хук темы оформит шапку и навбар
	UITableView *t = [self table];
	if (t == nil) return;
	if (![t.tableFooterView isKindOfClass:[MPColorsGridView class]]) {
		CGFloat w = t.bounds.size.width;
		if (w < 100.0f) w = 320.0f;
		MPColorsGridView *grid = [[MPColorsGridView alloc]
			initWithFrame:CGRectMake(0.0f, 0.0f, w, [MPColorsGridView heightForWidth:w])];
		t.tableFooterView = grid;
	}
}

@end

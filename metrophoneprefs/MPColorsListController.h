// MPColorsListController — страница «цвета» в стиле WP 8.1: большая шапка
// ставится общими хуками темы (эта страница — обычный PSListController),
// сетка цветов добавляется как tableFooterView (прокручивается вместе со списком).

#import <Preferences/PSListController.h>
#import "MPColorsGridView.h"

@interface MPColorsListController : PSListController
@end

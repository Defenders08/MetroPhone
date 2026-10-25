#import <UIKit/UIKit.h>

// Страница списка (страница 1 paging-скролла): поиск + алфавитный список приложений.
@interface MPAppListPageView : UIView

@property (nonatomic, assign) CGFloat topInset;                 // отступ под статус-бар
@property (nonatomic, readonly) UIButton *iOSButton;            // кнопка «iOS» — action вешает MPHomeController

- (void)reloadApps:(NSArray *)apps;     // NSArray<MPAppEntry *>, уже отсортирован по имени
- (void)applyStyle;                     // перечитать акцентный цвет
- (void)dismissKeyboard;

@end

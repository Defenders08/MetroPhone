#import <UIKit/UIKit.h>

// Свитчер многозадачности в стиле WP8.1: акцентный фон на весь экран,
// карточка приложения по центру (снимок экрана), соседние карточки
// выглядывают по краям, под карточкой — иконка и имя приложения.
//
// Управление:
//   касание карточки  — переход в приложение (onActivateBlock);
//   свайп карточки вниз — закрытие приложения (onCloseBlock);
//   кнопка Home       — выход из свитчера (обрабатывает Tweak.xm).
//
// Приватных API SpringBoard класс не использует: список запущенных
// приложений приходит снаружи (Tweak.xm читает SBApplicationController),
// иконки и имена — из MPAppDataSource.
@interface MPMultitaskView : UIView

@property (nonatomic, copy) void (^onActivateBlock)(NSString *bundleID);
@property (nonatomic, copy) void (^onCloseBlock)(NSString *bundleID);

// Живой снимок приложения, если кэшированного нет (например, карточка
// приложения на переднем плане). Вызывается при сборке карточки; может
// вернуть nil — тогда рисуется заглушка с иконкой.
@property (nonatomic, copy) UIImage *(^livePreviewBlock)(NSString *bundleID);

- (void)openAnimated:(BOOL)animated withAppIDs:(NSArray *)appIDs;
- (void)closeAnimated:(BOOL)animated;
- (BOOL)isOpen;

@end

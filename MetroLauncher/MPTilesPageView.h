#import <UIKit/UIKit.h>

// Страница плиток (страница 0 paging-скролла): сетка 4 колонки, вертикальный скролл,
// тап = запуск, долгое нажатие (0.6 с) = режим правки (MPTileEditor).
@interface MPTilesPageView : UIView

@property (nonatomic, assign) CGFloat topInset;   // отступ под статус-бар

// Вызывается, когда меняется режим правки — контроллер блокирует/разблокирует paging.
@property (nonatomic, copy) void (^editingChangedBlock)(BOOL editing);

// Ленивая загрузка раскладки и сборка плиток (пачками, чтобы не блокировать главный поток).
- (void)ensureLoadedWithApps:(NSArray *)apps;
- (BOOL)isLoaded;
- (BOOL)isEditing;

// Новый список приложений / бейджи. Раскладку не пересоздаёт: новые приложения — в конец (small).
- (void)syncWithApps:(NSArray *)apps;

- (void)applyStyle;               // перечитать цвета (плитки, кнопка «Готово»)
- (void)exitEditingIfNeeded;      // выйти из правки с сохранением (например, при скрытии лаунчера)

@end

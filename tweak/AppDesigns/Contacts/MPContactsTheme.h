// MPContactsTheme — метрики и цвета переоформления «Контактов»
// (com.apple.MobileAddressBook) в WP-pivot. Геометрия едина с «Часами» и
// «Календарём»: шапка 96, строка действий на 96, контент с 146.

#import <UIKit/UIKit.h>

// Геометрия pivot — единая с «Часами»/«Календарём»
#define MPConLead         16.0f   // левое поле: заголовки, действия, контент
#define MPConStride       320.0f  // вкладка = весь экран
#define MPConHeaderH      96.0f   // шапка: light 52 на y=24
#define MPConActionsH     30.0f   // строка действий на y=96
#define MPConHeaderBottom 126.0f  // низ шапки (96+30)
#define MPConTopGap       20.0f   // зазор кнопки → контент
#define MPConHeaderGap    24.0f   // зазор между заголовками в ленте
#define MPConActionsGap   14.0f   // шаг кнопок в строке действий
#define MPConActionsTop   90.0f   // строка действий пивота: topInset+90 (юзер поднял к вкладкам)
#define MPConPivotTag     0x4D50436F   // 'MPCo' — маркер нашей вьюхи

// Страницы-списки
#define MPConSearchH      33.0f   // поиск: прозрачный бокс, белая рамка 1px (мокап юзера)
#define MPConSearchBorder 1.0f    // рамка бокса поиска
#define MPConSectionH     36.0f   // заголовок-буква секции
#define MPConRowH         56.0f   // строка контакта: канон проекта (light 24 на y+7)
#define MPConDetailRowH   56.0f   // строка поля на экране контакта

@interface MPContactsTheme : NSObject

// Kill-switch: ключ contactsRestyle (домен ru.ash.metrophone), по умолчанию YES
+ (BOOL)restyleEnabled;

// Палитра «Настроек» (та же лестница, что в «Часах»/«Календаре»)
+ (UIColor *)mutedColor;          // белый 0.6 — подписи, метки полей
+ (UIColor *)faintColor;          // белый 0.26 — неактивные заголовки pivot
+ (UIColor *)disabledColor;       // белый 0.40 — выключенное
+ (UIColor *)placeholderColor;    // белый 0.30 — плейсхолдер поиска

// Плоская текстовая кнопка-действие шапки: белый light 24 (или свой кегль)
+ (UIButton *)actionButtonWithTitle:(NSString *)title;
+ (UIButton *)actionButtonWithTitle:(NSString *)title size:(CGFloat)size;

// Крупная текстовая кнопка (акцент/вторичная muted): light 24
+ (UIButton *)bigTextAction:(NSString *)title secondary:(BOOL)secondary;

@end

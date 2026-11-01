// MPClockTheme — метрики и цвета переоформления «Часов» (com.apple.mobiletimer)
// в WP-pivot. Все размеры сняты с утверждённого HTML-прототипа
// (ai/MetroPhone-часы-pivot.html, 4 итерации правок 29.10.2026, экран 320×480).

#import <UIKit/UIKit.h>

// Геометрия pivot — в системе дизайна «Настроек»: шапка 96 от верха окна
// (текст light 52 с ужатием на y=24, как MPSettingsHeaderView), строка действий
// 24 на y=96 (как перенесённые бар-кнопки), поля 16, плоские списки без
// разделителей. «Коробок» нет: действия — текст (акцент/приглушённый)
#define MPClockLead       16.0f   // левое поле: заголовки, действия, контент страниц
#define MPClockStride     320.0f  // вкладка = весь экран: соседняя не выглядывает
#define MPClockHeaderH    96.0f   // шапка: текст на y=24 в полосе 66 (как Настройки)
#define MPClockActionsH   30.0f   // строка действий ВНУТРИ страницы (кегль 24 требует ~29)
#define MPClockListTop    38.0f   // список мировой/будильников: строка кнопок (30) + зазор 8
#define MPClockHeaderBottom 126.0f // ИСТОРИЧЕСКОЕ (полоса действий в шапке убрана)
#define MPClockTopGap     20.0f   // зазор кнопки→первая строка (ужан по просьбе юзера)
#define MPClockHeaderGap  24.0f   // зазор между заголовками в ленте
#define MPClockActionsGap 14.0f   // шаг бар-кнопок в Настройках (+14)
#define MPClockPivotTag   0x4D50434B   // 'MPCk' — маркер нашей вьюхи в дереве

@interface MPClockTheme : NSObject

// Kill-switch: ключ clockRestyle (домен ru.ash.metrophone), по умолчанию YES
+ (BOOL)restyleEnabled;

// Палитра «Настроек»: подписи/значения 0.6, выключенный пункт 0.4,
// плейсхолдер 0.3, опасное действие — красный палитры (сохраняется)
+ (UIColor *)mutedColor;          // белый 0.6 — подписи, значения, заголовки секций
+ (UIColor *)faintColor;          // белый 0.26 — неактивные заголовки pivot
+ (UIColor *)disabledColor;       // белый 0.40 — выключенное время будильника
+ (UIColor *)placeholderColor;    // белый 0.30 — плейсхолдер поля имени
+ (UIColor *)dangerColor;         // палитра red (#E51400) — «удалить»

// Плоская текстовая кнопка-действие («изменить», «добавить»): light 16, белый
+ (UIButton *)actionButtonWithTitle:(NSString *)title;

// Крупная текстовая кнопка-действие (канон Настроек: «коробок нет», действие —
// акцентный текст): light 24, при нажатии приглушается. secondary=YES — muted
+ (UIButton *)bigTextAction:(NSString *)title secondary:(BOOL)secondary;

@end

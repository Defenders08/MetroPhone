# ЗАДАЧА: основа Metro-лаунчера для твика MetroPhone (iOS 6)

> **АРХИВ.** Это исходное ТЗ на UI-слой лаунчера (версия твика 0.2.x). Часть решений
> с тех пор изменена осознанно: лаунчер создаётся не из `applicationDidFinishLaunching:`,
> а через 60 с после старта SpringBoard; кнопки «Готово» нет (выход из правки — тап
> по фону); сетка плиток без внешних полей; добавлены свитчер многозадачности и
> переоформление «Настроек». Актуальное описание — в README.md.

Ты пишешь UI-слой Metro-лаунчера (стиль Windows Phone) для существующего Theos-твика **MetroPhone**, который живёт внутри SpringBoard на **iOS 6.1.3 (iPhone 4, armv7)**. Лаунчер — полноэкранная вьюха поверх родного рабочего стола: **Metro — основной стол** (появляется сам после разблокировки), со свайпом влево к алфавитному списку всех приложений.

Ты делаешь **только UI-слой** на публичных API iOS 6 против фиксированного контракта данных. Всё, что касается приватных API SpringBoard, уже написано и входит в этот промпт **готовым кодом** — вставляй как есть, не изменяй и не добавляй своих обращений к приватным классам, кроме тех, что явно есть в этом документе.

Работаешь в существующем проекте `/Users/ash/Documents/Проекты/MetroPhone`. Весь код и комментарии — на русском.

---

## 1. Контекст проекта

Проект уже содержит рабочий твик (версия 0.1.9): чёрный фон вместо обоев, плоские тёмные панели, подписи иконок в стиле WP, квадратные плитки-иконки, панель настроек. Твик стабильно живёт на устройстве — **не ломай то, что работает** (см. раздел «Запрещено»).

Сборка проверяется так (из папки проекта):

```bash
export THEOS="$HOME/theos"
make clean && make package FINALPACKAGE=1
```

Пакет должен собираться без ошибок. Существующие Makefile/control/plist менять не нужно, кроме **одной строки** в Makefile (см. раздел 6).

---

## 2. ЖЕЛЕЗНЫЕ ПРАВИЛА (нарушение = неработающий телефон)

Эти правила — результат реальной отладки на устройстве. SpringBoard убивается вотчдогом/jetsam при малейшем «жирном» коде на старте.

1. **В `%ctor` и `%hook`-конструкторах запрещены вызовы UIKit**: `UIFont`, `UIAppearance`, `UIGraphicsBeginImageContext`, создание вьюх. В `%ctor` допустимы только: `%init`, `CFPreferences`, `MPLog`, `dispatch_*`, `objc_*`. Иначе — дедлок главного потока, чёрный экран, сейфмод.
2. **Любая работа с UIKit — после запуска SpringBoard**: из `applicationDidFinishLaunching:` или позже. Вьюхи и шрифты создаются лениво, при первом показе.
3. **Главный поток после старта нельзя блокировать дольше ~100 мс**. Декодирование иконок — только в фоне, на **серийной** очереди (не конкурентной! 45 параллельных декодирований убивают SpringBoard по памяти), с `@autoreleasepool` внутри блока.
4. **Шрифты только через кэширующий хелпер** (код в разделе 5.7). Прямой `[UIFont fontWithName:]` без кэша — не использовать.
5. **Паттерн Logos**: `%orig;` — всегда отдельным оператором или последним оператором метода. Конструкция `{ %orig; return; }` **запрещена** — препроцессор ломается.
6. **Логирование**: в каждом входе (ctor, show/hide, редактирование, сохранение) вызывай готовый `MPLog` (объявление в разделе 5.8; реализация уже в Tweak.xm — просто объявляй `extern`-прототип или дублируй объявление `static void MPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);` **не реализуя** — реализация одна на бинарь недопустима: статические функции дублировать можно только с уникальными именами, поэтому **объяви и используй только NSLog** с префиксом `[MetroPhone][Launcher]`, если MPLog недоступен. Проще: используй `NSLog` везде в своих файлах.)
7. **Таргет iOS 6.0**: никаких API новее. Auto Layout не использовать — только вычисление фреймов вручную. `UICollectionView` не использовать (на A4 непредсказуем) — сетка плиток собирается вручную из UIView.
8. ARC включён (`-fobjc-arc` уже в Makefile). `weak` использовать осторожно (iOS 6 поддерживает), `unsafe_unretained` для делегатов не нужен.

---

## 3. Контракт данных (ГОТОВЫЙ КОД — вставить как есть, не изменять)

### 3.1 `MetroLauncher/MPAppDataSource.h`

```objc
#import <UIKit/UIKit.h>

// Одна запись приложения (папки не включаются — только приложения и web-клипы)
@interface MPAppEntry : NSObject
@property (nonatomic, copy)   NSString *bundleID;
@property (nonatomic, copy)   NSString *displayName;  // как есть, БЕЗ смены регистра
@property (nonatomic, assign) NSInteger badge;         // 0 = нет бейджа
@end

@interface MPAppDataSource : NSObject
+ (MPAppDataSource *)sharedDataSource;

// Быстрый список (без иконок — иконки грузятся лениво). Сортировка по displayName.
- (NSArray *)allApps;                                  // NSArray<MPAppEntry *>
- (MPAppEntry *)appWithBundleID:(NSString *)bundleID;

// Иконка декодируется в фоне и кэшируется; completion может прийти на любом потоке.
- (void)iconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion;

- (void)launchAppWithBundleID:(NSString *)bundleID;    // запуск приложения
@end

// Уведомление «список/бейджи изменились» (постится из хуков твика)
extern NSString * const MPAppsChangedNotification;
```

### 3.2 `MetroLauncher/MPAppDataSource.m`

```objc
#import "MPAppDataSource.h"
#import <objc/runtime.h>

NSString * const MPAppsChangedNotification = @"MPAppsChanged";

// ---- Приватные классы SpringBoard iOS 6.1 (сверены с дампом MP0w/iOS-Headers) ----
@interface SBIconController : NSObject
+ (id)sharedInstance;
- (id)model;
@end
@interface SBIconModel : NSObject
- (NSDictionary *)leafIconsByIdentifier;   // все листовые иконки (приложения + web-клипы)
@end
@interface SBIcon : NSObject
- (void)launch;                            // запуск приложения
- (int)badgeValue;
- (id)displayName;
- (NSString *)applicationBundleID;
- (id)application;                         // SBApplication (только у SBApplicationIcon)
@end
@interface SBApplication : NSObject
- (NSString *)path;                        // путь к .app бандлу
@end

// ---- Исходный квадратный PNG иконки из бандла (в iOS 6 иконки в бандлах — квадраты) ----
static NSCache *MPDsPngCache = nil;

static UIImage *MPDsIconForBundlePath(NSString *bundlePath) {
    if (bundlePath.length == 0) return nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ MPDsPngCache = [[NSCache alloc] init]; });

    id cached = [MPDsPngCache objectForKey:bundlePath];
    if (cached != nil) return [cached isKindOfClass:[UIImage class]] ? cached : nil;

    UIImage *best = nil;
    @autoreleasepool {
        NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
        if (info != nil) {
            NSMutableDictionary *candidates = [NSMutableDictionary dictionary];
            void (^consider)(NSString *) = ^(NSString *p) {
                if (p.length == 0 || [candidates objectForKey:p] != nil) return;
                if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                    UIImage *img = [UIImage imageWithContentsOfFile:p];
                    if (img != nil) [candidates setObject:img forKey:p];
                }
            };
            NSArray *iconFiles = nil;
            NSDictionary *primary = [info objectForKey:@"CFBundleIcons"][@"CFBundlePrimaryIcon"];
            if (primary != nil) iconFiles = [primary objectForKey:@"CFBundleIconFiles"];
            if (iconFiles == nil) iconFiles = [info objectForKey:@"CFBundleIconFiles"];
            NSMutableArray *names = [NSMutableArray arrayWithArray:iconFiles ?: @[]];
            NSString *legacy = [info objectForKey:@"CFBundleIconFile"];
            if (legacy != nil) [names addObject:legacy];
            for (NSString *name in names) {
                consider([bundlePath stringByAppendingPathComponent:name]);
                consider([bundlePath stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]]);
                consider([bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x.png", name]]);
                consider([bundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@@2x", name]]);
            }
            CGFloat bestPx = 0;
            for (UIImage *img in candidates.allValues) {
                CGFloat px = img.size.width * img.scale;
                if (px > bestPx) { bestPx = px; best = img; }
            }
        }
    }
    [MPDsPngCache setObject:(best ?: (id)[NSNull null]) forKey:bundlePath];
    return best;
}

static NSArray *MPDsCollectApps(void) {
    NSMutableArray *result = [NSMutableArray array];
    @try {
        id controller = [objc_getClass("SBIconController") sharedInstance];
        id model = [controller respondsToSelector:@selector(model)] ? [controller model] : nil;
        NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
            ? [model leafIconsByIdentifier] : nil;
        for (id icon in leafs.allValues) {
            if (![icon respondsToSelector:@selector(applicationBundleID)]) continue; // папки пропускаются
            NSString *bid = [icon applicationBundleID];
            if (bid.length == 0) continue;
            MPAppEntry *e = [[MPAppEntry alloc] init];
            e.bundleID = bid;
            e.displayName = ([icon respondsToSelector:@selector(displayName)] && [icon displayName])
                ? [icon displayName] : bid;
            e.badge = [icon respondsToSelector:@selector(badgeValue)] ? [icon badgeValue] : 0;
            [result addObject:e];
        }
    } @catch (NSException *ex) {
        NSLog(@"[MetroPhone][DataSource] сборка списка: %@ (%@)", ex.name, ex.reason);
    }
    [result sortUsingComparator:^(MPAppEntry *a, MPAppEntry *b) {
        return [a.displayName compare:b.displayName options:NSCaseInsensitiveSearch];
    }];
    return result;
}

static id MPDsFindIcon(NSString *bundleID) {
    id controller = [objc_getClass("SBIconController") sharedInstance];
    id model = [controller respondsToSelector:@selector(model)] ? [controller model] : nil;
    NSDictionary *leafs = [model respondsToSelector:@selector(leafIconsByIdentifier)]
        ? [model leafIconsByIdentifier] : nil;
    for (id icon in leafs.allValues) {
        if ([[icon applicationBundleID] isEqualToString:bundleID]) return icon;
    }
    return nil;
}

@implementation MPAppEntry
@end

@implementation MPAppDataSource

+ (MPAppDataSource *)sharedDataSource {
    static MPAppDataSource *ds = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ds = [[MPAppDataSource alloc] init]; });
    return ds;
}

- (NSArray *)allApps {
    return MPDsCollectApps();
}

- (MPAppEntry *)appWithBundleID:(NSString *)bundleID {
    for (MPAppEntry *e in [self allApps]) {
        if ([e.bundleID isEqualToString:bundleID]) return e;
    }
    return nil;
}

- (void)iconForEntry:(MPAppEntry *)entry completion:(void (^)(UIImage *icon))completion {
    if (entry == nil || completion == NULL) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            UIImage *icon = nil;
            @try {
                id sbIcon = MPDsFindIcon(entry.bundleID);
                id app = ([sbIcon respondsToSelector:@selector(application)]) ? [sbIcon application] : nil;
                NSString *path = ([app respondsToSelector:@selector(path)]) ? [app path] : nil;
                icon = MPDsIconForBundlePath(path);
            } @catch (NSException *ex) {
                NSLog(@"[MetroPhone][DataSource] иконка %@: %@", entry.bundleID, ex);
            }
            completion(icon); // nil = рисуй заглушку (первая буква имени)
        }
    });
}

- (void)launchAppWithBundleID:(NSString *)bundleID {
    @try {
        id icon = MPDsFindIcon(bundleID);
        if ([icon respondsToSelector:@selector(launch)]) [icon launch];
    } @catch (NSException *ex) {
        NSLog(@"[MetroPhone][DataSource] запуск %@: %@", bundleID, ex);
    }
}

@end
```

---

## 4. Спецификация UI

### 4.1 Контроллер `MPHomeController`

- Полноэкранный UIViewController (320×480 на этом устройстве; бери `[UIScreen mainScreen].applicationFrame`).
- Корневая вью: чёрный фон; внутри — paging-скролл (`UIScrollView`, `pagingEnabled`, без индикаторов), две страницы шириной экрана: **страница 0 — плитки**, **страница 1 — список приложений**.
- Методы жизненного цикла (вызываются из интеграционного кода, раздел 6):

```objc
- (void)installLauncherView;         // добавить self.view в SBScreenView (код дан в 6.2)
- (void)showMetroAnimated:(BOOL)a;   // показать + bringToFront; скрыть, если [SBAwayController isLocked]
- (void)hideMetroAnimated:(BOOL)a;   // спрятать (родной стол виден)
- (BOOL)isMetroVisible;
```

- Показ лаунчера: анимация только простым fade (alpha 0→1, 0.25 c) — никаких сложных анимаций. Учёт блокировки экрана (isLocked) делает интеграционный колбэк из раздела 6.2 — внутри `MPHomeController` приватные API не трогаются.
- На `MPAppsChangedNotification` — перечитать `allApps`, обновить список; **раскладку не пересоздавать**, новые приложения дописать в конец как small.

### 4.2 Страница плиток `MPTilesPageView`

- **Сетка**: 4 колонки; отступы по краям и между плитками 6 pt; единица сетки `U = (ширина − 5·6) / 4` (на 320 pt это ≈ 72 pt). Маленькая плитка = U×U, большая = (2U+6)×(2U+6).
- **Упаковка**: тайлы раскладываются в порядке `order` (из модели раскладки), поточно-колоночно сверху вниз: маленькая занимает 1×1 клетки, большая 2×2; упаковка без дыр (простой алгоритм «первое подходящее место»).
- **Вертикальный скролл** всей страницы (вложенный в paging-скролл — обычная связка, работает на iOS 6).
- **Вид плитки `MPTileView`**: фон плитки — очень тёмно-серый `[UIColor colorWithWhite:0.12 alpha:1]`, либо акцентный цвет, если в настройках `tileStyle == 1` (ключи настроек — раздел 5.6). Иконка приложения по центру, ширина 55 % от плитки; подпись ЗАГЛАВНЫМИ снизу, `HelveticaNeue-Light` 11 pt, белый цвет. Иконка загружается через `iconForEntry:completion:` (до прихода — заглушка: квадрат с первой буквой имени). Бейдж — красный кружок (`#E51400`) с белой цифрой в правом верхнем углу плитки.
- **Тап по плитке** → `[MPAppDataSource launchAppWithBundleID:]`.
- **Долгое нажатие (0.6 с)** → режим редактирования (см. 4.3).

### 4.3 Режим редактирования `MPTileEditor`

Вход: долгое нажатие на плитку. Выход: кнопка **«Готово»** (верх страницы, появляется только в режиме правки).

В режиме правки:
- плитки слегка «дрожат» (попеременный поворот ±1° через CABasicAnimation на transform);
- **перетаскивание**: палец двигает плитку (масштаб 1.1, полупрозрачность 0.8), при отпускании — вставка на позицию ближайшей плитки, остальные сдвигаются (перезапаковка);
- **одиночный тап по плитке** в режиме правки переключает размер small ↔ large (если большая не влезает — остаётся small);
- сохранение раскладки в plist — при нажатии «Готово» (формат в разделе 5);
- никаких запусков приложений в режиме правки.

Требование к стабильности: перетаскивание реализуется касаниями (`touchesBegan/Moved/Ended`) на уровне страницы, без UICollectionView и без UIKit-dragDrop.

### 4.4 Страница списка `MPAppListPageView`

- Сверху поле поиска: `UITextField` (тёмный фон `[UIColor colorWithWhite:0.15 alpha:1]`, белый текст, placeholder «поиск», ЗАГЛАВНЫЕ буквы не обязательны), высота 36 pt, отступ 6 pt.
- Ниже — `UITableView` (plain, чёрный фон): секции по первой букве displayName (ЗАГЛАВНАЯ), заголовок секции — акцентный цвет, `HelveticaNeue-Thin` 20 pt; строки: иконка 29×29 (или заглушка), имя `HelveticaNeue-Regular` 15 pt белым, бейдж справа красным кружком. Высота строки 44 pt.
- Поиск фильтрует строки по вхождению подстроки (case-insensitive) «на лету».
- **Тап по строке** → запуск приложения.
- **Кнопка «iOS»** (маленькая, правый верх списка, акцентный цвет) → `[self hideMetroAnimated:YES]` — возвращает родной стол.

### 4.5 Кнопка возврата в Metro

На родном столе (делается в интеграционном коде, раздел 6.2) — маленькая кнопка «M» (24×24, акцентный цвет, полупрозрачная, правый верхний угол) → `[showMetroAnimated:YES]`.

---

## 5. Модель раскладки и настройки

### 5.1 Файл раскладки

`/var/mobile/Library/Preferences/metrophone-layout.plist`, формат:

```xml
<dict>
  <key>tiles</key>
  <array>
    <dict><key>bid</key><string>com.apple.mobilesafari</string><key>size</key><string>large</string></dict>
    <dict><key>bid</key><string>com.apple.mobilephone</string><key>size</key><string>small</string></dict>
    ...
  </array>
</dict>
```

`order` — порядковый элемент массива. Приложения, которых нет в файле, дописываются в конец (small, по алфавиту). Файл пишется по «Готово», читается при первом показе страницы плиток (лениво, не в ctor!).

### 5.2 Настройки темы (читаются через CFPreferences, домен `ru.ash.metrophone`)

Ключи уже существуют (панель настроек твика): `enabled`, `accent` (строка: blue/purple/magenta/green/lime/orange/red/teal), `tileStyle` (0 = тёмные плитки, 1 = акцентные). Палитра для акцента: blue #1BA1E2, purple #A200FF, magenta #D80073, green #008A00, lime #A4C400, orange #F09609, red #E51400, teal #00ABA9.

### 5.3 Единая точка стиля `MPMetroStyle`

Класс с классовыми методами: `+ (UIColor *)accentColor;`, `+ (UIColor *)tileColor;`, `+ (UIFont *)thinFont:(CGFloat)size; lightFont: regularFont: mediumFont:` (HelveticaNeue-Thin/Light/Regular/Medium, кэшируются, fallback `[UIFont systemFontOfSize:]`), `+ (CGFloat)unitSize;` и константы отступов.

---

## 6. Интеграция (точки соединения с существующим Tweak.xm)

### 6.1 Makefile — заменить строку FILES на:

```make
MetroPhone_FILES = Tweak.xm MetroLauncher/MPAppDataSource.m MetroLauncher/MPHomeController.m MetroLauncher/MPTilesPageView.m MetroLauncher/MPTileView.m MetroLauncher/MPLayoutModel.m MetroLauncher/MPTileEditor.m MetroLauncher/MPAppListPageView.m MetroLauncher/MPMetroStyle.m
```

### 6.2 Код в конец Tweak.xm (перед `%ctor`; **именно этот код**, ничего больше в Tweak.xm не менять):

```objc
#pragma mark - Metro-лаунчер

#import "MetroLauncher/MPHomeController.h"

static MPHomeController *MPLauncher = nil;

static UIView *MPFindScreenView(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        for (UIView *v in w.subviews) {
            if ([NSStringFromClass([v class]) isEqualToString:@"SBScreenView"]) return v;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

@interface SBAwayController : NSObject
+ (id)sharedAwayController;
- (BOOL)isLocked;
@end

static void MPLockStateChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (MPLauncher == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL locked = [[objc_getClass("SBAwayController") sharedAwayController] isLocked];
        if (locked) [MPLauncher hideMetroAnimated:NO];
        else [MPLauncher showMetroAnimated:NO];
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)notification {
	%orig;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (MPLauncher != nil) return;
		MPLauncher = [[MPHomeController alloc] init];
		[MPLauncher installLauncherView];
		[MPLauncher showMetroAnimated:NO];
	});
}
%end
```

Кнопку «M» на родном столе делает сам `MPHomeController` методом `- (void)addMetroToggleButtonToView:(UIView *)nativeView;` (маленькая полупрозрачная «M» 24×24 в правом верхнем углу, тап → showMetro; добавляется один раз, при showMetro скрывается, при hideMetro — показывается). Кнопку «iOS» в списке — тоже `MPHomeController`.

Обработчик darwin-уведомления блокировки регистрируется в `%ctor` (добавь в конец `%ctor`):

```objc
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
		&MPLockStateChanged, CFSTR("com.apple.springboard.lockstate"), NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately);
```

И хук изменения бейджей (рядом с другими хуками SpringBoard):

```objc
%hook SBIcon
- (void)noteBadgeDidChange {
	%orig;
	[[NSNotificationCenter defaultCenter] postNotificationName:MPAppsChangedNotification object:nil];
}
%end
```

---

## 7. Файлы, которые ты создаёшь

```
MetroLauncher/
├── MPAppDataSource.h/.m      — контракт данных (раздел 3, без изменений)
├── MPHomeController.h/.m     — контейнер, 2 страницы, show/hide/install, кнопки M и iOS
├── MPTilesPageView.h/.m      — страница плиток: упаковка, скролл, тапы, долгое нажатие
├── MPTileView.h/.m           — плитка: фон, иконка, подпись, бейдж
├── MPLayoutModel.h/.m        — модель раскладки, чтение/запись plist, упаковка «первое подходящее место»
├── MPTileEditor.h/.m         — режим редактирования: drag, resize, дрожание
├── MPAppListPageView.h/.m    — алфавитный список + поиск
└── MPMetroStyle.h/.m         — акценты, шрифты (кэш), метрики сетки
```

---

## 8. Критерии приёмки

1. `make clean && make package FINALPACKAGE=1` собирается без ошибок (допустимы только существующие предупреждения линкера про tbd).
2. Твик ставится на устройство, **холодная загрузка SpringBoard проходит без зависаний и сейфмода** — стартовое окно не нагружено (всё лениво, после разблокировки).
3. Чек-лист на устройстве: после разблокировки виден Metro-стол; свайп влево — список приложений; поиск фильтрует; тап запускает приложение; долгое нажатие — режим правки; перетаскивание и смена размера работают; «Готово» сохраняет; respring восстанавливает раскладку; бейджи обновляются; кнопка «iOS» показывает родной стол; «M» возвращает в Metro; при блокировке лаунчер прячется (виден экран блокировки).
4. В консоли устройства нет `[MetroPhone][Launcher]`-ошибок.

## 9. Запрещено

- Менять `MPAppDataSource`, существующие хуки темы (`%group MPUikit`, `%group MPSpringBoard`), Makefile (кроме строки FILES), control, plists фильтров.
- Добавлять фреймворки, зависимости, UICollectionView, Auto Layout, API новее iOS 6.0, SwiftUI/Storyboard/xib — только код.
- Звать приватные классы SpringBoard вне `MPAppDataSource.m` и интеграционного кода раздела 6.2.
- Делать какую-либо работу с UIKit в `%ctor`.
- Использовать `{ %orig; return; }` в любых хуках.

Если какое-то требование невозможно выполнить — остановись и опиши проблему, не выдумывай обходные пути с приватными API.

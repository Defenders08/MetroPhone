// MPSettingsHooks — переоформление «Настроек» (com.apple.Preferences) в стиль WP 8.1.
// Принцип: оригинал отработал (%orig) → мы подкрасили. Логика, спецификаторы,
// навигация и контроллы не трогаются — только внешний вид созданных объектов.
//
// Селекторы сверены с дампом iOS 6.1 (MP0w/iOS-Headers, PrivateFrameworks/Preferences):
// PSListController: viewDidLoad, viewWillAppear:, tableView:cellForRowAtIndexPath:,
//                   tableView:heightForRowAtIndexPath:, viewForHeaderInSection: и др.
// PSTableCell: titleLabel, valueLabel, specifier, initWithStyle:reuseIdentifier:specifier:,
//              refreshCellContentsWithSpecifier:, layoutSubviews.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../MetroLauncher/MPMetroStyle.h"
#import "MPSettingsTheme.h"
#import "MPSettingsHeaderView.h"
#import "MPSettingsToggle.h"
#import "MPSettingsCellStyler.h"

static NSString * const MPSettingsHeaderKey = @"mp_settings_header";

// Ставится лениво из cellForRow, когда впервые встретилась кастомная ячейка
// с собственным layoutSubviews (APTableCell в Wi-Fi/Bluetooth).
void MPSettingsInstallCustomCellHooksIfNeeded(UITableViewCell *cell);

// Приватные классы (объявления для ARC, реализации — системные)
@interface PSListController : UIViewController
- (id)table;
@end

// iOS 5+: UINavigationItem умеет красить свой заголовок (категория — метода нет в SDK 10.3)
@interface UINavigationItem (MPSettingsTitle)
- (void)setTitleTextAttributes:(NSDictionary *)attributes;
@end

@interface PSTableCell : UITableViewCell
- (UILabel *)titleLabel;
- (UILabel *)valueLabel;
@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Вспомогательные

// Шапка, прикреплённая к таблице этого контроллера (или nil)
static MPSettingsHeaderView *MPAttachedHeader(UITableView *table) {
    if (![table.tableHeaderView isKindOfClass:[MPSettingsHeaderView class]]) return nil;
    return (MPSettingsHeaderView *)table.tableHeaderView;
}

// Локализованное имя приложения «Настройки» из бандла процесса
static NSString *MPSettingsDisplayName(void) {
    static NSString *name = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *info = [[NSBundle mainBundle] localizedInfoDictionary];
        NSDictionary *plain = [[NSBundle mainBundle] infoDictionary];
        name = [info objectForKey:@"CFBundleDisplayName"] ?: [plain objectForKey:@"CFBundleDisplayName"];
        if (name == nil) name = @"Настройки";
    });
    return name;
}

static void *MPLastTitleKey = &MPLastTitleKey;

// Определена ниже (после высот заголовков секций); объявлена заранее — её зовёт
// MPApplyPageStyle, который идёт раньше по тексту файла.
static void MPNormalizeTopGap(UITableView *table, UIViewController *controller);
static void MPClampSectionLabels(UITableView *table);

// Привязать/обновить шапку на таблице контроллера
static void MPInstallOrUpdateHeader(UIViewController *controller, UITableView *table) {
    if (table == nil) return;
    if (table.tableHeaderView != nil && ![table.tableHeaderView isKindOfClass:[MPSettingsHeaderView class]]) {
        return;                                     // у страницы есть свой заголовок — не трогаем
    }

    MPSettingsHeaderView *header = MPAttachedHeader(table);
    if (header == nil) {
        header = [[MPSettingsHeaderView alloc] initWithFrame:
            CGRectMake(0.0f, 0.0f, table.bounds.size.width, [MPSettingsHeaderView heightForWidth:table.bounds.size.width])];
        table.tableHeaderView = header;
    }
    // WP: заголовок подстраницы — «Wi-Fi», «Основные»… Источник: controller.title
    // (его выставляет PSListController) → navigationItem.title → запомненное имя.
    // Раньше первым шёл navigationItem.title, который тут же гасился: на переиспользованном
    // контроллере («Напоминания») шапка показывала «заметки» (вопрос 3B).
    NSString *page = controller.title;
    if (page.length == 0) page = controller.navigationItem.title;
    if (page.length == 0) page = objc_getAssociatedObject(controller, MPLastTitleKey);
    if (page.length == 0) page = MPSettingsDisplayName();
    if (page.length > 0) {
        objc_setAssociatedObject(controller, MPLastTitleKey, page, OBJC_ASSOCIATION_RETAIN);
    }
    // Заголовок навбара гасим, чтобы не дублировал шапку. Раньше это ломало
    // повторный вход (шапка брала имя оттуда); теперь имя уже взято из controller.title,
    // поэтому обнуление безопасно.
    if (controller.navigationItem.title.length > 0) {
        controller.navigationItem.title = @"";
    }
    header.pageTitle = page;
    [header setNeedsLayout];
}

// Плоский вид таблицы: чёрный фон, без карточек и разделителей
static void MPStyleTable(UITableView *table) {
    if (table == nil) return;
    table.backgroundColor = [UIColor blackColor];
    table.backgroundView = nil;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.separatorColor = nil;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Смена акцента (живое обновление)

// Страница «Цвета» (бандл настроек) пишет accentHex и постит Darwin-уведомление;
// здесь перечитываем настройки и помечаем всё видимое к перелayoutу.
static void MPMarkLayoutDirty(UIView *v) {
    [v setNeedsLayout];
    for (UIView *sub in v.subviews) MPMarkLayoutDirty(sub);
}

static void MPAccentChangedCallback(CFNotificationCenterRef center, void *observer,
                                    CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [MPMetroStyle reloadPreferences];
        [MPSettingsTheme reapplyAccentAppearance];
        for (UIWindow *w in [UIApplication sharedApplication].windows) MPMarkLayoutDirty(w);
    });
}

//──────────────────────────────────────────────────────────────────────────────
// Полный стайлинг страницы (таблица, шапка, навбар, кнопка «Назад»).
// Вызывается из viewDidLoad/viewWillAppear/viewDidAppear/reloadSpecifiers/reload:
// PSListController создаёт таблицу ЛЕНИВО (после дозагрузки спецификаторов),
// поэтому одного viewDidLoad мало — часть разделов оставалась штатной.
static BOOL MPStyleInProgress = NO;   // защита от повторного входа (дедлок в UIKit-блокировках)

// Флаг «отложенный повтор уже запланирован» на контроллере. Раньше повтор
// планировался заново после КАЖДОГО прохода — получалась бесконечная цепочка
// dispatch_after каждые 0.35 с, пока страница открыта (постоянная нагрузка на
// главный поток, на iPhone 4 — до вылета). Теперь повтор живёт один раз на
// «появление» страницы: флаг сбрасывается в viewWillAppear/viewDidAppear и
// перед вызовом из reloadData.
static void *MPReapplyScheduledKey = &MPReapplyScheduledKey;

static void MPArmReapply(UIViewController *controller) {
    objc_setAssociatedObject(controller, MPReapplyScheduledKey, @NO, OBJC_ASSOCIATION_RETAIN);
}

// Верхняя страница — страница ТВИКА? (класс контроллера из /Library/PreferenceBundles)
// Кэш по имени класса: страницы твиков не трогаем вообще — ни ячейки, ни секции.

static void MPApplyPageStyle(UIViewController *controller, UITableView *table) {
    if (MPStyleInProgress) return;      // вложенный вызов (изнутри reloadData) — выходим
    if (![MPSettingsTheme restyleEnabled]) return;

    // Стилизуем ТОЛЬКО системные страницы Настроек. Признак — ОТКУДА загружен класс:
    // системные контроллеры (включая подклассы Wi-Fi и др.) живут в /System/,
    // контроллеры твиков — в /Library/PreferenceBundles/. Твикам возвращаем штатный вид.
    // Исключение по классу (CyDown) ИЛИ по заголовку (Auxo и др. без класса)
    NSString *pageT = controller.navigationItem.title ?: controller.title;
    if ([MPSettingsTheme isControllerExcluded:controller] ||
        [MPSettingsTheme isTitleExcluded:pageT]) {
        // Исключённая страница: глобальный UIAppearance (прозрачный заголовок,
        // белые кнопки) делает белую страницу БЕЗ видимого выхода — возвращаем
        // навбару штатный вид iOS: тёмный заголовок, системный tint кнопок
        @try {
            [MPSettingsTheme resetBarButtonAppearance];   // кнопкам твика — родной вид
            UINavigationController *nav = controller.navigationController;
            UINavigationBar *bar = (nav != nil) ? nav.navigationBar : nil;
            if (bar != nil) {
                [bar setTitleTextAttributes:@{
                    UITextAttributeFont: [UIFont boldSystemFontOfSize:20.0f],
                    UITextAttributeTextColor: [UIColor darkTextColor],
                    UITextAttributeTextShadowColor: [UIColor clearColor],
                }];
                bar.tintColor = nil;               // системный tint кнопок
                bar.hidden = NO;
            }
            controller.navigationItem.hidesBackButton = NO;
        } @catch (NSException *e) {
            NSLog(@"[MetroPhone][Settings] excluded: %@ (%@)", e.name, e.reason);
        }
        return;
    }

    if (table != nil && table.numberOfSections == 0 && table.tableHeaderView == nil) {
        return;   // спецификаторы ещё грузятся — придём с reloadData
    }

    MPStyleInProgress = YES;
    @try {
        MPStyleTable(table);
        MPInstallOrUpdateHeader(controller, table);
        [MPSettingsTheme applyFlatBarButtonAppearance];   // «Изменить»/«Готово» — без глянца

        UINavigationController *nav = controller.navigationController;
        // В корневом меню иконок нет; на внутренних страницах показываем глифы
        MPSettingsIconsHidden = (nav == nil || nav.viewControllers.count <= 1);
        // есть ли на странице хоть одна иконка — от этого зависит левый край текста
        MPSettingsPageHasIcons = NO;
        @try {
            NSArray *all = [controller valueForKey:@"specifiers"];
            for (id sp in all) {
                if ([sp respondsToSelector:NSSelectorFromString(@"propertyForKey:")]) {
                    id (*sendObj)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
                    id icon = sendObj(sp, NSSelectorFromString(@"propertyForKey:"), @"icon");
                    if ([icon isKindOfClass:[NSString class]] && [(NSString *)icon length] > 0) {
                        MPSettingsPageHasIcons = YES;
                        break;
                    }
                }
            }
        } @catch (NSException *e) { MPSettingsPageHasIcons = NO; }
        NSString *pageTitle = [(controller.title ?: @"") lowercaseString];
        MPSettingsPageIsSounds = ([pageTitle rangeOfString:@"звук"].location != NSNotFound);
        [MPSettingsTheme styleNavigationBar:controller.navigationController.navigationBar];
        [MPSettingsTheme styleWindows];

        // WP 8.1: верхнего бара нет — контент под статус-баром. С кнопками бар остаётся.
        // Кнопки бывают и ЛЕВЫЕ (Done/назад у страниц твиков) — их тоже учитываем,
        // иначе навбар прятался вместе с единственной кнопкой выхода
        UINavigationItem *visibleItem = (nav != nil) ? nav.visibleViewController.navigationItem : nil;
        // «Назад» — в шапке; nav bar нужен ТОЛЬКО для явных кнопок («Готово», «Правка»)
        BOOL hasBarButtons = (nav != nil && nav.topViewController == controller &&
                              (visibleItem.rightBarButtonItems.count > 0 ||
                               visibleItem.leftBarButtonItems.count > 0));
        if (nav != nil) {
            nav.navigationBar.hidden = !hasBarButtons;
            // 1B: контейнер навигации уже начинается с 20 pt (под статус-баром).
            // Раньше таблице ставили ещё +20 — первый ряд уезжал вниз на 20 pt.
            CGFloat top = hasBarButtons ? 44.0f : 0.0f;
            if (table.superview != nil) {
                table.frame = CGRectMake(0.0f, top, table.superview.bounds.size.width,
                                         table.superview.bounds.size.height - top);
            } else {
                table.frame = CGRectMake(0.0f, top, table.bounds.size.width, table.bounds.size.height);
            }
        }

        BOOL hasHeader = [table.tableHeaderView isKindOfClass:[MPSettingsHeaderView class]];
        if (hasHeader) MPNormalizeTopGap(table, controller);
        MPClampSectionLabels(table);

        // Куда возвращаться: push в стеке ИЛИ модальное представление
        // (страницы настроек твиков часто открываются модально со своим стеком,
        // где контроллер ПЕРВЫЙ — раньше шеврон не ставился, а системная кнопка
        // пряталась: назад пропадал совсем)
        BOOL canPop = (nav != nil && nav.viewControllers.count > 1 &&
                       [nav.viewControllers firstObject] != controller);
        // модальность: сам контроллер ИЛИ его nav-стек представлен модально
        // (в момент viewWillAppear presentingViewController бывает ещё nil —
        // поэтому ниже есть отложенный повторный проход)
        BOOL isModal = (controller.presentingViewController != nil ||
                        (nav != nil && nav.presentingViewController != nil));

        if (hasHeader && (canPop || isModal)) {
            controller.navigationItem.hidesBackButton = YES;
            MPSettingsHeaderView *header = (MPSettingsHeaderView *)table.tableHeaderView;
            header.showsBackChevron = YES;
            __weak UIViewController *weakC = controller;
            header.backTapped = ^{
                if (canPop) {
                    [nav popViewControllerAnimated:YES];
                } else if (nav != nil && nav.presentingViewController != nil) {
                    [nav dismissViewControllerAnimated:YES completion:nil];
                } else if ([controller respondsToSelector:@selector(dismissViewControllerAnimated:completion:)]) {
                    [controller dismissViewControllerAnimated:YES completion:nil];
                }
                // раньше здесь был exit(0), если pop/dismiss не сработали, —
                // приложение молча умирало без всяких логов. Теперь просто
                // остаёмся на странице: никаких принудительных убийств.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
                        UIViewController *c = weakC;
                        if (c != nil && c.isViewLoaded && c.view.window != nil) {
                            MPLog(@"[Settings] назад не сработал — остаёмся на странице");
                        }
                    });
            };
        } else if (visibleItem.leftBarButtonItems.count > 0 ||
                   visibleItem.rightBarButtonItems.count > 0) {
            // вернуться есть чем, но без нашего шеврона — системной кнопке жить можно
            controller.navigationItem.hidesBackButton = NO;
            if (hasHeader) {
                MPSettingsHeaderView *header = (MPSettingsHeaderView *)table.tableHeaderView;
                header.showsBackChevron = NO;
                header.backTapped = nil;
            }
            if (nav != nil) nav.navigationBar.hidden = NO;
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] стиль страницы: %@ (%@)", e.name, e.reason);
    } @finally {
        MPStyleInProgress = NO;
    }

    // повторный проход: модальный present и title страницы твика дозревают позже.
    // Планируется ОДИН раз на появление страницы (флаг MPReapplyScheduledKey),
    // а не после каждого прохода — иначе цепочка живёт, пока страница открыта.
    NSNumber *scheduled = objc_getAssociatedObject(controller, MPReapplyScheduledKey);
    if (scheduled != nil && scheduled.boolValue) return;
    objc_setAssociatedObject(controller, MPReapplyScheduledKey, @YES, OBJC_ASSOCIATION_RETAIN);

    __weak UIViewController *weakC = controller;
    __weak UITableView *weakT = table;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            UIViewController *c = weakC;
            UITableView *t = weakT;
            if (c == nil || t == nil) return;
            if (t.dataSource != (id<UITableViewDataSource>)c &&
                ![c respondsToSelector:@selector(table)]) return;
            MPApplyPageStyle(c, t);
        });
}

//──────────────────────────────────────────────────────────────────────────────
%group MPSettings

%hook PSListController

- (void)viewDidLoad {
    %orig;
    [MPSettingsTheme setupAppearanceOnce];      // лениво, один раз, после запуска приложения
    // ВНИМАНИЕ: в viewDidLoad таблицы ещё нет (спецификаторы грузятся лениво) —
    // ранний вызов MPApplyPageStyle валил Настройки в белый экран
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    MPArmReapply(self);     // на это появление — один отложенный повтор
    MPApplyPageStyle(self, [self table]);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // к этому моменту таблица точно создана (ленивая сборка спецификаторов завершена);
    // здесь же переподхватываются страницы, собранные после viewWillAppear
    MPArmReapply(self);
    MPApplyPageStyle(self, [self table]);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    @try {
        // возвращаем заголовок навбара (следующая страница может быть без нашей шапки)
        UINavigationBar *bar = self.navigationController.navigationBar;
        if (bar != nil) {
            [bar setTitleTextAttributes:@{
                UITextAttributeFont: [MPMetroStyle thinFont:22.0f],
                UITextAttributeTextColor: [UIColor whiteColor],
                UITextAttributeTextShadowColor: [UIColor clearColor],
            }];
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] viewWillDisappear: %@ (%@)", e.name, e.reason);
    }
}

- (id)tableView:(id)tableView cellForRowAtIndexPath:(id)indexPath {
    UITableViewCell *cell = %orig;
    if (![MPSettingsTheme restyleEnabled]) return cell;

    if ([MPSettingsTheme debugEnabled]) {
        NSLog(@"[MetroPhone][Settings] ячейка: %@", NSStringFromClass([cell class]));
    }
    if ([cell isKindOfClass:[UITableViewCell class]]) {    // PSTableCell — его подкласс
        [MPSettingsCellStyler stylePSTableCell:cell];
    }
    // Кастомные ячейки (Wi-Fi/Bluetooth: APTableCell) переопределяют layoutSubviews
    // и не зовут super — наш общий хук на UITableViewCell их не видит. Вешаем хук
    // точечно на такой класс при первой встрече (один раз на процесс).
    MPSettingsInstallCustomCellHooksIfNeeded(cell);
    // У кастомных ячеек layout идёт ПОСЛЕ cellForRow и возвращает свои кадры —
    // просим переразметиться, чтобы наш хук (выше) применил стиль последним
    if (NSClassFromString(@"PSTableCell") != Nil &&
        ![cell isKindOfClass:NSClassFromString(@"PSTableCell")]) {
        [cell setNeedsLayout];
    }
    // Кастомные ячейки списков (Wi-Fi/VPN): лейблы белым, диски-кнопки квадратными.
    // Официальный момент UIKit для стилизации — безопасно (не во время layout).
    [MPSettingsCellStyler styleCellDeep:cell];
    return cell;
}

- (float)tableView:(id)tableView heightForRowAtIndexPath:(id)indexPath {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    // единая высота строки (56): и с подзаголовком, и без — по ТЗ допускается
    return (h > 1.0f) ? 56.0f : h;
}

static NSString *MPPlainHeaderText(NSString *t) {
    // 40B: системные заголовки приходят с двоеточием («Сортировать программы:»),
    // в WP подписи групп его не несут.
    if (t.length > 0 && [t hasSuffix:@":"]) return [t substringToIndex:t.length - 1];
    return t;
}

static void MPClampSectionLabels(UITableView *table) {
    // 31B: системные заголовки групп приходят шириной 320 при x=16 (вылет 336).
    // Нашу собственную вьюху правит MPStyleHeaderLabelDeep, но есть пути, где
    // метка создаётся позже/другим классом — добиваем по факту перед показом.
    if (table == nil) return;
    @try {
        for (UIView *v in table.subviews) {
            if ([v isKindOfClass:[UITableViewCell class]]) continue;
            if (CGRectGetHeight(v.frame) > 60.0f) continue;      // шапка страницы
            for (UIView *s in v.subviews) {
                if (![s isKindOfClass:[UILabel class]]) continue;
                UILabel *l = (UILabel *)s;
                CGRect f = l.frame;
                CGFloat maxW = table.bounds.size.width - f.origin.x - 16.0f;
                if (maxW > 40.0f && f.size.width > maxW + 0.5f) {
                    f.size.width = maxW;
                    l.frame = f;
                }
            }
        }
    } @catch (NSException *e) {
        // не критично: останется системная ширина
    }
}

static void MPStyleHeaderLabelDeep(UIView *v) {
    // iOS 6: секционные заголовки могут быть UITableViewHeaderFooterView
    if ([v isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UILabel *l = ((UITableViewHeaderFooterView *)v).textLabel;
        if (l != nil) {
            l.font = [MPMetroStyle lightFont:17.0f];
            l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
            l.backgroundColor = [UIColor clearColor];
            l.shadowColor = nil;
            l.shadowOffset = CGSizeZero;
        }
    }
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        l.text = MPPlainHeaderText(l.text);
        l.font = [MPMetroStyle lightFont:17.0f];
        l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];   // серые, поменьше
        l.backgroundColor = [UIColor clearColor];
        l.shadowColor = nil;
        l.shadowOffset = CGSizeZero;
        // выравнивание: метка — на 16 pt от края экрана (родной iOS ставит ~20,
        // из-за чего заголовки съезжали вправо относительно строк)
        UIView *host = l.superview;
        if (host != nil && host.bounds.size.width > 60.0f) {
            CGRect f = l.frame;
            CGFloat targetX = 16.0f - host.frame.origin.x;
            if (targetX < 2.0f) targetX = 2.0f;
            if (fabsf(f.origin.x - targetX) > 0.5f && f.origin.x >= 0.0f && f.origin.x < 40.0f) {
                f.size.width += (f.origin.x - targetX);
                f.origin.x = targetX;
                if (f.size.width > 60.0f) l.frame = f;
            }
            // Ширину не даём вылезать за экран: у родных заголовков она бывает
            // равна всей ширине таблицы (320), а метка стоит на 16 pt правее
            CGRect cf = l.frame;
            CGFloat maxW = host.bounds.size.width - cf.origin.x - 16.0f;
            if (maxW > 40.0f && cf.size.width > maxW + 0.5f) {
                cf.size.width = maxW;
                l.frame = cf;
            }
        }
    }
    for (UIView *sub in v.subviews) MPStyleHeaderLabelDeep(sub);
}

- (id)tableView:(id)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *v = %orig;
    if (![MPSettingsTheme restyleEnabled]) return v;
    @try {
        // PSListController для текстовых заголовков отдаёт nil — iOS рисует
        // штатную тень; создаём свою плоскую акцентную метку
        if (v == nil) {
            NSString *t = nil;
            if ([self respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) {
                t = [(id)self tableView:tableView titleForHeaderInSection:section];
            }
            if (t.length > 0) {
                CGFloat tw = ((UITableView *)tableView).bounds.size.width;
                UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tw, 28.0f)];
                wrap.backgroundColor = [UIColor blackColor];
                wrap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                UILabel *l = [[UILabel alloc] initWithFrame:
                              CGRectMake(16.0f, 3.0f, tw - 32.0f, 22.0f)];
                l.text = MPPlainHeaderText(t);
                l.font = [MPMetroStyle lightFont:17.0f];
                l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
                l.backgroundColor = [UIColor blackColor];
                l.shadowColor = nil;
                l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [wrap addSubview:l];
                return wrap;
            }
            return v;
        }
        MPStyleHeaderLabelDeep(v);
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] header: %@ (%@)", e.name, e.reason);
    }
    return v;
}

- (float)tableView:(id)tableView heightForFooterInSection:(NSInteger)section {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    NSString *t = nil;
    @try {
        if ([self respondsToSelector:@selector(tableView:titleForFooterInSection:)]) {
            t = [(id)self tableView:tableView titleForFooterInSection:section];
        }
    } @catch (NSException *e) { t = nil; }
    if (t.length == 0) return 8.0f;            // 28B/38B: пустые футеры — 8 pt
    // 35B: высота по реальному тексту, а не по «38 знакам в строке» —иначе
    // кириллица обрезалась «…», а латиница получала лишние строки.
    CGFloat w = ((UITableView *)tableView).bounds.size.width - 32.0f;
    UIFont *f = [MPMetroStyle regularFont:13.0f];
    CGSize sz = [t sizeWithFont:f constrainedToSize:CGSizeMake(w, CGFLOAT_MAX)
                  lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(sz.height) + 16.0f;           // 8 сверху + 8 снизу
}

- (float)tableView:(id)tableView heightForHeaderInSection:(NSInteger)section {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    // растягиваем только секции с настоящим заголовком; пустые (отступы групп) — минимальные
    NSString *title = nil;
    @try {
        if ([self respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) {
            title = [(id)self tableView:tableView titleForHeaderInSection:section];
        }
    } @catch (NSException *e) { title = nil; }
    BOOL hasTitle = (title != nil && title.length > 0);
    if (section == 0) return hasTitle ? 28.0f : 16.0f;
    return hasTitle ? 28.0f : 16.0f;           // 38B: пустые — 16 pt
}

// 1B: единый зазор под шапкой. Высота заголовка секции у разных контроллеров
// «Настроек» разная (10/17/28), поэтому зазор выравниваем inset'ом по факту:
// считаем, где реально начинается первая строка, и добиваем до 30 pt.
static void MPNormalizeTopGap(UITableView *table, UIViewController *controller) {
    if (table == nil || table.numberOfSections == 0) return;
    if ([table numberOfRowsInSection:0] == 0) return;
    @try {
        // если у первой группы есть подпись — она сама занимает место, не трогаем
        NSString *t = nil;
        if ([controller respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) {
            t = [(id)controller tableView:table titleForHeaderInSection:0];
        }
        if (t.length > 0) { table.contentInset = UIEdgeInsetsZero; return; }
        CGRect first = [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        CGFloat headerH = [MPSettingsHeaderView heightForWidth:table.bounds.size.width];
        CGFloat gap = first.origin.y - headerH;
        CGFloat delta = 30.0f - gap;
        if (fabsf(delta) < 0.5f) return;
        if (delta < -60.0f) delta = -60.0f;
        if (delta > 60.0f) delta = 60.0f;
        table.contentInset = UIEdgeInsetsMake(delta, 0.0f, 0.0f, 0.0f);
    } @catch (NSException *e) {
        // не критично: остаётся системный отступ
    }
}

static void MPStyleFooterLabelDeep(UIView *v) {
    if ([v isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UILabel *l = ((UITableViewHeaderFooterView *)v).textLabel;
        if (l != nil) {
            l.font = [MPMetroStyle regularFont:12.0f];
            l.textColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
            l.backgroundColor = [UIColor clearColor];
            l.shadowColor = nil;
            l.shadowOffset = CGSizeZero;
        }
    }
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        l.font = [MPMetroStyle regularFont:13.0f];                 // 42B
        l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
        l.backgroundColor = [UIColor clearColor];
        l.shadowColor = nil;
        l.shadowOffset = CGSizeZero;
        // футерам — та же геометрия 16 pt, что и заголовкам секций
        UIView *host = l.superview;
        if (host != nil && host.bounds.size.width > 60.0f) {
            CGRect f = l.frame;
            CGFloat targetX = 16.0f - host.frame.origin.x;
            if (targetX < 2.0f) targetX = 2.0f;
            if (fabsf(f.origin.x - targetX) > 0.5f && f.origin.x >= 0.0f && f.origin.x < 40.0f) {
                f.size.width += (f.origin.x - targetX);
                f.origin.x = targetX;
                if (f.size.width > 60.0f) l.frame = f;
            }
            // Ширину не даём вылезать за экран: у родных заголовков она бывает
            // равна всей ширине таблицы (320), а метка стоит на 16 pt правее
            CGRect cf = l.frame;
            CGFloat maxW = host.bounds.size.width - cf.origin.x - 16.0f;
            if (maxW > 40.0f && cf.size.width > maxW + 0.5f) {
                cf.size.width = maxW;
                l.frame = cf;
            }
        }
    }
    for (UIView *sub in v.subviews) MPStyleFooterLabelDeep(sub);
}

- (id)tableView:(id)tableView viewForFooterInSection:(NSInteger)section {
    UIView *v = %orig;
    if (![MPSettingsTheme restyleEnabled]) return v;
    @try {
        if (v != nil) {
            MPStyleFooterLabelDeep(v);
        } else {
            // текстовый футер: iOS рисует серым по центру с тенью — делаем плоским
            NSString *t = nil;
            if ([self respondsToSelector:@selector(tableView:titleForFooterInSection:)]) {
                t = [(id)self tableView:tableView titleForFooterInSection:section];
            }
            if (t.length > 0) {
                CGFloat tw = ((UITableView *)tableView).bounds.size.width;
                // 35B: та же формула, что в heightForFooterInSection:
                UIFont *ff = [MPMetroStyle regularFont:13.0f];
                CGSize sz = [t sizeWithFont:ff constrainedToSize:CGSizeMake(tw - 32.0f, CGFLOAT_MAX)
                              lineBreakMode:NSLineBreakByWordWrapping];
                CGFloat fh = ceilf(sz.height) + 16.0f;
                UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tw, fh)];
                wrap.backgroundColor = [UIColor blackColor];
                wrap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                UILabel *l = [[UILabel alloc] initWithFrame:
                              CGRectMake(16.0f, 8.0f, tw - 32.0f, fh - 12.0f)];
                l.text = t;
                l.font = ff;
                l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];   // 42B
                l.textAlignment = NSTextAlignmentLeft;
                l.numberOfLines = 0;
                l.backgroundColor = [UIColor blackColor];
                l.shadowColor = nil;
                l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [wrap addSubview:l];
                return wrap;
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] footer: %@ (%@)", e.name, e.reason);
    }
    return v;
}

%end

%hook PSTableCell

- (id)initWithStyle:(int)style reuseIdentifier:(id)reuseIdentifier specifier:(id)specifier {
    id cell = %orig;
    if ([MPSettingsTheme restyleEnabled] && cell != nil && YES) {
        [MPSettingsCellStyler stylePSTableCell:cell];
    }
    return cell;
}

- (void)refreshCellContentsWithSpecifier:(id)specifier {
    %orig;
    if ([MPSettingsTheme restyleEnabled] && YES) {
        [MPSettingsCellStyler stylePSTableCell:self];     // после обновления — перекраска
    }
}

- (void)layoutSubviews {
    %orig;
    if ([MPSettingsTheme restyleEnabled] && YES) {
        [MPSettingsCellStyler layoutPSTableCell:self];
    }
}

// «Парение» по-Zune: вместо подложки при нажатии подсвечивается сам текст
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    [MPSettingsCellStyler applyFloatingEffect:highlighted toCell:self];
}

// В grouped-таблице iOS 6 ячейки вставлены с отступом ~10 pt: растягиваем на всю ширину.
// Присвоение тех же значений второй раз безвредно (идемпотентно), рекурсии нет.
- (void)setFrame:(CGRect)frame {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    @try {
        UIView *sv = self.superview;
        if (sv == nil) return;
        CGFloat w = sv.bounds.size.width;
        if (self.frame.origin.x != 0.0f || fabsf(self.frame.size.width - w) > 0.5f) {
            self.frame = CGRectMake(0.0f, self.frame.origin.y, w, self.frame.size.height);
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] setFrame: %@ (%@)", e.name, e.reason);
    }
}

%end

// Таблица PSListController пересобирается ЛЕНИВО: setTable+/reloadData происходит
// ПОСЛЕ viewWillAppear/viewDidAppear — иначе часть разделов остаётся штатной
// и теряется кнопка «Назад». Стилизуем в момент перезагрузки таблицы.
%hook UITableView

- (void)reloadData {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    @try {
        id ds = self.dataSource;
        Class psList = objc_getClass("PSListController");   // класс из Preferences — не линкуем
        if (ds == nil || psList == nil || ![ds isKindOfClass:psList]) return;

        if (self.numberOfSections == 0) return;             // пустая — придём позже

        // Стилизация ИЗНУТРИ reloadData дедлочит (UIKit держит внутренние
        // блокировки таблицы) — откладываем на следующий проход ранлупа
        __weak UITableView *weakTable = self;
        __weak id weakDS = ds;
        dispatch_async(dispatch_get_main_queue(), ^{
            UITableView *t = weakTable;
            id d = weakDS;
            if (t == nil || d == nil) return;
            if (t.dataSource != d) return;                  // таблицу уже переподвесили
            MPArmReapply(d);                                // ленивая сборка — свой повтор
            MPApplyPageStyle(d, t);
        });
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] reloadData: %@ (%@)", e.name, e.reason);
    }
}

// Догоняющий проход для КАСТОМНЫХ ячеек (сети Wi-Fi, устройства Bluetooth):
// они создаются асинхронно, и система возвращает им системные цвета (синяя
// подключённая сеть, родной диск «›») уже ПОСЛЕ нашего cellForRowAtIndexPath.
// Работа переносится на следующий ранлуп (нельзя делать её внутри прохода
// лейаута) и выполняется не чаще 1 раза/с — идемпотентно и дёшево.
- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    @try {
        static CFAbsoluteTime last = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - last < 0.5) return;
        last = now;

        id ds = self.dataSource;
        Class psList = objc_getClass("PSListController");
        if (ds == nil || psList == nil || ![ds isKindOfClass:psList]) return;
        if ([MPSettingsTheme isControllerExcluded:ds]) return;
        NSString *pageT = nil;
        if ([ds respondsToSelector:@selector(navigationItem)]) {
            pageT = [(UIViewController *)ds navigationItem].title;
        }
        if ([MPSettingsTheme isTitleExcluded:pageT]) return;

        __weak UITableView *weakTable = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            UITableView *t = weakTable;
            if (t == nil) return;
            @try {
                NSMutableArray *custom = [NSMutableArray array];
                for (UITableViewCell *c in t.visibleCells) {
                    if (c == nil) continue;
                    if ([c isKindOfClass:NSClassFromString(@"PSTableCell")]) continue;
                    [custom addObject:NSStringFromClass([c class])];
                    [MPSettingsCellStyler styleCellDeep:c];
                }
                if (custom.count > 0) {
                    MPLog(@"[catchup] кастомных ячеек %u: %@", (unsigned)custom.count, custom);
                }
            } @catch (NSException *e) {
                NSLog(@"[MetroPhone][Settings] tableLayout: %@ (%@)", e.name, e.reason);
            }
        });
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] tableLayoutGate: %@ (%@)", e.name, e.reason);
    }
}

%end

// Универсальный слой: обычные UITableViewCell и кастомные подклассы (Wi-Fi, Bluetooth).
// Кастомные ячейки часто переопределяют layoutSubviews и не зовут super, поэтому
// оформляем их прямо здесь: цвет, отступ 16 pt, синие диски → акцентные.
%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    Class psClass = NSClassFromString(@"PSTableCell");
    if (psClass != Nil && [self isKindOfClass:psClass]) return;   // PS-ячейки оформлены выше
    [MPSettingsCellStyler styleGenericCell:self];
    [MPSettingsCellStyler styleCellDeep:self];
}

%end

// Синхронизация WP-тумблера с оригинальным свитчем (логика PS остаётся на свитче)
%hook UISwitch

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    %orig;
    @try {
        static char kToggleKey;
        MPSettingsToggle *t = objc_getAssociatedObject(self, &kToggleKey);
        if (t != nil) [t syncFromSwitch];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] toggle sync: %@ (%@)", e.name, e.reason);
    }
}

%end

// Поля ввода (пароль Wi-Fi, аккаунты): тёмная клавиатура, белый текст, плоское подчёркивание
// Ползунок: после родного layout растягиваем на всю ширину строки.
// Кадры из cellForRow/layoutPSTableCell система перезаписывает, а здесь мы
// уже последние в цепочке.
%hook UISlider

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    UIView *host = self.superview;
    if (host == nil || host.bounds.size.width < 100.0f) return;
    CGRect f = self.frame;
    if (f.size.width < 60.0f) return;                  // мелкие ползунки не трогаем
    CGFloat right = host.bounds.size.width - 16.0f;
    if (f.origin.x + f.size.width < right - 2.0f) {
        f.size.width = right - f.origin.x;
        self.frame = f;
    }
}

%end

%hook UITextField

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    static void *MPFieldStyledKey = &MPFieldStyledKey;
    if (objc_getAssociatedObject(self, MPFieldStyledKey) != nil) return;   // один раз на поле
    objc_setAssociatedObject(self, MPFieldStyledKey, @YES, OBJC_ASSOCIATION_RETAIN);
    [MPSettingsCellStyler styleTextField:self];
}

%end

%end // MPSettings

// Класс кастомной ячейки Wi-Fi/Bluetooth (iOS 6): объявляем как наследника
// UITableViewCell, иначе Logos типизирует self как NSObject и не даёт звать наш стиллер
@interface APTableCell : UITableViewCell
@end

// Ячейка устройства Bluetooth: свой layoutSubviews, синий текст и глянцевый диск
@interface BTTableCell : UITableViewCell
@end

//──────────────────────────────────────────────────────────────────────────────
// Кастомные ячейки Wi-Fi/Bluetooth (APTableCell): свой layoutSubviews.
// Ставим хук лениво — в момент, когда такая ячейка впервые появилась.
%group MPBTHooks
%hook BTTableCell
- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    [MPSettingsCellStyler layoutPSTableCell:self];
    [MPSettingsCellStyler styleCellDeep:self];
}
%end
%end // MPBTHooks

%group MPCustomCells

%hook APTableCell
- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    // после штатного лейаута: кадры заголовка и кастомных подписей (16 pt),
    // цвет, акцентные диски. layoutPSTableCell — потому что APTableCell наследует
    // PSTableCell, а свой layoutSubviews не зовёт super (наш общий хук мимо)
    [MPSettingsCellStyler layoutPSTableCell:self];
    [MPSettingsCellStyler styleGenericCell:self];
    [MPSettingsCellStyler styleCellDeep:self];
}
%end

%end // MPCustomCells

static BOOL MPCustomCellHooksInstalled = NO;

// Общий хук для ЛЮБОЙ кастомной ячейки «Настроек» (VPN, Twitter, App Store, Wi-Fi…):
// после родного layoutSubviews применяем наш стиль — тогда белый текст, отступ 16 pt
// и WP-стрелка появляются на всех страницах, а не по одной.
static NSMutableDictionary *MPCellOriginals = nil;

static void MPAnyCellLayout(id self, SEL _cmd) {
    NSValue *v = [MPCellOriginals objectForKey:NSStringFromClass([self class])];
    IMP orig = (v != nil) ? (IMP)[v pointerValue] : NULL;
    // orig == MPAnyCellLayout означает, что в словарь попал наш же хук (класс
    // получил унаследованный метод уже после подмены). Вызов себя — переполнение
    // стека и крэш «Настроек», поэтому такую запись игнорируем.
    if (orig != NULL && orig != (IMP)MPAnyCellLayout) ((void (*)(id, SEL))orig)(self, _cmd);
    if (![MPSettingsTheme restyleEnabled]) return;
    [MPSettingsCellStyler layoutPSTableCell:self];
    [MPSettingsCellStyler styleCellDeep:self];
}

static void MPHookCellClass(Class cls) {
    if (cls == Nil) return;
    NSString *name = NSStringFromClass(cls);
    if ([name isEqualToString:@"PSTableCell"] || [name isEqualToString:@"UITableViewCell"] ||
        [name isEqualToString:@"APTableCell"] || [name isEqualToString:@"BTTableCell"]) return;
    if (MPCellOriginals == nil) MPCellOriginals = [NSMutableDictionary dictionary];
    if ([MPCellOriginals objectForKey:name] != nil) return;

    Method m = class_getInstanceMethod(cls, @selector(layoutSubviews));
    if (m == NULL) return;
    IMP orig = method_getImplementation(m);

    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL own = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == @selector(layoutSubviews)) { own = YES; break; }
    }
    if (list != NULL) free(list);

    // Хук ставим ТОЛЬКО на класс, который объявляет layoutSubviews сам.
    // Если метод унаследован, его уже обрабатывает хук родителя (включая
    // %hook UITableViewCell). Копия на наследнике брала бы в качестве «оригинала»
    // наш же MPAnyCellLayout — отсюда была бесконечная рекурсия и крэш.
    if (!own) return;
    if (orig == (IMP)MPAnyCellLayout) return;      // повторное вешание — пропускаем
    [MPCellOriginals setObject:[NSValue valueWithPointer:(const void *)orig] forKey:name];
    method_setImplementation(m, (IMP)MPAnyCellLayout);
}

void MPSettingsInstallCustomCellHooksIfNeeded(UITableViewCell *cell) {
    if (cell == nil) return;
    NSString *cellClass = NSStringFromClass([cell class]);
    if ([cellClass isEqualToString:@"APTableCell"] || [cellClass isEqualToString:@"BTTableCell"]) {
        if (MPCustomCellHooksInstalled) return;
        MPCustomCellHooksInstalled = YES;
        @try {
            if ([cellClass isEqualToString:@"BTTableCell"]) %init(MPBTHooks); else %init(MPCustomCells);
        } @catch (NSException *e) {
            NSLog(@"[MetroPhone][Settings] хук %@: %@", cellClass, e.name);
        }
        return;
    }
    MPHookCellClass([cell class]);
}

//──────────────────────────────────────────────────────────────────────────────
// Рекурсивный поиск nav-контроллера в иерархии
static UINavigationController *MPFindNavController(UIViewController *root) {
    if (root == nil) return nil;
    if ([root isKindOfClass:[UINavigationController class]]) return (UINavigationController *)root;
    if (root.presentedViewController != nil) {
        UINavigationController *n = MPFindNavController(root.presentedViewController);
        if (n != nil) return n;
    }
    for (UIViewController *child in root.childViewControllers) {
        UINavigationController *n = MPFindNavController(child);
        if (n != nil) return n;
    }
    return nil;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Инициализация

// Вызывается из Tweak.xm (%ctor): хуки живут только в процессе «Настроек».
void MPSettingsInitIfNeeded(void) {
    @try {
        CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
        if (bid == nil || CFStringCompare(bid, CFSTR("com.apple.Preferences"), 0) != kCFCompareEqualTo) {
            return;                                        // чужой процесс — группа не активна
        }
        if (![MPSettingsTheme restyleEnabled]) {
            NSLog(@"[MetroPhone][Settings] kill-switch: перекраска выключена");
            return;
        }
        %init(MPSettings);

        // WP-стиль: Настройки всегда открываются с главной страницы.
        // iOS 6 восстанавливает последнюю посещённую — возвращаем в корень.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                static BOOL firstActivation = YES;
                if (firstActivation) {
                    firstActivation = NO;
                    return;   // первый запуск — уже в корне
                }
                @try {
                    UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
                    UINavigationController *nav = MPFindNavController(root);
                    if (nav != nil && nav.viewControllers.count > 1) {
                        [nav popToRootViewControllerAnimated:NO];
                        NSLog(@"[MetroPhone][Settings] активация: возврат в корень");
                    }
                } @catch (NSException *e) {
                    // молча
                }
            }];
        // сетка «Цвета» сигналит Darwin-уведомлением — слушаем, чтобы акцент
        // применялся без выхода из Настроек
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, &MPAccentChangedCallback,
                                        CFSTR("ru.ash.metrophone.accent-changed"),
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[MetroPhone][Settings] группа хуков установлена");
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] init: %@ (%@)", e.name, e.reason);
    }
}

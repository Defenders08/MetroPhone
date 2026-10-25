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
#import "../MetroLauncher/MPMetroStyle.h"
#import "MPSettingsTheme.h"
#import "MPSettingsHeaderView.h"
#import "MPSettingsToggle.h"
#import "MPSettingsCellStyler.h"

static NSString * const MPSettingsHeaderKey = @"mp_settings_header";

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
    // WP: заголовок подстраницы — «wi-fi», «основные»… Источник: navigationItem.title
    // (то, что раньше рисовал навбар) → controller.title → имя приложения.
    // Мы ГАСИМ navigationItem.title (чтобы навбар не дублировал), но помним
    // оригинал в associated object — иначе шапка остаётся пустой.
    NSString *page = controller.navigationItem.title;
    if (page.length == 0) page = controller.title;
    if (page.length == 0) page = objc_getAssociatedObject(controller, MPLastTitleKey);
    if (page.length == 0) page = MPSettingsDisplayName();
    if (page.length > 0 && ![page isEqualToString:MPSettingsDisplayName()]) {
        objc_setAssociatedObject(controller, MPLastTitleKey, page, OBJC_ASSOCIATION_RETAIN);
    }
    // гасим дублирующий заголовок навбара (текстовая модель — видимость чистая)
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
// Полный стайлинг страницы (таблица, шапка, навбар, кнопка «Назад»).
// Вызывается из viewDidLoad/viewWillAppear/viewDidAppear/reloadSpecifiers/reload:
// PSListController создаёт таблицу ЛЕНИВО (после дозагрузки спецификаторов),
// поэтому одного viewDidLoad мало — часть разделов оставалась штатной.
static void MPApplyPageStyle(UIViewController *controller, UITableView *table) {
    if (![MPSettingsTheme restyleEnabled]) return;
    if ([MPSettingsTheme isControllerExcluded:controller]) return;

    @try {
        MPStyleTable(table);
        MPInstallOrUpdateHeader(controller, table);

        UINavigationController *nav = controller.navigationController;
        [MPSettingsTheme styleNavigationBar:controller.navigationController.navigationBar];
        [MPSettingsTheme styleWindows];

        // WP 8.1: верхнего бара нет — контент под статус-баром. С кнопками бар остаётся.
        BOOL hasBarButtons = (nav != nil && nav.topViewController == controller &&
                              nav.visibleViewController.navigationItem.rightBarButtonItems.count > 0);
        if (nav != nil) {
            nav.navigationBar.hidden = !hasBarButtons;
            CGFloat top = hasBarButtons ? 44.0f : 20.0f;
            if (table.superview != nil) {
                table.frame = CGRectMake(0.0f, top, table.superview.bounds.size.width,
                                         table.superview.bounds.size.height - top);
            } else {
                table.frame = CGRectMake(0.0f, top, table.bounds.size.width, table.bounds.size.height);
            }
        }

        BOOL hasHeader = [table.tableHeaderView isKindOfClass:[MPSettingsHeaderView class]];
        controller.navigationItem.hidesBackButton = hasHeader;
        if (hasHeader) {
            MPSettingsHeaderView *header = (MPSettingsHeaderView *)table.tableHeaderView;
            BOOL isSubpage = (nav != nil && nav.viewControllers.count > 1 &&
                              [nav.viewControllers firstObject] != controller);
            header.showsBackChevron = isSubpage;
            header.backTapped = ^{
                [nav popViewControllerAnimated:YES];
            };
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] стиль страницы: %@ (%@)", e.name, e.reason);
    }
}

//──────────────────────────────────────────────────────────────────────────────
%group MPSettings

%hook PSListController

- (void)viewDidLoad {
    %orig;
    [MPSettingsTheme setupAppearanceOnce];      // лениво, один раз, после запуска приложения
    MPApplyPageStyle(self, [self table]);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    MPApplyPageStyle(self, [self table]);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // к этому моменту таблица точно создана (ленивая сборка спецификаторов завершена)
    MPApplyPageStyle(self, [self table]);
}

- (void)reloadSpecifiers {
    %orig;
    MPApplyPageStyle(self, [self table]);
}

- (void)reload {
    %orig;
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
    return cell;
}

- (float)tableView:(id)tableView heightForRowAtIndexPath:(id)indexPath {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    // единая высота строки (56): и с подзаголовком, и без — по ТЗ допускается
    return (h > 1.0f) ? 56.0f : h;
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
        l.font = [MPMetroStyle lightFont:17.0f];
        l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];   // серые, поменьше
        l.backgroundColor = [UIColor clearColor];
        l.shadowColor = nil;
        l.shadowOffset = CGSizeZero;
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
                UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tw, 34.0f)];
                wrap.backgroundColor = [UIColor blackColor];
                wrap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                UILabel *l = [[UILabel alloc] initWithFrame:
                              CGRectMake(16.0f, 0.0f, tw - 32.0f, 28.0f)];
                l.text = t;
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
    // текстовый футер с нашей плоской меткой: даём высоту по строкам
    NSString *t = nil;
    @try {
        if ([self respondsToSelector:@selector(tableView:titleForFooterInSection:)]) {
            t = [(id)self tableView:tableView titleForFooterInSection:section];
        }
    } @catch (NSException *e) { t = nil; }
    if (t.length > 0) {
        CGFloat lines = 1.0f + (CGFloat)(t.length / 55);
        return 8.0f + lines * 16.0f;
    }
    return h;
}

- (float)tableView:(id)tableView heightForHeaderInSection:(NSInteger)section {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    // растягиваем только секции с настоящим заголовком; пустые (отступы групп) — как были
    NSString *title = nil;
    @try {
        if ([self respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) {
            title = [(id)self tableView:tableView titleForHeaderInSection:section];
        }
    } @catch (NSException *e) { title = nil; }
    BOOL hasTitle = (title != nil && title.length > 0);
    return hasTitle ? 34.0f : h;
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
        l.font = [MPMetroStyle regularFont:12.0f];
        l.textColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
        l.backgroundColor = [UIColor clearColor];
        l.shadowColor = nil;
        l.shadowOffset = CGSizeZero;
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
                UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, tw, 44.0f)];
                wrap.backgroundColor = [UIColor blackColor];
                wrap.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                UILabel *l = [[UILabel alloc] initWithFrame:
                              CGRectMake(16.0f, 0.0f, tw - 32.0f, 44.0f)];
                l.text = t;
                l.font = [MPMetroStyle regularFont:12.0f];
                l.textColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
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
    if ([MPSettingsTheme restyleEnabled] && cell != nil) {
        [MPSettingsCellStyler stylePSTableCell:cell];
    }
    return cell;
}

- (void)refreshCellContentsWithSpecifier:(id)specifier {
    %orig;
    if ([MPSettingsTheme restyleEnabled]) {
        [MPSettingsCellStyler stylePSTableCell:self];     // после обновления — перекраска
    }
}

- (void)layoutSubviews {
    %orig;
    if ([MPSettingsTheme restyleEnabled]) {
        [MPSettingsCellStyler layoutPSTableCell:self];
    }
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

// Универсальный слой: обычные UITableViewCell (не PS) — тёмный плоский вид.
// Только точный класс: PS-ячейки оформлены выше, чужие подклассы не трогаем.
%hook UITableViewCell

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    if (![self isMemberOfClass:[UITableViewCell class]]) return;
    [MPSettingsCellStyler styleGenericCell:self];
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
        NSLog(@"[MetroPhone][Settings] группа хуков установлена");
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] init: %@ (%@)", e.name, e.reason);
    }
}

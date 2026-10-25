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
#import "MPSettingsCellStyler.h"

static NSString * const MPSettingsHeaderKey = @"mp_settings_header";

// Приватные классы (объявления для ARC, реализации — системные)
@interface PSListController : UIViewController
- (id)table;
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
    // WP: заголовок подстраницы — «wi-fi», «основные»… Берём navigationItem.title
    // (то, что раньше рисовал навбар), затем controller.title, затем имя приложения
    NSString *page = controller.navigationItem.title ?: controller.title ?: MPSettingsDisplayName();
    header.smallTitle = MPSettingsDisplayName();
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
%group MPSettings

%hook PSListController

- (void)viewDidLoad {
    %orig;
    [MPSettingsTheme setupAppearanceOnce];      // лениво, один раз, после запуска приложения
    if (![MPSettingsTheme restyleEnabled]) return;
    if ([MPSettingsTheme isControllerExcluded:self]) return;

    @try {
        MPStyleTable([self table]);
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] viewDidLoad: %@ (%@)", e.name, e.reason);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    if ([MPSettingsTheme isControllerExcluded:self]) return;

    @try {
        UITableView *table = [self table];
        MPStyleTable(table);
        MPInstallOrUpdateHeader(self, table);

        // WP 8.1: шапка заменяет и заголовок, и кнопку «Назад»
        BOOL hasHeader = [table.tableHeaderView isKindOfClass:[MPSettingsHeaderView class]];
        self.navigationItem.hidesBackButton = hasHeader;
        if (hasHeader) {
            MPSettingsHeaderView *header = (MPSettingsHeaderView *)table.tableHeaderView;
            UINavigationController *nav = self.navigationController;
            BOOL isSubpage = (nav != nil && nav.viewControllers.count > 1 &&
                              [nav.viewControllers firstObject] != self);
            header.showsBackChevron = isSubpage;
            header.backTapped = ^{
                [nav popViewControllerAnimated:YES];
            };
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] viewWillAppear: %@ (%@)", e.name, e.reason);
    }
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

- (id)tableView:(id)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *v = %orig;
    if (![MPSettingsTheme restyleEnabled]) return v;
    @try {
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)v;
            l.font = [MPMetroStyle lightFont:20.0f];
            l.textColor = [MPMetroStyle accentColor];     // заголовки групп — акцентные
            l.backgroundColor = [UIColor clearColor];
            l.shadowColor = nil;
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] header: %@ (%@)", e.name, e.reason);
    }
    return v;
}

- (float)tableView:(id)tableView heightForHeaderInSection:(NSInteger)section {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    return (h > 0.5f) ? 34.0f : h;                          // отступы групп 14 pt сверху
}

- (id)tableView:(id)tableView viewForFooterInSection:(NSInteger)section {
    UIView *v = %orig;
    if (![MPSettingsTheme restyleEnabled]) return v;
    @try {
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)v;
            l.font = [MPMetroStyle regularFont:12.0f];
            l.textColor = [UIColor colorWithWhite:1.0f alpha:0.5f];
            l.backgroundColor = [UIColor clearColor];
            l.shadowColor = nil;
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

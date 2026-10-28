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
#import "MetroLauncher/MPMetroStyle.h"
#import "MPSettingsTheme.h"
#import "MPSettingsHeaderView.h"
#import "MPSettingsToggle.h"
#import "MPSettingsCellStyler.h"

static NSString * const MPSettingsHeaderKey = @"mp_settings_header";

static UINavigationController *MPFindNavController(UIViewController *root);   // определён ниже

// Навигация «Настроек» живёт вне дерева вьюх: ищем бар и его делегата.
static UINavigationController *MPNavFromWindow(UIWindow *w) {
    if (w == nil) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
    while (stack.count > 0) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if ([v isKindOfClass:[UINavigationBar class]]) {
            id d = [(UINavigationBar *)v delegate];
            if ([d isKindOfClass:[UINavigationController class]]) return (UINavigationController *)d;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// Некоторые системные геттеры (на списках вроде «Язык») возвращают не массив,
// а строку — в журнале это «−[__NSCFString count]: unrecognized selector».
// Считаем такие значения безопасно, вместо прямого .count
static NSUInteger MPCount(id value) {
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]]) {
        return [(NSArray *)value count];
    }
    return 0;
}

// «Назад» для страниц вне PS (Spotlight, «Профили», сертификат, панели поиска):
// раньше шапке не назначался backTapped — стрелка «‹» была, а выхода не было.
static void MPSettingsGoBack(UIViewController *host, UIView *view) {
    UINavigationController *nav = host.navigationController;
    if (nav == nil && view != nil) nav = MPNavFromWindow(view.window);
    if (nav == nil) nav = MPFindNavController([UIApplication sharedApplication].keyWindow.rootViewController);
    BOOL went = NO;
    if (nav != nil && MPCount(nav.viewControllers) > 1) {
        [nav popViewControllerAnimated:YES];
        went = YES;
    } else if (nav != nil && nav.presentingViewController != nil) {
        [nav dismissViewControllerAnimated:YES completion:nil];
        went = YES;
    } else if (host != nil && host.presentingViewController != nil) {
        [host dismissViewControllerAnimated:YES completion:nil];
        went = YES;
    }
    MPLog(@"[Settings] назад: %@ (nav=%@, стек %lu)", went ? @"ок" : @"некуда",
          nav != nil ? NSStringFromClass([nav class]) : @"nil",
          (unsigned long)MPCount(nav.viewControllers));
}

static void MPSettingsGoBackFromTable(UITableView *table) {
    id delegate = table.delegate;
    UIViewController *host = [delegate isKindOfClass:[UIViewController class]] ? (UIViewController *)delegate : nil;
    MPSettingsGoBack(host, table);
}

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
static void MPStyleHeaderLabelDeep(UIView *v);

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

// STORE: контроллер ставит лейбл инфо-ячейки на y = −30, и он налезает на
// кнопку «Забыли Apple ID или пароль?». Класс живёт в бандле и появляется позже —
// поэтому перехватываем layoutSubviews не Logos'ом, а по факту загрузки класса.
static IMP MPStoreInfoOrigLayout = NULL;

static void MPStoreInfoLayout(UIView *self, SEL _cmd) {
    if (MPStoreInfoOrigLayout != NULL) {
        ((void (*)(id, SEL))MPStoreInfoOrigLayout)(self, _cmd);
    }
    for (UIView *v in self.subviews) {
        if (![v isKindOfClass:[UILabel class]]) continue;
        UILabel *l = (UILabel *)v;
        if (l.frame.size.height < 30.0f) continue;
        // 18 вместо 16: мелкий кегль даёт меньший боковой просвет, иначе абзац
        // выглядит левее строк (замер: 16,5 против 18,5)
        l.frame = CGRectMake(18.0f, 2.0f, MAX(200.0f, self.bounds.size.width - 34.0f),
                             MAX(26.0f, self.bounds.size.height - 2.0f));
        l.font = [MPMetroStyle regularFont:10.5f];
        l.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
        l.textAlignment = NSTextAlignmentLeft;
        l.numberOfLines = 0;
        l.lineBreakMode = NSLineBreakByWordWrapping;
    }
}

static IMP MPStoreLinkOrigLayout = NULL;

static void MPStyleStoreLinkView(UIView *v) {
    for (UIView *s in v.subviews) {
        if (![s isKindOfClass:[UIButton class]]) continue;
        UIButton *b = (UIButton *)s;
        NSString *title = [b titleForState:UIControlStateNormal];
        if (title.length == 0) {
            NSAttributedString *cur = [b attributedTitleForState:UIControlStateNormal];
            title = cur.string;
        }
        if (title.length == 0) title = b.titleLabel.text;
        if (title.length == 0) continue;
        NSAttributedString *at = [[NSAttributedString alloc] initWithString:title attributes:@{
            NSFontAttributeName: [MPMetroStyle mediumFont:15.0f],
            NSForegroundColorAttributeName: [MPMetroStyle accentColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone),
        }];
        [b setAttributedTitle:at forState:UIControlStateNormal];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        // у UIButton свой внутренний отступ 3 pt — из-за него текст ссылки
        // начинался правее строк списка; убираем, чтобы левый край был 16 pt
        b.contentEdgeInsets = UIEdgeInsetsZero;
        b.titleEdgeInsets = UIEdgeInsetsZero;
        b.titleLabel.textAlignment = NSTextAlignmentLeft;
        // 13 вместо 16: у глифа «З» левый боковой просвет ~3 pt, и при 16 ссылка
        // визуально уезжала правее строк списка (замер по снимку: 20 pt против 18,5)
        b.frame = CGRectMake(13.0f, 6.0f, MAX(120.0f, v.bounds.size.width - 29.0f), 24.0f);
    }
}

static void MPStoreLinkLayout(UIView *self, SEL _cmd) {
    if (MPStoreLinkOrigLayout != NULL) {
        ((void (*)(id, SEL))MPStoreLinkOrigLayout)(self, _cmd);
    }
    MPStyleStoreLinkView(self);
}

static void MPInstallStoreInfoHookIfNeeded(void) {
    if (MPStoreInfoOrigLayout != NULL) return;
    Class c = NSClassFromString(@"SUSettingsAppleIDInfoHeaderCell");
    if (c != Nil) {
        Method m = class_getInstanceMethod(c, @selector(layoutSubviews));
        if (m != NULL) MPStoreInfoOrigLayout = method_setImplementation(m, (IMP)MPStoreInfoLayout);
    }
    if (MPStoreLinkOrigLayout == NULL) {
        Class f = NSClassFromString(@"SUSettingsLinkHeaderFooterView");
        if (f != Nil) {
            Method fm = class_getInstanceMethod(f, @selector(layoutSubviews));
            if (fm != NULL) MPStoreLinkOrigLayout = method_setImplementation(fm, (IMP)MPStoreLinkLayout);
        }
    }
}

// Кнопки навбара («Изменить», «Готово») переносим в нашу шапку: в WP верхнего
// бара нет. Прокси хранит UIBarButtonItem и вызывает его target/action.
@interface MPBarItemProxy : NSObject
@property (nonatomic, strong) UIBarButtonItem *item;
- (void)tap:(id)sender;
@end

@implementation MPBarItemProxy
- (void)tap:(id)sender {
    if (self.item.target != nil && [self.item.target respondsToSelector:self.item.action]) {
        void (*send)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        send(self.item.target, self.item.action, self.item);
    }
}
@end

static void MPAttachHeaderButtons(UITableView *table, UINavigationItem *item) {
    MPSettingsHeaderView *h = MPAttachedHeader(table);
    if (h == nil) return;
    for (UIView *v in [h.subviews copy]) {
        if (v.tag == 0x4D504254) [v removeFromSuperview];
    }
    CGFloat needH = 96.0f;
    if (item != nil) {
        NSMutableArray *items = [NSMutableArray array];
        [items addObjectsFromArray:item.leftBarButtonItems ?: @[]];
        [items addObjectsFromArray:item.rightBarButtonItems ?: @[]];
        CGFloat x = 16.0f;
        for (UIBarButtonItem *bi in items) {
            NSString *title = bi.title;
            if (title.length == 0) {
                // у модальных форм элемент часто собран из своего UINavigationButton
                UIView *cv = bi.customView;
                if ([cv isKindOfClass:[UIButton class]]) {
                    title = [(UIButton *)cv titleForState:UIControlStateNormal];
                } else if ([cv isKindOfClass:[UILabel class]]) {
                    title = [(UILabel *)cv text];
                }
            }
            if (title.length == 0) continue;
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.tag = 0x4D504254;
            b.titleLabel.font = [MPMetroStyle mediumFont:15.0f];
            [b setTitle:title forState:UIControlStateNormal];
            [b setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            CGFloat w = [title sizeWithFont:b.titleLabel.font].width + 10.0f;
            b.frame = CGRectMake(x, 96.0f, w, 24.0f);
            MPBarItemProxy *proxy = [[MPBarItemProxy alloc] init];
            proxy.item = bi;
            [b addTarget:proxy action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(b, (__bridge const void *)@"mpBarProxy", proxy,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [h addSubview:b];
            x += w + 14.0f;
        }
        needH = 126.0f;                       // 96 шапки + 30 под кнопку
    }
    if (fabsf(h.frame.size.height - needH) > 0.5f) {
        CGRect f = h.frame;
        f.size.height = needH;
        h.frame = f;
        table.tableHeaderView = h;            // таблица пересчитает высоту шапки
    }
}

// Сертификат в «Профилях»: шестерёнка, красный статус и глянцевая «Удалить»
// лежат внутри MCDetailsDescriptionView, а не в contentView ячейки.
static UIView *MPCertFind(UIView *root, NSString *className) {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count > 0) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if ([NSStringFromClass([v class]) isEqualToString:className]) return v;
        [stack addObjectsFromArray:v.subviews];
    }
    return nil;
}

// Шапка сертификата: сам MCDetailsHeaderCell или его ближайший предок.
static char kMPCertEmptyDesc;

static UIView *MPCertHeaderCell(UIView *root) {
    UIView *v = root;
    for (int i = 0; v != nil && i < 10; i++, v = v.superview) {
        if ([NSStringFromClass([v class]) isEqualToString:@"MCDetailsHeaderCell"]) return v;
    }
    return MPCertFind(root, @"MCDetailsHeaderCell");
}

static void MPStyleCertificateView(UIView *root) {
    UIView *header = MPCertHeaderCell(root);
    if (header == nil) return;

    UIView *content = nil;
    Class ccClass = NSClassFromString(@"UITableViewCellContentView");
    for (UIView *s in header.subviews) {
        if (ccClass != Nil && [s isKindOfClass:ccClass]) { content = s; break; }
    }
    if (content == nil) content = header;

    // шестерёнка сертификата — в проекте строк без иконок
    for (UIView *s in content.subviews) {
        if ([s isKindOfClass:[UIImageView class]]) s.hidden = YES;
    }

    // Имя, статус и «Удалить» живут не в contentView, а в MCDetailsHeaderContentView:
    // родной layout центрирует этот блок (x=97, ширина 191), из-за чего имя обрезалось
    // до «Hanabi's Updated Ro…». Разбираем блок и ставим его к левому краю.
    UIView *block = MPCertFind(content, @"MCDetailsHeaderContentView");
    if (block == nil) block = content;
    CGFloat blockW = content.bounds.size.width - 12.0f;    // 10 pt contentView + 6 = 16 pt
    if (block != content) {
        block.frame = CGRectMake(6.0f, 4.0f, blockW,
                                 MAX(80.0f, content.bounds.size.height - 8.0f));
    }

    UILabel *name = nil;
    UIView *status = nil;
    UIButton *button = nil;
    for (UIView *s in block.subviews) {
        if ([s isKindOfClass:[UIButton class]]) {
            button = (UIButton *)s;
            continue;
        }
        // Статус — не UILabel, а MCUIGradientLabel (рисует текст градиентом)
        if ([NSStringFromClass([s class]) isEqualToString:@"MCUIGradientLabel"]) {
            status = s;
            continue;
        }
        if (![s isKindOfClass:[UILabel class]]) continue;
        UILabel *l = (UILabel *)s;
        if (l.text.length == 0) {              // пустой дубль статуса
            l.hidden = YES;
            continue;
        }
        l.hidden = NO;                         // текст мог появиться после первого layout
        if (name == nil) name = l; else status = l;
    }

    if (name != nil) {
        name.frame = CGRectMake(0.0f, 0.0f, blockW, 30.0f);
        name.textAlignment = NSTextAlignmentLeft;
        name.font = [MPMetroStyle lightFont:24.0f];
        name.textColor = [UIColor whiteColor];
        name.adjustsFontSizeToFitWidth = YES;
        name.minimumFontSize = 13.0f;
        name.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    if (status != nil) {
        status.frame = CGRectMake(0.0f, 32.0f, blockW, 18.0f);
        if ([status isKindOfClass:[UILabel class]]) {
            UILabel *sl = (UILabel *)status;
            sl.textAlignment = NSTextAlignmentLeft;
            sl.font = [MPMetroStyle regularFont:13.0f];
        }
        // цвет не трогаем: «Не проверен» — индикатор состояния, а не декор
    }
    if (button != nil) {
        // Строка-действие в языке проекта: акцентный текст без плашки и рамки
        [button setBackgroundImage:nil forState:UIControlStateNormal];
        [button setBackgroundImage:nil forState:UIControlStateHighlighted];
        button.backgroundColor = [UIColor clearColor];
        button.layer.cornerRadius = 0.0f;
        button.layer.borderWidth = 0.0f;
        [button setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
        button.titleLabel.font = [MPMetroStyle mediumFont:15.0f];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.titleEdgeInsets = UIEdgeInsetsMake(0.0f, -16.0f, 0.0f, 0.0f);   // линия 16 pt
        for (UIView *bs in button.subviews) {
            if ([bs isKindOfClass:[UIImageView class]]) bs.hidden = YES;
        }
        button.frame = CGRectMake(0.0f, 54.0f, blockW, 26.0f);
    }

    // Описание сертификата: у корневых CA родная вьюха пустая, но занимает 58–202 pt —
    // между кнопкой и «Более подробно» оставалась чёрная полоса. Проверяем после того,
    // как страница достроилась (в момент layout содержимое ещё не создано), и сворачиваем.
    UITableView *tv = (UITableView *)header.superview;
    if ([tv isKindOfClass:[UITableView class]]) {
        // Соседняя строка «Более подробно» — обычная UITableViewCell: приводим её
        // к общему языку страницы (текст 16 pt, аксессуар у правого края 304).
        for (UITableViewCell *c in tv.visibleCells) {
            if ([c class] != [UITableViewCell class]) continue;
            for (UIView *v in c.contentView.subviews) {
                if (![v isKindOfClass:[UILabel class]]) continue;
                CGRect f = v.frame;
                f.origin.x = 6.0f;                     // contentView начинается на 10 pt
                f.size.width = c.contentView.bounds.size.width - 6.0f;
                v.frame = f;
            }
            for (UIView *v in c.subviews) {
                if (v == c.contentView || ![v isKindOfClass:[UIButton class]]) continue;
                ((UIButton *)v).contentHorizontalAlignment =
                    UIControlContentHorizontalAlignmentRight;
            }
        }
        static char kMPCertChecked;
        if (objc_getAssociatedObject(tv, &kMPCertChecked) == nil) {
            objc_setAssociatedObject(tv, &kMPCertChecked, @YES, OBJC_ASSOCIATION_RETAIN);
            __weak UITableView *weakTable = tv;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                UITableView *t = weakTable;
                if (t == nil) return;
                UITableViewCell *descCell = nil;
                for (UITableViewCell *c in t.visibleCells) {
                    if ([NSStringFromClass([c class]) isEqualToString:@"MCDetailsDescriptionTableCell"]) {
                        descCell = c;
                        break;
                    }
                }
                if (descCell == nil) return;                 // строки нет — ничего не делаем
                UIView *desc = MPCertFind(descCell, @"MCDetailsDescriptionView");
                BOOL empty = (desc == nil || desc.subviews.count == 0);
                if (empty && objc_getAssociatedObject(t, &kMPCertEmptyDesc) == nil) {
                    objc_setAssociatedObject(t, &kMPCertEmptyDesc, @YES, OBJC_ASSOCIATION_RETAIN);
                    [t reloadData];
                }
            });
        }
    }
}

// Родной layout блока шапки центрирует имя/статус/кнопку — после него ставим свои кадры.
// Хук — только на сам блок: class_addMethod добавляет переопределение ЭТОМУ классу,
// а не UIView (иначе ломается layout всего процесса — именно это и случалось).
static IMP MPHeaderBlockLayoutOrig = NULL;

static void MPHeaderBlockLayout(UIView *self, SEL _cmd) {
    if (MPHeaderBlockLayoutOrig != NULL) {
        ((void (*)(id, SEL))MPHeaderBlockLayoutOrig)(self, _cmd);
    }
    MPStyleCertificateView(self);
}

static IMP MPCertHeightOrig = NULL;

static float MPCertHeight(id self, SEL _cmd, UITableView *tv, NSIndexPath *ip) {
    float h = 44.0f;
    if (MPCertHeightOrig != NULL) {
        h = ((float (*)(id, SEL, UITableView *, NSIndexPath *))MPCertHeightOrig)(self, _cmd, tv, ip);
    }
    if (![ip isKindOfClass:[NSIndexPath class]]) return h;
    // Страница сертификата: 96 (шапка) + 16 + 109 + 202 + 44 = 467 при экране 460 —
    // последняя строка обрезалась. Шапке хватает 89 (в ячейке получается 90), строке — 56.
    if (ip.section == 0 && ip.row == 0 && h > 80.0f && h < 140.0f) return 89.0f;
    // Пустое описание у корневых сертификатов — 58–202 pt чёрной полосы посередине.
    if (ip.section == 0 && ip.row == 1 && h > 20.0f &&
        objc_getAssociatedObject(tv, &kMPCertEmptyDesc) != nil) return 0.0f;
    if (ip.section == 0 && ip.row == 2 && h > 30.0f && h < 60.0f) return 56.0f;
    return h;
}

// Безопасная установка: если у класса своего метода нет, class_addMethod добавит
// переопределение только ему (родительский IMP остаётся в origOut).
static void MPInstallMethodHook(Class c, SEL sel, IMP imp, IMP *origOut) {
    if (c == Nil || origOut == NULL || *origOut != NULL) return;
    Method m = class_getInstanceMethod(c, sel);
    if (m == NULL) return;
    const char *types = method_getTypeEncoding(m);
    IMP orig = method_getImplementation(m);
    if (class_addMethod(c, sel, imp, types)) {
        *origOut = orig;
    } else {
        Method own = class_getInstanceMethod(c, sel);
        *origOut = method_setImplementation(own, imp);
    }
}

static void MPInstallCertificateHookIfNeeded(void) {
    MPInstallMethodHook(NSClassFromString(@"MCDetailsHeaderContentView"),
                        @selector(layoutSubviews), (IMP)MPHeaderBlockLayout,
                        &MPHeaderBlockLayoutOrig);
    // Класс страницы — из бандла ManagedConfiguration, поэтому берём его по факту.
    MPInstallMethodHook(NSClassFromString(@"MCConfigurationDetailsController"),
                        @selector(tableView:heightForRowAtIndexPath:), (IMP)MPCertHeight,
                        &MPCertHeightOrig);
}

static void MPStyleUsageHeader(UITableView *table) {
    // USAGE: «Доступно: 6,4 ГБ» / «Занято: 7,5 ГБ» — родные метки шириной 102 pt,
    // текст в них не влезал («Доступно: 6,…»). Ужимаем кегль и разрешаем
    // уменьшение шрифта — вместо обрезки.
    if (table == nil) return;
    for (UIView *v in table.subviews) {
        if (![NSStringFromClass([v class]) isEqualToString:@"UsageTotalUsedHeader"]) continue;
        for (UIView *s in v.subviews) {
            if (![s isKindOfClass:[UILabel class]]) continue;
            UILabel *l = (UILabel *)s;
            l.font = [MPMetroStyle regularFont:12.0f];
            l.adjustsFontSizeToFitWidth = YES;
            l.minimumFontSize = 9.0f;
            l.lineBreakMode = NSLineBreakByClipping;
        }
    }
}

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
        MPStyleUsageHeader(table);
        MPInstallStoreInfoHookIfNeeded();   // классы Store появляются при первом показе страницы
        MPInstallCertificateHookIfNeeded(); // «Профили»: класс сертификата из бандла
        for (UIView *v in table.subviews) {
            if ([NSStringFromClass([v class]) isEqualToString:@"SUSettingsLinkHeaderFooterView"]) {
                MPStyleStoreLinkView(v);
            }
        }
        [MPSettingsTheme applyFlatBarButtonAppearance];   // «Изменить»/«Готово» — без глянца

        UINavigationController *nav = controller.navigationController;
        // В корневом меню иконок нет; на внутренних страницах показываем глифы
        MPSettingsIconsHidden = (nav == nil || MPCount(nav.viewControllers) <= 1);
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
                              (MPCount(visibleItem.rightBarButtonItems) > 0 ||
                               MPCount(visibleItem.leftBarButtonItems) > 0));
        if (nav != nil) {
            // WP: верхнего бара нет никогда; кнопки («Изменить»/«Готово»)
            // переносятся в нашу шапку под заголовок.
            nav.navigationBar.hidden = YES;
            MPAttachHeaderButtons(table, hasBarButtons ? visibleItem : nil);

            // Страховка: если кнопки есть, а перенести их не удалось (у элемента
            // нет title — форма VPN собирает бар из своих UINavigationButton),
            // оставляем системный бар. Иначе «Отменить»/«Сохранить» пропадают
            // и страницу нельзя ни сохранить, ни закрыть.
            if (hasBarButtons) {
                NSUInteger proxies = 0;
                for (UIView *v in [MPAttachedHeader(table).subviews copy]) {
                    if (v.tag == 0x4D504254) proxies++;
                }
                if (proxies == 0) {
                    nav.navigationBar.hidden = NO;
                    MPLog(@"[Settings] кнопки бара не перенеслись — бар оставлен (%@)",
                          NSStringFromClass([controller class]));
                }
            }
            CGFloat top = 0.0f;
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

        // Кастомные заголовки-вьюхи контроллера («Фотопоток» на странице «Фото и
        // камера» — MSSPhotoStreamHeaderView) не приходят в viewForHeaderInSection:
        // стилизуем их прямо среди подвью таблицы (та же плоская типографика).
        for (UIView *v in table.subviews) {
            if ([NSStringFromClass([v class]) isEqualToString:@"MSSPhotoStreamHeaderView"]) {
                MPStyleHeaderLabelDeep(v);
            }
        }

        // Куда возвращаться: push в стеке ИЛИ модальное представление
        // (страницы настроек твиков часто открываются модально со своим стеком,
        // где контроллер ПЕРВЫЙ — раньше шеврон не ставился, а системная кнопка
        // пряталась: назад пропадал совсем)
        BOOL canPop = (nav != nil && MPCount(nav.viewControllers) > 1 &&
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
        } else if (MPCount(visibleItem.leftBarButtonItems) > 0 ||
                   MPCount(visibleItem.rightBarButtonItems) > 0) {
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
    // «Type» в формах: сегменты разложены списком из трёх радио-строк (3×56)
    @try {
        if ([self respondsToSelector:@selector(indexForIndexPath:)] &&
            [self respondsToSelector:@selector(specifierAtIndex:)]) {
            NSInteger (*sendIdx)(id, SEL, id) = (NSInteger (*)(id, SEL, id))objc_msgSend;
            NSInteger flat = sendIdx(self, @selector(indexForIndexPath:), indexPath);
            if (flat >= 0) {
                id (*sendSpec)(id, SEL, long) = (id (*)(id, SEL, long))objc_msgSend;
                id spec = sendSpec(self, @selector(specifierAtIndex:), (long)flat);
                if (spec != nil && [spec respondsToSelector:NSSelectorFromString(@"propertyForKey:")]) {
                    id (*sendProp)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
                    id cellType = sendProp(spec, NSSelectorFromString(@"propertyForKey:"), @"cell");
                    if ([cellType isKindOfClass:[NSString class]] &&
                        [(NSString *)cellType isEqualToString:@"PSSegmentCell"]) {
                        return 168.0f;
                    }
                }
            }
        }
    } @catch (NSException *e) {
        // не критично: останется штатная высота
    }
    // STORE: строка с «Apple ID — это учетная запись…» — 70 pt, чтобы лейбл
    // (после нашей правки layoutSubviews) влез целиком под ссылкой.
    if ([NSStringFromClass([self class]) isEqualToString:@"StoreSettingsController"]) {
        NSIndexPath *ip = (NSIndexPath *)indexPath;
        if ([ip isKindOfClass:[NSIndexPath class]] && ip.section == 1) return 70.0f;
    }
    // Спец-строки выше 100 pt (превью обоев: картинки 154 pt) резать до 56 нельзя:
    // превью вылезают на «Автояркость» и на подпись «Обои».
    if (h > 100.0f) return h;
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

// Есть ли глубже в дереве кнопка (кнопочные футеры вроде SUSettingsLinkHeaderFooterView)
static BOOL MPViewContainsButton(UIView *v) {
    if ([v isKindOfClass:[UIButton class]]) return YES;
    for (UIView *sub in v.subviews) {
        if (MPViewContainsButton(sub)) return YES;
    }
    return NO;
}

// Кнопки внутри футера — строки-действия: акцент вместо серого цвета футера
static void MPAccentFooterButtons(UIView *v) {
    if ([v isKindOfClass:[UIButton class]]) {
        [(UIButton *)v setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
        return;
    }
    for (UIView *sub in v.subviews) MPAccentFooterButtons(sub);
}

- (float)tableView:(id)tableView heightForFooterInSection:(NSInteger)section {
    CGFloat h = %orig;
    if (![MPSettingsTheme restyleEnabled]) return h;
    // STORE: футер секции «Войти» — ссылка «Забыли Apple ID или пароль?».
    // Родная высота 35 pt; при 8 pt кнопка вылезала на текст следующей ячейки.
    if ([NSStringFromClass([self class]) isEqualToString:@"StoreSettingsController"] && section == 1) {
        // Родная высота (35). Лейбл следующей ячейки контроллер ставит на y = −30,
        // из-за чего он попадает на кнопку «Забыли Apple ID…». Подгонка футера
        // двигает и лейбл (он привязан к ячейке) — нужна правка layoutSubviews
        // самой SUSettingsAppleIDInfoHeaderCell, это отдельная задача.
        return h;
    }
    NSString *t = nil;
    @try {
        if ([self respondsToSelector:@selector(tableView:titleForFooterInSection:)]) {
            t = [(id)self tableView:tableView titleForFooterInSection:section];
        }
    } @catch (NSException *e) { t = nil; }
    if (t.length == 0) {
        // 28B/38B: пустые футеры — 8 pt. ВАЖНО: НЕ увеличиваем даже для кнопочных
        // футеров (STORE: SUSettingsLinkHeaderFooterView): StoreSettingsController
        // считает высоту ячейки с текстом «Apple ID — это учетная запись…» как
        // «79 − высота футера», и при больших футерах ячейка ужимается, а её
        // лейбл вылезает на кнопку. Лейбл сдвигается ниже кнопки в styleCellDeep.
        return 8.0f;
    }
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
    // спец-заголовки с несколькими строками (USAGE: UsageTotalUsedHeader с
    // «Место хранения / Доступно / Занято») приходят с родной высотой 60+ —
    // наша типографическая 28 сжимала их, и лейблы вылезали на ячейки
    if (hasTitle) return (h > 60.0f) ? h : 28.0f;
    return 16.0f;                              // 38B: пустые — 16 pt
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
            // Кнопка-ссылка в футере («Забыли Apple ID или пароль?»): это
            // строка-действие — акцентом, серый цвет футера ей не подходит
            if (MPViewContainsButton(v)) {
                MPAccentFooterButtons(v);
            }
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

%hook StoreSettingsController
- (float)tableView:(id)tableView heightForRowAtIndexPath:(id)indexPath {
    float h = %orig;
    NSIndexPath *ip = (NSIndexPath *)indexPath;
    // секция «Войти»: под ссылкой идёт абзац про Apple ID — 76 pt, иначе он сжат
    if ([ip isKindOfClass:[NSIndexPath class]] && ip.section == 1) return 76.0f;
    return h;
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
// WP-радио вместо системной галочки: свой аксессуар + защита от рекурсии
static BOOL MPRadioGuard = NO;
static char kMPRadioView;

%hook UITableViewCell

// UITableViewCellAccessoryCheckmark рисует синюю галочку iOS. По референсу WP 8.1
// выбор — белое радио (кольцо + точка): подменяем аксессуар, тип переводим в None,
// чтобы UIKit не нарисовал галочку вместе с нашей вьюхой.
- (void)setAccessoryType:(UITableViewCellAccessoryType)type {
    %orig;
    if (MPRadioGuard) return;
    if (![MPSettingsTheme restyleEnabled]) return;
    if (type == UITableViewCellAccessoryCheckmark) {
        UIImageView *v = [[UIImageView alloc] initWithImage:[MPSettingsCellStyler radioImageSelected:YES]];
        objc_setAssociatedObject(v, &kMPRadioView, @YES, OBJC_ASSOCIATION_RETAIN);
        MPRadioGuard = YES;
        self.accessoryType = UITableViewCellAccessoryNone;
        MPRadioGuard = NO;
        self.accessoryView = v;
    } else if (type == UITableViewCellAccessoryNone) {
        UIView *av = self.accessoryView;
        if (av != nil && objc_getAssociatedObject(av, &kMPRadioView) != nil) {
            self.accessoryView = nil;
        }
    }
}

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    Class psClass = NSClassFromString(@"PSTableCell");
    if (psClass != Nil && [self isKindOfClass:psClass]) return;   // PS-ячейки оформлены выше
    [MPSettingsCellStyler styleGenericCell:self];
    [MPSettingsCellStyler styleCellDeep:self];

    // Страницы вне PS («Основные → Spotlight» и подобные): обычные UITableViewCell.
    // Родной левый отступ 34 pt (место под ручку сортировки) и разделители —
    // приводим к общему языку: текст с 16 pt, чёрный фон, шапка страницы.
    if ([NSStringFromClass([self class]) isEqualToString:@"MCDetailsHeaderCell"]) {
        MPInstallCertificateHookIfNeeded();   // страница не PS — хуки ставим по факту ячейки
        MPStyleCertificateView(self);
    }
    if ([self class] == [UITableViewCell class]) {
        for (UIView *v in self.contentView.subviews) {
            // иконки (галочки, шестерёнки сертификатов) — в проекте строк без иконок
            if ([v isKindOfClass:[UIImageView class]]) {
                v.hidden = YES;
                continue;
            }
            // «Удалить» у сертификата — родная красная кнопка: оставляем действие,
            // но в стиле проекта — акцентный текст без плашки
            if ([v isKindOfClass:[UIButton class]]) {
                UIButton *b = (UIButton *)v;
                b.backgroundColor = [UIColor clearColor];
                b.layer.cornerRadius = 0.0f;
                b.layer.borderWidth = 0.0f;
                b.layer.borderColor = [UIColor clearColor].CGColor;
                [b setTitleColor:[MPMetroStyle accentColor] forState:UIControlStateNormal];
                b.titleLabel.font = [MPMetroStyle mediumFont:15.0f];
                continue;
            }
            if (![v isKindOfClass:[UILabel class]]) continue;
            UILabel *l = (UILabel *)v;
            CGRect f = l.frame;
            if (f.size.height >= 30.0f && f.origin.x > 16.5f) {
                f.size.width = MAX(80.0f, f.size.width - (f.origin.x - 16.0f));
                f.origin.x = 16.0f;
                l.frame = f;
            }
        }
        for (UIView *v in self.subviews) {
            if (v != self.contentView && v.frame.size.height <= 1.0f) v.hidden = YES;
        }
        UITableView *tv = (UITableView *)self.superview;
        if ([tv isKindOfClass:[UITableView class]]) {
            static char kMPPlainPage;
            if (objc_getAssociatedObject(tv, &kMPPlainPage) == nil) {
                objc_setAssociatedObject(tv, &kMPPlainPage, @YES, OBJC_ASSOCIATION_RETAIN);
                // единый ритм: строки 56 pt, как на PS-страницах
                if (fabsf(tv.rowHeight - 56.0f) > 0.5f) {
                    tv.rowHeight = 56.0f;
                    dispatch_async(dispatch_get_main_queue(), ^{ [tv reloadData]; });
                }
            }
            if (tv.tableHeaderView == nil) {
                id d = tv.delegate;
                NSString *title = nil;
                if ([d respondsToSelector:@selector(navigationItem)])
                    title = [[(UIViewController *)d navigationItem] title];
                if (title.length == 0 && [d respondsToSelector:@selector(title)])
                    title = [(UIViewController *)d title];
                if (title.length > 0) {
                    MPSettingsHeaderView *h = [[MPSettingsHeaderView alloc] initWithFrame:
                        CGRectMake(0.0f, 0.0f, tv.bounds.size.width,
                                   [MPSettingsHeaderView heightForWidth:tv.bounds.size.width])];
                    h.pageTitle = title;
                    h.showsBackChevron = YES;      // это всегда подстраница
                    __weak UITableView *weakPlainTable = tv;
                    h.backTapped = ^{ MPSettingsGoBackFromTable(weakPlainTable); };
                    tv.tableHeaderView = h;
                }
            }
        }
    }

    // WP-радио: держим наш аксессуар у правой линии (16 pt от края экрана)
    UIView *acc = self.accessoryView;
    if (acc != nil && objc_getAssociatedObject(acc, &kMPRadioView) != nil) {
        CGSize sz = acc.bounds.size;
        acc.frame = CGRectMake(self.bounds.size.width - 16.0f - sz.width,
                               (self.bounds.size.height - sz.height) / 2.0f,
                               sz.width, sz.height);
    }
}

%end

// Синхронизация WP-тумблера с оригинальным свитчем (логика PS остаётся на свитче)
// Сегментные контролы («Type» в форме VPN): бегунок-квадрат должен ехать за
// выбором, а метки — менять насыщенность. После смены индекса просим ячейку
// переразметиться (стиль сегментов живёт в layoutPSTableCell).
%hook UISegmentedControl

- (void)setSelectedSegmentIndex:(NSInteger)selectedSegmentIndex {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    __weak UISegmentedControl *weakSeg = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UISegmentedControl *seg = weakSeg;
        if (seg == nil) return;
        UIView *view = seg.superview;
        while (view != nil && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
        if (view != nil) [MPSettingsCellStyler layoutPSTableCell:(UITableViewCell *)view];
    });
}

%end

%hook UISwitch

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    %orig;
    @try {
        // состояние может меняться программно (система, refreshCellContents) без
        // лейаута — зеркалим в оверлей, если он уже создан
        [MPSettingsToggle syncExistingForSwitch:self];
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

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Панели поиска («Часовой пояс»)

// У таких панелей (TimeZonePane) нет ни нашей шапки, ни видимого навбара:
// навбар остался скрытым с предыдущей страницы, а таблица — светлая. Ставим
// шапку с «‹» и приводим панель к тёмному виду проекта.
static char kMPSearchPaneStyled;
static char kMPSearchPaneHeader;
static char kMPSearchPaneOwner;
static char kMPSearchPaneWindow;
static const NSInteger kMPPaneHeaderTag = 0x4D504831;   // 'MPH1'
static const CGFloat kMPPaneWindowLevel = 1050.0f;

// Шапка панели живёт в СВОЁМ окне над клавиатурой: когда поле получает фокус,
// iOS показывает клавиатуру с чёрной подложкой поверх окна приложения, и шапка,
// лежавшая в нём, исчезала вместе с контентом.
static UIWindow *MPPaneWindowFor(UIViewController *vc, CGFloat w, CGFloat hH) {
    UIWindow *win = objc_getAssociatedObject(vc, &kMPSearchPaneWindow);
    if (win == nil) {
        win = [[UIWindow alloc] initWithFrame:CGRectMake(0.0f, 20.0f, w, hH)];
        win.windowLevel = kMPPaneWindowLevel;
        win.backgroundColor = [UIColor blackColor];
        win.hidden = NO;
        objc_setAssociatedObject(win, &kMPSearchPaneOwner, vc, OBJC_ASSOCIATION_ASSIGN);
        objc_setAssociatedObject(vc, &kMPSearchPaneWindow, win, OBJC_ASSOCIATION_RETAIN);
    }
    win.frame = CGRectMake(0.0f, 20.0f, w, hH);
    win.hidden = NO;
    return win;
}

// Поле поиска панели: тёмная плашка 16…304, без системной рамки и синего кольца.
// Вызывается и при первом появлении, и на каждом layout — контроллер сбрасывает кадр.
static void MPStyleSearchPaneField(UIViewController *vc) {
    UIView *root = vc.view;
    if (root == nil) return;
    UITextField *tf = (UITextField *)MPCertFind(root, @"UISearchField");
    if (tf == nil) return;    CGFloat w = root.bounds.size.width;
    if (w < 10.0f) w = 320.0f;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1.0f, 1.0f), NO, 0.0f);
    [[UIColor colorWithWhite:0.12f alpha:1.0f] setFill];
    UIRectFill(CGRectMake(0.0f, 0.0f, 1.0f, 1.0f));
    UIImage *fill = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    tf.background = [fill stretchableImageWithLeftCapWidth:0 topCapHeight:0];
    tf.backgroundColor = [UIColor colorWithWhite:0.12f alpha:1.0f];
    tf.textColor = [UIColor whiteColor];
    tf.borderStyle = UITextBorderStyleNone;
    tf.keyboardAppearance = UIKeyboardAppearanceAlert;
    // reloadInputViews здесь НЕ вызывать: после него клавиатурное окно становится
    // непрозрачным и накрывает весь контент панели (проверено 0.21.7).
    tf.layer.borderWidth = 0.0f;
    tf.layer.borderColor = [UIColor clearColor].CGColor;
    for (UIView *s in tf.subviews) {
        // рамка/градиент, которые iOS добавляет полю при фокусе
        if ([NSStringFromClass([s class]) isEqualToString:@"UITextFieldBorderView"]) s.hidden = YES;
    }
    CGRect ff = tf.frame;
    ff.origin.x = 16.0f;
    ff.size.width = w - 32.0f;
    tf.frame = ff;
    for (UIView *s in tf.superview.subviews) {
        if (s == tf) continue;
        if ([s isKindOfClass:[UIImageView class]] &&
            s.bounds.size.width >= w - 1.0f && s.bounds.size.height <= 60.0f) {
            s.hidden = YES;                     // градиентная полоса поиска
        }
    }
}

// Тёмная клавиатура: UISearchField игнорирует keyboardAppearance поля, но менять
// его через хук becomeFirstResponder нельзя — сбивает фокус (проверено 0.21.0).

// Панель (TimeZonePane) сама раскладывает поле в своём layoutSubviews —
// после него возвращаем кадр 16…304.
static IMP MPPaneLayoutOrig = NULL;

// Сильнее layout: любой setFrame панели держим ниже шапки.
static IMP MPPaneSetFrameOrig = NULL;

static void MPPaneSetFrame(UIView *self, SEL _cmd, CGRect frame) {
    frame.origin.y = 96.0f;
    if (self.superview != nil) {
        frame.size.height = self.superview.bounds.size.height - 96.0f;
    }
    if (MPPaneSetFrameOrig != NULL) {
        ((void (*)(id, SEL, CGRect))MPPaneSetFrameOrig)(self, _cmd, frame);
    }
}

static void MPPaneLayout(UIView *self, SEL _cmd) {
    if (MPPaneLayoutOrig != NULL) {
        ((void (*)(id, SEL))MPPaneLayoutOrig)(self, _cmd);
    }
    // Контроллер при фокусе возвращает панель на y=0 — тогда поле и таблица
    // уезжают под нашу шапку и экран становится чёрным. Держим панель ниже шапки.
    // Заодно возвращаем видимость, если её спрятали (alpha/hidden).
    if (self.alpha < 1.0f) self.alpha = 1.0f;
    if (self.hidden) self.hidden = NO;
    CGFloat headerH = 96.0f;
    UIView *parent = self.superview;
    if (parent != nil) {
        CGRect f = self.frame;
        CGFloat wantH = parent.bounds.size.height - headerH;
        if (fabsf(f.origin.y - headerH) > 0.5f || fabsf(f.size.height - wantH) > 0.5f) {
            f.origin.y = headerH;
            f.size.height = wantH;
            self.frame = f;
        }
    }
    UIResponder *r = [self nextResponder];
    while (r != nil && ![r isKindOfClass:[UIViewController class]]) r = [r nextResponder];
    if ([r isKindOfClass:[UIViewController class]] &&
        objc_getAssociatedObject(r, &kMPSearchPaneHeader) != nil) {
        MPStyleSearchPaneField((UIViewController *)r);
    }
}

static void MPStyleSearchPaneIfNeeded(UIViewController *vc) {
    if (vc == nil) return;
    UIView *root = vc.view;
    if (root == nil) return;
    if (objc_getAssociatedObject(vc, &kMPSearchPaneStyled) != nil) {
        // шапка живёт в своём окне: если окно спрятали — вернуть
        MPSettingsHeaderView *prev = objc_getAssociatedObject(vc, &kMPSearchPaneHeader);
        UIWindow *prevWin = objc_getAssociatedObject(vc, &kMPSearchPaneWindow);
        if (prev != nil && prev.superview == nil && prevWin != nil) [prevWin addSubview:prev];
        if (prevWin != nil) prevWin.hidden = NO;
        return;
    }
    UIView *field = MPCertFind(root, @"UISearchField");
    if (field == nil) return;                       // это не поисковая панель
    objc_setAssociatedObject(vc, &kMPSearchPaneStyled, @YES, OBJC_ASSOCIATION_RETAIN);
    // хук на класс панели: её layout сбрасывает кадр поля
    if (field.superview != nil) {
        MPInstallMethodHook([field.superview class], @selector(layoutSubviews),
                            (IMP)MPPaneLayout, &MPPaneLayoutOrig);
        MPInstallMethodHook([field.superview class], @selector(setFrame:),
                            (IMP)MPPaneSetFrame, &MPPaneSetFrameOrig);
    }
    CGFloat w = root.bounds.size.width;
    if (w < 10.0f) w = 320.0f;
    CGFloat hH = [MPSettingsHeaderView heightForWidth:w];

    root.backgroundColor = [UIColor blackColor];

    // сдвигаем поле и таблицу вниз под шапку
    for (UIView *v in [root.subviews copy]) {
        CGRect f = v.frame;
        f.origin.y += hH;
        CGFloat maxH = root.bounds.size.height - f.origin.y;
        if (f.size.height > maxH) f.size.height = MAX(0.0f, maxH);
        v.frame = f;
        // градиентная полоса поиска больше не нужна
        if ([v isKindOfClass:[UIImageView class]] && f.size.width >= w - 1.0f && f.size.height <= 60.0f) {
            v.hidden = YES;
        }
    }

    MPSettingsHeaderView *header = [[MPSettingsHeaderView alloc] initWithFrame:
                                   CGRectMake(0.0f, 0.0f, w, hH)];
    header.pageTitle = (vc.navigationItem.title.length > 0) ? vc.navigationItem.title : vc.title;
    header.showsBackChevron = YES;
    header.tag = kMPPaneHeaderTag;
    objc_setAssociatedObject(header, &kMPSearchPaneOwner, vc, OBJC_ASSOCIATION_ASSIGN);
    __weak UIViewController *weakVC = vc;
    header.backTapped = ^{
        UIViewController *host = weakVC;
        MPSettingsGoBack(host, host.view);
    };
    // Шапку держим в отдельном окне над клавиатурой: подложка клавиатуры
    // закрывает окно приложения целиком, и шапка из него пропадала.
    objc_setAssociatedObject(vc, &kMPSearchPaneHeader, header, OBJC_ASSOCIATION_RETAIN);
    UIWindow *hWin = MPPaneWindowFor(vc, w, hH);
    header.frame = CGRectMake(0.0f, 0.0f, w, hH);
    [hWin addSubview:header];

    if ([field isKindOfClass:[UITextField class]]) {
        MPStyleSearchPaneField(vc);
    }

    UITableView *table = (UITableView *)MPCertFind(root, @"UITableView");
    if (table != nil) {
        table.backgroundColor = [UIColor blackColor];
        table.separatorStyle = UITableViewCellSeparatorStyleNone;
        if (table.alpha < 1.0f) table.alpha = 1.0f;
        if (table.hidden) table.hidden = NO;
    }
    MPLog(@"[Settings] панель поиска оформлена: %@", NSStringFromClass([vc class]));
}

%hook UIViewController

// Контроллер панели пересчитывает кадр поля на каждом layout — возвращаем наш.
- (void)viewDidLayoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    if (objc_getAssociatedObject(self, &kMPSearchPaneHeader) == nil) return;
    @try {
        MPStyleSearchPaneField(self);
    } @catch (NSException *e) {
        // не критично
    }
}

// Ушли с панели — прячем её окно, иначе шапка осталась бы над предыдущей страницей.
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIWindow *paneWindow = objc_getAssociatedObject(self, &kMPSearchPaneWindow);
    if (paneWindow != nil) paneWindow.hidden = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    @try {
        // спрятать окна шапок чужих панелей поиска
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.windowLevel != kMPPaneWindowLevel) continue;
            id owner = objc_getAssociatedObject(w, &kMPSearchPaneOwner);
            if (owner != self) w.hidden = YES;
        }
        MPStyleSearchPaneIfNeeded(self);
        // Страховка от «некуда выйти»: если на странице нет нашей шапки,
        // показываем родной навбар с кнопкой назад.
        __weak UIViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *vc = weakSelf;
            if (vc == nil) return;
            UINavigationController *nav = vc.navigationController;
            if (nav == nil || nav.topViewController != vc) return;
            BOOL ours = (MPCertFind(vc.view, @"MPSettingsHeaderView") != nil) ||
                        (objc_getAssociatedObject(vc, &kMPSearchPaneHeader) != nil);
            if (ours != nav.navigationBar.hidden) {
                nav.navigationBar.hidden = ours;
                MPLog(@"[Settings] навбар: %@ (%@)", ours ? @"скрыт" : @"показан",
                      NSStringFromClass([vc class]));
            }
        });
    } @catch (NSException *e) {
        // не критично
    }
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

// Флаги РАЗДЕЛЬНЫЕ: раньше один флаг на обе группы — если Wi-Fi (APTableCell)
// встречался раньше Bluetooth (BTTableCell), %init(MPBTHooks) не вызывался НИКОГДА,
// и строки устройств оставались родными (синий текст, глянцевый диск).
static BOOL MPCustomAPHooksInstalled = NO;
static BOOL MPCustomBTHooksInstalled = NO;

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
    if ([cellClass isEqualToString:@"APTableCell"]) {
        if (MPCustomAPHooksInstalled) return;
        MPCustomAPHooksInstalled = YES;
        @try {
            %init(MPCustomCells);
        } @catch (NSException *e) {
            NSLog(@"[MetroPhone][Settings] хук APTableCell: %@", e.name);
        }
        return;
    }
    if ([cellClass isEqualToString:@"BTTableCell"]) {
        if (MPCustomBTHooksInstalled) return;
        MPCustomBTHooksInstalled = YES;
        @try {
            %init(MPBTHooks);
        } @catch (NSException *e) {
            NSLog(@"[MetroPhone][Settings] хук BTTableCell: %@", e.name);
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
#pragma mark - «Дата и время» (DatePane)

// Почему отдельный слой: DatePane — не PSListController, а PSEditingPane (UIView)
// внутри DateController (сверено с бинарником Preferences 6.1.3: суперкласс
// PSEditingPane, 9 своих методов). Таблицу из двух строк и UIDatePicker он
// собирает сам, поэтому общий слой (он висит на PSListController) сюда не
// доходит: экран оставался родным — полосатый фон, белая дата на белой плашке,
// глянцевый барабан (вопрос 53, ответ 53B: тёмный фон + белый текст).

// Первая вьюху заданного класса в поддереве (таблица и пикер лежат прямо в панели)
static UIView *MPDatePaneFind(UIView *root, Class cls) {
    if (root == nil) return nil;
    if ([root isKindOfClass:cls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = MPDatePaneFind(sub, cls);
        if (found != nil) return found;
    }
    return nil;
}

// Тёмный барабан: в iOS 6 UIDatePicker собран из картинок (градиенты, тени,
// полоса выбора) и полупрозрачных таблиц. Гасим картинки, полосе выбора даём
// плоскую белую заливку 8 %, цифры — белые (53B).
static void MPDatePaneStylePickerView(UIView *view) {
    for (UIView *sub in view.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([sub isKindOfClass:[UIImageView class]]) {
            sub.hidden = YES;                       // градиенты, тени, «шторки» колёс
        } else if ([sub isKindOfClass:[UITableView class]]) {
            UITableView *t = (UITableView *)sub;
            t.backgroundColor = [UIColor clearColor];
            t.separatorStyle = UITableViewCellSeparatorStyleNone;
        } else if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)sub;
            l.textColor = [UIColor whiteColor];
            l.shadowColor = nil;
            l.backgroundColor = [UIColor clearColor];
        }
        if ([cls isEqualToString:@"_UIPickerViewTopFrame"]) {
            sub.hidden = YES;                       // тень над колесом
        }
        if ([cls isEqualToString:@"_UIPickerViewSelectionBar"]) {
            sub.hidden = YES;                       // своя полоса выбора — ниже
        }
        if ([cls isEqualToString:@"UIDatePickerContentView"] ||
            [cls isEqualToString:@"UITableViewCellContentView"] ||
            [cls isEqualToString:@"UIPickerTableViewWrapperCell"]) {
            sub.backgroundColor = [UIColor clearColor];
        }
        MPDatePaneStylePickerView(sub);
    }
}

// Метки своих вью в барабане, чтобы не плодить их на каждом лейауте
static const NSInteger MPDatePaneBackdropTag = 0x4D5031;
static const NSInteger MPDatePaneBandTag     = 0x4D5032;

// Прямые подвью _UIDatePickerView: градиенты колёс, шторки, полосы выбора и
// сама градиентная подложка. iOS 6 ПЕРЕСОБИРАЕТ их на каждом лейауте барабана,
// поэтому одного прохода мало: прячем последними — из хука самого барабана.
static void MPDatePaneStylePickerInner(UIView *inner) {
    if (inner == nil) return;
    static BOOL busy = NO;
    if (busy) return;
    busy = YES;
    @try {
        for (UIView *sub in [inner.subviews copy]) {
            NSString *cls = NSStringFromClass([sub class]);
            if ([cls isEqualToString:@"_UIOnePartImageView"] ||
                [cls isEqualToString:@"_UIPickerViewTopFrame"] ||
                [cls isEqualToString:@"_UIPickerViewSelectionBar"] ||
                [cls isEqualToString:@"_UIPickerWheelView"]) {   // он рисует 1-px разделители колёс
                sub.hidden = YES;                   // своя плоская полоса выбора
                continue;
            }
            // Подложка-градиент — обычный UIView во весь барабан (без метки)
            if ([cls isEqualToString:@"UIView"] && sub.tag == 0 &&
                CGSizeEqualToSize(sub.frame.size, inner.bounds.size) && sub.frame.origin.y == 0.0f) {
                sub.hidden = YES;
                continue;
            }
            if ([sub isKindOfClass:[UITableView class]]) {
                UITableView *t = (UITableView *)sub;
                t.backgroundColor = [UIColor clearColor];
                t.separatorStyle = UITableViewCellSeparatorStyleNone;
            }
        }
        inner.backgroundColor = [UIColor blackColor];

        // Свой фон и своя полоса: держим их первыми в списке (под колёсами)
        UIView *backdrop = [inner viewWithTag:MPDatePaneBackdropTag];
        if (backdrop == nil) {
            backdrop = [[UIView alloc] initWithFrame:inner.bounds];
            backdrop.tag = MPDatePaneBackdropTag;
            backdrop.backgroundColor = [UIColor blackColor];
            backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        }
        backdrop.frame = inner.bounds;
        [inner insertSubview:backdrop atIndex:0];

        UIView *band = [inner viewWithTag:MPDatePaneBandTag];
        if (band == nil) {
            band = [[UIView alloc] initWithFrame:CGRectZero];
            band.tag = MPDatePaneBandTag;
            band.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.10f];
            band.userInteractionEnabled = NO;       // касания — колёсам
        }
        band.frame = CGRectMake(0.0f, (inner.bounds.size.height - 44.0f) / 2.0f,
                                inner.bounds.size.width, 44.0f);
        // Полоса — ПОВЕРХ колёс: таблицы колёс рисуют чёрный фон сами, поэтому
        // под ними её видно только по бокам (два серых прямоугольника)
        [inner addSubview:band];
    } @finally {
        busy = NO;
    }
}

static void MPDatePaneStylePicker(UIDatePicker *picker) {
    picker.backgroundColor = [UIColor blackColor];
    MPDatePaneStylePickerView(picker);
    MPDatePaneStylePickerInner(picker.subviews.count > 0 ? [picker.subviews objectAtIndex:0] : nil);
}

// Готовая шапка страницы с выходом по тапу — общая для «Даты и времени» и
// «Обновления ПО» (обе страницы собираются не общим слоем PSListController)
static MPSettingsHeaderView *MPMakeHeader(UITableView *table, NSString *title) {
    MPSettingsHeaderView *header = [[MPSettingsHeaderView alloc] initWithFrame:
        CGRectMake(0.0f, 0.0f, table.bounds.size.width,
                   [MPSettingsHeaderView heightForWidth:table.bounds.size.width])];
    header.pageTitle = title;                  // шапка сама делает строчные
    header.showsBackChevron = YES;
    __weak UITableView *weakTable = table;
    header.backTapped = ^{
        UITableView *t = weakTable;
        UINavigationController *nav = (t != nil) ? MPNavFromWindow(t.window) : nil;
        MPLog(@"[Settings] шапка «%@»: возврат (nav=%@, стек %lu)", title,
              nav != nil ? NSStringFromClass([nav class]) : @"nil",
              (unsigned long)MPCount(nav.viewControllers));
        if (nav != nil && MPCount(nav.viewControllers) > 1) {
            [nav popViewControllerAnimated:YES];
        } else if (nav != nil && nav.presentingViewController != nil) {
            [nav dismissViewControllerAnimated:YES completion:nil];   // модальная форма
        } else if (nav != nil) {
            nav.navigationBar.hidden = NO;     // выйти некуда — вернуть родной бар
        }
    };
    return header;
}

// Шапка страницы с выходом по тапу — как на остальных страницах «Настроек»
static void MPDatePaneInstallHeader(UITableView *table) {
    if (table == nil) return;
    MPSettingsHeaderView *header = MPAttachedHeader(table);
    if (header == nil) {
        header = MPMakeHeader(table, @"Дата и время");
        table.tableHeaderView = header;
        table.contentInset = UIEdgeInsetsZero;
        table.contentOffset = CGPointZero;     // страница была прокручена под навбар
    }
    header.pageTitle = @"Дата и время";        // шапка сама делает строчные
    header.showsBackChevron = YES;
    [header setNeedsLayout];
}

// Защита от рекурсии: rowHeight вызывает reloadData, тот — снова layoutSubviews
static BOOL MPDatePaneApplying = NO;

static void MPDatePaneApply(UIView *pane) {
    if (pane == nil || MPDatePaneApplying) return;
    MPDatePaneApplying = YES;
    @try {
        UITableView *table = (UITableView *)MPDatePaneFind(pane, [UITableView class]);
        if (table != nil) {
            table.backgroundColor = [UIColor blackColor];
            table.backgroundView = nil;
            table.separatorStyle = UITableViewCellSeparatorStyleNone;
            if (table.contentInset.top != 0.0f) table.contentInset = UIEdgeInsetsZero;
            MPDatePaneInstallHeader(table);
            if (fabs(table.rowHeight - 56.0f) > 0.5f) {
                table.rowHeight = 56.0f;        // строка списка, как на других страницах
            }
        }
        UIDatePicker *picker = (UIDatePicker *)MPDatePaneFind(pane, [UIDatePicker class]);
        if (picker != nil) MPDatePaneStylePicker(picker);

        // Выход — шеврон в шапке; верхний бар на этой странице ничего не добавляет
        UINavigationController *nav = MPNavFromWindow(pane.window);
        if (nav != nil && !nav.navigationBar.hidden) nav.navigationBar.hidden = YES;
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] DatePane: %@ (%@)", e.name, e.reason);
    }
    MPDatePaneApplying = NO;
}

// DatePane создаёт ячейки сам, без спецификатора: titleLabel у PSTableCell не
// создан, поэтому кегль и цвет задаём прямо метке — как у строк списка.
static void MPDatePaneStyleCell(UITableViewCell *cell) {
    if (cell == nil) return;
    [MPSettingsCellStyler stylePSTableCell:cell];
    [MPSettingsCellStyler styleGenericCell:cell];
    for (UIView *sub in cell.contentView.subviews) {
        if (![sub isKindOfClass:[UILabel class]]) continue;
        UILabel *label = (UILabel *)sub;
        label.font = [MPMetroStyle lightFont:24.0f];
        label.textColor = [UIColor whiteColor];
        label.shadowColor = nil;
        label.backgroundColor = [UIColor clearColor];
    }
}

%group MPDatePaneHooks

%hook DatePane

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    MPDatePaneApply((UIView *)self);   // DatePane — PSEditingPane (UIView), Logos знает только имя
}

- (id)tableView:(id)tableView cellForRowAtIndexPath:(id)indexPath {
    UITableViewCell *cell = %orig;
    if ([MPSettingsTheme restyleEnabled] && [cell isKindOfClass:[UITableViewCell class]]) {
        MPDatePaneStyleCell(cell);
    }
    return cell;
}

%end

// Барабан пересобирает градиенты при каждом лейауте — гасим их последними,
// иначе они возвращаются поверх нашего чёрного фона
%hook _UIDatePickerView

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    MPDatePaneStylePickerInner((UIView *)self);
}

%end

// Колёса пикера создают ячейки при прокрутке — красим метку на каждом лейауте,
// иначе новые значения появляются чёрными на чёрном
%hook UIDatePickerContentView

- (void)layoutSubviews {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    UIView *pane = (UIView *)self;      // класс приватный: Logos видит только forward declaration
    pane.backgroundColor = [UIColor clearColor];
    for (UIView *sub in pane.subviews) {
        if (![sub isKindOfClass:[UILabel class]]) continue;
        UILabel *label = (UILabel *)sub;
        label.textColor = [UIColor whiteColor];
        label.shadowColor = nil;
        label.backgroundColor = [UIColor clearColor];
    }
}

%end

%end // MPDatePaneHooks

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - «Обновление ПО» (SoftwareUpdatePrefController)

// Контроллер — подкласс PSListController (сверено с бинарником Preferences:
// superclass PSListController, своя таблица PrefsSUTableView), но на входе в
// страницу таблица ПУСТАЯ (0 секций: идёт проверка обновлений) — общий слой
// выходит по «спецификаторы ещё грузятся» и экран остаётся родным: полосатая
// подложка, тёмно-синяя жирная строка «Проверяю наличие обновлений…», серый
// спиннер. Вдобавок страница — тупик: навбар скрыт с прошлой страницы, а шапки
// нет. Поэтому шапку и тёмное оформление ставим сразу, не дожидаясь списка.
static void MPStyleSoftwareUpdateBits(UITableView *table) {
    if (table == nil) return;
    // Таблица страницы умеет рисовать полосатый узор сама
    if ([table respondsToSelector:NSSelectorFromString(@"_setDrawsCheckeredPattern:")]) {
        void (*sendPattern)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
        sendPattern(table, NSSelectorFromString(@"_setDrawsCheckeredPattern:"), NO);
    }
    for (UIView *sub in table.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls isEqualToString:@"UITableViewBackgroundView"]) {
            sub.hidden = YES;                      // полосатая подложка iOS 6
            continue;
        }
        if ([sub isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)sub;
            label.font = [MPMetroStyle lightFont:17.0f];
            label.textColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
            label.shadowColor = nil;
            label.backgroundColor = [UIColor clearColor];
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumFontSize = 12.0f;
            // кадры контроллер переставляет сам после нас — положение не трогаем
            continue;
        }
        if ([sub isKindOfClass:[UIActivityIndicatorView class]]) {
            ((UIActivityIndicatorView *)sub).color = [MPMetroStyle accentColor];
        }
    }
}

static UITableView *MPSUTableOf(id controller) {
    if (controller == nil || ![controller respondsToSelector:@selector(table)]) return nil;
    id (*sendObj)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return (UITableView *)sendObj(controller, @selector(table));
}

static void MPStyleSoftwareUpdateTable(UITableView *table);

// Страница пересобирается сама: у PrefsSUTableView есть свой setSUState:, а у
// контроллера — updateState; оба переставляют подложку, подпись и спиннер ПОСЛЕ
// нас. Поэтому в каждом таком хуке просим повторный проход следующим тиком
// ранлупа — уже поверх работы системы.
static void MPSUStyleSoon(UITableView *table) {
    if (table == nil) return;
    static CFAbsoluteTime last = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - last < 0.15) return;             // не штормим: проход дешёвый, но лишний
    last = now;
    __weak UITableView *weakTable = table;
    dispatch_async(dispatch_get_main_queue(), ^{
        MPStyleSoftwareUpdateTable(weakTable);
    });
}

static void MPStyleSoftwareUpdateTable(UITableView *table) {
    if (table == nil) return;
    table.backgroundColor = [UIColor blackColor];
    table.backgroundView = nil;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    MPStyleSoftwareUpdateBits(table);
    if (MPAttachedHeader(table) == nil) {
        table.tableHeaderView = MPMakeHeader(table, @"Обновление ПО");
        MPLog(@"[SU] шапка поставлена (%@)", NSStringFromClass([table class]));
    }
    // Выход — шеврон в шапке: навбар с прошлой страницы оставался скрытым,
    // а кнопки «назад» на этой странице нет
    UINavigationController *nav = MPNavFromWindow(table.window);
    if (nav != nil && !nav.navigationBar.hidden) nav.navigationBar.hidden = YES;
}

%group MPSoftwareUpdateHooks

%hook SoftwareUpdatePrefController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    MPSUStyleSoon(MPSUTableOf(self));
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    MPSUStyleSoon(MPSUTableOf(self));
}

// Состояние проверки обновлений сменилось — контроллер перестроил страницу
- (void)updateState {
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    MPSUStyleSoon(MPSUTableOf(self));
}

- (void)setSUState:(int)state {   // в бинарнике v12@0:4i8
    %orig;
    if (![MPSettingsTheme restyleEnabled]) return;
    MPSUStyleSoon(MPSUTableOf(self));
}

%end

%end // MPSoftwareUpdateHooks

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - «Язык» (LanguageCell)

// В списке языков iOS 6 название каждого языка — КАРТИНКА (LanguageCell держит
// UIImageView 200×43 с чёрным текстом на белой плашке). Перекрасить такую
// картинку нечем, поэтому инвертируем её: белые буквы на чёрном, плашка
// сливается с фоном строки. Шрифт не трогаем — язык остаётся в своей графике
// (японский, арабский и т. д. иначе не показать).
//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Предпросмотр контролов (инструмент разработки)

// Рисует сегментный контрол с нашим оформлением в PNG — чтобы подбирать вид
// вкладок без захода в форму VPN (см. команду tabpreview в отладочном канале).
@interface MPSettingsCellStyler (MPPreview)
+ (void)mp_restoreSegmentedControl:(UITableViewCell *)cell;
@end

void MPPreviewSegmentTabs(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                            reuseIdentifier:nil];
            cell.frame = CGRectMake(0.0f, 0.0f, 320.0f, 168.0f);
            cell.backgroundColor = [UIColor blackColor];
            cell.contentView.backgroundColor = [UIColor blackColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:
                                       @[@"L2TP", @"PPTP", @"IPSec"]];
            seg.frame = CGRectMake(16.0f, 10.0f, 288.0f, 36.0f);
            seg.selectedSegmentIndex = 1;
            [cell.contentView addSubview:seg];
            [cell layoutIfNeeded];
            [MPSettingsCellStyler mp_restoreSegmentedControl:cell];
            [cell layoutIfNeeded];

            UIGraphicsBeginImageContextWithOptions(cell.bounds.size, YES, 0.0f);
            [cell.layer renderInContext:UIGraphicsGetCurrentContext()];
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            BOOL ok = [UIImagePNGRepresentation(img) writeToFile:
                       @"/var/mobile/Library/Caches/metrophone/tab-preview.png" atomically:YES];
            MPLog(@"[preview] список радио → %@", ok ? @"ок" : @"НЕ записан");
        } @catch (NSException *e) {
            MPLog(@"[preview] !! %@ — %@", e.name, e.reason);
        }
    });
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
        %init(MPDatePaneHooks);      // «Основные → Дата и время»: PSEditingPane, не PS
        %init(MPSoftwareUpdateHooks); // «Основные → Обновление ПО»: до загрузки списка

        // WP-стиль: Настройки всегда открываются с главной страницы.
        // iOS 6 восстанавливает последнюю посещённую — возвращаем в корень.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(NSNotification *note) {
                static BOOL firstActivation = YES;
                // Краулеру нужен гарантированный корень после перезапуска:
                // он кладёт флаг force-root, и мы один раз сбрасываем стек.
                NSString *forceFlag = @"/var/mobile/Library/Caches/metrophone/force-root";
                BOOL forceRoot = [[NSFileManager defaultManager] fileExistsAtPath:forceFlag];
                if (forceRoot) {
                    [[NSFileManager defaultManager] removeItemAtPath:forceFlag error:NULL];
                } else if (firstActivation) {
                    firstActivation = NO;
                    return;   // первый запуск — уже в корне
                }
                // iOS восстанавливает последнюю страницу уже ПОСЛЕ активации,
                // поэтому сбрасываем стек с задержкой.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    @try {
                        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
                        UINavigationController *nav = MPFindNavController(root);
                        if (nav != nil && MPCount(nav.viewControllers) > 1) {
                            [nav popToRootViewControllerAnimated:NO];
                            NSLog(@"[MetroPhone][Settings] активация: возврат в корень");
                        }
                    } @catch (NSException *e) {
                        // молча
                    }
                });
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


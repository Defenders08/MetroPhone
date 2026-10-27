#import "MPSettingsCellStyler.h"
#import "MPSettingsTheme.h"
#import "MPSettingsToggle.h"
#import <objc/message.h>
#import <CoreText/CoreText.h>

static const CGFloat MPCellStyleInset = 16.0f;      // базовый отступ от края экрана

// Теги наших иконок Wi-Fi-строк (замок и уровень сети).
static NSInteger const MPLockTag = 0x4D504C31;   // 'MPL1'
static NSInteger const MPSigTag  = 0x4D505331;   // 'MPS1'

@interface MPSettingsCellStyler ()
+ (void)mp_repairBrokenLabelsAndFields:(UITableViewCell *)cell;
+ (void)mp_normalizeAccessory:(UITableViewCell *)cell;
+ (void)mp_styleNetworkRow:(UITableViewCell *)cell;
@end

// Корневое меню «Настроек» — без иконок; внутренние страницы — с глифами.
// Ставится хуком страницы (MPApplyPageStyle) перед отрисовкой ячеек.
BOOL MPSettingsIconsHidden = NO;
BOOL MPSettingsPageHasIcons = NO;
BOOL MPSettingsPageIsSounds = NO;

// Красный ли цвет (опасные действия — цвет сохраняем, перекрашиваем только чёрный/серый/синий)
static BOOL MPCGColorIsRed(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return (r > 0.7f && g < 0.35f && b < 0.35f);
}

@implementation MPSettingsCellStyler

#pragma mark - WP-глифы (шрифт Metro UI Icons, MIT)

// Шрифт лежит в пакете: /Library/Application Support/MetroPhone/metro-ui-core.ttf.
// Регистрируем один раз и рисуем глиф как текст — иконка всегда белая, любого
// размера, без набора PNG в бандле.
static UIFont *MPGlyphFont(CGFloat size) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *path = @"/Library/Application Support/MetroPhone/metro-ui-core.ttf";
		if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
			CTFontManagerRegisterFontsForURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
			                                 kCTFontManagerScopeProcess, NULL);
		}
	});
	return [UIFont fontWithName:@"metro-ui-core" size:size];
}

static NSMutableDictionary *MPGlyphCache = nil;
static NSMutableSet       *MPGlyphRegistry = nil;   // все наши отрисованные глифы

static void MPGlyphSetup(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		MPGlyphCache = [NSMutableDictionary dictionary];
		MPGlyphRegistry = [NSMutableSet set];
	});
}

static UIImage *MPGlyphImage(unichar code, CGFloat side) {
	MPGlyphSetup();
	NSString *key = [NSString stringWithFormat:@"%C|%.0f", code, side];
	UIImage *cached = [MPGlyphCache objectForKey:key];
	if (cached != nil) return cached;

	UIFont *font = MPGlyphFont(side * 0.94f);
	if (font == nil) return nil;
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0f);
	[[UIColor whiteColor] setFill];
	NSString *s = [NSString stringWithCharacters:&code length:1];
	CGSize ts = [s sizeWithFont:font];
	[s drawAtPoint:CGPointMake(floorf((side - ts.width) / 2.0f), floorf((side - ts.height) / 2.0f))
	      withFont:font];
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (img != nil) {
		[MPGlyphCache setObject:img forKey:key];
		[MPGlyphRegistry addObject:img];
	}
	return img;
}

static BOOL MPIsOurGlyph(UIImage *image) {
	if (image == nil) return NO;
	MPGlyphSetup();
	return [MPGlyphRegistry containsObject:image];
}

#pragma mark - PS-ячейки

+ (void)stylePSTableCell:(UITableViewCell *)cell {
    @try {
        // плоский фон и подсветка нажатия
        cell.backgroundColor = [UIColor blackColor];
        cell.backgroundView = nil;
        cell.selectedBackgroundView = [MPSettingsTheme flatSelectionBackground];
        cell.multipleSelectionBackgroundView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;      // шевроны «>» убраны

        UILabel *title = [cell respondsToSelector:@selector(titleLabel)] ? (UILabel *)[cell performSelector:@selector(titleLabel)] : nil;
        UILabel *value = [cell respondsToSelector:@selector(valueLabel)] ? (UILabel *)[cell performSelector:@selector(valueLabel)] : nil;

        if (title != nil) {
            title.font = [MPMetroStyle lightFont:24.0f];
            // Длинные названия («Включить MetroPhone») не должны обрезаться:
            // ужимаем кегль в строку до 15 pt вместо хвостового многоточия
            title.adjustsFontSizeToFitWidth = YES;
            title.minimumFontSize = 15.0f;
            title.numberOfLines = 1;
            title.lineBreakMode = NSLineBreakByTruncatingTail;
            if (!MPCGColorIsRed(title.textColor)) {            // красные («Стереть…») не трогаем
                title.textColor = cell.isUserInteractionEnabled ? [UIColor whiteColor]
                                              : [UIColor colorWithWhite:1.0f alpha:0.4f];
            }
            title.backgroundColor = [UIColor clearColor];
            title.shadowColor = nil;

            // Строки-действия (PSButtonCell: «Перезапустить SpringBoard»,
            // «Добавить конфигурацию VPN…») — акцентом, чтобы отличались от списка
            @try {
                id spec = [cell valueForKey:@"specifier"];
                if (spec != nil && [spec respondsToSelector:NSSelectorFromString(@"propertyForKey:")]) {
                    id (*sendObj)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
                    id kind = sendObj(spec, NSSelectorFromString(@"propertyForKey:"), @"cell");
                    if ([kind isKindOfClass:[NSString class]] &&
                        [(NSString *)kind rangeOfString:@"Button"].location != NSNotFound) {
                        title.textColor = [MPMetroStyle accentColor];
                    }
                }
            } @catch (NSException *e) {
                // спецификатора нет — строка остаётся обычной
            }
        }
        if (value != nil) {
            value.font = [MPMetroStyle regularFont:13.0f];
            value.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
            value.backgroundColor = [UIColor clearColor];
            value.shadowColor = nil;
        }

        // Иконок в «Настройках» нет: чистый текстовый список, всё по 16 pt
        cell.imageView.image = nil;
        cell.imageView.hidden = YES;

        // Кастомные лейблы внутри ячейки (списки Wi-Fi/VPN и т.п.) — перекрашиваем
        // белым, сохраняя размер; красные не трогаем
        for (UIView *sub in cell.contentView.subviews) {
            if ([sub isKindOfClass:[UILabel class]] && sub != title && sub != value) {
                UILabel *l = (UILabel *)sub;
                if (!MPCGColorIsRed(l.textColor)) l.textColor = [UIColor whiteColor];
                l.backgroundColor = [UIColor clearColor];
                l.shadowColor = nil;
            }
        }

        // тумблеры/слайдеры остаются справа — их раскладка в layoutPSTableCell
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] styleCell: %@ (%@)", e.name, e.reason);
    }
}

+ (void)layoutPSTableCell:(UITableViewCell *)cell {
    @try {
        // PSTableCell возвращает «карточку» (скруглённый фон) в своём layoutSubviews —
        // убираем в каждом проходе, после %orig
        if (cell.backgroundView != nil) cell.backgroundView = nil;
        if (cell.selectedBackgroundView != nil &&
            ![cell.selectedBackgroundView.backgroundColor isEqual:[UIColor colorWithWhite:1.0f alpha:0.12f]]) {
            cell.selectedBackgroundView = [MPSettingsTheme flatSelectionBackground];
        }

        CGRect b = cell.contentView.bounds;

        UILabel *title = [cell respondsToSelector:@selector(titleLabel)] ? (UILabel *)[cell performSelector:@selector(titleLabel)] : nil;
        UILabel *value = [cell respondsToSelector:@selector(valueLabel)] ? (UILabel *)[cell performSelector:@selector(valueLabel)] : nil;
        BOOL hasValue = (value.text.length > 0);

        // Контрол справа (тумблер/слайдер/галочка-поле) — если он есть, текст не шире его
        // PSControlTableCell хранит контрол в свойстве control (свитч/слайдер
        // лежат ПРЯМО в ячейке, не в contentView); fallback — поиск по подвью
        UIView *control = nil;
        if ([cell respondsToSelector:@selector(control)]) {
            control = [(id<MPHasControl>)cell control];
        }
        if (control == nil) {
            for (UIView *v in cell.subviews) {
                if ([v isKindOfClass:[UIControl class]]) { control = v; break; }
            }
        }
        if (control == nil) {
            for (UIView *v in cell.contentView.subviews) {
                if ([v isKindOfClass:[UIControl class]]) { control = v; break; }
            }
        }

        if ([control isKindOfClass:[UISlider class]]) {
            [MPSettingsTheme styleSlider:(UISlider *)control];   // WP-ползунок на каждом проходе
            // Растягиваем на всю ширину строки: родной ползунок короче, справа
            // остаётся пустое место (кадр ставим здесь — после layout системы)
            CGRect sf = control.frame;
            CGFloat rightEdge = cell.bounds.size.width - MPCellStyleInset;
            if (sf.origin.x + sf.size.width < rightEdge - 2.0f) {
                sf.size.width = rightEdge - sf.origin.x;
                control.frame = sf;
            }
        }
        if ([control isKindOfClass:[UISwitch class]]) {
            // WP-тумблер поверх оригинального UISwitch (оригинал скрыт, жив)
            MPSettingsToggle *tg = [MPSettingsToggle attachedToggleForSwitch:(UISwitch *)control];
            [tg syncFrameFromSwitch];
            [tg syncFromSwitch];
        }
        CGFloat rightLimit = b.size.width - MPCellStyleInset;
        if (control != nil) {
            rightLimit = MIN(rightLimit, control.frame.origin.x - 8.0f);
        }

        // grouped-таблица вставляет contentView на ~10 pt — компенсируем,
        // чтобы текст был на 16 pt от края экрана
        CGFloat inset = MPCellStyleInset - 10.0f;
        if (inset < 2.0f) inset = 2.0f;

        // Если у строки есть иконка — текст сдвигается правее её (16 + 24 + 8)
        BOOL hasIcon = NO;
        CGFloat textInset = inset;   // один левый край для всех строк
        if (hasIcon) {
            cell.imageView.frame = CGRectMake(inset, (b.size.height - 24.0f) / 2.0f, 24.0f, 24.0f);
        }

        if (title != nil) {
            CGFloat titleY = hasValue ? 7.0f : 14.0f;   // 27B: без подзаголовка — 14 pt
            title.frame = CGRectMake(textInset, titleY,
                                     rightLimit - textInset, 30.0f);
            // цвет возвращаем здесь: кастомные ячейки (Wi-Fi) перекрашивают
            // заголовок своим layoutSubviews уже после нашего cellForRow
            UIColor *want = [UIColor whiteColor];
            if (!MPCGColorIsRed(title.textColor) && ![title.textColor isEqual:want]) {
                title.textColor = want;
            }
        }
        if (value != nil && hasValue) {
            // значение iOS «справа» переносится ПОД заголовок серым
            value.frame = CGRectMake(textInset, CGRectGetMaxY(title.frame) - 5.0f,   // 14B
                                     b.size.width - textInset - MPCellStyleInset, 18.0f);
            value.textAlignment = NSTextAlignmentLeft;
        }

        // Кастомные подписи внутри PS-ячейки (имя сети Wi-Fi и т.п.): штатный
        // layoutSubviews уже отработал, поэтому правим ЗДЕСЬ — иначе ячейка
        // вернёт свои отступы и синий системный цвет обратно.
        for (UIView *sub in cell.contentView.subviews) {
            if (![sub isKindOfClass:[UILabel class]] || sub == title || sub == value) continue;
            UILabel *l = (UILabel *)sub;
            CGRect f = l.frame;
            if (f.origin.x < textInset) {
                f.size.width = MAX(0.0f, f.size.width - (textInset - f.origin.x));
                f.origin.x = textInset;
                l.frame = f;
            }
            if (!MPCGColorIsRed(l.textColor)) l.textColor = [UIColor whiteColor];
            l.shadowColor = nil;
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] layoutCell: %@ (%@)", e.name, e.reason);
    }
}

#pragma mark - Глубокая перекраска одной ячейки

+ (void)mp_repairBrokenLabelsAndFields:(UITableViewCell *)cell {
    // 17B: у DNDSwitchCell (корень) и PSEditableTableCell (App Store, «Пароль»)
    // метка выходит с x = −8 и шириной 14 pt — на экране видно «l.»/«L.», а поле
    // ввода вообще имеет нулевой кадр. Чиним точечно, по признаку поломки.
    UIView *cv = cell.contentView;
    if (cv == nil) return;
    CGFloat cvW = cv.bounds.size.width;
    CGFloat targetX = 16.0f - cv.frame.origin.x;
    if (targetX < 0.0f) targetX = 0.0f;

    UILabel *mainLabel = nil;
    for (UIView *v in cv.subviews) {
        if (![v isKindOfClass:[UILabel class]]) continue;
        UILabel *l = (UILabel *)v;
        if (l.text.length == 0) continue;
        BOOL broken = (l.frame.origin.x < 0.0f) ||
                      (l.frame.size.width < 40.0f && l.text.length > 2);
        if (broken) {
            CGRect f = l.frame;
            f.origin.x = targetX;
            f.size.width = cvW - targetX - 120.0f;      // место под тумблер/контрол
            if (f.size.width < 80.0f) f.size.width = cvW - targetX - 16.0f;
            f.origin.y = (cv.bounds.size.height - f.size.height) / 2.0f;
            l.frame = f;
        }
        if (mainLabel == nil) mainLabel = l;
    }

    for (UIView *v in cv.subviews) {
        if (![v isKindOfClass:[UITextField class]]) continue;
        UITextField *fld = (UITextField *)v;
        if (fld.frame.size.width >= 40.0f && fld.frame.size.height >= 10.0f) continue;
        CGFloat x = mainLabel ? CGRectGetMaxX(mainLabel.frame) + 8.0f : targetX;
        if (x < targetX) x = targetX;
        fld.frame = CGRectMake(x, 12.0f, cvW - x - 16.0f, 30.0f);
    }
}

+ (void)mp_normalizeAccessory:(UITableViewCell *)cell {
    // Кнопка-шеврон (Wi-Fi, Bluetooth) приходит с отступом 10 pt от края: её кадр
    // считают в координатах ячейки, а лежит она то в ячейке, то в contentView (сдвиг 10).
    // Правим в обоих случаях: правый край — 16 pt от края экрана, как слева.
    UIView *cv = cell.contentView;
    NSArray *hosts = cv != nil ? @[cell, cv] : @[cell];
    for (UIView *host in hosts) {
        CGFloat inset = 16.0f - host.frame.origin.x;
        if (inset < 2.0f) inset = 2.0f;
        for (UIView *v in host.subviews) {
            if (![v isKindOfClass:[UIButton class]]) continue;
            CGRect f = v.frame;
            if (f.size.width < 36.0f || f.size.width > 56.0f || f.size.height < 36.0f) continue;
            CGFloat x = host.bounds.size.width - f.size.width - inset;
            if (x < 0.0f || fabsf(f.origin.x - x) < 0.5f) continue;
            f.origin.x = x;
            v.frame = f;
        }
    }
}

// Иконки Wi-Fi-строк: замок (глиф Metro) и уровень сети (полоски).
// Решение 27.10 «иконок нет» остаётся для остальных строк — здесь исключение по прямой просьбе.
static UIImage *MPSignalBarsImage(NSInteger level) {
    static NSMutableDictionary *cache = nil;
    if (cache == nil) cache = [NSMutableDictionary dictionary];
    if (level < 1) level = 1;
    if (level > 4) level = 4;
    NSString *key = [NSString stringWithFormat:@"sig-%ld", (long)level];
    UIImage *cached = [cache objectForKey:key];
    if (cached != nil) return cached;
    CGFloat heights[4] = {4.0f, 6.0f, 9.0f, 12.0f};
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(18.0f, 12.0f), NO, 0.0f);
    for (int i = 0; i < 4; i++) {
        UIColor *c = (i < level) ? [UIColor colorWithWhite:1.0f alpha:0.92f]
                                 : [UIColor colorWithWhite:1.0f alpha:0.22f];
        [c setFill];
        UIRectFill(CGRectMake(i * 5.0f, 12.0f - heights[i], 3.0f, heights[i]));
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img != nil) [cache setObject:img forKey:key];
    return img;
}

static id MPValueForKeySafe(id obj, NSString *key) {
    if (obj == nil) return nil;
    @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}

// Уровень сети: пробуем открытые KVC-ключи ячейки и её network, иначе 3 полоски.
static NSInteger MPNetworkLevel(UITableViewCell *cell) {
    NSArray *keys = @[@"signalStrength", @"strength", @"bars", @"scaledRSSI", @"rssi"];
    id net = MPValueForKeySafe(cell, @"network");
    for (id obj in (net != nil ? @[cell, net] : @[cell])) {
        for (NSString *k in keys) {
            id v = MPValueForKeySafe(obj, k);
            if ([v respondsToSelector:@selector(integerValue)]) {
                NSInteger n = [v integerValue];
                // 0 система отдаёт и когда сеть «без уровня» — считаем это неизвестным
                if (n >= 1 && n <= 4) return n;
            }
        }
    }
    return 3;
}

+ (void)mp_styleNetworkRow:(UITableViewCell *)cell {
    if (![NSStringFromClass([cell class]) isEqualToString:@"APTableCell"]) return;
    UIView *cv = cell.contentView;
    if (cv == nil) return;

    // Имя сети: видимая метка с текстом, не «Другая…» и не служебная строка.
    UILabel *nameLabel = nil;
    for (UIView *v in cv.subviews) {
        if (![v isKindOfClass:[UILabel class]]) continue;
        UILabel *l = (UILabel *)v;
        if (l.hidden || l.text.length == 0) continue;
        if ([l.text hasPrefix:@"Другая"] || [l.text hasSuffix:@"…"]) continue;
        nameLabel = l;
        break;
    }
    if (nameLabel == nil) {
        // «Другая…» и служебные строки без имени: ячейка могла быть переиспользована
        // из сети — прячем наши полоски/замок, иначе они остаются висеть.
        UIImageView *staleSig = (UIImageView *)[cell viewWithTag:MPSigTag];
        UIImageView *staleLock = (UIImageView *)[cell viewWithTag:MPLockTag];
        if (staleSig != nil) staleSig.hidden = YES;
        if (staleLock != nil) staleLock.hidden = YES;
        return;
    }

    // 83B: подключённая сеть приходит с системным синим tint — в нашем списке имя белое.
    nameLabel.textColor = [UIColor whiteColor];

    // Замок есть, если у системного значка (11×15) есть картинка — сеть с паролем.
    BOOL secured = NO;
    for (UIView *v in cv.subviews) {
        if (![v isKindOfClass:[UIImageView class]]) continue;
        if (v.frame.size.width > 18.0f || v.frame.size.height < 12.0f) continue;
        if (((UIImageView *)v).image != nil) { secured = YES; break; }
    }
    NSInteger level = MPNetworkLevel(cell);

    // Правый край: перед шевроном, если он есть, иначе 16 pt от края экрана.
    CGFloat right = cell.bounds.size.width - 16.0f;
    for (UIView *v in cell.subviews) {
        if (![v isKindOfClass:[UIButton class]]) continue;
        if (v.frame.size.width < 36.0f || v.frame.size.width > 56.0f) continue;
        right = v.frame.origin.x - 8.0f;
        break;
    }
    CGFloat sigX = right - 18.0f;
    CGFloat lockX = sigX - 6.0f - 14.0f;
    CGFloat midY = (cell.bounds.size.height - 14.0f) / 2.0f;

    UIImageView *lock = (UIImageView *)[cell viewWithTag:MPLockTag];
    if (secured) {
        if (lock == nil) {
            lock = [[UIImageView alloc] initWithImage:MPGlyphImage(0xe660, 14.0f)];
            lock.tag = MPLockTag;
            [cell addSubview:lock];
        }
        lock.hidden = NO;
        lock.frame = CGRectMake(lockX, midY + 0.5f, 14.0f, 14.0f);
    } else if (lock != nil) {
        lock.hidden = YES;
    }

    UIImageView *sig = (UIImageView *)[cell viewWithTag:MPSigTag];
    if (sig == nil) {
        sig = [[UIImageView alloc] init];
        sig.tag = MPSigTag;
        [cell addSubview:sig];
    }
    sig.hidden = NO;      // APTableCell прячет добавленные вьюхи — показываем явно
    lock.hidden = secured ? NO : YES;
    sig.image = MPSignalBarsImage(level);
    sig.frame = CGRectMake(sigX, (cell.bounds.size.height - 12.0f) / 2.0f, 18.0f, 12.0f);

    // Длинное имя не должно заезжать под замок: режем метку по его левому краю,
    // но никогда не сужаем её до нуля — иначе название пропадает совсем.
    CGFloat textRight = lockX - 8.0f - cv.frame.origin.x;
    if (textRight > 60.0f) {
        CGRect nf = nameLabel.frame;
        CGFloat newW = textRight - nf.origin.x;
        if (newW >= 120.0f && nf.origin.x + nf.size.width > textRight) {
            nf.size.width = newW;
            nameLabel.frame = nf;
        }
    }
}

+ (void)styleCellDeep:(UITableViewCell *)cell {
    @try {
        [self mp_repairBrokenLabelsAndFields:cell];
        [self mp_normalizeAccessory:cell];
        [self mp_styleNetworkRow:cell];
        for (UIView *v in cell.contentView.subviews) {
            [self mp_recolorView:v];
        }
        for (UIView *v in cell.subviews) {
            if (v == cell.contentView) continue;
            [self mp_recolorView:v];
        }
        [self mp_alignCustomLabels:cell];
        [self mp_styleEmbeddedControls:cell];
    } @catch (NSException *e) {
        // не критично
    }
}

// Контролы ВНУТРИ кастомных ячеек (ползунок громкости «Звуков» живёт не в
// PS-ячейке): ищем по всему дереву и оформляем как положено
+ (void)mp_styleEmbeddedControls:(UITableViewCell *)cell {
    NSArray *frontier = [NSArray arrayWithObjects:cell, nil];
    while (frontier.count > 0) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in frontier) {
            if ([v isKindOfClass:[UISlider class]]) {
                [MPSettingsTheme styleSlider:(UISlider *)v];
                // Растягиваем на всю ширину строки: у родного ползунка ширина
                // короче строки, и справа остаётся пустое место
                UIView *host = v.superview;
                if (host != nil && host.bounds.size.width > 100.0f) {
                    CGRect f = v.frame;
                    // 16 pt от края экрана, а не от contentView (он сдвинут на 10)
                    CGFloat inset = 16.0f - host.frame.origin.x;
                    if (inset < 2.0f) inset = 2.0f;
                    CGFloat right = host.bounds.size.width - inset;
                    if (f.origin.x + f.size.width < right - 2.0f) {
                        f.size.width = right - f.origin.x;
                        v.frame = f;
                    }
                }
            } else if ([v isKindOfClass:[UISwitch class]]) {
                MPSettingsToggle *tg = [MPSettingsToggle attachedToggleForSwitch:(UISwitch *)v];
                [tg syncFrameFromSwitch];
                [tg syncFromSwitch];
            }
            [next addObjectsFromArray:v.subviews];
        }
        frontier = next;
    }
}

// Квадратный акцентный «›» на месте круглого синего диска. Работает и для
// UIButton (убираем глянцевую картинку), и для UIImageView (просто вьюха с
// картинкой диска) — в этом случае пристраиваем метку со стрелкой.
static void MPMakeDiscAccent(UIView *v, CGFloat w, CGFloat h) {
    // Вместо глянцевого синего диска iOS — белая стрелка из набора Windows Phone
    UIImage *chev = MPGlyphImage(0xe69b, 28.0f);
    v.backgroundColor = [UIColor clearColor];
    v.layer.cornerRadius = 0.0f;
    if ([v isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)v;
        [btn setBackgroundImage:nil forState:UIControlStateNormal];
        [btn setBackgroundImage:nil forState:UIControlStateHighlighted];
        [btn setTitle:nil forState:UIControlStateNormal];
        if (chev != nil) [btn setImage:chev forState:UIControlStateNormal];
    } else if ([v isKindOfClass:[UIImageView class]]) {
        if (chev != nil) ((UIImageView *)v).image = chev;
        for (UIView *sub in v.subviews) sub.hidden = YES;   // старые накладки не нужны
    }
}

+ (void)mp_recolorView:(UIView *)v inControl:(BOOL)inControl {
    // круглый синий диск «›» у подключённых сетей/устройств: ловим по форме
    // (квадратные границы ~14–30 pt). Он бывает UIButton с глянцем (рамка/круг
    // не гарантированы) и UIImageView с картинкой — для картинки различаем
    // по синему цвету (замки/сигналы — серые, диски — синие)
    // Аксессуар-кнопка справа (глянцевый диск iOS, 40×55 и т.п.) → WP-стрелка
    if ([v isKindOfClass:[UIButton class]] && v.frame.origin.x > 200.0f &&
        v.bounds.size.width <= 60.0f && v.bounds.size.height <= 60.0f) {
        UIImage *chev = MPGlyphImage(0xe69b, 28.0f);
        UIButton *btn = (UIButton *)v;
        [btn setBackgroundImage:nil forState:UIControlStateNormal];
        [btn setBackgroundImage:nil forState:UIControlStateHighlighted];
        [btn setTitle:nil forState:UIControlStateNormal];
        if (chev != nil) [btn setImage:chev forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor clearColor];
        v.layer.cornerRadius = 0.0f;
        for (UIView *sub in v.subviews) if ([sub isKindOfClass:[UIImageView class]]) sub.hidden = YES;
    }
    CGFloat vw = v.bounds.size.width, vh = v.bounds.size.height;
    // Кружок «›» бывает не идеально квадратным (29×31 у Wi-Fi): допускаем 4 pt
    BOOL squareSmall = (vw >= 14.0f && vw <= 34.0f && fabsf(vw - vh) <= 4.0f);
    if (squareSmall && ![v isKindOfClass:[UILabel class]]) {
        BOOL isButton = [v isKindOfClass:[UIButton class]];
        BOOL isCircle = (v.layer.cornerRadius >= vw / 2.0f - 1.5f);
        BOOL isBlueImage = NO;
        if (!isButton && !isCircle && [v isKindOfClass:[UIImageView class]]) {
            isBlueImage = [self mp_imageLooksBlue:((UIImageView *)v).image];
        }
        // Аксессуар «›» в ячейке Wi-Fi — это картинка внутри UIButton и почти
        // квадрат; сама картинка бывает синей с белым кольцом, поэтому
        // цветовой тест её не ловит — узнаём по вложенности и размеру
        BOOL accessoryDisc = (vw >= 20.0f && [v.superview isKindOfClass:[UIButton class]] &&
                              v.superview.bounds.size.width <= 60.0f);
        MPLog(@"[disc] %@ %gx%g corner=%.1f btn=%d circle=%d blue=%d",
              NSStringFromClass([v class]), vw, vh, v.layer.cornerRadius,
              isButton, isCircle, isBlueImage);
        if (isButton || isCircle || isBlueImage || accessoryDisc) {
            MPMakeDiscAccent(v, vw, vh);
            return;   // внутрь диска не идём
        }
    }
    // Внутри контролов (слайдер, свитч) мелкие UIImageView — это треки и бегунок:
    // скрытие «мелких иконок» убивало ползунки громкости и яркости целиком.
    if (!inControl && [v isKindOfClass:[UIImageView class]] && v.bounds.size.width <= 24.0f &&
        v.tag != MPLockTag && v.tag != MPSigTag &&
        !MPIsOurGlyph(((UIImageView *)v).image) &&
        ![v.superview isKindOfClass:[UIButton class]]) {
        v.hidden = YES;   // без мелких иконок: ровный левый край и никаких тёмных значков
    }
    if ([v isKindOfClass:[UIImageView class]]) {
        // Мелкие служебные иконки (замок, значок Wi-Fi) НЕ тинтуем: в iOS 6 они
        // непрозрачные, и заливка SourceIn превращала их в сплошные квадраты.
        // Серый цвет оригинала на чёрном читается нормально.
    }
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        CGFloat r1=0,g1=0,b1=0,a1=0;
        BOOL parsed = [l.textColor getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
        BOOL isRed  = parsed && (r1 > 0.7f && g1 < 0.35f && b1 < 0.35f);
        // серая семья (белый/серый/чёрный) остаётся — значения и подписи
        BOOL isGray = parsed && (fabsf(r1 - g1) < 0.08f && fabsf(g1 - b1) < 0.08f);
        if (!parsed || (!isRed && !isGray)) {
            l.textColor = [UIColor whiteColor];   // синие/цветные → белые
            // Жирные подписи (названия VPN-конфигураций) — в тонкий шрифт проекта
            if ([l.font.fontName rangeOfString:@"Bold"].location != NSNotFound ||
                [l.font.fontName rangeOfString:@"Semibold"].location != NSNotFound) {
                l.font = [MPMetroStyle lightFont:l.font.pointSize];
            }
        }
        l.shadowColor = nil;
    }
    BOOL subInControl = inControl || [v isKindOfClass:[UISlider class]] ||
                        [v isKindOfClass:[UISwitch class]];
    for (UIView *sub in v.subviews) [self mp_recolorView:sub inControl:subInControl];
}

// Обёртка для внешних вызовов: корень дерева — не внутри контрола
+ (void)mp_recolorView:(UIView *)v {
    [self mp_recolorView:v inControl:NO];
}

// Синяя ли картинка (глянцевый синий диск iOS): рисуем в 8×8 и считаем
// сине-доминантные пиксели. Серые замки/сигналы дают NO.
+ (BOOL)mp_imageLooksBlue:(UIImage *)image {
    if (image == nil) return NO;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(8.0f, 8.0f), NO, 1.0f);
    [image drawInRect:CGRectMake(0.0f, 0.0f, 8.0f, 8.0f)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRef cg = small.CGImage;
    if (cg == NULL) return NO;
    NSUInteger w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    if (w == 0 || h == 0) return NO;
    NSUInteger bytesPerRow = w * 4;
    unsigned char *px = (unsigned char *)malloc(bytesPerRow * h);
    if (px == NULL) return NO;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, bytesPerRow, space,
        kCGImageAlphaPremultipliedLast);
    CFRelease(space);                 // контекст копирует пространство — не отпускали, текло
    BOOL blue = NO;
    if (ctx != NULL) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
        int blueCount = 0, total = 0;
        for (NSUInteger y = 0; y < h; y++) {
            for (NSUInteger x = 0; x < w; x++) {
                unsigned char *p = px + y * bytesPerRow + x * 4;
                if (p[3] < 200) continue;                 // прозрачное
                total++;
                if (p[2] > 110 && p[2] > p[0] + 30 && p[2] > p[1] + 20) blueCount++;
            }
        }
        blue = (total > 8 && blueCount * 2 > total);
        CFRelease(ctx);
    }
    free(px);
    return blue;
}

// «Парение» по-Zune: при нажатии у текста строки появляется лёгкая светлая
// тень (никаких подложек). Вызывается из хука PSTableCell setHighlighted:.
+ (void)applyFloatingEffect:(BOOL)highlighted toCell:(UITableViewCell *)cell {
    @try {
        UIColor *shadow = highlighted ? [UIColor colorWithWhite:1.0f alpha:0.65f] : nil;
        CGSize offset = highlighted ? CGSizeMake(0.0f, 1.0f) : CGSizeZero;

        NSArray *labels = nil;
        if ([cell isKindOfClass:NSClassFromString(@"PSTableCell")]) {
            NSMutableArray *m = [NSMutableArray array];
            UILabel *title = [cell respondsToSelector:@selector(titleLabel)] ? (UILabel *)[cell performSelector:@selector(titleLabel)] : nil;
            UILabel *value = [cell respondsToSelector:@selector(valueLabel)] ? (UILabel *)[cell performSelector:@selector(valueLabel)] : nil;
            if (title != nil) [m addObject:title];
            if (value != nil) [m addObject:value];
            for (UIView *v in cell.contentView.subviews) {
                if ([v isKindOfClass:[UILabel class]] && ![m containsObject:v]) [m addObject:v];
            }
            labels = m;
        } else {
            NSMutableArray *m = [NSMutableArray array];
            if (cell.textLabel != nil) [m addObject:cell.textLabel];
            if (cell.detailTextLabel != nil) [m addObject:cell.detailTextLabel];
            labels = m;
        }
        for (UILabel *l in labels) {
            l.shadowColor = shadow;
            l.shadowOffset = offset;
        }
    } @catch (NSException *e) {
        // не критично
    }
}

// Кастомные ячейки (сети Wi-Fi, устройства Bluetooth) ставят свои лейблы с
// системным отступом ~10 pt — выравниваем текст на общие 16 pt от края экрана.
// Лейбл может лежать во вложенном контейнере — ищем рекурсивно в координатах
// contentView, сдвигаем целый контейнер (вместе с лейблом).
+ (void)mp_alignCustomLabels:(UITableViewCell *)cell {
    if ([cell isKindOfClass:NSClassFromString(@"PSTableCell")]) return;   // PS-ячейки правит layoutPSTableCell
    UIView *cv = cell.contentView;
    if (cv == nil) return;
    CGFloat target = 16.0f - cv.frame.origin.x;
    if (target < 0.0f) target = 0.0f;

    // самый левый текст: ищем во всём дереве, координаты приводим к contentView
    UIView *main = nil;
    CGFloat mainX = 1e9f;
    NSMutableArray *frontier = [NSMutableArray arrayWithObject:cv];
    while (frontier.count > 0) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in frontier) {
            if ([v isKindOfClass:[UILabel class]]) {
                CGPoint p = [cv convertPoint:v.frame.origin fromView:v.superview];
                if (p.x < mainX) { mainX = p.x; main = v; }
            }
            [next addObjectsFromArray:v.subviews];
        }
        frontier = next;
    }
    if (main == nil || mainX < 0.0f || mainX >= target - 0.5f) return;

    // сдвигаем ближайшего предка-контейнер целиком (чтобы не ломать внутреннюю
    // геометрию лейбла), если это возможно; иначе сам лейбл
    UIView *mover = main;
    while (mover.superview != nil && mover.superview != cv &&
           mover.superview.frame.origin.x == mover.frame.origin.x) {
        mover = mover.superview;   // контейнер совпадает по X — двигаем его
    }
    CGFloat shift = target - mainX;
    CGRect f = mover.frame;
    if (f.size.width - shift > 40.0f) {
        f.origin.x += shift;
        f.size.width -= shift;
        mover.frame = f;
    }
}

// Белый тинт произвольного маленького изображения (замок, сигнал и т.п.)
+ (UIImage *)mp_whiteTintedImage:(UIImage *)image {
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGRect r = CGRectMake(0.0f, 0.0f, image.size.width, image.size.height);
    [image drawInRect:r];
    // SourceIn: закрашиваем непрозрачные пиксели белым, сохраняя альфу
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetBlendMode(ctx, kCGBlendModeSourceIn);
    [[UIColor colorWithWhite:1.0f alpha:0.92f] setFill];
    UIRectFill(r);
    UIImage *out_ = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out_;
}

#pragma mark - Универсальные ячейки

+ (void)styleGenericCell:(UITableViewCell *)cell {
    @try {
        cell.backgroundColor = [UIColor blackColor];
        if (cell.backgroundView != nil) cell.backgroundView = nil;
        cell.selectedBackgroundView = [MPSettingsTheme flatSelectionBackground];

        if (cell.textLabel != nil) {
            if (!MPCGColorIsRed(cell.textLabel.textColor)) {
                cell.textLabel.textColor = [UIColor whiteColor];
            }
            cell.textLabel.shadowColor = nil;
        }
        if (cell.detailTextLabel != nil) {
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
            cell.detailTextLabel.shadowColor = nil;
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] genericCell: %@ (%@)", e.name, e.reason);
    }
}

#pragma mark - Поля ввода

+ (void)styleTextField:(UITextField *)field {
    @try {
        // тёмная клавиатура (пароли Wi-Fi и т.п.)
        field.keyboardAppearance = UIKeyboardAppearanceAlert;
        // белый текст, если ещё не задан осмысленный цвет
        UIColor *tc = field.textColor;
        if (tc == nil || [tc isEqual:[UIColor blackColor]]) {
            field.textColor = [UIColor whiteColor];
        }
        // плоское подчёркивание вместо рамки
        field.borderStyle = UITextBorderStyleNone;
        field.backgroundColor = [UIColor clearColor];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] textField: %@ (%@)", e.name, e.reason);
    }
}

@end

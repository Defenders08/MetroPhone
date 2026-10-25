#import "MPSettingsCellStyler.h"
#import "MPSettingsTheme.h"
#import "MPSettingsToggle.h"

static const CGFloat MPCellStyleInset = 16.0f;

// Красный ли цвет (опасные действия — цвет сохраняем, перекрашиваем только чёрный/серый/синий)
static BOOL MPCGColorIsRed(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return (r > 0.7f && g < 0.35f && b < 0.35f);
}

@implementation MPSettingsCellStyler

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
            if (!MPCGColorIsRed(title.textColor)) {            // красные («Стереть…») не трогаем
                title.textColor = cell.isUserInteractionEnabled ? [UIColor whiteColor]
                                              : [UIColor colorWithWhite:1.0f alpha:0.4f];
            }
            title.backgroundColor = [UIColor clearColor];
            title.shadowColor = nil;
        }
        if (value != nil) {
            value.font = [MPMetroStyle regularFont:13.0f];
            value.textColor = [UIColor colorWithWhite:1.0f alpha:0.6f];
            value.backgroundColor = [UIColor clearColor];
            value.shadowColor = nil;
        }

        // иконки слева скрываем (WP-список без иконок); imageView не удаляем
        cell.imageView.hidden = YES;

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

        if (title != nil) {
            CGFloat titleY = hasValue ? 6.0f : (b.size.height - 30.0f) / 2.0f;
            title.frame = CGRectMake(inset, titleY,
                                     rightLimit - inset, 30.0f);
        }
        if (value != nil && hasValue) {
            // значение iOS «справа» переносится ПОД заголовок серым
            value.frame = CGRectMake(inset + 1.0f, CGRectGetMaxY(title.frame) - 2.0f,
                                     b.size.width - inset * 2.0f, 18.0f);
            value.textAlignment = NSTextAlignmentLeft;
        }
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] layoutCell: %@ (%@)", e.name, e.reason);
    }
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
        if (field.placeholder != nil) {
            field.placeholder = field.placeholder; // текст не меняем
        }
        // плоское подчёркивание вместо рамки
        field.borderStyle = UITextBorderStyleNone;
        field.backgroundColor = [UIColor clearColor];
    } @catch (NSException *e) {
        NSLog(@"[MetroPhone][Settings] textField: %@ (%@)", e.name, e.reason);
    }
}

@end

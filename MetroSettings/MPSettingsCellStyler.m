#import "MPSettingsCellStyler.h"
#import "MPSettingsTheme.h"

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
        UIView *control = nil;
        for (UIView *v in cell.contentView.subviews) {
            if ([v isKindOfClass:[UISwitch class]] || [v isKindOfClass:[UISlider class]] ||
                [v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UISegmentedControl class]]) {
                control = v;
                break;
            }
        }
        CGFloat rightLimit = b.size.width - MPCellStyleInset;
        if (control != nil) {
            rightLimit = MIN(rightLimit, control.frame.origin.x - 8.0f);
        }

        if (title != nil) {
            CGFloat titleY = hasValue ? 6.0f : (b.size.height - 30.0f) / 2.0f;
            title.frame = CGRectMake(MPCellStyleInset, titleY,
                                     rightLimit - MPCellStyleInset, 30.0f);
        }
        if (value != nil && hasValue) {
            // значение iOS «справа» переносится ПОД заголовок серым
            value.frame = CGRectMake(MPCellStyleInset + 1.0f, CGRectGetMaxY(title.frame) - 2.0f,
                                     b.size.width - MPCellStyleInset * 2.0f, 18.0f);
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

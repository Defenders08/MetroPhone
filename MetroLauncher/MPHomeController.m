#import "MPHomeController.h"
#import "MPTilesPageView.h"
#import "MPAppListPageView.h"
#import "MPMetroStyle.h"
#import "MPAppDataSource.h"

// Поиск контейнера для лаунчера. Класс SBScreenView ищется только по ИМЕНИ (строковое сравнение),
// никаких сообщений приватным классам не отправляется. Дублирует MPFindScreenView из Tweak.xm,
// потому что та функция static и из этого файла недоступна.
static UIView *MPHCFindHostView(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        for (UIView *v in w.subviews) {
            if ([NSStringFromClass([v class]) isEqualToString:@"SBScreenView"]) return v;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

@implementation MPHomeController {
    UIScrollView     *_pager;
    MPTilesPageView  *_tilesPage;
    MPAppListPageView *_listPage;
    UIButton         *_toggleButton;     // «M» на родном столе

    BOOL _visible;
    BOOL _contentScheduled;
    BOOL _contentLoaded;
    NSInteger _loadAttempts;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        // Только подписка — никакого UIKit в init.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(appsChanged:)
                                                     name:MPAppsChangedNotification
                                                   object:nil];
        MPLog(@"контроллер создан");
    }
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Вьюха

- (void)loadView {
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    // Вью на весь экран (чёрный фон закрывает и область под статус-баром),
    // а содержимое страниц отступает на applicationFrame.origin.y.
    CGFloat top = [MPMetroStyle statusBarInset];

    UIView *root = [[UIView alloc] initWithFrame:bounds];
    root.backgroundColor = [UIColor blackColor];
    self.view = root;

    _pager = [[UIScrollView alloc] initWithFrame:bounds];
    _pager.backgroundColor = [UIColor blackColor];
    _pager.pagingEnabled = YES;
    _pager.showsHorizontalScrollIndicator = NO;
    _pager.showsVerticalScrollIndicator = NO;
    _pager.directionalLockEnabled = YES;
    _pager.delaysContentTouches = NO;      // касания сразу уходят странице плиток
    _pager.contentSize = CGSizeMake(w * 2.0f, h);
    [root addSubview:_pager];

    _tilesPage = [[MPTilesPageView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _tilesPage.topInset = top;
    __weak MPHomeController *weakSelf = self;
    _tilesPage.editingChangedBlock = ^(BOOL editing) {
        MPHomeController *c = weakSelf;
        if (c != nil) c->_pager.scrollEnabled = !editing;      // в правке свайп между страницами выключен
    };
    [_pager addSubview:_tilesPage];

    _listPage = [[MPAppListPageView alloc] initWithFrame:CGRectMake(w, 0, w, h)];
    _listPage.topInset = top;
    [_listPage.iOSButton addTarget:self action:@selector(iosButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_pager addSubview:_listPage];
}

#pragma mark - Установка

- (void)installLauncherView {
    UIView *v = self.view;
    if (v.superview != nil) return;
    // Главное окно берём из хука SBWallpaperView (в iOS 6.1 sharedApplication.windows
    // пуст, а класса SBScreenView не существует) — см. MPSharedHostWindow.
    UIView *host = MPSharedHostWindow();
    if (host == nil) host = MPHCFindHostView();
    if (host == nil) {
        UIWindow *key = [UIApplication sharedApplication].keyWindow;
        MPLog(@"установка: окно не захвачено (keyWindow=%d, окон=%d) — повтор через 15 с",
              key != nil, (int)[UIApplication sharedApplication].windows.count);
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(installLauncherView) object:nil];
        [self performSelector:@selector(installLauncherView) withObject:nil afterDelay:15.0];
        return;
    }
    v.alpha = 0.0f;
    v.hidden = YES;
    [host addSubview:v];
    [self addMetroToggleButtonToView:host];
    MPLog(@"вьюха установлена в %@", NSStringFromClass([host class]));
}

- (void)addMetroToggleButtonToView:(UIView *)nativeView {
    if (_toggleButton != nil || nativeView == nil) return;
    CGFloat w = nativeView.bounds.size.width;
    _toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _toggleButton.frame = CGRectMake(w - 24.0f - 4.0f, 22.0f, 24.0f, 24.0f);
    _toggleButton.backgroundColor = [[MPMetroStyle accentColor] colorWithAlphaComponent:0.6f];
    [_toggleButton setTitle:@"M" forState:UIControlStateNormal];
    [_toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _toggleButton.titleLabel.font = [MPMetroStyle mediumFont:13.0f];
    [_toggleButton addTarget:self action:@selector(metroButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    _toggleButton.hidden = _visible;                         // виден, только когда Metro спрятан
    [nativeView addSubview:_toggleButton];
}

#pragma mark - Показ / скрытие

- (BOOL)isMetroVisible { return _visible; }

- (void)showMetroAnimated:(BOOL)animated {
    [MPMetroStyle reloadPreferences];
    if (![MPMetroStyle isEnabled]) {          // твик выключен в настройках
        [self hideMetroAnimated:NO];
        return;
    }
    MPLog(@"показать Metro (animated=%d)", animated ? 1 : 0);

    UIView *v = self.view;
    if (v.superview == nil) [self installLauncherView];
    if (v.superview == nil) return;

    _visible = YES;
    [v.superview bringSubviewToFront:v];
    _toggleButton.hidden = YES;

    if (_contentLoaded) [self applyStyleToPages];
    else [self scheduleContentLoad];

    v.hidden = NO;
    if (animated && v.alpha < 1.0f) {
        [UIView animateWithDuration:0.25 delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ v.alpha = 1.0f; } completion:nil];
    } else {
        v.alpha = 1.0f;
    }
}

- (void)hideMetroAnimated:(BOOL)animated {
    MPLog(@"спрятать Metro (animated=%d)", animated ? 1 : 0);
    _visible = NO;
    [_tilesPage exitEditingIfNeeded];          // правка завершается с сохранением
    [_listPage dismissKeyboard];

    if (_toggleButton != nil) {
        _toggleButton.backgroundColor = [[MPMetroStyle accentColor] colorWithAlphaComponent:0.6f];
        _toggleButton.hidden = ![MPMetroStyle isEnabled];
        [_toggleButton.superview bringSubviewToFront:_toggleButton];
    }

    UIView *v = self.view;
    if (v.superview == nil) return;
    if (animated && !v.hidden) {
        [UIView animateWithDuration:0.25 delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ v.alpha = 0.0f; }
                         completion:^(BOOL finished) {
                             if (!_visible) v.hidden = YES;      // за время fade мог быть показан снова
                         }];
    } else {
        v.alpha = 0.0f;
        v.hidden = YES;
    }
}

- (void)metroButtonTapped { [self showMetroAnimated:YES]; }

- (void)homeButtonPressed {
    // как «назад» в WP8: Home завершает правку стартового экрана
    [_tilesPage exitEditingIfNeeded];
}
- (void)iosButtonTapped   { [self hideMetroAnimated:YES]; }

#pragma mark - Ленивая загрузка содержимого

// Содержимое не грузится на старте SpringBoard: сначала пауза, затем сборка плиток пачками.
- (void)scheduleContentLoad {
    if (_contentLoaded || _contentScheduled) return;
    _contentScheduled = YES;
    [self performSelector:@selector(loadContent) withObject:nil afterDelay:0.3];
}

- (void)loadContent {
    _contentScheduled = NO;
    if (_contentLoaded) return;

    // датасорс умеет читать иконки только внутри SpringBoard — в чужом
    // UIKit-процессе лаунчер должен молчать
    if (NSClassFromString(@"SBIconView") == nil) return;

    NSArray *apps = [[MPAppDataSource sharedDataSource] allApps];
    if (apps.count == 0) {
        // Модель иконок SpringBoard ещё не готова — повторяем (не затирая раскладку пустым списком).
        if (_loadAttempts++ < 20) {
            MPLog(@"список приложений пуст, повтор %ld", (long)_loadAttempts);
            _contentScheduled = YES;
            [self performSelector:@selector(loadContent) withObject:nil afterDelay:1.0];
        } else {
            MPLog(@"ОШИБКА: список приложений так и не появился");
        }
        return;
    }
    _contentLoaded = YES;
    [self view];                                // гарантируем, что вьюха и страницы созданы
    [self applyStyleToPages];
    [_listPage reloadApps:apps];
    [_tilesPage ensureLoadedWithApps:apps];
    MPLog(@"содержимое загружено, приложений: %lu", (unsigned long)apps.count);
}

- (void)applyStyleToPages {
    [_tilesPage applyStyle];
    [_listPage applyStyle];
}

#pragma mark - Изменение списка / бейджей

- (void)appsChanged:(NSNotification *)n {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self appsChanged:n]; });
        return;
    }
    if (!_contentLoaded) return;
    // noteBadgeDidChange сыплется пачками — склеиваем в одно обновление.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadAppsNow) object:nil];
    [self performSelector:@selector(reloadAppsNow) withObject:nil afterDelay:0.4];
}

- (void)reloadAppsNow {
    if (!_contentLoaded) return;
    NSArray *apps = [[MPAppDataSource sharedDataSource] allApps];
    [_listPage reloadApps:apps];
    [_tilesPage syncWithApps:apps];
}

@end

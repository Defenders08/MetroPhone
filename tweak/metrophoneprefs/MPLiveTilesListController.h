#import <Preferences/Preferences.h>

// Страница «Виджеты» (Настройки → MetroPhone → Живые плитки → Настройка виджетов):
// PSSwitchCell вкл/выкл на каждый виджет (LiveTiles.plist, Darwin-пост после
// каждого переключения) + кастомный футер MPLiveTileSizeView с размерами.
@interface MPLiveTilesListController : PSListController
@end

#import <Foundation/Foundation.h>

// Размеры плиток Windows Phone 8: занимают ячейки базовой 4-колоночной сетки
typedef enum {
    MPTileSizeSmall  = 0,   // 1×1 — квадрат с одну ячейку
    MPTileSizeMedium = 1,   // 2×2 — квадрат с 4 маленькие плитки
    MPTileSizeWide   = 2,   // 4×2 — во всю ширину сетки, высотой с Medium
} MPTileSize;

// Пролёты плитки по сетке (в ячейках): ширина и высота
NSUInteger MPTileSpanX(MPTileSize size);
NSUInteger MPTileSpanY(MPTileSize size);

// Один тайл раскладки. col/row заполняются упаковкой (packWithColumns:).
@interface MPTileItem : NSObject
@property (nonatomic, copy)     NSString *bundleID;
@property (nonatomic, assign)   MPTileSize tileSize;   // small / medium / wide
@property (nonatomic, assign)   NSInteger col;
@property (nonatomic, assign)   NSInteger row;
@end

// Модель раскладки: порядок тайлов, размеры, чтение/запись plist, упаковка.
@interface MPLayoutModel : NSObject

@property (nonatomic, readonly) NSMutableArray *items;   // NSMutableArray<MPTileItem *>, порядок = order
@property (nonatomic, readonly) NSInteger rowCount;      // число занятых рядов после упаковки

+ (NSString *)layoutPath;                                // /var/mobile/Library/Preferences/metrophone-layout.plist
+ (MPLayoutModel *)sharedModel;                           // общий экземпляр (страница плиток и список)

- (void)load;                                            // читает plist (если файла нет — пусто)
- (BOOL)save;                                            // пишет plist (в конце режима правки)

// Сверка со списком приложений: убирает исчезнувшие, дописывает новые в конец как small.
// Возвращает YES, если состав тайлов изменился. Пустой список apps игнорируется (защита от затирания).
- (BOOL)syncWithApps:(NSArray *)apps;

// «Первое подходящее место», мозаика без наложений: small 1×1, medium 2×2, wide 4×2.
- (void)packWithColumns:(NSInteger)columns;

- (void)moveItemFromIndex:(NSInteger)from toIndex:(NSInteger)to;   // + перепаковка
- (BOOL)cycleSizeAtIndex:(NSInteger)index;                          // small → medium → wide → small (+ перепаковка)

// Открепление плитки от стартового экрана (кнопка «×»): приложение остаётся
// в списке, вернуть плитку можно долгим нажатием на строку в списке приложений.
- (void)excludeBundleID:(NSString *)bundleID;      // убрать плитку + не возвращать при сверке
- (void)pinBundleID:(NSString *)bundleID;          // вернуть плитку (small, в конец)
- (BOOL)isBundleIDExcluded:(NSString *)bundleID;

@end

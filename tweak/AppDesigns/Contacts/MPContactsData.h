// MPContactsData — слой данных «Контактов»: AddressBook C API + кэш людей
// по секциям-буквам + избранное в наших префах (в AddressBook iOS 6 своего
// флага «избранное» нет). Хранилище одно на процесс (sharedData); процесс —
// системное приложение Contacts~iphone, полный доступ без запроса.

#import <UIKit/UIKit.h>
#import <AddressBook/AddressBook.h>

// Значение поля контакта (телефон/почта): метка для подписи и само значение
@interface MPContactsFieldValue : NSObject
@property (nonatomic, copy) NSString *label;   // локализованная метка («мобильный»)
@property (nonatomic, copy) NSString *value;   // «+7 900 …» / «mail@example.com»
@end

// Лёгкая обёртка записи адресной книги: то, что нужно спискам и экрану контакта
@interface MPContactsPerson : NSObject
@property (nonatomic, assign) NSInteger recordID;   // ABRecordGetRecordID
@property (nonatomic, copy) NSString *name;         // составное имя (или организация)
@property (nonatomic, copy) NSString *sortKey;      // по нему сортировка/секции
@property (nonatomic, copy) NSString *initials;     // «АИ» — круг-заглушка фото
@property (nonatomic, copy) NSString *organization;
@property (nonatomic, retain) NSArray *phones;      // MPContactsFieldValue
@property (nonatomic, retain) NSArray *emails;      // MPContactsFieldValue
@property (nonatomic, retain) UIImage *photo;       // уже ужатая до 240 px; может быть nil
- (NSString *)primaryPhone;                         // первый телефон или nil
- (NSString *)primaryEmail;                         // первая почта или nil
@end

// Секция списка: буква + люди внутри
@interface MPContactsSection : NSObject
@property (nonatomic, copy) NSString *letter;
@property (nonatomic, retain) NSArray *people;      // MPContactsPerson
@end

// Постится после изменения хранилища (внешнее/наше) — страницы перечитывают
extern NSString * const MPContactsDataDidChangeNotification;

@interface MPContactsData : NSObject

+ (MPContactsData *)sharedData;

// Секции-буквы со всеми людьми (уже отсортированы); с фильтром — поиск
- (NSArray *)sections;
- (NSArray *)sectionsMatching:(NSString *)query;
- (NSArray *)favoriteSections;
- (NSArray *)favoriteSectionsMatching:(NSString *)query;

- (MPContactsPerson *)personForRecordID:(NSInteger)recordID;

// Фото карточки — лениво (в списке фото не грузятся ради скорости запуска);
// результат кэшируется в person.photo
- (UIImage *)photoForPerson:(MPContactsPerson *)person;

// Прямой доступ к хранилищу — нативному редактору (Hooks):
// personRefForRecordID возвращает ссылку по Get-Rule (не удержана)
- (ABAddressBookRef)addressBook;
- (ABRecordRef)personRefForRecordID:(NSInteger)recordID;

// Избранное — наши префы (домен ru.ash.metrophone, ключ contactsFavorites)
- (BOOL)isFavorite:(NSInteger)recordID;
- (void)setFavorite:(BOOL)fav forRecordID:(NSInteger)recordID;

// Перечитать хранилище (+ пост MPContactsDataDidChange)
- (void)invalidatePeople;

// Создать контакт и сохранить в адресную книгу (хотя бы одно поле непустое).
// YES — записано; после — invalidatePeople (списки перечитают сами).
- (BOOL)createPersonWithFirstName:(NSString *)first lastName:(NSString *)last
                     organization:(NSString *)org
                            phone:(NSString *)phone
                            email:(NSString *)email;
// Растёт при каждом invalidate — страницы сравнивают его, чтобы не
// пересобираться зря при viewDidAppear/активации без изменений данных
@property (nonatomic, readonly) NSUInteger dataGeneration;

@end

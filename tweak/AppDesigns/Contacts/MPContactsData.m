#import "MPContactsData.h"
#import "MPContactsTheme.h"
#import "MetroLauncher/MPMetroStyle.h"   // MPLog
#import <AddressBook/AddressBook.h>

NSString * const MPContactsDataDidChangeNotification = @"MPContactsDataDidChange";

// хелперы объявлены до использования (C-статика)
static NSString *MPContactsCopyString(ABRecordRef rec, ABPropertyID prop);
static NSArray *MPContactsCopyMultiValue(ABRecordRef rec, ABPropertyID prop);
static UIImage *MPContactsCopyPhoto(ABRecordRef rec);

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Модели

@implementation MPContactsFieldValue
@end

@implementation MPContactsPerson

- (NSString *)primaryPhone {
    return self.phones.count > 0 ? ((MPContactsFieldValue *)self.phones[0]).value : nil;
}

- (NSString *)primaryEmail {
    return self.emails.count > 0 ? ((MPContactsFieldValue *)self.emails[0]).value : nil;
}

@end

@implementation MPContactsSection
@end

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Слой данных

static void MPContactsABChangedCallback(ABAddressBookRef ab, CFDictionaryRef info, void *context);

@implementation MPContactsData {
    ABAddressBookRef _ab;
    NSArray *_people;               // MPContactsPerson, отсортированы
    NSArray *_allSections;          // MPContactsSection, пересобираются лениво
    NSMutableSet *_favorites;       // NSNumber(recordID)
    NSUInteger _generation;
}

+ (MPContactsData *)sharedData {
    static MPContactsData *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MPContactsData alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        _favorites = [NSMutableSet set];
        // избранные лежат в наших префах: массив NSNumber(recordID)
        CFPreferencesAppSynchronize(CFSTR("ru.ash.metrophone"));
        CFArrayRef v = (CFArrayRef)CFPreferencesCopyAppValue(CFSTR("contactsFavorites"),
                                                             CFSTR("ru.ash.metrophone"));
        if (v != NULL) {
            for (id item in (__bridge NSArray *)v) {
                if ([item isKindOfClass:[NSNumber class]]) [_favorites addObject:item];
            }
            CFRelease(v);
        }

        // хранилище одно на процесс; системное приложение — доступ полный
        _ab = ABAddressBookCreateWithOptions(NULL, NULL);
        if (_ab == NULL) _ab = ABAddressBookCreate();
        if (_ab != NULL) {
            ABAddressBookRegisterExternalChangeCallback(_ab, &MPContactsABChangedCallback, NULL);
        } else {
            MPLog(@"[Contacts] !! AddressBook не открылся");
        }
    }
    return self;
}

- (void)dealloc {
    if (_ab != NULL) CFRelease(_ab);
}

// Внешнее изменение хранилища (контакт поправлен в другом приложении) —
// колбэк может прийти с любого потока, уводим на main
static void MPContactsABChangedCallback(ABAddressBookRef ab, CFDictionaryRef info, void *context) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MPContactsData sharedData] invalidatePeople];
    });
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Чтение хранилища

// Один проход по всем записям: человек + поля. Вызывается лениво и после
// invalidate — адресная книга телефона конечна (сотни записей), полный
// рефетч дешевле и надёжнее инкрементального кэша EventKit.
- (void)loadPeopleIfNeeded {
    if (_people != nil) return;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    NSMutableArray *people = [NSMutableArray array];
    if (_ab != NULL) {
        CFArrayRef all = ABAddressBookCopyArrayOfAllPeople(_ab);
        ABPersonSortOrdering order = ABPersonGetSortOrdering();   // порядок имён по локали
        for (NSInteger i = 0; i < CFArrayGetCount(all); i++) {
            ABRecordRef rec = (ABRecordRef)CFArrayGetValueAtIndex(all, i);
            MPContactsPerson *p = [[MPContactsPerson alloc] init];
            p.recordID = ABRecordGetRecordID(rec);

            // имя: составное → организация → заглушка
            CFStringRef cn = ABRecordCopyCompositeName(rec);
            if (cn != NULL) {
                p.name = [(__bridge NSString *)cn copy];
                CFRelease(cn);
            } else {
                CFStringRef org = (CFStringRef)ABRecordCopyValue(rec, kABPersonOrganizationProperty);
                if (org != NULL) {
                    p.name = [(__bridge NSString *)org copy];
                    CFRelease(org);
                } else {
                    p.name = @"Без имени";
                }
            }

            // ключ сортировки и секций: фамилия-имя или имя-фамилия по порядку локали
            NSString *first = MPContactsCopyString(rec, kABPersonFirstNameProperty);
            NSString *last = MPContactsCopyString(rec, kABPersonLastNameProperty);
            if (order == kABPersonSortByFirstName) {
                p.sortKey = [NSString stringWithFormat:@"%@ %@", first ?: @"", last ?: @""];
            } else {
                p.sortKey = [NSString stringWithFormat:@"%@ %@", last ?: @"", first ?: @""];
            }
            if ([p.sortKey stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceCharacterSet]].length == 0) {
                p.sortKey = p.name;
            }

            // инициалы для круга-заглушки
            NSMutableString *ini = [NSMutableString string];
            if (first.length > 0) [ini appendFormat:@"%C", [first characterAtIndex:0]];
            if (last.length > 0) [ini appendFormat:@"%C", [last characterAtIndex:0]];
            if (ini.length == 0) {
                if (p.organization.length > 0) {
                    [ini appendFormat:@"%C", [p.organization characterAtIndex:0]];
                } else {
                    [ini appendString:@"#"];
                }
            }
            p.initials = ini.uppercaseString;
            p.organization = MPContactsCopyString(rec, kABPersonOrganizationProperty);

            p.phones = MPContactsCopyMultiValue(rec, kABPersonPhoneProperty);
            p.emails = MPContactsCopyMultiValue(rec, kABPersonEmailProperty);
            // ФОТО ЗДЕСЬ НЕ ГРУЗИМ: декод+ужим сотен картинок на A4 вешал
            // запуск на секунды (главный виновник «медленно грузит»).
            // Фото берём лениво — photoForPerson: на карточке.

            [people addObject:p];
        }
        if (all != NULL) CFRelease(all);
    }
    _people = [people sortedArrayUsingComparator:
               ^NSComparisonResult(MPContactsPerson *a, MPContactsPerson *b) {
        return [a.sortKey caseInsensitiveCompare:b.sortKey];
    }];
    _allSections = nil;
    MPLog(@"[Contacts] книга: %ld чел за %.0f мс",
          (long)_people.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
}

static NSString *MPContactsCopyString(ABRecordRef rec, ABPropertyID prop) {
    CFStringRef v = (CFStringRef)ABRecordCopyValue(rec, prop);
    if (v == NULL) return nil;
    NSString *s = [(__bridge NSString *)v copy];
    CFRelease(v);
    return s;
}

// многозначные поля (телефоны/почты) → массив MPContactsFieldValue
static NSArray *MPContactsCopyMultiValue(ABRecordRef rec, ABPropertyID prop) {
    ABMultiValueRef mv = (ABMultiValueRef)ABRecordCopyValue(rec, prop);
    if (mv == NULL) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger i = 0; i < ABMultiValueGetCount(mv); i++) {
        CFStringRef val = (CFStringRef)ABMultiValueCopyValueAtIndex(mv, i);
        CFStringRef lbl = ABMultiValueCopyLabelAtIndex(mv, i);
        MPContactsFieldValue *fv = [[MPContactsFieldValue alloc] init];
        if (val != NULL) {
            fv.value = [(__bridge NSString *)val copy];
            CFRelease(val);
        }
        if (lbl != NULL) {
            CFStringRef loc = ABAddressBookCopyLocalizedLabel(lbl);
            fv.label = loc != NULL ? [(__bridge NSString *)loc copy] : @"";
            if (loc != NULL) CFRelease(loc);
            CFRelease(lbl);
        }
        if (fv.value.length > 0) [out addObject:fv];
    }
    CFRelease(mv);
    return out;
}

// фото, ужатое до 240 px: исходники бывают по мегабайту, декодировать такую
// картинку на каждый показ списка на A4 недопустимо
static UIImage *MPContactsCopyPhoto(ABRecordRef rec) {
    if (!ABPersonHasImageData(rec)) return nil;
    CFDataRef data = ABPersonCopyImageData(rec);
    if (data == NULL) return nil;
    UIImage *img = [UIImage imageWithData:(__bridge NSData *)data];
    CFRelease(data);
    if (img == nil) return nil;
    CGFloat maxSide = 240.0f;
    CGSize sz = img.size;
    if (sz.width <= maxSide && sz.height <= maxSide) return img;
    CGFloat k = MIN(maxSide / sz.width, maxSide / sz.height);
    CGSize nsz = CGSizeMake(floorf(sz.width * k), floorf(sz.height * k));
    UIGraphicsBeginImageContext(nsz);
    [img drawInRect:CGRectMake(0.0f, 0.0f, nsz.width, nsz.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return small;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Секции

// Буква секции: первый символ ключа сортировки (заглавный), не-буква → «#»
static NSString *MPContactsLetterForSortKey(NSString *key) {
    if (key.length == 0) return @"#";
    NSString *up = [[key substringToIndex:1] uppercaseString];
    unichar c = [up characterAtIndex:0];
    if ((c >= 'A' && c <= 'Z') || (c >= 0x0410 && c <= 0x044F)) return up;   // латиница+кириллица
    return @"#";
}

- (NSArray *)buildSectionsFromPeople:(NSArray *)people {
    NSMutableArray *sections = [NSMutableArray array];
    MPContactsSection *cur = nil;
    for (MPContactsPerson *p in people) {
        NSString *letter = MPContactsLetterForSortKey(p.sortKey);
        if (cur == nil || ![letter isEqualToString:cur.letter]) {
            cur = [[MPContactsSection alloc] init];
            cur.letter = letter;
            cur.people = [NSMutableArray array];
            [sections addObject:cur];
        }
        [(NSMutableArray *)cur.people addObject:p];
    }
    return sections;
}

- (NSArray *)sections {
    [self loadPeopleIfNeeded];
    if (_allSections == nil) _allSections = [self buildSectionsFromPeople:_people];
    return _allSections;
}

- (NSArray *)sectionsMatching:(NSString *)query {
    return [self buildSectionsFromPeople:[self peopleMatching:query fromPeople:self.allPeople]];
}

- (NSArray *)favoriteSections {
    return [self buildSectionsFromPeople:self.allFavorites];
}

- (NSArray *)favoriteSectionsMatching:(NSString *)query {
    return [self buildSectionsFromPeople:[self peopleMatching:query fromPeople:self.allFavorites]];
}

// фильтр поиска: имя/организация (без учёта регистра и диакритики) или цифры телефона
- (NSArray *)peopleMatching:(NSString *)query fromPeople:(NSArray *)src {
    NSString *q = [query stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceCharacterSet]];
    if (q.length == 0) return src;
    NSMutableArray *out = [NSMutableArray array];
    for (MPContactsPerson *p in src) {
        NSRange r = [p.name rangeOfString:q
                                  options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
        if (r.location != NSNotFound) { [out addObject:p]; continue; }
        for (MPContactsFieldValue *fv in p.phones) {
            if ([fv.value rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [out addObject:p];
                break;
            }
        }
    }
    return out;
}

- (NSArray *)allPeople {
    [self loadPeopleIfNeeded];
    return _people ?: @[];
}

- (NSArray *)allFavorites {
    [self loadPeopleIfNeeded];
    NSMutableArray *out = [NSMutableArray array];
    for (MPContactsPerson *p in _people) {
        if ([_favorites containsObject:@(p.recordID)]) [out addObject:p];
    }
    return out;
}

- (MPContactsPerson *)personForRecordID:(NSInteger)recordID {
    [self loadPeopleIfNeeded];
    for (MPContactsPerson *p in _people) {
        if (p.recordID == recordID) return p;
    }
    return nil;
}

- (ABAddressBookRef)addressBook {
    return _ab;
}

- (ABRecordRef)personRefForRecordID:(NSInteger)recordID {
    return _ab != NULL ? ABAddressBookGetPersonWithRecordID(_ab, recordID) : NULL;
}

// фото лениво: только для открытой карточки, с кэшем в самой обёртке
- (UIImage *)photoForPerson:(MPContactsPerson *)person {
    if (person.photo != nil) return person.photo;
    ABRecordRef rec = [self personRefForRecordID:person.recordID];
    if (rec == NULL) return nil;
    UIImage *img = MPContactsCopyPhoto(rec);
    // Get-Rule: ссылку не удерживаем — запись живёт, пока жив адресбук
    person.photo = img;
    return img;
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Избранное (наши префы)

- (BOOL)isFavorite:(NSInteger)recordID {
    return [_favorites containsObject:@(recordID)];
}

- (void)setFavorite:(BOOL)fav forRecordID:(NSInteger)recordID {
    NSNumber *k = @(recordID);
    if (fav) [_favorites addObject:k];
    else [_favorites removeObject:k];

    NSMutableArray *arr = [[_favorites allObjects] mutableCopy];
    CFPreferencesSetAppValue(CFSTR("contactsFavorites"),
                             (__bridge CFArrayRef)arr,
                             CFSTR("ru.ash.metrophone"));
    CFPreferencesAppSynchronize(CFSTR("ru.ash.metrophone"));
    [self invalidatePeople];
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Создание контакта

- (BOOL)createPersonWithFirstName:(NSString *)first lastName:(NSString *)last
                     organization:(NSString *)org
                            phone:(NSString *)phone
                            email:(NSString *)email {
    if (_ab == NULL) return NO;
    // хоть что-то должно быть заполнено — пустые контакты не создаём
    NSString *first2 = [first stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
    NSString *last2 = [last stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
    NSString *org2 = [org stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceCharacterSet]];
    NSString *phone2 = [phone stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
    NSString *email2 = [email stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
    if (first2.length == 0 && last2.length == 0 && org2.length == 0 &&
        phone2.length == 0 && email2.length == 0) {
        MPLog(@"[Contacts] создание: все поля пустые — отмена");
        return NO;
    }

    @try {
        ABRecordRef rec = ABPersonCreate();
        if (first2.length > 0) {
            ABRecordSetValue(rec, kABPersonFirstNameProperty, (__bridge CFStringRef)first2, NULL);
        }
        if (last2.length > 0) {
            ABRecordSetValue(rec, kABPersonLastNameProperty, (__bridge CFStringRef)last2, NULL);
        }
        if (org2.length > 0) {
            ABRecordSetValue(rec, kABPersonOrganizationProperty, (__bridge CFStringRef)org2, NULL);
        }
        if (phone2.length > 0) {
            ABMultiValueRef mv = ABMultiValueCreateMutable(kABMultiStringPropertyType);
            ABMultiValueAddValueAndLabel(mv, (__bridge CFStringRef)phone2,
                                         kABPersonPhoneMobileLabel, NULL);
            ABRecordSetValue(rec, kABPersonPhoneProperty, mv, NULL);
            CFRelease(mv);
        }
        if (email2.length > 0) {
            ABMultiValueRef mv = ABMultiValueCreateMutable(kABMultiStringPropertyType);
            ABMultiValueAddValueAndLabel(mv, (__bridge CFStringRef)email2,
                                         kABHomeLabel, NULL);
            ABRecordSetValue(rec, kABPersonEmailProperty, mv, NULL);
            CFRelease(mv);
        }
        BOOL ok = ABAddressBookAddRecord(_ab, rec, NULL);
        if (ok) ok = ABAddressBookSave(_ab, NULL);
        CFRelease(rec);
        MPLog(@"[Contacts] контакт создан: %@ %@ (%@)", first2, last2,
              ok ? @"записан" : @"!! ошибка записи");
        [self invalidatePeople];
        return ok;
    } @catch (NSException *e) {
        MPLog(@"[Contacts] !! создание: %@ — %@", e.name, e.reason);
        return NO;
    }
}

//──────────────────────────────────────────────────────────────────────────────
#pragma mark - Invalidate

- (void)invalidatePeople {
    _people = nil;
    _allSections = nil;
    _generation++;
    [[NSNotificationCenter defaultCenter]
     postNotificationName:MPContactsDataDidChangeNotification object:nil];
}

- (NSUInteger)dataGeneration {
    return _generation;
}

@end

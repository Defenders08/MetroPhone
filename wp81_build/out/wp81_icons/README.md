# Коллекция иконок плиток Windows Phone 8.1

Собранные оригинальные иконки (тайлы/логотипы) стандартных приложений ОС
Windows Phone 8.1 и популярных сторонних приложений. Предназначено для
лаунчера MetroPhone (твик Metro-темы) и личного/некоммерческого использования.

## Структура архива

```
wp81_icons/
  standard/<имя_приложения>/  — системные приложения WP8.1
  third_party/<имя_приложения>/ — сторонние приложения
  normalized/               — единый размер (PNG 150x150 и 256x256), <app>_150.png
  redraw/                   — перерисованные наборы (только неоригинальные иконки)
  manifest.csv              — реестр всех файлов (см. колонки ниже)
  README.md                 — этот файл
```

Все файлы сохранены без перекодирования и масштабирования (оригиналы из
пакетов .xap/.appx или PE-ресурсов системных приложений). Дедупликация —
по SHA-256: каждый уникальный файл встречается один раз.

## Итоги

- Приложений в категории **standard**: 29
- Приложений в категории **third_party**: 71
- Приложений с redraw-иконками: 0
- Всего уникальных файлов иконок: 849

## Таблица приложений

| Приложение | Категория | Издатель | Найденные размеры | Источник | Тип |
|---|---|---|---|---|---|
| Battery Sense | standard | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 106x106, 150x150, 170x170, 210x210, 360x360, 44x44, 62x62, 71x71, 99x99 | образ эмулятора WP8.1 (archive.org) | original |
| Bing Finance | standard | Microsoft Corporation | 100x100, 120x120, 150x150, 159x159, 238x102, 336x336, 44x44, 661x336 | образ эмулятора WP8.1 (archive.org) | original |
| Bing Food & Drink | standard | Microsoft Corporation | 100x100, 150x150, 159x159, 30x30, 336x336, 50x50, 661x336 | образ эмулятора WP8.1 (archive.org) | original |
| Bing Health & Fitness | standard | Microsoft Corporation | 100x100, 136x30, 144x144, 150x150, 159x159, 230x230, 30x30, 336x336, 50x50, 54x54, 661x336, 98x30 | образ эмулятора WP8.1 (archive.org) | original |
| Bing News | standard | Microsoft Corporation | 100x100, 159x159, 336x336, 565x120, 661x336, 688x1229, 80x80 | образ эмулятора WP8.1 (archive.org) | original |
| Bing Sports | standard | Microsoft Corporation | 100x100, 120x120, 150x150, 159x159, 336x336, 44x44, 661x336 | образ эмулятора WP8.1 (archive.org) | original |
| Bing Travel | standard | Microsoft Corporation | 100x100, 150x150, 159x159, 1x1, 336x336, 44x44, 691x336 | образ эмулятора WP8.1 (archive.org) | original |
| Bing Weather | standard | Microsoft Corporation | 100x100, 159x159, 336x336, 661x336 | образ эмулятора WP8.1 (archive.org) | original |
| Calculator | standard | Microsoft | 108x108, 48x48, 76x76 | образ эмулятора WP8.1 (archive.org) | original |
| Calendar | standard | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 106x106, 114x114, 128x128, 142x142, 150x150, 156x156, 170x170, 210x210, 213x213, 284x284, 310x150, 360x360, 434x210, 44x44, 62x62, 71x71, 744x360, 85x85, 99x99 | образ эмулятора WP8.1 (archive.org) | original |
| Certificate Installer | standard | Microsoft | 173x136, 21x21, 277x218, 33x33, 43x43, 69x69 | образ эмулятора WP8.1 (archive.org) | original |
| Comms (Mail/People/Tasks) | standard | Microsoft | 10x21, 16x34, 24x24, 38x38, 43x43, 48x48, 69x69, 76x76 | образ эмулятора WP8.1 (archive.org) | original |
| Display Settings+ | standard | Microsoft Mobile | 336x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Dolby Headphones (Audio) | standard | Nokia Corporation | 173x173 | archive.org/items/majkelsoft-xap | original |
| Driving Mode | standard | Microsoft | 432x45, 691x72, 972x101 | образ эмулятора WP8.1 (archive.org) | original |
| Feedback | standard | Microsoft Mobile | 159x159, 336x336 | archive.org/items/majkelsoft-xap | original |
| Files | standard | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 150x150, 44x44, 71x71 | образ эмулятора WP8.1 (archive.org) | original |
| IE Tile Manager | standard | Microsoft Corporation | 44x44, 50x50 | archive.org/items/majkelsoft-xap | original |
| Internet Explorer | standard | Microsoft Corporation | 150x150, 50x50, 70x70 | образ эмулятора WP8.1 (archive.org) | original |
| Keyboard | standard | Microsoft | 43x43, 69x69 | образ эмулятора WP8.1 (archive.org) | original |
| MSN Weather | standard | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 142x142, 16x16, 20x20, 24x24, 256x256, 300x300, 30x30, 32x32, 36x36, 40x40, 48x48, 60x60, 620x300, 620x620, 64x64, 72x72, 80x80, 88x88, 96x96 | archive.org/items/MSNWeatherUWP/Microsoft.BingWeather_8wekyb3d8bbwe.zip | original |
| Media (Xbox Games UI) | standard | Microsoft | 101x101, 138x138, 1x1025, 1x800, 63x63, 86x86 | образ эмулятора WP8.1 (archive.org) | original |
| Notification Center | standard | Microsoft | 100x100, 62x62 | образ эмулятора WP8.1 (archive.org) | original |
| Office Hub | standard | Microsoft | 108x108, 1291x1920, 14x16, 159x159, 16x19, 173x173, 18x18, 19x19, 20x20, 223x223, 22x26, 26x19, 277x277, 29x29, 29x34, 30x30, 329x104, 32x32, 32x36, 33x21, 36x43, 389x389, 41x41, 43x43, 45x45, 48x48, 48x72, 526x166, 52x52, 538x800, 53x34, 69x69, 72x72, 740x234, 74x47, 76x76, 860x1279, 97x97, 99x99 | образ эмулятора WP8.1 (archive.org) | original |
| OneDrive | standard | OneDriveApp | 139x139, 223x223, 473x473, 972x473 | образ эмулятора WP8.1 (archive.org) | original |
| Podcasts | standard | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 106x106, 150x150, 170x170, 210x210, 360x360, 44x44, 62x62, 71x71, 99x99 | образ эмулятора WP8.1 (archive.org) | original |
| Xbox Games Hub | standard | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 100x100, 134x202, 1394x672, 159x159, 220x220, 316x316, 336x336, 672x672, 691x336, 71x110 | образ эмулятора WP8.1 (archive.org) | original |
| Xbox Music | standard | Microsoft Corporation | 159x159, 336x336, 691x336, 99x99 | образ эмулятора WP8.1 (archive.org) | original |
| Xbox Video | standard | Microsoft Corporation | 100x100, 159x159, 336x336, 691x336, 99x99 | образ эмулятора WP8.1 (archive.org) | original |
| ABC News | third_party | ABC | 159x159, 336x336, 691x336 | archive.org/items/fifa-14_202403/XAP/ABC%20News.xap | original |
| AMC | third_party | AMC SHOWPLACE THEATRES, INC. | 159x159, 336x336, 62x62, 691x336 | archive.org/items/fifa-14_202403/XAP/AMC.xap | original |
| Afterlight | third_party | CN=Madhuri | 120x120, 126x126, 150x150, 16x16, 210x210, 248x120, 248x248, 24x24, 256x256, 270x270, 30x30, 310x150, 310x310, 32x32, 42x42, 434x210, 434x434, 48x48, 54x54, 558x270, 558x558, 56x56, 70x70, 98x98 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Airport City | third_party | GAME INSIGHT GLOBAL LIMITED | 159x159, 336x336, 99x99 | archive.org/items/windows-phone-pdalife/Airport%20City.xap | original |
| AllTube Player | third_party | Kay61 | 173x173, 62x62 | archive.org/items/winphone-xap/AllTube%20Player%20Pro%20v3.4.7.0%20%5BWinphone%20Iz%5D.xap | original |
| Amazing Alex | third_party | Rovio Entertainment Ltd | 173x173, 62x62 | archive.org/items/xap-archive/Amazing%20Alex%20v1.0.7.0%20%5BWinphone%20Iz%5D.xap | original |
| Amazon | third_party | CN=5050E920-F712-4A72-AFD4-2E82CC365EEF | 150x150, 30x30, 310x150, 310x310 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Angry Birds Classic | third_party | Rovio Entertainment Ltd | 100x100, 159x159, 336x336, 691x336 | archive.org/items/carls-xap-archive/Angry%20Birds%20Classic%204.2.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Angry Birds Epic | third_party | Rovio Entertainment Ltd | 110x110, 202x202 | archive.org/items/windows-phone-pdalife/Angry%20Birds%20Epic.xap | original |
| Angry Birds Go! | third_party | Rovio Entertainment Ltd | 336x336, 50x50 | archive.org/items/carls-xap-archive/Angry%20Birds%20Go%21%20v1.8.7.0%20%5BWinphone%20Iz%5D.xap | original |
| Angry Birds Space | third_party | Rovio Entertainment Ltd | 100x100, 159x159, 336x336, 691x336 | archive.org/items/carls-xap-archive/Angry%20Birds%20Space%202.0.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Asphalt 5 | third_party | GAMELOFT SA | 173x173 | archive.org/items/carls-xap-archive/Asphalt%205%20v1.33.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Baconit (Reddit) | third_party | Quinn Damerell | 100x100, 143x202, 38x38, 78x110 | archive.org/items/fifa-14_202403/XAP/Baconit_3.0.1.xap | original |
| Bad Piggies | third_party | Rovio Entertainment Ltd | 105x105, 159x159, 336x336, 691x336 | archive.org/items/carls-xap-archive/BadPiggies%20v1.6.1.0%20%5BWinphone%20Iz%5D.xap | original |
| Bejeweled LIVE | third_party | — | 173x173 | archive.org/items/winphone-xap/%5BDev.Unlock%5DBejeweled.LIVE.1.1.xap | original |
| Bike Race | third_party | Top Free Games Best Apps | 300x300 | archive.org/items/carls-xap-archive/Bike%20Race%20v1.0.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Box | third_party | CN=6682ECEE-1C3A-4A8B-AFC7-8D2136C5F959 | 150x150, 30x30, 310x150, 310x310 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Candy Crush Saga | third_party | XiaomiCandy | 173x173, 62x62 | archive.org/items/winphone-xap/Candy%20Crush%20Saga%20v1.0.0.1%20%5BWinphone%20Iz%5D.xap | original |
| Crossy Road | third_party | CN=F09E8811-26A4-4DC0-81DE-ECCB3699A043 | 120x120, 126x126, 150x150, 16x16, 210x210, 248x248, 24x24, 256x256, 270x270, 30x30, 310x150, 310x310, 32x32, 42x42, 434x210, 434x434, 48x48, 54x54, 558x558, 56x56, 70x70, 98x98 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Cut the Rope | third_party | Zeptolab UK Ltd | 173x173, 62x62 | archive.org/items/fifa-14_202403/XAP/Cut%20The%20Rope%20v1.7.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Cut the Rope 2 | third_party | CN=9F84FC0F-E616-49FF-9410-D8AC6DAE95F7 | 106x106, 170x170, 360x360 | archive.org/items/cut-the-rope-2-for-win-8/AppxBundleApp/ZeptoLabUKLimited.CuttheRope2_2016.609.1315.0_neutral_~_sq9zxnwrk84pj.zip | original |
| Cut the Rope: Experiments | third_party | Zeptolab UK Ltd | 173x173, 62x62 | archive.org/items/winphone-xap/Cut%20The%20Rope%20Exp.%20v1.2.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Dailymotion | third_party | CN=7438315D-B885-4004-9609-0BD67D55D411 | 150x150, 30x30, 310x150 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Despicable Me: Minion Rush | third_party | Gameloft. | 159x159, 336x336, 691x336, 99x99 | archive.org/items/despicable-me-minion-rush-windows-phone/Despicable%20Me%20Minion%20Rush.xap | original |
| Doodle Jump | third_party | GameHouse Live | 173x173 | archive.org/items/winphone-xap/Doodle%20Jump%201.8.1.0%20%5BWinphone%20Iz%5D.xap | original |
| Facebook (Beta) | third_party | Microsoft Corporation | 160x160, 300x300, 30x30, 691x336 | archive.org/items/majkelsoft-xap | original |
| Fitbit | third_party | CN=92480AC4-06D9-4A8C-8391-44373C8AC01E | 106x106, 150x150, 170x170, 210x210, 310x150, 360x360, 434x210, 44x44, 62x62, 71x71, 744x360, 99x99 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Flipboard | third_party | CN=E7268B71-AD1D-4F1F-BD8B-1F3D76F6C653 | 150x150, 30x30, 310x150, 310x310, 70x70 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Fruit Ninja | third_party | Microsoft Studios™ | 173x173, 64x64 | archive.org/items/00013-guitar-hero-5-v-1-1-0-0/Fruit%20Ninja%20v1.1-winphoneiz.cf.xap | original |
| Geometry Dash | third_party | RobTop Games | 100x100, 159x159, 336x336, 691x336 | archive.org/items/carls-xap-archive/Geometry%20Dash%20v2.0.1.xap | original |
| Google Search | third_party | Google Inc. | 173x173, 62x62 | archive.org/items/winphone-xap/Google%20v.1.0.0.0.xap | original |
| Gravity Guy | third_party | Miniclip | 173x173 | archive.org/items/00013-guitar-hero-5-v-1-1-0-0/Gravity_Guy_v1.1.0.0.xap | original |
| Jetpack Joyride | third_party | Halfbrick Studios | 100x100 | archive.org/items/winphone-xap/Jetpack%20Joyride.xap | original |
| Kinectimals | third_party | Microsoft Studios | 173x173 | archive.org/items/carls-xap-archive/Kinectimals%20v1.0.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Metro Video Player | third_party | CN=C93ED6AF-ECD7-4C44-9C14-03C0A3FDA846 | 142x142, 16x16, 24x24, 256x256, 300x300, 48x48, 620x300, 88x88 | archive.org/items/MetroVideoPlayer/58119AnnanZubair.WindowsVideoPlayer_ftf4k455bcwd6.zip | original |
| Microsoft Jigsaw | third_party | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 120x120, 150x150, 16x16, 248x120, 248x248, 24x24, 256x256, 30x30, 310x150, 310x310, 32x32, 48x48, 70x70 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Microsoft Mahjong | third_party | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 150x150, 30x30, 310x150, 310x310 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Microsoft Minesweeper | third_party | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 150x150, 30x30, 310x150, 310x310 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Microsoft Solitaire Collection | third_party | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 150x150, 30x30, 310x150, 310x310 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Minecraft | third_party | CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US | 150x150, 210x210, 310x150, 434x210, 44x44, 62x62, 71x71, 99x99 | archive.org/items/microsoft.-minecraft-uwp-0.14.0.0/Microsoft.Minecraft.PE_0.14.0.0.zip | original |
| Mirror's Edge | third_party | Nokia Corporation | 173x173, 62x62 | archive.org/items/carls-xap-archive/Mirrors%20Edge%201.0.0.0%20.xap | original |
| Need for Speed: Hot Pursuit | third_party | Electronic Arts | 173x173 | archive.org/items/carls-xap-archive/NFS%20Hot%20Pursuit%20v1.0.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Netflix | third_party | CN=52120C15-ACFA-47FC-A7E3-4974DBA79445 | 106x106, 150x150, 170x170, 360x360, 71x71, 744x360 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Nokia Care | third_party | Microsoft Mobile | 159x159, 336x336, 691x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia Cinemagraph | third_party | Microsoft Mobile | 159x159, 336x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia Creative Studio | third_party | Microsoft Mobile | 159x159, 336x336, 691x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia Device Hub | third_party | Microsoft Mobile | 336x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia MixRadio | third_party | Microsoft Mobile | 159x159, 336x336, 38x38, 691x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia Pro Camera | third_party | Microsoft Mobile | 159x159, 336x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia Selfie | third_party | Microsoft Mobile | 159x159, 336x336, 99x99 | archive.org/items/majkelsoft-xap | original |
| Nokia Storyteller | third_party | Microsoft Mobile | 1500x843, 159x159, 99x99 | archive.org/items/majkelsoft-xap | original |
| One More Line | third_party | CN=A5544147-0E2B-4EBA-923C-45D266CB33F0 | 106x106, 170x170, 360x360, 744x360 | archive.org/items/oneMoreLine-windows-phone/OneMoreLine-APPX.zip | original |
| PhotoFunia | third_party | CN=96DFAFBB-4D39-4376-B969-2FB4273A1422 | 120x120, 150x150, 248x120, 248x248, 24x24, 30x30, 310x150, 310x310 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Plants vs. Zombies | third_party | PopCap Games | 173x173 | archive.org/items/plantsvs-zombiesv10xap/PlantsvsZombies.xap | original |
| Prognoza | third_party | Dino Borogovac | 159x159, 336x336, 50x50, 691x336 | archive.org/items/prognoza-2.6.4.2/Prognoza_2.6.4.2.xap | original |
| Real Racing 2 | third_party | Nokia Corporation | 173x173, 62x62 | archive.org/items/carls-xap-archive/Real%20Racing%202%20v1.0.0.0-Winphone%20Iz.xap | original |
| Sonic The Hedgehog 4: Episode I | third_party | SEGA | 173x173 | archive.org/items/carls-xap-archive/Sonic%204%20Episode%20I%201.2.0.0-winphoneiz.cf.xap | original |
| Spider-Man Unlimited | third_party | Gameloft. | 159x159, 336x336, 691x336, 99x99 | archive.org/items/carls-xap-archive/Spider-Man%20Unlimited%20Beta%20v1.0.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Survivalcraft | third_party | Candy Rufus Games | 173x173, 62x62 | archive.org/items/carls-xap-archive/Survivalcraft%20v1.26.6.0%20%5BWinphone%20Iz%5D.xap | original |
| Temple Run | third_party | Imangi Studios, LLC | 110x110, 202x202, 99x99 | archive.org/items/carls-xap-archive/Temple%20Run%20v1.5.3.0%20%5BWinphone%20Iz%5D.xap | original |
| Terraria | third_party | 505 Games | 159x159, 336x336, 99x99 | archive.org/items/carls-xap-archive/Terraria%20v1.0.0.0%20%5BWinphone%20Iz%5D.xap | original |
| Tetris | third_party | Electronic Arts | 173x173 | archive.org/items/00013-guitar-hero-5-v-1-1-0-0/Tetris_v1.3.0.0.xap | original |
| The Amazing Spider-Man | third_party | Gameloft | 159x159, 336x336, 691x336, 99x99 | archive.org/items/carls-xap-archive/The%20Amazing%20Spider-Man%20v1.0.1.6%20%5BWinphone%20Iz%5D.xap | original |
| The Silent Age | third_party | CN=Sunboyheng | 106x106, 170x170, 360x360, 744x360 | archive.org/items/silent-age-2015.508.834.2193.appxbundle/Silent%20Age%202015.508.834.2193.appxbundle.zip | original |
| TripAdvisor | third_party | CN=F142D528-558C-4AD0-AC51-A0D59CB7CEFE | 150x150, 24x24, 30x30, 310x150, 310x310, 42x42, 54x54, 70x70 | archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия) | original |
| Twitter | third_party | Twitter Inc. | 100x100, 159x159, 336x336, 38x38, 691x336 | archive.org/items/majkelsoft-xap | original |
| UC Browser | third_party | UC Mobile Limited | 173x173, 62x62 | archive.org/items/00013-guitar-hero-5-v-1-1-0-0/ucbrowser.xap | original |
| Where's My Perry? | third_party | Disney | 100x100, 159x159, 336x336 | archive.org/items/carls-xap-archive/Where%27s%20My%20Perry_%20v1.0.2.0%20%5BWinphone%20Iz%5D.xap | original |
| Where's My Water? | third_party | Disney | 100x100, 159x159, 336x336 | archive.org/items/wmw-archive/wmw/full/windows_phone/wmw-1.0.4.0.xap | original |
| Wreck-It Ralph | third_party | [raresharesoft.blogspot.in] | 100x100, 159x159, 336x336, 691x336 | archive.org/items/carls-xap-archive/Wreck-It%20Ralph%20v1.0.0.10%20%5BWinphone%20Iz%5D.xap | original |
| eBay | third_party | eBay Inc. | 120x120, 150x150, 16x16, 173x173, 248x120, 24x24, 256x256, 30x30, 310x150, 32x32, 48x48, 62x62 | archive.org/items/fifa-14_202403/XAP/eBay_v1.17.0.0.xap | original |

## Приложения, для которых оригинал найти не удалось

- **N.O.V.A. 3** — в архиве archive.org соответствующий пакет не найден.

## Намеренно пропущенные пакеты

- **Perfect Shift** — архив 610 МБ превышает лимит загрузчика.
- **Game Studio Tycoon 2** — пакет упакован в RAR (нет распаковки RAR5).
- **N.O.V.A. 3** — XAP крупнее 600 МБ (лимит загрузчика).
- **Angry Birds Rio/Seasons/Star Wars/Star Wars II/Stella, Amazing Alex (частично), Bejeweled Live +, Carcassonne, Battleship, Age of Sparta, Bubble Town 2, Burn the Rope, CarneyVale: Showtime, Bug Village, Wordament, Tetris Blitz, Hydro Thunder GO, Monopoly, Sonic Dash** — файлы item `archive.org/details/wp-xbl-games_202212` закрыты доступом (HTTP 401, требуется вход в аккаунт archive.org); обходить защиту запрещено.
- **Spotify, Shazam, WhatsApp, Instagram, Telegram, Uber, Dropbox, HERE Maps,**
  **2GIS, Яндекс.приложения** — оригинальных XAP/APPX-пакетов в публичных
  архивах не найдено (см. «Недоступные источники» ниже); 4PDA отдаёт файлы
  только авторизованным пользователям.

### Системные приложения без оригинальных пакетов

Часть ядра WP8.1 (Телефон, Сообщения, Люди, Камера, Магазин, Карты, Кортана,
Skype) в образе эмулятора не представлена в виде отдельных пакетов — эти
приложения в ОС являются частью оболочки. Оригинальные тайлы для них можно
получить только дампом retail-прошивки (FFU), поэтому здесь они отсутствуют.
Перерисованные версии можно добавить через папку redraw/ (набор MetroStation).

## Лицензии и товарные знаки

Все иконки, логотипы и названия приложений являются товарными знаками и
объектами авторского права их правообладателей: Microsoft Corporation,
Nokia/Microsoft Mobile, Meta, WhatsApp LLC, Viber Media, Telegram, Google LLC,
Yandex, Rovio, Gameloft, EA, Uber, Dropbox, Evernote, Netflix, Spotify и других.
Коллекция собрана в учебных/исследовательских целях для личного
некоммерческого использования (тема MetroPhone для Windows Phone 8.1).
Коммерческое использование иконок запрещено без разрешения правообладателей.

Перерисованные наборы (папка redraw/): MetroStation от yankoa (DeviantArt),
лицензия CC BY-NC-SA 3.0 — только некоммерческое использование с указанием
авторства и сохранением лицензии производных работ.

## Недоступные источники и ручные действия

- **4PDA** (https://4pda.to/forum/index.php?showtopic=1052376 — каталог программ
  для WP8.1, showtopic=331476 — набор WindowsPhone_Tiles.zip, showtopic=547567 —
  системные пакеты): сайт закрыт анти-ботом (HTTP 403) и отдаёт вложения только
  авторизованным пользователям. Ручное действие: войти в аккаунт, скачать нужные
  XAP и положить их в `cache/pkg/` — этап `extract` подхватит их автоматически.
- **Viber и Opera Mini**: официальные XAP из открытых архивов зашифрованы
  PlayReady (сигнатура WRMHEADER). Расшифровка — обход DRM, не выполнялась.
  Ручное действие: взять распакованные (декриптованные) копии из своих
  резервных копий и положить в `cache/pkg/`.
- **DeviantArt, набор MetroStation (yankoa, CC BY-NC-SA 3.0)**
  (https://www.deviantart.com/yankoa/art/MetroStation-183210118): страница
  публична, но ZIP доступен только после входа в аккаунт DeviantArt.
  Ручное действие: скачать и положить `WindowsPhone_Tiles.zip` в `cache/`,
  затем перезапустить этап `redraw` — папка redraw/ заполнится автоматически.
- **archive.org/items/wp-xbl-games_202212** — файлы закрыты доступом (HTTP 401,
  требуется вход в аккаунт archive.org).
- **Windows Phone 8.1 SDK** (archive.org/items/windowsphone81sdkupdate1_202303) —
  тёмный item (доступ ограничен правообладателем).
- **Wayback Machine** (страницы Windows Phone Store): снапшоты страниц приложений
  в основном отсутствуют или HTTP 404, API периодически отдаёт rate-limit.

## Как воспроизвести сборку

Скрипт: `build_icons.py` (Python 3.8+, зависимости: Pillow). Шаги:

```bash
pip3 install Pillow
python3 build_icons.py download   # скачивание пакетов с archive.org
python3 build_icons.py emulator   # системные приложения из образа эмулятора
python3 build_icons.py extract    # извлечение иконок по манифестам
python3 build_icons.py normalize  # normalized/ (150 и 256 px)
python3 build_icons.py redraw     # перерисованные наборы (если доступны)
python3 build_icons.py report     # manifest.csv + README.md + wp81_icons.zip
```

Подготовка образа эмулятора (один раз, до этапа `emulator`):

```bash
# 1. Скачать эмулятор WP8.1 (638 МБ):
curl -L "https://archive.org/download/windows-phone-8.1-emulator.-7z/Windows%20Phone%208.1%20Emulator.7z" -o cache/wp81_emulator.7z
# 2. Извлечь flash.vhd и конвертировать в raw (скрипт vhd_to_raw.py):
7z x cache/wp81_emulator.7z "Windows Phone 8.1/flash.vhd" -ocache/
python3 vhd_to_raw.py "cache/Windows Phone 8.1/flash.vhd" cache/flash.raw
# 3. Вырезать раздел MainOS (NTFS, offset 45154816, размер 2393296896)
#    разреженно в cache/mainos.img (см. build_icons.py, этап emulator).
```

Источники (все публично доступные):

- https://archive.org/details/windows-phone-8.1-emulator.-7z — образ эмулятора WP8.1
- https://archive.org/details/majkelsoft-xap — XAP системных приложений
- https://archive.org/details/wp-xbl-games_202212 — XBL-игры для WP
- https://archive.org/details/carls-xap-archive, /details/winphone-xap,
  /details/fifa-14_202403 — XAP-архивы приложений и игр
- https://archive.org/details/Win8AppxArchive — Windows 8 Store (для приложений,
  у которых есть Phone-версия: Netflix, Flipboard, Kindle и др.)
- 4PDA (https://4pda.to/forum/index.php?showtopic=1052376) — недоступен скрипту
  (требуется вход/капча): ручное действие, при необходимости скачайте XAP оттуда
  и положите в cache/pkg/ — этап extract подхватит их автоматически.

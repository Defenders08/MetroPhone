#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_icons.py — сборка коллекции иконок плиток Windows Phone 8.1.

Этапы (перезапуск безопасен: скачанное пропускается):
  1. download  — скачивание XAP/APPX-пакетов с archive.org (по списку ниже).
  2. emulator  — извлечение системных приложений из образа эмулятора WP8.1
                 (cache/mainos.img: XAP-ы из PROGRAMS/CommonFiles/Xaps и
                 иконки из Assets-DLL нативных приложений карвингом PNG).
  3. extract   — разбор всех пакетов по манифестам (WMAppManifest.xml /
                 AppxManifest.xml), сохранение иконок, дедупликация по SHA-256.
  4. normalize — папка normalized/ (PNG 150x150 и 256x256).
  5. redraw    — перерисованный набор MetroStation (если доступен) либо
                 cache/WindowsPhone_Tiles.zip, положенный вручную.
  6. report    — manifest.csv, README.md, wp81_icons.zip.

Использование:
  python3 build_icons.py            # все этапы по порядку
  python3 build_icons.py download   # только один этап
"""
import csv
import hashlib
import io
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import zipfile

BASE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(BASE, 'cache')
OUT = os.path.join(BASE, 'out')
TREE = os.path.join(OUT, 'wp81_icons')
STATE_FILE = os.path.join(CACHE, 'downloads.json')

UA = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) wp81-icons-builder/1.0'}

os.makedirs(CACHE, exist_ok=True)
os.makedirs(TREE, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(os.path.join(BASE, 'build.log'), mode='a', encoding='utf-8'),
    ])
log = logging.getLogger('build_icons')

IA = 'https://archive.org/download'

# ---------------------------------------------------------------------------
# Список целевых пакетов: (имя приложения, категория, item на archive.org,
# регулярка имени файла). Имя None — берём из манифеста пакета.
# Категория: standard | third_party
# ---------------------------------------------------------------------------
DOWNLOADS = [
    # --- стандартные (магазинные обновления системных приложений, majkelsoft-xap)
    ('Bing News', 'standard', 'majkelsoft-xap', r'bingnews\.xap$'),
    ('Bing Finance', 'standard', 'majkelsoft-xap', r'bingfinance\.xap$'),
    ('Bing Sports', 'standard', 'majkelsoft-xap', r'bingsports\.xap$'),
    ('Bing Travel', 'standard', 'majkelsoft-xap', r'bingtravel\.xap$'),
    ('Bing Weather', 'standard', 'majkelsoft-xap', r'bingweather\.xap$'),
    ('Bing Food & Drink', 'standard', 'majkelsoft-xap', r'foodanddrink\.xap$'),
    ('Bing Health & Fitness', 'standard', 'majkelsoft-xap', r'healthandfitness\.xap$'),
    ('Xbox Music', 'standard', 'majkelsoft-xap', r'XboxMusic\.Retail\.xap$'),
    ('Xbox Video', 'standard', 'majkelsoft-xap', r'XboxVideo\.Retail\.xap$'),
    ('OneDrive', 'standard', 'majkelsoft-xap', r'OneDriveWPB\.xap$'),
    ('Xbox Games Hub', 'standard', 'majkelsoft-xap', r'GamesHub\.Retail\.xap$'),
    ('IE Tile Manager', 'standard', 'majkelsoft-xap', r'IETileManager_Retail\.xap$'),
    ('Nokia MixRadio', 'third_party', 'majkelsoft-xap', r'mixradio\.xap$'),
    ('Nokia Pro Camera', 'third_party', 'majkelsoft-xap', r'nokiacamera\.xap$'),
    ('Nokia Selfie', 'third_party', 'majkelsoft-xap', r'selfie\.xap$'),
    ('Nokia Storyteller', 'third_party', 'majkelsoft-xap', r'storyteller\.xap$'),
    ('Nokia Cinemagraph', 'third_party', 'majkelsoft-xap', r'cinemagraph\.xap$'),
    ('Nokia Creative Studio', 'third_party', 'majkelsoft-xap', r'creativestudio\.xap$'),
    ('Nokia Device Hub', 'third_party', 'majkelsoft-xap', r'devicehubspiderman\.xap$'),
    ('Nokia Care', 'third_party', 'majkelsoft-xap', r'care\.xap$'),
    ('Display Settings+', 'standard', 'majkelsoft-xap', r'displaysettings\.xap$'),
    ('Touch Settings', 'standard', 'majkelsoft-xap', r'touchsettings\.xap$'),
    ('Access Point (Network+)', 'standard', 'majkelsoft-xap', r'networkplus\.xap$'),
    ('Feedback', 'standard', 'majkelsoft-xap', r'feedback\.xap$'),
    ('Facebook (Beta)', 'third_party', 'majkelsoft-xap', r'FacebookWPB\.xap$'),
    ('Twitter', 'third_party', 'majkelsoft-xap', r'xap/Twitter\.xap$'),
    ('Dolby Headphones (Audio)', 'standard', 'majkelsoft-xap', r'xap/audio\.xap$'),
    # --- стандартные из эмулятора WP8.1 нельзя скачать напрямую — их берёт этап emulator
    # --- сторонние: отдельные items
    # Viber и Opera Mini: официальные XAP зашифрованы PlayReady (WRMHEADER) —
    # расшифровка запрещена (DRM), исключены из загрузки.
    ('UC Browser', 'third_party', '00013-guitar-hero-5-v-1-1-0-0', r'ucbrowser\.xap$'),
    ('Minecraft', 'third_party', 'microsoft.-minecraft-uwp-0.14.0.0', r'Microsoft\.Minecraft\.PE_0\.14\.0\.0\.zip$'),
    ('The Silent Age', 'third_party', 'silent-age-2015.508.834.2193.appxbundle', r'Silent Age 2015.*\.appxbundle\.zip$'),
    ('Despicable Me: Minion Rush', 'third_party', 'despicable-me-minion-rush-windows-phone', r'\.xap$'),
    ('Prognoza', 'third_party', 'prognoza-2.6.4.2', r'\.xap$'),
    ('MSN Weather', 'standard', 'MSNWeatherUWP', r'Microsoft\.BingWeather_8wekyb3d8bbwe\.zip$'),
    ('Metro Video Player', 'third_party', 'MetroVideoPlayer', r'WindowsVideoPlayer_.*\.zip$'),
    ('One More Line', 'third_party', 'oneMoreLine-windows-phone', r'OneMoreLine-APPX\.zip$'),
    ('Cut the Rope 2', 'third_party', 'cut-the-rope-2-for-win-8', r'CuttheRope2_2016\.609\.1315\.0.*\.zip$'),
    ('Plague Inc.', 'third_party', 'PlagueIncRT', r'NdemicCreationsLTD.*\.zip$'),
    # --- сторонние: winphone-xap
    ('Candy Crush Saga', 'third_party', 'winphone-xap', r'Candy Crush Saga.*\.xap$'),
    ('Cut the Rope: Experiments', 'third_party', 'winphone-xap', r'Cut The Rope Exp.*\.xap$'),
    ('Cut the Rope', 'third_party', 'fifa-14_202403', r'Cut The Rope v.*\.xap$'),
    ('Doodle Jump', 'third_party', 'winphone-xap', r'Doodle Jump.*\.xap$'),
    ('Jetpack Joyride', 'third_party', 'winphone-xap', r'Jetpack Joyride\.xap$'),
    ('Google Search', 'third_party', 'winphone-xap', r'Google v\.1\.0\.0\.0\.xap$'),
    ('AllTube Player', 'third_party', 'winphone-xap', r'AllTube Player Pro.*\.xap$'),
    ('Bejeweled LIVE', 'third_party', 'winphone-xap', r'Bejeweled\.LIVE\.1\.1\.xap$'),
    # --- сторонние: fifa-14_202403 (XAP/…)
    ('ABC News', 'third_party', 'fifa-14_202403', r'XAP/ABC News\.xap$'),
    ('AMC', 'third_party', 'fifa-14_202403', r'XAP/AMC\.xap$'),
    ('Baconit (Reddit)', 'third_party', 'fifa-14_202403', r'Baconit_3\.0\.1\.xap$'),
    ('eBay', 'third_party', 'fifa-14_202403', r'eBay_v1\.17\.0\.0\.xap$'),
    # --- сторонние: carls-xap-archive
    ('Temple Run', 'third_party', 'carls-xap-archive', r'Temple Run v.*\.xap$'),
    ('Terraria', 'third_party', 'carls-xap-archive', r'Terraria v.*\.xap$'),
    ('Geometry Dash', 'third_party', 'carls-xap-archive', r'Geometry Dash v2\.0\.1\.xap$'),
    ('Need for Speed: Hot Pursuit', 'third_party', 'carls-xap-archive', r'NFS Hot Pursuit.*\.xap$'),
    ('Asphalt 5', 'third_party', 'carls-xap-archive', r'Asphalt 5 v1\.33\.0\.0.*\.xap$'),
    ('Survivalcraft', 'third_party', 'carls-xap-archive', r'Survivalcraft v.*\.xap$'),
    ('The Amazing Spider-Man', 'third_party', 'carls-xap-archive', r'Amazing Spider-Man v.*\.xap$'),
    ('Wreck-It Ralph', 'third_party', 'carls-xap-archive', r'Wreck-It Ralph v.*\.xap$'),
    ("Sonic The Hedgehog 4: Episode I", 'third_party', 'carls-xap-archive', r'Sonic 4 Episode I 1\.2\.0\.0.*\.xap$'),
    ("Mirror's Edge", 'third_party', 'carls-xap-archive', r'Mirrors Edge.*\.xap$'),
    ('N.O.V.A. 3', 'third_party', 'carls-xap-archive', r'N\.O\.V\.A\.3.*\.xap$'),
    ('Real Racing 2', 'third_party', 'carls-xap-archive', r'Real Racing 2.*\.xap$'),
    ("Assassin's Creed", 'third_party', 'carls-xap-archive', r"Assassin's Creed v1\.0\.0\.0.*\.xap$"),
    ('Angry Birds Go!', 'third_party', 'carls-xap-archive', r'Angry Birds Go!.*\.xap$'),
    ('Bike Race', 'third_party', 'carls-xap-archive', r'Bike Race v.*\.xap$'),
    ('Kinectimals', 'third_party', 'carls-xap-archive', r'Kinectimals v.*\.xap$'),
    ('Spider-Man Unlimited', 'third_party', 'carls-xap-archive', r'Spider-Man Unlimited.*\.xap$'),
    ("Where's My Perry?", 'third_party', 'carls-xap-archive', r"Where's My Perry.*\.xap$"),
    # --- сторонние: wp-xbl-games_202212 закрыт (HTTP 401) — замены из открытых items
    ('Angry Birds Classic', 'third_party', 'carls-xap-archive', r'Angry Birds Classic 4\.2\.0\.0.*\.xap$'),
    ('Angry Birds Space', 'third_party', 'carls-xap-archive', r'Angry Birds Space 2\.0\.0\.0.*\.xap$'),
    ('Bad Piggies', 'third_party', 'carls-xap-archive', r'BadPiggies.*\.xap$'),
    ('Amazing Alex', 'third_party', 'xap-archive', r'Amazing Alex v1\.0\.7\.0.*\.xap$'),
    ('Plants vs. Zombies', 'third_party', 'plantsvs-zombiesv10xap', r'PlantsvsZombies\.xap$'),
    ('Angry Birds Epic', 'third_party', 'windows-phone-pdalife', r'Angry Birds Epic\.xap$'),
    ('Airport City', 'third_party', 'windows-phone-pdalife', r'Airport City\.xap$'),
    ('Mini Dash', 'third_party', '20011-mini-dash-v.-1.0.2.0', r'\.xap$'),
    ("Where's My Water?", 'third_party', 'wmw-archive', r'wmw-1\.0\.4\.0\.xap$'),
    ('Tetris', 'third_party', '00013-guitar-hero-5-v-1-1-0-0', r'Tetris_v1\.3\.0\.0\.xap$'),
    ('Fruit Ninja', 'third_party', '00013-guitar-hero-5-v-1-1-0-0', r'Fruit Ninja v1\.1.*\.xap$'),
    ('Gravity Guy', 'third_party', '00013-guitar-hero-5-v-1-1-0-0', r'Gravity_Guy_v1\.1\.0\.0\.xap$'),
]

# Приложения Windows 8 Store (Win8AppxArchive) — только те, у которых была
# Phone-версия. Формат: (имя, регулярка пути внутри item, item)
WIN8APX = [
    ('Netflix', r'Original APPX/.*4DF9E0F8\.Netflix.*\.zip$'),
    ('Flipboard', r'Original APPX/News/Flipboard\.Flipboard_2017.*\.zip$'),
    ('Kindle', r'Original APPX/.*KindleforWindows8_2\.1\.0\.2.*\.zip$'),
    ('eBay', r'Original APPX/Shopping/eBayInc\.eBay_1618n3s9xq8tw\.zip$'),
    ('TripAdvisor', r'Folder dumps/8\.1 TripAdvisorLLC\..*\.zip$'),
    ('Dailymotion', r'Generated APPX/Entertainment/DailymotionSA\.Dailymotion_2\.0\.1\.63.*\.zip$'),
    ('VK', r'Generated APPX/C6965DD5\.VK_2\.3\.2\.1.*\.zip$'),
    ('Google Search (Win8)', r'Original APPX/GoogleInc\.GoogleSearch_yfg5n0ztvskxp\.zip$'),
    ('Xbox One SmartGlass', r'Original APPX/Entertainment/Microsoft\.XboxOneSmartGlass_.*\.zip$'),
    ('Xbox Companion', r'Original APPX/Entertainment/Microsoft\.XboxCompanion_.*\.zip$'),
    ('Amazon', r'Original APPX/Shopping/Amazon\.com\.Amazon_2015.*\.zip$'),
    ('Fitbit', r'Original APPX/Sports/Fitbit\.Fitbit_2\.4.*\.zip$'),
    ('AccuWeather', r'Generated APPX/9456_AccuWeather\.AccuWeatherforWindows8_2\.1\.7\.2.*\.zip$'),
    ('Microsoft Solitaire Collection', r'Generated APPX/Games/Microsoft\.MicrosoftSolitaireCollection_2\.11.*\.zip$'),
    ('Microsoft Mahjong', r'Folder dumps/8\.1 Microsoft\.MicrosoftMahjong_.*\.zip$'),
    ('Microsoft Minesweeper', r'Generated APPX/Games/Microsoft\.MicrosoftMinesweeper_.*\.zip$'),
    ('Microsoft Jigsaw', r'Generated APPX/Games/Microsoft\.MicrosoftJigsaw_.*\.zip$'),
    ('PhotoFunia', r'Generated APPX/CapsuleDigital\.PhotoFunia_5\.2\.0\.0.*\.zip$'),
    ('Afterlight', r'Generated APPX/AfterlightCollectiveInc\.Afterlight_2\.5\.0\.0.*\.zip$'),
    ('Box', r'Folder dumps/8\.1 134D4F5B\.Box_1\.7\.0\.2210.*\.zip$'),
    ('Merriam-Webster Dictionary', r'Generated APPX/9456_D22CCC44\.Merriam-WebsterDictionary_.*\.zip$'),
    ('Crossy Road', r'Generated APPX/Games/Yodo1Ltd\.CrossyRoad_1\.1\.3\.0.*\.zip$'),
    ('mysms', r'Folder dumps/8\.0 UptoElevenDigitalSolution\.mysms-Textanywhere_.*\.zip$'),
    ('Zinio', r'Generated APPX/9456_ZinioLLC\.Zinio_1\.2\.0\.0.*\.zip$'),
    ('Microsoft Treasure Hunt', r'Generated APPX/Games/8\.1/Microsoft\.MicrosoftTreasureHunt_.*\.zip$'),
    ('Red Karaoke', r'Generated APPX/9456_PlanetaRedSL\.RedKaraoke_1\.0\.0\.11.*\.zip$'),
]

# Нативные системные приложения эмулятора (папка в PROGRAMS -> имя).
NATIVE_APPS = {
    'ALARMS': 'Alarms',
    'CALC7': 'Calculator',
    'PHOTOS': 'Photos',
    'SETTINGS': 'Settings',
    'WALLET': 'Wallet',
    'INTERNETEXPLORER': 'Internet Explorer',
    'OFFICE': 'Office Hub',
    'STORAGESENSE': 'Storage Sense',
    'REMEMBER': 'OneNote',
    'START': 'Start',
    'WEHSTART': 'Start (shell)',
    'KIDZONECUSTOMIZATION': 'Kids Corner',
    'FINDMYPHONE': 'Find My Phone',
    'ABOUTCPL': 'About',
    'CERTINSTALLER': 'Certificate Installer',
    'DRIVINGMODESETTINGS': 'Driving Mode',
    'NOCENTERSETTINGSCPL': 'Notification Center',
    'COMMSAPPLICATIONS': 'Comms (Mail/People/Tasks)',
    'MEDIA': 'Media (Xbox Games UI)',
    'REGIONCPL': 'Region',
    'BATTERYSAVERCPL': 'Battery Saver',
    'BRIGHTNESSCPL': 'Brightness',
    'KEYBOARDCPL': 'Keyboard',
    'REGIONCPL': 'Region',
    'RINGTONESANDSOUNDS': 'Ringtones+Sounds',
    'ROTATIONLOCKCPL': 'Rotation Lock',
    'SPEECHCPL': 'Speech',
    'THEMECPL': 'Theme',
    'DATETIMECPL': 'Date+Time',
    'LOCATIONUXCPL': 'Location',
    'MIRRORCPL': 'Project My Screen',
    'NAVBARCPL': 'Navigation Bar',
    'ACCESSIBILITYCPL': 'Ease of Access',
    'ADVERTISINGIDCPL': 'Advertising ID',
    'CELLUX': 'Cellular+SIM',
    'WIFIUXBLUE': 'Wi-Fi',
    'BTUXCPL': 'Bluetooth',
    'TELCPL': 'Mobile Network',
    'VPNUX': 'VPN',
    'LOCKANDWALLPAPER': 'Lock Screen',
    'NOTIFICATIONPLATFORMMIGRATOR': None,
}

PNG_SIG = b'\x89PNG\r\n\x1a\n'
PNG_END = b'IEND\xaeB`\x82'

MANIFEST_ROWS = []          # строки manifest.csv
SEEN_SHA = set()            # дедупликация


def slug(name):
    s = re.sub(r"[^A-Za-z0-9]+", "_", name).strip('_')
    return s or 'app'


# ---------------------------------------------------------------------------
# Загрузка файлов
# ---------------------------------------------------------------------------

def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, encoding='utf-8') as f:
            return json.load(f)
    return {}


def save_state(st):
    with open(STATE_FILE, 'w', encoding='utf-8') as f:
        json.dump(st, f, indent=1, ensure_ascii=False)


def http_get(url, dest, max_mb=600):
    """Скачивает файл с докачкой-пропуском; возвращает путь."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    tmp = dest + '.part'
    req = urllib.request.Request(url, headers=UA)
    limit = max_mb * 1024 * 1024
    with urllib.request.urlopen(req, timeout=120) as r, open(tmp, 'wb') as f:
        total = 0
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                f.close(); os.remove(tmp)
                raise IOError(f'превышен лимит {max_mb} МБ: {url}')
            f.write(chunk)
    os.replace(tmp, dest)
    return dest


def item_meta(item):
    """Метаданные item archive.org (кэшируются в cache/)."""
    p = os.path.join(CACHE, f'meta_{re.sub(r"[^A-Za-z0-9_.-]", "_", item)}.json')
    if not os.path.exists(p):
        url = f'https://archive.org/metadata/{item}'
        http_get(url, p, max_mb=50)
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def find_file(item, pattern, max_mb=600):
    """Ищет в item файл по регулярке; возвращает (имя, url, размер)."""
    meta = item_meta(item)
    rx = re.compile(pattern, re.I)
    for f in meta.get('files', []):
        name = f['name']
        if rx.search(name) and name.lower().endswith(('.xap', '.appx', '.appxbundle', '.zip')):
            size = int(f.get('size') or 0)
            if size > max_mb * 1024 * 1024:
                log.warning('  пропущен (большой): %s (%d МБ)', name, size // (1024 * 1024))
                return None
            url = f'{IA}/{item}/' + urllib.parse.quote(name)
            return name, url, size
    return None


def download_stage():
    st = load_state()
    for app, cat, item, pattern in DOWNLOADS:
        key = f'{item}::{pattern}'
        if (st.get(key) or {}).get('status') in ('ok', 'not_found'):
            log.info('уже скачано: %s', app)
            continue
        hit = find_file(item, pattern)
        if not hit:
            log.warning('НЕ НАЙДЕН: %s (%s) по шаблону %s', app, item, pattern)
            st[key] = {'status': 'not_found', 'app': app}
            save_state(st)
            continue
        name, url, size = hit
        dest = os.path.join(CACHE, 'pkg', re.sub(r'[^A-Za-z0-9_.-]', '_', f'{app}_{os.path.basename(name)}'))
        log.info('качаю %s: %s (%.1f МБ)', app, name, size / (1024 * 1024))
        try:
            http_get(url, dest)
            st[key] = {'status': 'ok', 'app': app, 'category': cat,
                       'file': name, 'url': url, 'path': dest}
        except Exception as e:
            log.error('ошибка скачивания %s: %s', app, e)
            st[key] = {'status': 'error', 'error': str(e)}
        save_state(st)
    # Win8AppxArchive — по общему метаданному item
    meta = item_meta('Win8AppxArchive')
    for app, pattern in WIN8APX:
        key = f'Win8AppxArchive::{app}'
        if (st.get(key) or {}).get('status') in ('ok', 'not_found'):
            continue
        rx = re.compile(pattern, re.I)
        hit = None
        for f in meta.get('files', []):
            if rx.search(f['name']):
                hit = f
                break
        if not hit:
            log.warning('НЕ НАЙДЕН в Win8AppxArchive: %s', app)
            st[key] = {'status': 'not_found'}
            save_state(st)
            continue
        name = hit['name']
        url = f'{IA}/Win8AppxArchive/' + urllib.parse.quote(name)
        dest = os.path.join(CACHE, 'pkg', re.sub(r'[^A-Za-z0-9_.-]', '_', f'{app}_{os.path.basename(name)}'))
        log.info('качаю (Win8): %s (%.1f МБ)', name, int(hit.get('size', 0)) / (1024 * 1024))
        try:
            http_get(url, dest, max_mb=200)
            st[key] = {'status': 'ok', 'app': app, 'category': 'third_party',
                       'file': name, 'url': url, 'path': dest, 'platform': 'win8_store'}
        except Exception as e:
            log.error('ошибка скачивания %s: %s', app, e)
            st[key] = {'status': 'error', 'error': str(e)}
        save_state(st)
    log.info('Этап download завершён')


# ---------------------------------------------------------------------------
# Этап emulator: системные приложения WP8.1 из образа
# ---------------------------------------------------------------------------

def run_7z(args, **kw):
    return subprocess.run(['7z'] + args, capture_output=True, text=True, **kw)


def ensure_emulator_extract():
    """Извлекает XAP-ы и Assets-DLL из cache/mainos.img (если он есть)."""
    xap_dir = os.path.join(CACHE, 'sysxap')
    dll_dir = os.path.join(CACHE, 'sysdll')
    img = os.path.join(CACHE, 'mainos.img')
    if not (os.path.exists(xap_dir) and os.path.exists(dll_dir)):
        if not os.path.exists(img):
            log.warning('mainos.img нет — системные приложения из эмулятора пропущены. '
                        'Скачайте эмулятор WP8.1 и выполните шаги из README (этап emulator).')
            return None, None
        os.makedirs(xap_dir, exist_ok=True)
        os.makedirs(dll_dir, exist_ok=True)
        log.info('извлекаю XAP-ы из mainos.img…')
        run_7z(['x', img, f'-o{xap_dir}', '-y', '-bso0',
                'PROGRAMS/CommonFiles/Xaps/*.xap', 'PROGRAMS/CommonFiles/Xaps/*.appx'])
        log.info('извлекаю Assets-DLL из mainos.img…')
        run_7z(['x', img, f'-o{dll_dir}', '-y', '-bso0',
                'PROGRAMS/*/*480x800.dll', 'PROGRAMS/*/*768x1280.dll',
                'PROGRAMS/*/*1080x1920.dll'])
    return xap_dir, dll_dir


def carve_pngs(blob):
    """Карвинг PNG из бинарного блока (PE-ресурсы). Возвращает список байтов."""
    out, i = [], 0
    while True:
        i = blob.find(PNG_SIG, i)
        if i < 0:
            break
        end = blob.find(PNG_END, i)
        if end > 0:
            out.append(blob[i:end + 8])
            i = end + 8
        else:
            i += 1
    return out


def emulator_stage():
    xap_dir, dll_dir = ensure_emulator_extract()
    if not xap_dir:
        return
    # 1) XAP-ы системных приложений из образа
    for fn in sorted(os.listdir(os.path.join(xap_dir, 'PROGRAMS/CommonFiles/Xaps'))):
        p = os.path.join(xap_dir, 'PROGRAMS/CommonFiles/Xaps', fn)
        low = fn.lower()
        if low.endswith('.xap'):
            base_name = low.replace('.xap', '')
            app = {'bingnews': 'Bing News', 'bingweather': 'Bing Weather',
                   'bingfinance': 'Bing Finance', 'bingsports': 'Bing Sports',
                   'bingtravel': 'Bing Travel', 'bingfood': 'Bing Food & Drink',
                   'binghealth': 'Bing Health & Fitness',
                   'xboxmusic': 'Xbox Music', 'xboxmusic_x86': 'Xbox Music',
                   'xboxvideo': 'Xbox Video', 'xboxvideo_x86': 'Xbox Video',
                   'onedrivewpb': 'OneDrive', 'gameshub_release': 'Xbox Games Hub',
                   'gameshub_release_x86': 'Xbox Games Hub',
                   'skypestub': None, 'ietilemanager': 'Internet Explorer'}.get(
                       base_name,
                       re.sub(r'[_x]+86\.xap$', '', fn))
            if app:
                pkg = {'app': app, 'category': 'standard', 'file': fn,
                       'url': 'внутренний файл образа эмулятора WP8.1 '
                              '(archive.org/items/windows-phone-8.1-emulator.-7z)',
                       'path': p, 'source': 'emulator'}
                extract_package(pkg)
        elif low.endswith('.appx'):
            if low.startswith('microsoft.media.playready') or low.startswith('microsoft.vclibs'):
                continue  # системные библиотеки без иконок
            app = {'exp.apps.calendar.production_x86': 'Calendar',
                   'exp.apps.podcast.production_x86': 'Podcasts',
                   'appplat.apps.filemanager.production_x86': 'Files',
                   'batterysensestore_x86': 'Battery Sense'}.get(low.replace('.appx', ''), fn)
            pkg = {'app': app, 'category': 'standard', 'file': fn,
                   'url': 'внутренний файл образа эмулятора WP8.1 '
                          '(archive.org/items/windows-phone-8.1-emulator.-7z)',
                   'path': p, 'source': 'emulator'}
            extract_package(pkg)
    # 2) Нативные приложения: карвинг PNG из Assets-DLL
    if dll_dir and os.path.isdir(dll_dir):
        programs = os.path.join(dll_dir, 'PROGRAMS')
        if os.path.isdir(programs):
            for folder in sorted(os.listdir(programs)):
                sub = os.path.join(programs, folder)
                if not os.path.isdir(sub):
                    continue
                name = NATIVE_APPS.get(folder, folder.title())
                if not name:
                    continue
                out_dir = os.path.join(TREE, 'standard', slug(name))
                saved = 0
                for fn in sorted(os.listdir(sub)):
                    if not fn.lower().endswith('.dll'):
                        continue
                    blob = open(os.path.join(sub, fn), 'rb').read()
                    for idx, png in enumerate(carve_pngs(blob)):
                        if not save_icon(png, out_dir, f'{fn[:-4]}_{idx}.png',
                                         app=name, category='standard',
                                         package_id=folder, publisher='Microsoft',
                                         version='8.1',
                                         source_url='образ эмулятора WP8.1: '
                                                    'archive.org/details/windows-phone-8.1-emulator.-7z',
                                         source_type='original'):
                            continue
                        saved += 1
                if saved:
                    log.info('нативное %s: %d PNG из Assets-DLL', name, saved)


# ---------------------------------------------------------------------------
# Разбор пакетов
# ---------------------------------------------------------------------------

def read_zip(path):
    """Открывает zip; поддерживает вложенные .appx в .appxbundle."""
    try:
        return zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        return None


def appx_logo_paths(manifest_text):
    """Пути логотипов из AppxManifest.xml (Square*/Wide*/StoreLogo)."""
    res = {}
    for m in re.finditer(
            r'((?:Square|Wide)\d+x\d+Logo|StoreLogo)\s*=\s*"([^"]+)"', manifest_text):
        res[m.group(1)] = m.group(2)
    return res


def xap_icon_paths(manifest_text):
    """Пути иконок из WMAppManifest.xml — все .png/.jpg из атрибутов."""
    vals = set(re.findall(r'>([\w\\\./ -]+\.(?:png|jpg|jpeg))<', manifest_text, re.I))
    vals |= set(re.findall(r'"([\w\\\./ -]+\.(?:png|jpg|jpeg))"', manifest_text, re.I))
    return [v for v in vals if not v.lower().endswith('background_bg.png')]


def xap_manifest_info(zf, root):
    """(title, version, publisher, productid) из WMAppManifest.xml."""
    try:
        txt = zf.read(os.path.join(root, 'WMAppManifest.xml') if root else 'WMAppManifest.xml').decode('utf-8', 'replace')
    except KeyError:
        return None, None, None, None
    app = re.search(r'<App\b[^>]*>', txt)
    title = version = publisher = pid = None
    if app:
        s = app.group(0)
        title = re.search(r'Title="([^"]*)"', s)
        version = re.search(r'Version="([^"]*)"', s)
        publisher = re.search(r'Publisher="([^"]*)"', s)
        pid = re.search(r'ProductID="([^"]*)"', s)
    return (title.group(1) if title else None,
            version.group(1) if version else None,
            publisher.group(1) if publisher else None,
            pid.group(1) if pid else None)


def appx_identity(manifest_text):
    name = version = publisher = None
    m = re.search(r'<Identity\b[^>]*/?>', manifest_text)
    if m:
        s = m.group(0)
        n = re.search(r'Name="([^"]*)"', s)
        v = re.search(r'Version="([^"]*)"', s)
        p = re.search(r'Publisher="([^"]*)"', s)
        name = n.group(1) if n else None
        version = v.group(1) if v else None
        publisher = p.group(1) if p else None
    return name, version, publisher


def img_size(data):
    try:
        from PIL import Image
        with Image.open(io.BytesIO(data)) as im:
            return im.size
    except Exception:
        return None, None


def save_icon(data, out_dir, filename, app, category, package_id, publisher,
              version, source_url, source_type):
    """Сохраняет PNG/JPG c дедупликацией и записью в manifest. -> bool"""
    global MANIFEST_ROWS
    sha = hashlib.sha256(data).hexdigest()
    if sha in SEEN_SHA:
        return False
    SEEN_SHA.add(sha)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, filename)
    with open(path, 'wb') as f:
        f.write(data)
    w, h = img_size(data)
    MANIFEST_ROWS.append({
        'app_name': app, 'package_id': package_id or '', 'publisher': publisher or '',
        'version': version or '', 'category': category, 'file': path,
        'width': w or '', 'height': h or '', 'source_url': source_url,
        'source_type': source_type, 'sha256': sha,
    })
    return True


def norm_join(base_dir, rel):
    """Склеивает путь из манифеста (с \\ или /) с путём внутри пакета."""
    rel = rel.replace('\\', '/').lstrip('/')
    return (base_dir + '/' + rel) if base_dir else rel


def try_read(zf, full):
    """Читает файл из пакета, подбирая разделитель (в XAP записи с '\\')."""
    for cand in (full, full.replace('\\', '/'), full.replace('/', '\\')):
        try:
            return zf.read(cand)
        except KeyError:
            continue
    return None


def collect_scale_variants(zf, base):
    """Все файлы пакета — варианты base.png (scale/targetsize/флэт)."""
    b = base[:-4] if base.lower().endswith('.png') else base
    d = os.path.dirname(b)
    stem = os.path.basename(b)
    out = []
    for n in zf.namelist():
        dn, fn = os.path.split(n.replace('\\', '/'))
        if dn == d and (fn == stem + '.png' or fn.startswith(stem + '.')):
            if fn.lower().endswith(('.png', '.jpg')):
                out.append(n)
    return out


def extract_package(pkg):
    """Разбирает один пакет (xap/appx/appxbundle/zip-дамп) и сохраняет иконки."""
    path = pkg.get('path')
    app = pkg['app']
    category = pkg['category']
    source_url = pkg['url']
    platform = pkg.get('platform', 'wp81')
    zf = pkg.get('_zipobj')
    if zf is None:
        zf = read_zip(path)
    if zf is None:
        log.warning('не zip: %s', path)
        return
    names = zf.namelist()
    saved = 0

    # --- XAP (Windows Phone Silverlight)
    wm = [n for n in names if n.lower().endswith('/wmappmanifest.xml') or n.lower() == 'wmappmanifest.xml']
    if wm:
        root = os.path.dirname(wm[0])
        mtxt = zf.read(wm[0]).decode('utf-8', 'replace')
        title, version, publisher, pid = xap_manifest_info(zf, root)
        if app is None:
            app = title or os.path.basename(path)
        out_dir = os.path.join(TREE, category, slug(app))
        icons = xap_icon_paths(mtxt)
        icons.append('ApplicationIcon.png')
        seen = set()
        for rel in icons:
            full = norm_join(root, rel)
            if full.lower() in seen:
                continue
            seen.add(full.lower())
            data = try_read(zf, full)
            if data is None:
                continue
            base = os.path.basename(full)
            if save_icon(data, out_dir, base, app, category, pid or '',
                         publisher, version, source_url, 'original'):
                saved += 1
        if saved:
            log.info('%s (XAP): %d иконок', app, saved)
        else:
            # фолбэк: типовые имена файлов иконок, если манифест не дал ссылок
            rx_fb = re.compile(
                r'(applicationicon|background|iconic|smallbackground|tile|logo)', re.I)
            for n in names:
                b = os.path.basename(n.replace('\\', '/'))
                low = n.lower()
                if (b.lower().endswith(('.png', '.jpg')) and rx_fb.search(b)
                        and 'content/' not in low and 'images/' not in low):
                    data = zf.read(n)
                    if save_icon(data, out_dir, b, app, category, pid or '',
                                 publisher, version, source_url, 'original'):
                        saved += 1
                        if saved >= 12:
                            break
            if saved:
                log.info('%s (XAP, фолбэк по именам файлов): %d иконок', app, saved)
            else:
                log.warning('%s (XAP): иконки по манифесту не найдены', app)
        return

    # --- APPX / APPXBUNDLE / zip-дамп Win8
    manifest = None
    for n in names:
        if n.lower().endswith('/appxmanifest.xml') or n.lower() == 'appxmanifest.xml':
            manifest = n
            break
    if manifest is None:
        # appxbundle / zip с вложенными пакетами: рекурсивно вскрываем,
        # пропуская фреймворки (.NET Native, VCLibs, PlayReady)
        depth = pkg.get('_depth', 0)
        if depth >= 3:
            log.warning('%s: слишком глубокая вложенность', app or path)
            return
        inner = [n for n in names
                 if n.lower().endswith(('.appx', '.appxbundle'))
                 and not re.search(r'net\.native|vclibs|playready', n, re.I)]
        for n in sorted(inner, key=lambda x: -zf.getinfo(x).file_size):
            try:
                bz = zipfile.ZipFile(io.BytesIO(zf.read(n)))
            except zipfile.BadZipFile:
                continue
            log.info('%s: вложенный %s', app or path, n)
            return extract_package({**pkg, 'path': None, '_zipobj': bz,
                                    '_nested': n, '_depth': depth + 1})
        log.warning('%s: AppxManifest/логотипы не найдены в %s', app or path, path)
        return

    zfobj = pkg.get('_zipobj') or zf
    mtxt = zfobj.read(manifest).decode('utf-8', 'replace')
    pkg_name, version, publisher = appx_identity(mtxt)
    if app is None:
        app = pkg_name or os.path.basename(path)
    out_dir = os.path.join(TREE, category, slug(app))
    base_dir = os.path.dirname(manifest)
    logos = appx_logo_paths(mtxt)
    for kind, rel in logos.items():
        base = norm_join(base_dir, rel)
        for n in collect_scale_variants(zfobj, base):
            data = try_read(zfobj, n)
            if data is None:
                continue
            fn = os.path.basename(n.replace('\\', '/'))
            if save_icon(data, out_dir, fn, app, category, pkg_name or '',
                         publisher, version, source_url, 'original'):
                saved += 1
    if saved:
        log.info('%s (APPX%s): %d иконок', app,
                 ', Win8' if platform == 'win8_store' else '', saved)
    else:
        # логотипы лежат внутри resources.pri (бинарный MRM) — карвим PNG
        pris = [n for n in zfobj.namelist() if n.lower().endswith('.pri')]
        carved = 0
        for pn in pris:
            try:
                blob = zfobj.read(pn)
            except KeyError:
                continue
            for idx, png in enumerate(carve_pngs(blob)):
                if carved >= 40:
                    break
                w, h = img_size(png)
                if not w or w < 44 or h < 44:
                    continue
                if save_icon(png, out_dir,
                             f'{os.path.basename(pn)}_{idx}_{w}x{h}.png',
                             app, category, pkg_name or '', publisher, version,
                             source_url, 'original'):
                    carved += 1
        if carved:
            log.info('%s (APPX, карвинг из %s): %d иконок', app,
                     os.path.basename(pris[0]), carved)
        else:
            log.warning('%s (APPX): иконки не найдены (%s)', app, path)


def extract_stage():
    st = load_state()
    os.makedirs(os.path.join(CACHE, 'pkg'), exist_ok=True)
    for key, rec in st.items():
        if not isinstance(rec, dict) or rec.get('status') != 'ok':
            continue
        path = rec.get('path')
        if path and os.path.exists(path):
            extract_package(rec)
    log.info('Этап extract завершён')


# ---------------------------------------------------------------------------
# Нормализация
# ---------------------------------------------------------------------------

def normalize_stage():
    try:
        from PIL import Image
    except ImportError:
        log.warning('Pillow не установлен — normalized/ пропущен')
        return
    nd = os.path.join(TREE, 'normalized')
    os.makedirs(nd, exist_ok=True)
    apps = {}
    for row in MANIFEST_ROWS:
        apps.setdefault((row['category'], slug(row['app_name'])), row['app_name'])
    for (cat, s), name in sorted(apps.items()):
        best, best_score = None, -1
        app_dir = os.path.join(TREE, cat, s)
        if not os.path.isdir(app_dir):
            continue
        for fn in os.listdir(app_dir):
            p = os.path.join(app_dir, fn)
            try:
                with Image.open(p) as im:
                    w, h = im.size
            except Exception:
                continue
            if w != h:
                score = min(w, h) / 4   # широкие плитки менее пригодны
            else:
                score = w
            if 100 <= w <= 400 and w == h:
                score += 1000           # предпочитаем квадратные 100–400 px
            if score > best_score:
                best, best_score = p, score
        if not best:
            continue
        with Image.open(best) as im:
            im = im.convert('RGBA')
            side = min(im.size)
            left = (im.width - side) // 2
            top = (im.height - side) // 2
            im = im.crop((left, top, left + side, top + side))
            for size in (150, 256):
                out = im.resize((size, size), Image.LANCZOS)
                out.save(os.path.join(nd, f'{s}_{size}.png'))
    log.info('Этап normalize завершён (%d приложений)', len(apps))


# ---------------------------------------------------------------------------
# Redraw (запасной источник)
# ---------------------------------------------------------------------------

REDRAW_URLS = [
    'https://www.deviantart.com/yankoa/art/MetroStation-Icons-331610893',
]

def redraw_stage():
    rd = os.path.join(TREE, 'redraw')
    os.makedirs(rd, exist_ok=True)
    local = os.path.join(CACHE, 'WindowsPhone_Tiles.zip')
    if os.path.exists(local):
        zf = zipfile.ZipFile(local)
        n = 0
        for info in zf.infolist():
            if info.filename.lower().endswith('.png'):
                data = zf.read(info)
                fn = os.path.basename(info.filename)
                app = re.sub(r'\.png$', '', fn, flags=re.I)
                out = os.path.join(rd, slug(app))
                save_icon(data, out, fn, app, 'redraw', '', '', '',
                          'MetroStation (yankoa, CC BY-NC-SA 3.0), локальный файл '
                          'WindowsPhone_Tiles.zip', 'redraw')
                n += 1
        log.info('redraw: %d файлов из локального набора', n)
        return
    ok = False
    for url in REDRAW_URLS:
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read(200000).decode('utf-8', 'replace')
            if 'deviantart' in url and ('error' in body.lower() or len(body) < 1000):
                continue
            ok = True  # страница доступна, но прямой ZIP без кнопки не скачать
        except Exception as e:
            log.info('redraw источник недоступен: %s (%s)', url, e)
    if not ok:
        log.warning('redraw: набор MetroStation недоступен автоматически (DeviantArt '
                    'отдаёт ZIP только после входа в аккаунт). Ручное действие: скачайте '
                    'https://www.deviantart.com/yankoa/art/MetroStation-183210118 '
                    '(или WindowsPhone_Tiles.zip из темы 4PDA showtopic=331476) и положите '
                    'в cache/WindowsPhone_Tiles.zip, затем перезапустите этап redraw.')


# ---------------------------------------------------------------------------
# Отчёт: manifest.csv, README.md, zip
# ---------------------------------------------------------------------------

def write_manifest():
    global MANIFEST_ROWS
    p = os.path.join(TREE, 'manifest.csv')
    if not MANIFEST_ROWS and os.path.exists(p):
        # отчёт запущен отдельным процессом — восстанавливаем из прошлого CSV
        with open(p, encoding='utf-8') as f:
            for r in csv.DictReader(f):
                r['file'] = os.path.join(TREE, r['file'])
                MANIFEST_ROWS.append(r)
        log.info('manifest восстановлен из прошлого CSV: %d записей', len(MANIFEST_ROWS))
    cols = ['app_name', 'package_id', 'publisher', 'version', 'category',
            'file', 'width', 'height', 'source_url', 'source_type', 'sha256']
    with open(p, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in sorted(MANIFEST_ROWS, key=lambda x: (x['category'], x['app_name'], x['file'])):
            r2 = dict(r)
            r2['file'] = os.path.relpath(r['file'], TREE)
            w.writerow(r2)
    log.info('manifest.csv: %d записей', len(MANIFEST_ROWS))


def apps_summary():
    """{app: {category, sizes:set, source, types:set}} по manifest-строкам."""
    apps = {}
    for r in MANIFEST_ROWS:
        a = apps.setdefault(r['app_name'], {
            'category': r['category'], 'sizes': set(), 'source': r['source_url'],
            'types': set(), 'publisher': r['publisher'], 'version': r['version']})
        if r['width'] and r['height']:
            a['sizes'].add(f"{r['width']}x{r['height']}")
        a['types'].add(r['source_type'])
    return apps


def write_readme():
    apps = apps_summary()
    std = {k: v for k, v in apps.items() if v['category'] == 'standard'}
    tp = {k: v for k, v in apps.items() if v['category'] == 'third_party'}
    rd = {k: v for k, v in apps.items() if v['category'] == 'redraw'}
    n_icons = len(MANIFEST_ROWS)

    lines = []
    A = lines.append
    A('# Коллекция иконок плиток Windows Phone 8.1')
    A('')
    A('Собранные оригинальные иконки (тайлы/логотипы) стандартных приложений ОС')
    A('Windows Phone 8.1 и популярных сторонних приложений. Предназначено для')
    A('лаунчера MetroPhone (твик Metro-темы) и личного/некоммерческого использования.')
    A('')
    A('## Структура архива')
    A('')
    A('```')
    A('wp81_icons/')
    A('  standard/<имя_приложения>/  — системные приложения WP8.1')
    A('  third_party/<имя_приложения>/ — сторонние приложения')
    A('  normalized/               — единый размер (PNG 150x150 и 256x256), <app>_150.png')
    A('  redraw/                   — перерисованные наборы (только неоригинальные иконки)')
    A('  manifest.csv              — реестр всех файлов (см. колонки ниже)')
    A('  README.md                 — этот файл')
    A('```')
    A('')
    A('Все файлы сохранены без перекодирования и масштабирования (оригиналы из')
    A('пакетов .xap/.appx или PE-ресурсов системных приложений). Дедупликация —')
    A('по SHA-256: каждый уникальный файл встречается один раз.')
    A('')
    A('## Итоги')
    A('')
    A(f'- Приложений в категории **standard**: {len(std)}')
    A(f'- Приложений в категории **third_party**: {len(tp)}')
    A(f'- Приложений с redraw-иконками: {len(rd)}')
    A(f'- Всего уникальных файлов иконок: {n_icons}')
    A('')
    A('## Таблица приложений')
    A('')
    A('| Приложение | Категория | Издатель | Найденные размеры | Источник | Тип |')
    A('|---|---|---|---|---|---|')

    def row(name, a):
        src = a['source']
        if 'emulator' in src or 'эмулятор' in src:
            src_s = 'образ эмулятора WP8.1 (archive.org)'
        elif 'majkelsoft-xap' in src:
            src_s = 'archive.org/items/majkelsoft-xap'
        elif 'Win8AppxArchive' in src:
            src_s = 'archive.org/items/Win8AppxArchive (Win8 Store, у приложения есть Phone-версия)'
        else:
            m = re.search(r'archive\.org/(?:download|details)/([^)]+)', src)
            src_s = 'archive.org/items/' + m.group(1) if m else src[:70]
        sizes = ', '.join(sorted(a['sizes'])) or '—'
        types = '/'.join(sorted(a['types']))
        A(f"| {name} | {a['category']} | {a['publisher'] or '—'} | {sizes} | {src_s} | {types} |")

    for name, a in sorted(std.items()):
        row(name, a)
    for name, a in sorted(tp.items()):
        row(name, a)
    for name, a in sorted(rd.items()):
        row(name, a)
    A('')

    # Не найденные
    st = load_state()
    missing = [(k, v) for k, v in st.items()
               if isinstance(v, dict) and v.get('status') == 'not_found']
    if missing:
        A('## Приложения, для которых оригинал найти не удалось')
        A('')
        for k, v in sorted(missing, key=lambda x: x[1].get('app', x[0])):
            A(f"- **{v.get('app', k)}** — в архиве archive.org соответствующий пакет не найден.")
        A('')
    A('## Намеренно пропущенные пакеты')
    A('')
    A('- **Perfect Shift** — архив 610 МБ превышает лимит загрузчика.')
    A('- **Game Studio Tycoon 2** — пакет упакован в RAR (нет распаковки RAR5).')
    A('- **N.O.V.A. 3** — XAP крупнее 600 МБ (лимит загрузчика).')
    A('- **Angry Birds Rio/Seasons/Star Wars/Star Wars II/Stella, Amazing Alex'
      ' (частично), Bejeweled Live +, Carcassonne, Battleship, Age of Sparta,'
      ' Bubble Town 2, Burn the Rope, CarneyVale: Showtime, Bug Village, Wordament,'
      ' Tetris Blitz, Hydro Thunder GO, Monopoly, Sonic Dash** — файлы item'
      ' `archive.org/details/wp-xbl-games_202212` закрыты доступом (HTTP 401,'
      ' требуется вход в аккаунт archive.org); обходить защиту запрещено.')
    A('- **Spotify, Shazam, WhatsApp, Instagram, Telegram, Uber, Dropbox, HERE Maps,**')
    A('  **2GIS, Яндекс.приложения** — оригинальных XAP/APPX-пакетов в публичных')
    A('  архивах не найдено (см. «Недоступные источники» ниже); 4PDA отдаёт файлы')
    A('  только авторизованным пользователям.')
    A('')
    A('### Системные приложения без оригинальных пакетов')
    A('')
    A('Часть ядра WP8.1 (Телефон, Сообщения, Люди, Камера, Магазин, Карты, Кортана,')
    A('Skype) в образе эмулятора не представлена в виде отдельных пакетов — эти')
    A('приложения в ОС являются частью оболочки. Оригинальные тайлы для них можно')
    A('получить только дампом retail-прошивки (FFU), поэтому здесь они отсутствуют.')
    A('Перерисованные версии можно добавить через папку redraw/ (набор MetroStation).')
    A('')
    A('## Лицензии и товарные знаки')
    A('')
    A('Все иконки, логотипы и названия приложений являются товарными знаками и')
    A('объектами авторского права их правообладателей: Microsoft Corporation,')
    A('Nokia/Microsoft Mobile, Meta, WhatsApp LLC, Viber Media, Telegram, Google LLC,')
    A('Yandex, Rovio, Gameloft, EA, Uber, Dropbox, Evernote, Netflix, Spotify и других.')
    A('Коллекция собрана в учебных/исследовательских целях для личного')
    A('некоммерческого использования (тема MetroPhone для Windows Phone 8.1).')
    A('Коммерческое использование иконок запрещено без разрешения правообладателей.')
    A('')
    A('Перерисованные наборы (папка redraw/): MetroStation от yankoa (DeviantArt),')
    A('лицензия CC BY-NC-SA 3.0 — только некоммерческое использование с указанием')
    A('авторства и сохранением лицензии производных работ.')
    A('')
    A('## Недоступные источники и ручные действия')
    A('')
    A('- **4PDA** (https://4pda.to/forum/index.php?showtopic=1052376 — каталог программ')
    A('  для WP8.1, showtopic=331476 — набор WindowsPhone_Tiles.zip, showtopic=547567 —')
    A('  системные пакеты): сайт закрыт анти-ботом (HTTP 403) и отдаёт вложения только')
    A('  авторизованным пользователям. Ручное действие: войти в аккаунт, скачать нужные')
    A('  XAP и положить их в `cache/pkg/` — этап `extract` подхватит их автоматически.')
    A('- **Viber и Opera Mini**: официальные XAP из открытых архивов зашифрованы')
    A('  PlayReady (сигнатура WRMHEADER). Расшифровка — обход DRM, не выполнялась.')
    A('  Ручное действие: взять распакованные (декриптованные) копии из своих')
    A('  резервных копий и положить в `cache/pkg/`.')
    A('- **DeviantArt, набор MetroStation (yankoa, CC BY-NC-SA 3.0)**')
    A('  (https://www.deviantart.com/yankoa/art/MetroStation-183210118): страница')
    A('  публична, но ZIP доступен только после входа в аккаунт DeviantArt.')
    A('  Ручное действие: скачать и положить `WindowsPhone_Tiles.zip` в `cache/`,')
    A('  затем перезапустить этап `redraw` — папка redraw/ заполнится автоматически.')
    A('- **archive.org/items/wp-xbl-games_202212** — файлы закрыты доступом (HTTP 401,')
    A('  требуется вход в аккаунт archive.org).')
    A('- **Windows Phone 8.1 SDK** (archive.org/items/windowsphone81sdkupdate1_202303) —')
    A('  тёмный item (доступ ограничен правообладателем).')
    A('- **Wayback Machine** (страницы Windows Phone Store): снапшоты страниц приложений')
    A('  в основном отсутствуют или HTTP 404, API периодически отдаёт rate-limit.')
    A('')
    A('## Как воспроизвести сборку')
    A('')
    A('Скрипт: `build_icons.py` (Python 3.8+, зависимости: Pillow). Шаги:')
    A('')
    A('```bash')
    A('pip3 install Pillow')
    A('python3 build_icons.py download   # скачивание пакетов с archive.org')
    A('python3 build_icons.py emulator   # системные приложения из образа эмулятора')
    A('python3 build_icons.py extract    # извлечение иконок по манифестам')
    A('python3 build_icons.py normalize  # normalized/ (150 и 256 px)')
    A('python3 build_icons.py redraw     # перерисованные наборы (если доступны)')
    A('python3 build_icons.py report     # manifest.csv + README.md + wp81_icons.zip')
    A('```')
    A('')
    A('Подготовка образа эмулятора (один раз, до этапа `emulator`):')
    A('')
    A('```bash')
    A('# 1. Скачать эмулятор WP8.1 (638 МБ):')
    A('curl -L "https://archive.org/download/windows-phone-8.1-emulator.-7z/'
    'Windows%20Phone%208.1%20Emulator.7z" -o cache/wp81_emulator.7z')
    A('# 2. Извлечь flash.vhd и конвертировать в raw (скрипт vhd_to_raw.py):')
    A('7z x cache/wp81_emulator.7z "Windows Phone 8.1/flash.vhd" -ocache/')
    A('python3 vhd_to_raw.py "cache/Windows Phone 8.1/flash.vhd" cache/flash.raw')
    A('# 3. Вырезать раздел MainOS (NTFS, offset 45154816, размер 2393296896)')
    A('#    разреженно в cache/mainos.img (см. build_icons.py, этап emulator).')
    A('```')
    A('')
    A('Источники (все публично доступные):')
    A('')
    A('- https://archive.org/details/windows-phone-8.1-emulator.-7z — образ эмулятора WP8.1')
    A('- https://archive.org/details/majkelsoft-xap — XAP системных приложений')
    A('- https://archive.org/details/wp-xbl-games_202212 — XBL-игры для WP')
    A('- https://archive.org/details/carls-xap-archive, /details/winphone-xap,')
    A('  /details/fifa-14_202403 — XAP-архивы приложений и игр')
    A('- https://archive.org/details/Win8AppxArchive — Windows 8 Store (для приложений,')
    A('  у которых есть Phone-версия: Netflix, Flipboard, Kindle и др.)')
    A('- 4PDA (https://4pda.to/forum/index.php?showtopic=1052376) — недоступен скрипту')
    A('  (требуется вход/капча): ручное действие, при необходимости скачайте XAP оттуда')
    A('  и положите в cache/pkg/ — этап extract подхватит их автоматически.')
    A('')
    p = os.path.join(TREE, 'README.md')
    with open(p, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    log.info('README.md готов')


def zip_stage():
    zpath = os.path.join(BASE, 'wp81_icons.zip')
    if os.path.exists(zpath):
        os.remove(zpath)
    shutil.make_archive(os.path.splitext(zpath)[0], 'zip', OUT, 'wp81_icons')
    log.info('zip готов: %s (%.1f МБ)', zpath, os.path.getsize(zpath) / (1024 * 1024))


# ---------------------------------------------------------------------------

STAGES = {
    'download': download_stage,
    'emulator': emulator_stage,
    'extract': extract_stage,
    'normalize': normalize_stage,
    'redraw': redraw_stage,
    'report': lambda: (write_manifest(), write_readme()),
    'zip': zip_stage,
}


def main():
    stages = sys.argv[1:] or list(STAGES)
    t0 = time.time()
    for s in stages:
        log.info('=== Этап %s ===', s)
        STAGES[s]()
    log.info('Готово за %.1f c. Иконок: %d, приложений: %d',
             time.time() - t0, len(MANIFEST_ROWS),
             len({r['app_name'] for r in MANIFEST_ROWS}))


if __name__ == '__main__':
    main()

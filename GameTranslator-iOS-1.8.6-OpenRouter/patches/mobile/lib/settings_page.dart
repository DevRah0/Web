// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:convert';

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'bridge.dart';
import 'diagnostics_page.dart';
import 'extra_region_page.dart';
import 'health_page.dart';
import 'history_page.dart';
import 'home_page.dart';
import 'intro_page.dart';
import 'l10n.dart';
import 'main.dart';
import 'tv_install_page.dart';
import 'ui.dart';

/// Ayarlar sekmesi, iOS ayarları düzeninde: çeviri, altyazı bölgesi, TV'deki görünüm, PS5 ve hakkında.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.setup, required this.onSetupChanged, required this.active});

  final SetupInfo setup;
  final Future<void> Function() onSetupChanged;

  /// Sekme ekranda mı? Arkadayken oyun görüntüsü istenmez.
  final bool active;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  static const languages = {
    'tr': 'Türkçe',
    'en': 'İngilizce',
    'de': 'Almanca',
    'fr': 'Fransızca',
    'es': 'İspanyolca',
    'it': 'İtalyanca',
    'pt': 'Portekizce',
    'ru': 'Rusça',
    'ar': 'Arapça',
    'ja': 'Japonca',
    'zh': 'Çince',
    'ko': 'Korece',
    'pl': 'Lehçe',
    'nl': 'Felemenkçe',
    'id': 'Endonezce',
    'hi': 'Hintçe',
    'fa': 'Farsça',
    'uk': 'Ukraynaca',
    'el': 'Yunanca',
    'hu': 'Macarca',
    'ro': 'Romence',
    'cs': 'Çekçe',
    'sv': 'İsveççe',
    'th': 'Tayca',
    'vi': 'Vietnamca',
    'he': 'İbranice',
    'az': 'Azerice',
  };

  static const languagesEn = {
    'tr': 'Turkish',
    'en': 'English',
    'de': 'German',
    'fr': 'French',
    'es': 'Spanish',
    'it': 'Italian',
    'pt': 'Portuguese',
    'ru': 'Russian',
    'ar': 'Arabic',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'ko': 'Korean',
    'pl': 'Polish',
    'nl': 'Dutch',
    'id': 'Indonesian',
    'hi': 'Hindi',
    'fa': 'Persian',
    'uk': 'Ukrainian',
    'el': 'Greek',
    'hu': 'Hungarian',
    'ro': 'Romanian',
    'cs': 'Czech',
    'sv': 'Swedish',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'he': 'Hebrew',
    'az': 'Azerbaijani',
  };

  /// Arayüz diline göre dil adları.
  static Map<String, String> get languageNames => L.en ? languagesEn : languages;

  static const flags = {
    'tr': '🇹🇷',
    'en': '🇬🇧',
    'de': '🇩🇪',
    'fr': '🇫🇷',
    'es': '🇪🇸',
    'it': '🇮🇹',
    'pt': '🇵🇹',
    'ru': '🇷🇺',
    'ar': '🇸🇦',
    'ja': '🇯🇵',
    'zh': '🇨🇳',
    'ko': '🇰🇷',
    'pl': '🇵🇱',
    'nl': '🇳🇱',
    'id': '🇮🇩',
    'hi': '🇮🇳',
    'fa': '🇮🇷',
    'uk': '🇺🇦',
    'el': '🇬🇷',
    'hu': '🇭🇺',
    'ro': '🇷🇴',
    'cs': '🇨🇿',
    'sv': '🇸🇪',
    'th': '🇹🇭',
    'vi': '🇻🇳',
    'he': '🇮🇱',
    'az': '🇦🇿',
  };

  /// Gemini modelleri (ai-models.json); ilki varsayılandır.
  static Map<String, String> get geminiModels => {
        'gemini-3.5-flash-lite': L.t('Hızlı ve ucuz (önerilen)', 'Fast and cheap (recommended)'),
        'gemini-3.6-flash': L.t('Daha iyi çeviri, biraz yavaş', 'Better translation, a little slower'),
      };

  static Map<String, String> get textColors => {
        'white': L.t('Beyaz', 'White'),
        'yellow': L.t('Sarı', 'Yellow'),
        'cyan': L.t('Camgöbeği', 'Cyan'),
        'green': L.t('Yeşil', 'Green'),
        'orange': L.t('Turuncu', 'Orange'),
      };

  /// Altyazı yazı tipleri (yalnız iOS; TV uygulaması 1.0.9 ve üstü gösterir).
  static Map<String, String> get subtitleFonts => {
        'default': L.t('Standart', 'Standard'),
        'quicksand': 'Quicksand',
      };

  static Map<String, String> get placements => {
        'cover': L.t('Oyunun altyazısını örterek', 'Covering the game\'s subtitle'),
        'above': L.t('Oyunun altyazısının üstünde', 'Above the game\'s subtitle'),
        'below': L.t('Oyunun altyazısının altında', 'Below the game\'s subtitle'),
        'fixed': L.t('Ekranın altında sabit', 'Fixed at the bottom of the screen'),
      };

  static Map<String, String> get edges => {
        'top': L.t('Üst', 'Top'),
        'bottom': L.t('Alt', 'Bottom'),
        'left': L.t('Sol', 'Left'),
        'right': L.t('Sağ', 'Right'),
      };
  static const defaultRegion = {'top': 0.62, 'bottom': 0.97, 'left': 0.14, 'right': 0.86};

  /// Tek dokunuşla bölge seçimleri (Windows'taki Alt/Üst/Tam seçimlerinin genişletilmişi). "Özel" hiçbiriyle eşleşmeyen değerlerdir.
  static const regionPresets = <(String, Map<String, double>)>[
    ('Alt orta (standart)', {'top': 0.62, 'bottom': 0.97, 'left': 0.14, 'right': 0.86}),
    ('Alt yarı', {'top': 0.50, 'bottom': 0.98, 'left': 0.05, 'right': 0.95}),
    ('Geniş alt bant', {'top': 0.70, 'bottom': 0.98, 'left': 0.03, 'right': 0.97}),
    ('Üst bölge', {'top': 0.03, 'bottom': 0.30, 'left': 0.10, 'right': 0.90}),
    ('Tam ekran', {'top': 0.02, 'bottom': 0.98, 'left': 0.02, 'right': 0.98}),
  ];

  /// Hazır seçimin ekranda görünen adı (kimlik olarak Türkçe ad kullanılır).
  static String presetLabel(String name) {
    if (!L.en) return name;
    return const {
          'Alt orta (standart)': 'Bottom center (default)',
          'Alt yarı': 'Lower half',
          'Geniş alt bant': 'Wide bottom band',
          'Üst bölge': 'Top area',
          'Tam ekran': 'Full screen',
          'Özel': 'Custom',
        }[name] ??
        name;
  }

  /// Geçerli bölgeyle eşleşen hazır seçimin adı; yoksa 'Özel'.
  String matchingPreset(AppSettings s) {
    for (final (name, values) in regionPresets) {
      if (values.entries.every((e) => (s.regionValue(e.key) - e.value).abs() <= 0.006)) return name;
    }
    return 'Özel';
  }

  AppSettings? settings;
  final deepLController = TextEditingController();
  final openRouterController = TextEditingController();
  bool openRouterSaved = false;
  bool checkingOpenRouter = false;
  (bool, String)? openRouterResult;

  final geminiController = TextEditingController();
  final geminiStyleController = TextEditingController();
  final geminiStyleFocus = FocusNode();
  bool checkingGemini = false;
  bool updatingPatches = false;
  (bool, String)? patchesResult;

  /// Bilgisayar sürümündeki "Oyun" seçimi: en üstte Otomatik, altında Türkçe yaması olan oyunlar.
  Future<void> pickGame() async {
    final games = await Bridge.packList();
    if (!mounted) return;
    final options = <String, String>{'': L.t('Otomatik (oyunu kendisi bulur)', 'Automatic (finds the game itself)')};
    for (final game in games) {
      options[game.id] = L.t('${game.title} · ${game.entries} satır', '${game.title} · ${game.entries} lines');
    }
    final picked = await showApplePicker(context, title: L.t('Oyun', 'Game'), options: options, selected: settings?.packChoice ?? '');
    if (picked != null) change((s) => s.json['packChoice'] = picked);
    if (games.isNotEmpty) setState(() => gameTitles = {for (final game in games) game.id: game.title});
  }

  Map<String, String> gameTitles = {};

  /// Paket listesi henüz alınmadıysa kimlikten okunur ad: "mafia-the-old-country" → "Mafia The Old Country".
  static String titleFromId(String id) => id
      .split(RegExp('[-_]'))
      .where((w) => w.isNotEmpty)
      .map((w) => RegExp(r'^(ii|iii|iv|v|vi|vii|viii|ix|x|xi|xii)$').hasMatch(w) ? w.toUpperCase() : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  Future<void> updatePatches() async {
    setState(() {
      updatingPatches = true;
      patchesResult = null;
    });
    final result = await Bridge.updatePatches();
    if (!mounted) return;
    setState(() {
      updatingPatches = false;
      patchesResult = result;
    });
  }
  (bool, String)? geminiResult;

  /// Anahtarı hemen kaydeder ve bir deneme çevirisiyle sınar.
  Future<void> checkGemini() async {
    final current = settings;
    if (current == null) return;
    current.json['geminiKey'] = geminiController.text.trim();
    saveTimer?.cancel();
    setState(() {
      checkingGemini = true;
      geminiResult = null;
    });
    await Bridge.saveSettings(current);
    final result = await Bridge.checkGemini(geminiController.text.trim());
    if (!mounted) return;
    setState(() {
      checkingGemini = false;
      geminiResult = result;
    });
  }
  Future<void> checkOpenRouter() async {
    final key = openRouterController.text.trim();
    if (key.isEmpty) {
      setState(() => openRouterResult = (false, 'Enter an OpenRouter API key.'));
      return;
    }
    setState(() {
      checkingOpenRouter = true;
      openRouterResult = null;
    });
    final test = await Bridge.checkOpenRouter(key);
    if (!mounted) return;
    setState(() {
      checkingOpenRouter = false;
      openRouterResult = test;
      if (test.$1) {
        openRouterSaved = true;
        openRouterController.clear();
      }
    });
  }

  bool checkingDeepL = false;
  (bool, String)? deepLResult;

  /// DeepL anahtarını hemen kaydeder ve kota sorgusuyla sınar.
  Future<void> checkDeepL() async {
    final current = settings;
    if (current == null) return;
    current.json['deepLKey'] = deepLController.text.trim();
    saveTimer?.cancel();
    setState(() {
      checkingDeepL = true;
      deepLResult = null;
    });
    await Bridge.saveSettings(current);
    final result = await Bridge.checkDeepL(deepLController.text.trim());
    if (!mounted) return;
    setState(() {
      checkingDeepL = false;
      deepLResult = result;
    });
  }

  Uint8List? preview;
  Timer? saveTimer;
  Timer? previewTimer;
  StreamSubscription<EngineState>? stateSubscription;

  /// Önceki çalıştırmadaki çökme (yalnız iOS).
  CrashInfo? crash;

  /// PS5'siz deneme açık mı (yalnız iOS).
  bool demoOn = false;

  /// Altyazı bölgesinde sürgünün ayarladığı kenar.
  String edge = 'top';

  @override
  void initState() {
    super.initState();
    load();
    geminiStyleFocus.addListener(onStyleFocus);
    if (Platform.isIOS) {
      loadIosExtras();
      stateSubscription = Bridge.states.listen((next) {
        final demo = next.demo;
        if (mounted && demo != null && demo != demoOn) setState(() => demoOn = demo);
      });
    }
    // Bölge ayarlanırken oyun görüntüsü güncel kalsın.
    previewTimer = Timer.periodic(const Duration(seconds: 2), (_) => refreshPreview());
  }

  @override
  void didUpdateWidget(covariant SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sekmeden çıkılırken kutuda kaydedilmemiş ek talimat kalmasın.
    if (oldWidget.active && !widget.active) commitStyleNote();
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    previewTimer?.cancel();
    stateSubscription?.cancel();
    geminiStyleFocus.removeListener(onStyleFocus);
    geminiStyleFocus.dispose();
    final current = settings;
    if (current != null) {
      current.json['geminiStyleNote'] = geminiStyleController.text;
      Bridge.saveSettings(current);
    }
    openRouterController.dispose();
    deepLController.dispose();
    geminiController.dispose();
    geminiStyleController.dispose();
    super.dispose();
  }

  /// Ek talimat yazarken kaydedilmez (akışta her kayıt çevirmeni yeniden kurar); klavyede "bitti", odak gidince ya da
  /// sekmeden çıkınca bir kez kaydedilir. Kayıtlı metinle aynıysa kayıt yapılmaz.
  void commitStyleNote() {
    final current = settings;
    final text = geminiStyleController.text;
    if (current == null || current.geminiStyleNote == text) return;
    current.json['geminiStyleNote'] = text;
    saveTimer?.cancel();
    Bridge.saveSettings(current);
  }

  void onStyleFocus() {
    if (!geminiStyleFocus.hasFocus) commitStyleNote();
  }

  /// iOS'a özgü bilgiler: önceki çökme ve deneme durumu.
  Future<void> loadIosExtras() async {
    final lastCrash = await Bridge.lastCrash();
    bool? demo;
    try {
      demo = (await Bridge.state()).demo;
    } on Object {
      demo = null;
    }
    if (!mounted) return;
    setState(() {
      crash = lastCrash;
      if (demo != null) demoOn = demo;
    });
  }

  Future<void> setDemo(bool on) async {
    setState(() => demoOn = on);
    if (on) {
      await Bridge.demoStart();
    } else {
      await Bridge.demoStop();
    }
  }

  Future<void> resetAll() async {
    final confirmed = await confirmApple(
      context,
      title: L.t('Bütün ayarlar sıfırlansın mı?', 'Reset all settings?'),
      message: L.t(
        'Çeviri, bölge, görünüm ve sözlük ayarları varsayılana döner. '
            'PS5 eşleştirmesi, PSN hesabı ve API anahtarların korunur.',
        'Translation, area, appearance and glossary settings return to their defaults. '
            'Your PS5 pairing, PSN account and API keys are kept.',
      ),
      action: L.t('Sıfırla', 'Reset'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    saveTimer?.cancel();
    final fresh = await Bridge.resetSettings();
    if (!mounted) return;
    if (fresh == null) {
      toast(context, L.t('Ayarlar sıfırlanamadı.', 'Could not reset settings.'));
      return;
    }
    setState(() {
      settings = fresh;
      deepLController.text = fresh.deepLKey;
      geminiController.text = fresh.geminiKey;
      geminiStyleController.text = fresh.geminiStyleNote;
    });
    L.apply(fresh.uiLanguage);
    toast(context, L.t('Ayarlar sıfırlandı.', 'Settings reset.'));
  }

  String crashTime(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)}.${at.year} ${clockText(at)}';
  }

  void showCrash() {
    final info = crash;
    if (info == null) return;
    final report = '${crashTime(info.at)}\n${info.kind}: ${info.name}\n\n${info.detail}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (sheet, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(L.t('Önceki çalıştırma çöktü', 'The previous run crashed'), style: Txt.title2),
            const SizedBox(height: 4),
            Text('${crashTime(info.at)} · ${info.name}', style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: report));
                    toast(context, L.t('Çökme bilgisi kopyalandı.', 'Crash details copied.'));
                  },
                  child: Text(L.t('Kopyala', 'Copy')),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(sheet).pop();
                    await Bridge.clearCrash();
                    if (mounted) setState(() => crash = null);
                  },
                  child: Text(L.t('Sil', 'Delete'), style: const TextStyle(color: Tokens.danger)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              info.detail.isEmpty ? L.t('Ayrıntı yok.', 'No details.') : info.detail,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Tokens.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  /// Ek okuma alanını düzenleme sayfasında açar; kaydedilince ya da silinince ayarlara işler.
  Future<void> editExtra(int index) async {
    final current = settings;
    if (current == null) return;
    final regions = current.extraRegions;
    if (index < 0 || index >= regions.length) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      appleRoute((_) => ExtraRegionPage(initial: regions[index], image: preview)),
    );
    if (result == null || !mounted) return;
    change((s) {
      final list = s.extraRegions;
      if (index >= list.length) return;
      if (result['delete'] == true) {
        list.removeAt(index);
      } else {
        list[index] = result;
      }
      s.json['extraRegions'] = list;
    });
  }

  Future<void> addExtra() async {
    final current = settings;
    if (current == null || current.extraRegions.length >= 3) return;
    final count = current.extraRegions.length;
    change((s) {
      s.json['extraRegions'] = [
        ...s.extraRegions,
        {'top': 0.05, 'bottom': 0.25, 'left': 0.10, 'right': 0.90, 'name': L.t('Alan ${count + 1}', 'Area ${count + 1}')},
      ];
    });
    await editExtra(count);
  }

  Future<void> load() async {
    final loaded = await Bridge.settings();
    final hasOpenRouterKey = Platform.isIOS ? await Bridge.hasOpenRouterKey() : false;
    final image = await Bridge.snapshot(width: 640);
    if (!mounted) return;
    setState(() {
      settings = loaded;
      openRouterSaved = hasOpenRouterKey;
      preview = image;
      deepLController.text = loaded.deepLKey;
      geminiController.text = loaded.geminiKey;
      geminiStyleController.text = loaded.geminiStyleNote;
    });
  }

  Future<void> refreshPreview() async {
    if (!mounted || !widget.active) return;
    final image = await Bridge.snapshot(width: 640);
    if (mounted && image != null) setState(() => preview = image);
  }

  /// Değişiklik hemen ekrana yansır; kaydetme sürgü sürüklenirken her adımda değil, kısa bir aradan sonra yapılır.
  void change(void Function(AppSettings) edit) {
    final current = settings;
    if (current == null) return;
    setState(() => edit(current));
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 300), () => Bridge.saveSettings(current));
  }

  Widget _presetChip(String label, {required bool selected, VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Tokens.accent : Tokens.inset,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label, style: Txt.subhead.copyWith(fontFamily: 'Inter', color: Colors.white, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ),
      );

  void setRegion(String edge, double next) => change((s) {
        final region = s.region;
        // Kaydederken uygulanan sınırlar: üst ve sol kenar en çok %95, alt ve sağ kenar en az %5.
        final value = edge == 'top' || edge == 'left' ? next.clamp(0.0, 0.95) : next.clamp(0.05, 1.0);
        region[edge] = value;
        // Bölge en az %5 yüksekliğinde ve genişliğinde kalır.
        if (edge == 'top' && region['bottom'] < value + 0.05) region['bottom'] = (value + 0.05).clamp(0.0, 1.0);
        if (edge == 'bottom' && region['top'] > value - 0.05) region['top'] = (value - 0.05).clamp(0.0, 1.0);
        if (edge == 'left' && region['right'] < value + 0.05) region['right'] = (value + 0.05).clamp(0.0, 1.0);
        if (edge == 'right' && region['left'] > value - 0.05) region['left'] = (value - 0.05).clamp(0.0, 1.0);
        s.json['region'] = region;
      });

  void setStyle(String key, Object value) => change((s) {
        final style = s.style;
        style[key] = value;
        s.json['style'] = style;
      });

  /// Oyunun dili: ekran okuma (Vision) yalnız bunları okuyabilir.
  static const sourceCodes = ['en', 'ja', 'zh', 'ko', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'uk', 'ar', 'th', 'vi', 'tr'];

  Future<void> pickLanguage(String key, String title, {Iterable<String>? only}) async {
    final names = languageNames;
    final options = only == null ? names : {for (final code in only) code: names[code] ?? code};
    final picked = await showApplePicker(context, title: title, options: options, selected: settings?.json[key] as String?, leading: flags);
    if (picked != null) change((s) => s.json[key] = picked);
  }

  /// Ek talimat kutusunun hazır seçenekleri (etiket, kutuya yazılan metin).
  List<(String, String)> get styleNotePresets => [
        (L.t('Samimi', 'Casual'), L.t('Samimi, günlük konuşma diliyle çevir.', 'Translate in a casual, everyday tone.')),
        (L.t('Argo', 'Slang'), L.t('Argo ve sokak ağzını koru, yumuşatma.', 'Keep slang and street talk, do not soften it.')),
        (L.t('Resmî', 'Formal'), L.t('Resmî ve saygılı bir dille çevir.', 'Translate in a formal, respectful tone.')),
        (L.t('Kısa', 'Short'), L.t('Çeviriyi kısa ve öz tut.', 'Keep the translation short and to the point.')),
      ];

  /// Seçenek kutunun metninin yerine geçer; elle yazılmış gibi kaydedilir.
  void applyStyleNote(String text) {
    geminiStyleController.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    change((s) => s.json['geminiStyleNote'] = text);
  }

  Future<void> pickGeminiModel() async {
    final picked = await showApplePicker(context, title: L.t('Gemini modeli', 'Gemini model'), options: geminiModels, selected: geminiModelId);
    if (picked != null) change((s) => s.json['geminiModel'] = picked);
  }

  String get geminiModelId {
    final id = settings?.json['geminiModel'] as String?;
    return geminiModels.containsKey(id) ? id! : geminiModels.keys.first;
  }

  Future<void> pickTextColor() async {
    final current = settings?.style['textColor'] as String?;
    final picked = await showApplePicker(
      context,
      title: L.t('Yazı rengi', 'Text color'),
      options: textColors,
      selected: textColors.containsKey(current) ? current : 'white',
    );
    if (picked != null) setStyle('textColor', picked);
  }

  Future<void> pickSubtitleFont() async {
    final current = settings?.style['subtitleFont'] as String?;
    final picked = await showApplePicker(
      context,
      title: L.t('Altyazı yazı tipi', 'Subtitle font'),
      options: subtitleFonts,
      selected: subtitleFonts.containsKey(current) ? current : 'default',
    );
    if (picked != null) setStyle('subtitleFont', picked);
  }

  Future<void> pickPlacement() async {
    final picked = await showApplePicker(context, title: L.t('Altyazının yeri', 'Subtitle position'), options: placements, selected: settings?.style['placement'] as String?);
    if (picked != null) setStyle('placement', picked);
  }

  /// Arayüz dili ayarını seçtirir; seçilen dil hemen uygulanır.
  Future<void> pickUiLanguage() async {
    final picked = await showApplePicker(
      context,
      title: L.t('Uygulama dili', 'App language'),
      options: {
        'auto': L.t('Otomatik (telefonun dili)', 'Automatic (phone language)'),
        'tr': 'Türkçe',
        'en': 'English',
      },
      selected: settings?.uiLanguage ?? 'auto',
    );
    if (picked == null) return;
    L.apply(picked);
    if (mounted) change((s) => s.json['uiLanguage'] = picked);
  }

  String get uiLanguageLabel => switch (settings?.uiLanguage ?? 'auto') {
        'tr' => 'Türkçe',
        'en' => 'English',
        _ => L.t('Otomatik', 'Automatic'),
      };

  Future<void> editGlossary() async {
    final current = settings;
    if (current == null) return;
    final text = await Navigator.of(context).push<String>(appleRoute((_) => GlossaryPage(initial: current.glossary)));
    if (text != null) change((s) => s.json['glossary'] = text);
  }

  Future<void> sendTest() async {
    await Bridge.testSubtitle();
    if (mounted) toast(context, L.t('Deneme altyazısı gönderildi.', 'Test subtitle sent.'));
  }

  Future<void> confirmForget({required bool account}) async {
    final confirmed = await confirmApple(
      context,
      title: account ? L.t('PSN hesabı değiştirilsin mi?', 'Change the PSN account?') : L.t('PS5 yeniden eşleştirilsin mi?', 'Pair the PS5 again?'),
      message: account
          ? L.t('Kayıtlı hesap ve PS5 eşleştirmesi silinir; kurulumu baştan yaparsın.', 'The saved account and PS5 pairing are removed; you will set everything up again.')
          : L.t(
              'Kayıtlı eşleştirme silinir; PS5\'teki "Cihaz Eşleştir" koduyla yeniden eşleştirirsin.',
              'The saved pairing is removed; you will pair again using the "Link Device" code on the PS5.',
            ),
      action: L.t('Sil ve Devam Et', 'Delete and Continue'),
      destructive: true,
    );
    if (!confirmed) return;
    await Bridge.stop();
    if (account) {
      await Bridge.forgetAccount();
    } else {
      await Bridge.forgetConsole();
    }
    await widget.onSetupChanged();
  }

  void showIntro() {
    Navigator.of(context).push(appleRoute<void>((context) => IntroPage(replay: true, onDone: () async => Navigator.of(context).pop())));
  }

  Future<void> showLogs() async {
    final lines = await Bridge.logs();
    if (!mounted) return;
    final text = lines.isEmpty ? L.t('Henüz kayıt yok.', 'No entries yet.') : lines.reversed.join('\n');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (sheet, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                Expanded(child: Text(L.t('Günlük', 'Log'), style: Txt.title2)),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.of(sheet).pop();
                    toast(context, L.t('Günlük kopyalandı.', 'Log copied.'));
                  },
                  child: Text(L.t('Kopyala', 'Copy')),
                ),
              ],
            ),
            Text(L.t('Bir sorun olduğunda destek için bu kayıtları paylaşabilirsin.', 'If something goes wrong, you can share these entries with support.'), style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            const SizedBox(height: 12),
            SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Tokens.textSecondary, height: 1.45)),
          ],
        ),
      ),
    );
  }

  String get glossarySummary {
    final (terms, keep, problem) = GlossaryPage.inspect(settings?.glossary ?? '');
    if (problem != null) return L.t('Hatalı', 'Invalid');
    if (terms + keep == 0) return L.t('Boş', 'Empty');
    return L.t('${terms + keep} terim', '${terms + keep} terms');
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s == null) return const Center(child: CupertinoActivityIndicator(radius: 14));
    final style = s.style;
    return LargeTitleList(
      title: L.t('Ayarlar', 'Settings'),
      children: [
        if (Platform.isIOS && crash != null) ...[
          Group(
            inset: 60,
            children: [
              Cell(
                icon: CupertinoIcons.exclamationmark_triangle_fill,
                iconColor: Tokens.danger,
                title: L.t('Önceki çalıştırma çöktü', 'The previous run crashed'),
                subtitle: '${crashTime(crash!.at)} · ${crash!.name}',
                chevron: true,
                onTap: showCrash,
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        // ---------------------------------------------------------------- Genel (yalnız iOS: Android'de arayüz Türkçedir)
        if (Platform.isIOS) ...[
          GroupHeader(L.t('GENEL', 'GENERAL')),
          Group(
            inset: 60,
            children: [
              Cell(
                icon: CupertinoIcons.globe,
                iconColor: Tokens.teal,
                title: L.t('Uygulama dili', 'App language'),
                value: uiLanguageLabel,
                chevron: true,
                onTap: pickUiLanguage,
              ),
            ],
          ),
        ],
        // ---------------------------------------------------------------- Çeviri
        GroupHeader(L.t('ÇEVİRİ', 'TRANSLATION')),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.gamecontroller_fill,
              iconColor: Tokens.indigo,
              title: L.t('Oyunun dili', 'Game language'),
              value: '${flags[s.sourceLanguage] ?? ''} ${languageNames[s.sourceLanguage] ?? s.sourceLanguage}',
              chevron: true,
              onTap: () => pickLanguage('sourceLanguage', L.t('Oyunun dili', 'Game language'), only: sourceCodes),
            ),
            Cell(
              icon: CupertinoIcons.globe,
              iconColor: Tokens.accent,
              title: L.t('Çeviri dili', 'Translation language'),
              value: '${flags[s.targetLanguage] ?? ''} ${languageNames[s.targetLanguage] ?? s.targetLanguage}',
              chevron: true,
              onTap: () => pickLanguage('targetLanguage', L.t('Çeviri dili', 'Translation language')),
            ),
            if (s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.book_fill,
                iconColor: Tokens.warning,
                title: L.t('Terim sözlüğü', 'Glossary'),
                value: glossarySummary,
                chevron: true,
                onTap: editGlossary,
              ),
            if (s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.cube_box_fill,
                iconColor: Tokens.success,
                title: L.t('Oyun paketleri', 'Game packs'),
                subtitle: L.t('GTA V, RDR2, Elden Ring… satırları hazır Türkçesiyle', 'GTA V, RDR2, Elden Ring… lines with ready-made Turkish'),
                trailing: CupertinoSwitch(
                  value: s.packsEnabled,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['packsEnabled'] = value),
                ),
              ),
            if (Platform.isIOS && s.packsEnabled && s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.gamecontroller_fill,
                iconColor: Tokens.accent,
                title: L.t('Oyun', 'Game'),
                value: s.packChoice.isEmpty ? L.t('Otomatik', 'Automatic') : (gameTitles[s.packChoice] ?? titleFromId(s.packChoice)),
                chevron: true,
                onTap: pickGame,
              ),
            if (Platform.isIOS && s.packsEnabled && s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
              Cell(
                icon: CupertinoIcons.arrow_down_circle_fill,
                iconColor: Tokens.success,
                title: updatingPatches ? L.t('Yamalar denetleniyor…', 'Checking patches…') : L.t('Topluluk yamalarını güncelle', 'Update community patches'),
                subtitle: patchesResult?.$2 ??
                    L.t('Yeni ve güncellenen oyun yamalarını indirir (haftada bir kendiliğinden)', 'Downloads new and updated game patches (automatically once a week)'),
                onTap: updatingPatches ? null : updatePatches,
              ),
            if (Platform.isIOS)
              Cell(
                icon: CupertinoIcons.game_controller_solid,
                iconColor: Tokens.accent,
                title: L.t('Tuş yazılarını gizle', 'Hide button labels'),
                subtitle: L.t('Altyazının yanındaki "SKIP", "RESUME" gibi düğme yazıları çevrilmez', 'Button labels next to the subtitle, such as "SKIP" or "RESUME", are not translated'),
                trailing: CupertinoSwitch(
                  value: s.hideButtonHints,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['hideButtonHints'] = value),
                ),
              ),
          ],
        ),
        if (s.sourceLanguage == 'en' && s.targetLanguage == 'tr')
          GroupFooter(L.t(
            'Oyunun paketinde bulunan satır çeviri motoruna gitmeden paketteki Türkçesiyle gösterilir. '
                'Paketler CouchSubs topluluğundan gelir ve haftada bir yenilenir.',
            'A line found in the game\'s pack is shown with the pack\'s Turkish text without going to the translation engine. '
                'Packs come from the CouchSubs community and are refreshed once a week.',
          )),
        GroupHeader(L.t('ÇEVİRİ MOTORU', 'TRANSLATION ENGINE')),
        Group(
          children: [
            Cell(
              title: 'Google',
              subtitle: L.t('İnternet ister, anahtar gerekmez. Çoğu oyun için önerilir.', 'Needs internet, no key required. Recommended for most games.'),
              checked: s.engine == 'google',
              onTap: () => change((s) => s.json['engine'] = 'google'),
            ),
            Cell(
              title: 'DeepL',
              subtitle: L.t('Daha doğal cümleler; kendi DeepL API anahtarınla çalışır.', 'More natural sentences; works with your own DeepL API key.'),
              checked: s.engine == 'deepl',
              onTap: () => change((s) => s.json['engine'] = 'deepl'),
            ),
            if (s.engine == 'deepl' || (Platform.isIOS && s.engine == 'gemini' && s.engineFailover))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: deepLController,
                      autocorrect: false,
                      decoration: InputDecoration(hintText: L.t('DeepL API anahtarı', 'DeepL API key')),
                      onChanged: (value) => change((s) => s.json['deepLKey'] = value.trim()),
                    ),
                    // Kontrol köprü metodu yalnız iOS'ta var; Android'de düğme gösterilmez.
                    if (Platform.isIOS) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: checkingDeepL ? null : checkDeepL,
                        child: Text(checkingDeepL ? L.t('Deneniyor…', 'Testing…') : L.t('Kaydet ve dene', 'Save and test')),
                      ),
                      if (deepLResult != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            deepLResult!.$2,
                            style: Txt.subhead.copyWith(color: deepLResult!.$1 ? Tokens.success : Tokens.danger),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            // Original UI retained. Only a new opt-in translation provider is added.
            if (Platform.isIOS)
              Cell(
                title: 'OpenRouter · Hy-MT2',
                subtitle: L.t(
                  'Oyunlar için doğal Arapça çeviri. API ücreti kullanıma göredir.',
                  'Professional Arabic game localization. Pay-as-you-go API.',
                ),
                checked: s.engine == 'openrouter',
                onTap: () => change((s) {
                  s.json['engine'] = 'openrouter';
                  s.json['sourceLanguage'] = 'en';
                  s.json['targetLanguage'] = 'ar';
                }),
              ),
            if (Platform.isIOS && s.engine == 'openrouter')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: openRouterController,
                      autocorrect: false,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: openRouterSaved
                            ? 'OpenRouter key saved securely · enter a new key to replace'
                            : 'OpenRouter API key',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: checkingOpenRouter ? null : checkOpenRouter,
                      child: Text(checkingOpenRouter ? 'Testing…' : 'Save and test'),
                    ),
                    if (openRouterResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          openRouterResult!.$2,
                          style: Txt.subhead.copyWith(
                            color: openRouterResult!.$1 ? Tokens.success : Tokens.danger,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      L.t(
                        'Yalnız İngilizce → Arapça. Anahtar iPhone Keychain içinde saklanır. '
                        'Bağlantı başarısız olursa Google yedek motordur.',
                        'English → Arabic only. Key is stored in iPhone Keychain. '
                        'Google is the fallback if OpenRouter is unavailable.',
                      ),
                      style: Txt.subhead.copyWith(color: Tokens.textSecondary),
                    ),
                  ],
                ),
              ),
            // Yapay zekâ çevirisi (bilgisayar sürümündeki gibi); şimdilik yalnız iPhone'da.
            if (Platform.isIOS)
              Cell(
                title: 'Google Gemini',
                subtitle: s.engineFailover && s.deepLKey.isNotEmpty
                    ? L.t(
                        'Yapay zekâ ile en doğal Türkçe. Ücretsiz anahtarla çalışır. Sınır dolunca DeepL, o da olmazsa Google kullanılır.',
                        'The most natural translation, powered by AI. Works with a free key. When the limit is reached, DeepL is used, or Google if that fails too.',
                      )
                    : L.t(
                        'Yapay zekâ ile en doğal Türkçe. Ücretsiz anahtarla çalışır; sınır dolunca bir dakika Google kullanılır.',
                        'The most natural translation, powered by AI. Works with a free key; when the limit is reached, Google is used for a minute.',
                      ),
                checked: s.engine == 'gemini',
                onTap: () => change((s) => s.json['engine'] = 'gemini'),
              ),
            if (Platform.isIOS && (s.engine == 'gemini' || (s.engine == 'deepl' && s.engineFailover)))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: geminiController,
                      autocorrect: false,
                      obscureText: true,
                      decoration: InputDecoration(hintText: L.t('Gemini API anahtarı', 'Gemini API key')),
                      onChanged: (value) => change((s) => s.json['geminiKey'] = value.trim()),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: checkingGemini ? null : checkGemini,
                      child: Text(checkingGemini ? L.t('Deneniyor…', 'Testing…') : L.t('Kaydet ve dene', 'Save and test')),
                    ),
                    if (geminiResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          geminiResult!.$2,
                          style: Txt.subhead.copyWith(color: geminiResult!.$1 ? Tokens.success : Tokens.danger),
                        ),
                      ),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                      onPressed: () => Bridge.openUrl('https://aistudio.google.com/apikey'),
                      child: Text(L.t('Ücretsiz Google Gemini API anahtarı al', 'Get a free Google Gemini API key')),
                    ),
                  ],
                ),
              ),
            if (Platform.isIOS && s.engine == 'gemini')
              Cell(
                title: L.t('Gemini modeli', 'Gemini model'),
                subtitle: geminiModels[geminiModelId] ?? '',
                chevron: true,
                onTap: pickGeminiModel,
              ),
            if (Platform.isIOS && (s.engine == 'gemini' || (s.engine == 'deepl' && s.engineFailover)))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: geminiStyleController,
                      focusNode: geminiStyleFocus,
                      textInputAction: TextInputAction.done,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: L.t('Ek talimat (isteğe bağlı), ör. Samimi dille çevir', 'Extra instruction (optional), e.g. Translate casually'),
                        counterText: '',
                      ),
                      // Yazarken kaydedilmez; yalnız hazır seçeneklerin seçili görünümü güncellenir.
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => commitStyleNote(),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in styleNotePresets)
                          _presetChip(preset.$1, selected: geminiStyleController.text == preset.$2, onTap: () => applyStyleNote(preset.$2)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      L.t("Gemini'ye üslup notu. Yalnız Gemini çevirirken etkilidir.", 'A style note for Gemini. Only applies when Gemini is translating.'),
                      style: Txt.footnote.copyWith(color: Tokens.textSecondary),
                    ),
                  ],
                ),
              ),
            if (Platform.isIOS && (s.engine == 'deepl' || s.engine == 'gemini'))
              Cell(
                title: L.t('Kota dolunca diğer motora geç', 'Switch engines when quota runs out'),
                subtitle: L.t(
                  'DeepL ya da Gemini kotası dolunca anahtarı girilmiş diğer motor, o da olmazsa Google çevirir. Kota açılınca geri döner.',
                  'When the DeepL or Gemini quota runs out, the other engine (if its key is entered), or else Google, translates. It switches back when the quota is available again.',
                ),
                trailing: CupertinoSwitch(
                  value: s.engineFailover,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['engineFailover'] = value),
                ),
              ),
            if (Platform.isIOS && s.engineFailover && s.engine == 'deepl' && s.deepLKey.isNotEmpty && s.targetLanguage == 'tr' && s.geminiKey.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(L.t('Geçiş için Gemini anahtarını da gir.', 'Enter your Gemini key too to enable switching.'), style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
              ),
            if (Platform.isIOS && s.engineFailover && s.engine == 'gemini' && s.geminiKey.isNotEmpty && s.deepLKey.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(L.t('Geçiş için DeepL anahtarını da gir.', 'Enter your DeepL key too to enable switching.'), style: Txt.subhead.copyWith(color: Tokens.textSecondary)),
              ),
            if (Platform.isIOS && s.engine == 'deepl' && s.deepLKey.isEmpty && s.geminiKey.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(L.t('DeepL anahtarı boş; şu an Google çeviriyor.', 'The DeepL key is empty; Google is translating right now.'), style: Txt.subhead.copyWith(color: Tokens.warning)),
              ),
            if (Platform.isIOS && s.engine == 'gemini' && s.geminiKey.isEmpty && s.deepLKey.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(L.t('Gemini anahtarı boş; şu an Google çeviriyor.', 'The Gemini key is empty; Google is translating right now.'), style: Txt.subhead.copyWith(color: Tokens.warning)),
              ),
            Cell(
              title: L.t('Cihazda', 'On device'),
              subtitle: Platform.isIOS
                  ? L.t(
                      'İnternetsiz çalışır (Apple Çeviri). Önce iPhone\'da Ayarlar › Uygulamalar › Çeviri › İndirilen Diller\'den İngilizce ve Türkçe\'yi indir.',
                      'Works offline (Apple Translate). First download English and Turkish in the iPhone\'s Settings › Apps › Translate › Downloaded Languages.',
                    )
                  : L.t('İnternetsiz çalışır; kalitesi daha düşüktür. Dil modeli bir kez iner.', 'Works offline; quality is lower. The language model downloads once.'),
              checked: s.engine == 'mlkit',
              onTap: () => change((s) => s.json['engine'] = 'mlkit'),
            ),
          ],
        ),
        GroupFooter(L.t(
          'İnternet koparsa çeviri kendiliğinden cihazdaki modele geçer. DeepL anahtarı boşsa ya da çalışmazsa Google kullanılır.',
          'If the internet drops, translation switches to the on-device model by itself. If the DeepL key is empty or fails, Google is used.',
        )),

        // ---------------------------------------------------------------- Altyazı bölgesi
        GroupHeader(L.t('ALTYAZI BÖLGESİ', 'SUBTITLE AREA')),
        // Otomatik bulma yalnız iOS'ta var.
        if (Platform.isIOS) ...[
          Group(
            inset: 16,
            children: [
              Cell(
                title: L.t('Altyazı alanını otomatik bul', 'Find subtitle area automatically'),
                subtitle: L.t(
                  'Bütün ekranı tarar, biraz daha fazla pil harcar; altyazıyı bulana kadar elle ayarlanan alan kullanılır.',
                  'Searches the whole screen and uses a bit more battery; until it finds the subtitle, the area you set by hand is used.',
                ),
                trailing: CupertinoSwitch(
                  value: s.autoRegion,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['autoRegion'] = value),
                ),
              ),
              Cell(
                title: L.t('Yalnız altyazıyı çevir', 'Translate subtitles only'),
                subtitle: L.t(
                  'Tabela, gösterge ve menü yazıları çevrilmez. Altyazı kaçıyorsa kapat.',
                  'Signs, on-screen indicators and menu text are not translated. Turn off if subtitles are being missed.',
                ),
                trailing: CupertinoSwitch(
                  value: s.subtitleOnly,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['subtitleOnly'] = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Glass(
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (preview != null) RegionPreview(image: preview!, settings: s, subtitle: L.t('Örnek altyazı', 'Sample subtitle')) else _RegionPlaceholder(settings: s),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in [...regionPresets.map((p) => p.$1), 'Özel'])
                      _presetChip(
                        presetLabel(name),
                        selected: matchingPreset(s) == name,
                        onTap: name == 'Özel'
                            ? null
                            : () => change((s) => s.json['region'] = Map<String, dynamic>.from(regionPresets.firstWhere((p) => p.$1 == name).$2)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: edge,
                  backgroundColor: Tokens.inset,
                  thumbColor: const Color(0xFF636366),
                  children: {
                    for (final entry in edges.entries)
                      entry.key: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(entry.value, style: Txt.subhead.copyWith(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w500)),
                      ),
                  },
                  onValueChanged: (value) => setState(() => edge = value ?? edge),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoSlider(
                        value: s.regionValue(edge).clamp(0.0, 1.0),
                        activeColor: Tokens.accent,
                        onChanged: (value) => setRegion(edge, (value * 100).round() / 100),
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text('%${(s.regionValue(edge) * 100).round()}', textAlign: TextAlign.end, style: Txt.body.copyWith(color: Tokens.textSecondary)),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Cell(title: L.t('Varsayılana Dön', 'Reset to Default'), titleColor: Tokens.accent, onTap: () => change((s) => s.json['region'] = Map<String, dynamic>.from(defaultRegion))),
            ],
          ),
        ),
        GroupFooter(L.t(
          'Mavi çerçeveyi oyunun altyazısının çıktığı yere getir. Çerçeve dar olursa cümlenin başı ya da sonu kesilir.',
          'Move the blue frame over where the game\'s subtitle appears. If the frame is too narrow, the start or end of a sentence is cut off.',
        )),
        if (Platform.isIOS && s.autoRegion)
          GroupFooter(L.t(
            'Otomatik bulma açıkken bu alan yedek olarak kullanılır: altyazı bulunana kadar yalnız buradaki çerçeve okunur.',
            'While automatic finding is on, this area is the fallback: only this frame is read until the subtitle is found.',
          )),
        if (Platform.isIOS) ...[
          GroupHeader(L.t('EK OKUMA ALANLARI', 'EXTRA READING AREAS')),
          Group(
            children: [
              for (var i = 0; i < s.extraRegions.length; i++)
                Cell(
                  title: s.extraRegions[i]['name'] as String? ?? L.t('Alan ${i + 1}', 'Area ${i + 1}'),
                  subtitle: L.t(
                    'Üst %${(((s.extraRegions[i]['top'] as num?) ?? 0) * 100).round()} · Alt %${(((s.extraRegions[i]['bottom'] as num?) ?? 0) * 100).round()}',
                    'Top ${(((s.extraRegions[i]['top'] as num?) ?? 0) * 100).round()}% · Bottom ${(((s.extraRegions[i]['bottom'] as num?) ?? 0) * 100).round()}%',
                  ),
                  chevron: true,
                  onTap: () => editExtra(i),
                ),
              if (s.extraRegions.length < 3) Cell(title: L.t('Alan ekle', 'Add area'), titleColor: Tokens.accent, onTap: addExtra),
            ],
          ),
          GroupFooter(L.t(
            'Görev notu, harita yazısı gibi başka yerdeki yazıları da çevirebilirsin (en çok 3 alan). '
                'Çeviri açıkken ana ekranda her alan için bir düğme çıkar; dokununca o alan bir kez okunur.',
            'You can also translate text elsewhere, such as quest notes or map labels (up to 3 areas). '
                'While translation is on, the home screen shows a button for each area; tapping it reads that area once.',
          )),
        ],

        // ---------------------------------------------------------------- TV'de görünüm
        GroupHeader(L.t('TV\'DE GÖRÜNÜM', 'APPEARANCE ON THE TV')),
        Group(
          children: [
            _ControlRow(
              title: L.t('Yazı boyutu', 'Text size'),
              child: _Segmented(
                value: '${style['fontSize']}',
                items: {
                  '36': L.t('Küçük', 'Small'),
                  '46': L.t('Orta', 'Medium'),
                  '58': L.t('Büyük', 'Large'),
                  '72': L.t('Dev', 'Huge'),
                },
                onChanged: (value) => setStyle('fontSize', int.parse(value)),
              ),
            ),
            if (Platform.isIOS)
              Cell(
                title: L.t('Yazı rengi', 'Text color'),
                subtitle: textColors[style['textColor']] ?? textColors['white'],
                chevron: true,
                onTap: pickTextColor,
              )
            else
              _ControlRow(
                title: L.t('Yazı rengi', 'Text color'),
                child: _Segmented(
                  value: style['textColor'] as String,
                  items: {'white': L.t('Beyaz', 'White'), 'yellow': L.t('Sarı', 'Yellow')},
                  onChanged: (value) => setStyle('textColor', value),
                ),
              ),
            Cell(
              title: L.t('Altyazının yeri', 'Subtitle position'),
              subtitle: placements[style['placement']] ?? '',
              chevron: true,
              onTap: pickPlacement,
            ),
            if (Platform.isIOS && style['placement'] == 'cover')
              Cell(
                title: L.t('Oyunun yazı boyuna uy', 'Match the game\'s text size'),
                subtitle: L.t('Kapalıyken yazı ayardaki boyda kalır, sığmazsa küçülür. Açıkken oyunun altyazısının boyuna yaklaşır.',
                    'When off, the text stays at the size you chose and shrinks if it does not fit. When on, it approaches the size of the game\'s subtitle.'),
                trailing: CupertinoSwitch(
                  value: s.matchGameTextSize,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => change((s) => s.json['matchGameTextSize'] = value),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(L.t('Zemin koyuluğu', 'Background darkness'), style: Txt.body)),
                      Text('%${style['background']}', style: Txt.body.copyWith(color: Tokens.textSecondary)),
                    ],
                  ),
                  CupertinoSlider(
                    value: (style['background'] as num).toDouble().clamp(0, 100),
                    max: 100,
                    divisions: 20,
                    activeColor: Tokens.accent,
                    onChanged: (value) => setStyle('background', value.round()),
                  ),
                ],
              ),
            ),
            if (style['placement'] == 'fixed')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(L.t('Ekran konumu (alttan yükseklik)', 'Screen position (height from the bottom)'), style: Txt.body)),
                      Text('%${(style['bottomPercent'] as num? ?? 7).round()}', style: Txt.body.copyWith(color: Tokens.textSecondary)),
                    ],
                  ),
                  CupertinoSlider(
                    value: (style['bottomPercent'] as num? ?? 7).toDouble().clamp(0, 85),
                    max: 85,
                    divisions: 85,
                    activeColor: Tokens.accent,
                    onChanged: (value) => setStyle('bottomPercent', value.round()),
                  ),
                ],
              ),
            ),
            Cell(
              title: L.t('Önceki satır da görünsün', 'Keep the previous line visible'),
              subtitle: L.t('Yeni cümlenin üstünde bir önceki cümle soluk kalır', 'The previous sentence stays faded above the new one'),
              trailing: CupertinoSwitch(
                value: style['stackPrevious'] as bool? ?? true,
                activeTrackColor: Tokens.success,
                onChanged: (value) => setStyle('stackPrevious', value),
              ),
            ),
            Cell(
              title: L.t('Kalın yazı', 'Bold text'),
              trailing: CupertinoSwitch(value: style['bold'] as bool, activeTrackColor: Tokens.success, onChanged: (value) => setStyle('bold', value)),
            ),
            // Bilgisayar sürümündeki "Konuşmacı adı renkli"; TV uygulaması adı ("ENZO:") ayrı renkte yazar.
            if (Platform.isIOS)
              Cell(
                title: L.t('Konuşmacı adı renkli', 'Colored speaker name'),
                subtitle: L.t('Konuşanın adı (ör. ENZO:) sarı, sarı yazıda açık mavi', 'The speaker\'s name (e.g. ENZO:) is yellow, or light blue when the text is yellow'),
                trailing: CupertinoSwitch(
                  value: style['speakerColor'] as bool? ?? false,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => setStyle('speakerColor', value),
                ),
              ),
            if (Platform.isIOS && (style['speakerColor'] as bool? ?? false))
              Cell(
                title: L.t('Her konuşmacıya ayrı renk', 'A colour for each speaker'),
                subtitle: L.t(
                  'Her konuşanın adı kendi renginde yazılır. Eski TV uygulamasında tek renk kalır.',
                  'Each speaker\'s name gets its own colour. Older TV apps keep a single colour.',
                ),
                trailing: CupertinoSwitch(
                  value: style['speakerColorsEnabled'] as bool? ?? true,
                  activeTrackColor: Tokens.success,
                  onChanged: (value) => setStyle('speakerColorsEnabled', value),
                ),
              ),
            if (Platform.isIOS)
              Cell(
                title: L.t('Altyazı yazı tipi', 'Subtitle font'),
                subtitle: subtitleFonts[style['subtitleFont']] ?? subtitleFonts['default'],
                chevron: true,
                onTap: pickSubtitleFont,
              ),
            Cell(title: L.t('TV\'ye Deneme Altyazısı Gönder', 'Send a Test Subtitle to the TV'), titleColor: Tokens.accent, onTap: sendTest),
            if (Platform.isIOS)
              Cell(
                title: L.t('PS5\'siz Deneme', 'Try Without a PS5'),
                subtitle: L.t(
                  'Örnek altyazı satırları çevrilip TV\'ye gönderilir; PS5 gerekmez. Kapatana kadar sürer.',
                  'Sample subtitle lines are translated and sent to the TV; no PS5 needed. Keeps going until you turn it off.',
                ),
                trailing: CupertinoSwitch(value: demoOn, activeTrackColor: Tokens.success, onChanged: setDemo),
              ),
          ],
        ),

        // ---------------------------------------------------------------- TV uygulaması
        GroupHeader(L.t('TV UYGULAMASI', 'TV APP')),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.tv_fill,
              iconColor: Tokens.purple,
              title: L.t('TV Uygulamasını Kur', 'Install the TV App'),
              subtitle: L.t('LG ve Android TV\'ye telefondan; güncellemek için de', 'To LG and Android TV from the phone; also for updating'),
              chevron: true,
              onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const TvInstallPage())),
            ),
          ],
        ),

        // ---------------------------------------------------------------- PS5
        const GroupHeader('PS5'),
        Group(
          inset: 60,
          children: [
            Cell(
              icon: CupertinoIcons.gamecontroller_fill,
              iconColor: Tokens.gray,
              title: widget.setup.consoleName ?? 'PS5',
              subtitle: widget.setup.consoleHost ?? '',
              trailing: Pill(text: L.t('Eşleşti', 'Paired'), color: Tokens.success),
            ),
            Cell(
              icon: CupertinoIcons.power,
              iconColor: Tokens.success,
              title: L.t('Dinlenme modundan uyandır', 'Wake from rest mode'),
              trailing: CupertinoSwitch(
                value: s.autoWake,
                activeTrackColor: Tokens.success,
                onChanged: (value) => change((s) => s.json['autoWake'] = value),
              ),
            ),
          ],
        ),
        GroupFooter(L.t('Çeviri başlarken PS5 dinlenme modundaysa açılır.', 'If the PS5 is in rest mode when translation starts, it is woken up.')),
        const SizedBox(height: 14),
        Group(
          children: [
            Cell(title: L.t('PS5\'i Yeniden Eşleştir', 'Pair the PS5 Again'), titleColor: Tokens.accent, onTap: () => confirmForget(account: false)),
            Cell(title: L.t('PSN Hesabını Değiştir', 'Change PSN Account'), titleColor: Tokens.danger, onTap: () => confirmForget(account: true)),
          ],
        ),

        if (Platform.isIOS) ...[
          GroupHeader(L.t('TANI', 'DIAGNOSTICS')),
          Group(
            inset: 60,
            children: [
              Cell(
                icon: CupertinoIcons.clock_fill,
                iconColor: Tokens.indigo,
                title: L.t('Altyazı Geçmişi', 'Subtitle History'),
                chevron: true,
                onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const HistoryPage())),
              ),
              Cell(
                icon: CupertinoIcons.dot_radiowaves_left_right,
                iconColor: Tokens.success,
                title: L.t('Sistem Durumu', 'System Status'),
                chevron: true,
                onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const HealthPage())),
              ),
              Cell(
                icon: CupertinoIcons.circle_fill,
                iconColor: Tokens.danger,
                title: L.t('Tanı Kaydı', 'Diagnostics Recording'),
                subtitle: L.t('Sorunu kaydedip geliştiriciye gönder', 'Record a problem and send it to the developer'),
                chevron: true,
                onTap: () => Navigator.of(context).push(appleRoute<void>((_) => const DiagnosticsPage())),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Group(children: [Cell(title: L.t('Tüm Ayarları Sıfırla', 'Reset All Settings'), titleColor: Tokens.danger, onTap: resetAll)]),
          GroupFooter(L.t('PS5 eşleştirmesi, PSN hesabı ve API anahtarların silinmez.', 'Your PS5 pairing, PSN account and API keys are not deleted.')),
        ],

        // ---------------------------------------------------------------- Hakkında
        GroupHeader(L.t('HAKKINDA', 'ABOUT')),
        Group(
          inset: 60,
          children: [
            Cell(icon: CupertinoIcons.play_circle_fill, iconColor: Tokens.purple, title: L.t('Tanıtımı Göster', 'Show the Introduction'), chevron: true, onTap: showIntro),
            Cell(icon: CupertinoIcons.doc_text_fill, iconColor: Tokens.gray, title: L.t('Günlük', 'Log'), chevron: true, onTap: showLogs),
            Cell(
              icon: CupertinoIcons.info,
              iconColor: Tokens.accent,
              title: L.t('Sürüm', 'Version'),
              value: widget.setup.version.isEmpty ? '—' : widget.setup.version,
            ),
          ],
        ),
        GroupFooter(
          L.t(
            'Oyun görüntüsü ve hesap bilgilerin telefonda kalır. Çevrimiçi motor seçiliyse yalnızca okunan altyazı metni çeviri '
                'servisine gönderilir.\n\nGameTranslator açık kaynaklıdır (AGPL-3.0). Sony ya da PlayStation ile bağlantılı değildir.',
            'Your game picture and account details stay on the phone. If an online engine is selected, only the subtitle text that was read '
                'is sent to the translation service.\n\nGameTranslator is open source (AGPL-3.0). It is not affiliated with Sony or PlayStation.',
          ),
        ),
        if (Platform.isIOS)
          GroupFooter(L.t(
            'TV altyazısı için Quicksand yazı tipi uygulamayla gelir: Copyright 2011 The Quicksand Project Authors, '
                'SIL Open Font License 1.1 (lisans metni uygulama paketinde, OFL.txt).',
            'The Quicksand font for TV subtitles ships with the app: Copyright 2011 The Quicksand Project Authors, '
                'SIL Open Font License 1.1 (licence text in the app bundle, OFL.txt).',
          )),
      ],
    );
  }
}

/// Başlığı üstte, denetimi altında olan satır (parçalı seçiciler için).
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Text(title, style: Txt.body), const SizedBox(height: 10), child],
      ),
    );
  }
}

/// iOS'un kayan parçalı seçicisi.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.items, required this.onChanged});

  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<String>(
      groupValue: items.containsKey(value) ? value : null,
      backgroundColor: Tokens.inset,
      thumbColor: const Color(0xFF636366),
      children: {
        for (final entry in items.entries)
          entry.key: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(entry.value, style: Txt.subhead.copyWith(fontFamily: 'Inter', color: Colors.white, fontWeight: FontWeight.w500)),
          ),
      },
      onValueChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

/// Çeviri kapalıyken oyun görüntüsü yoktur; bölge boş bir ekran üstünde gösterilir.
class _RegionPlaceholder extends StatelessWidget {
  const _RegionPlaceholder({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black)),
            Positioned(
              left: 0,
              right: 0,
              top: 18,
              child: Text(L.t('Çeviri açıkken burada oyun görüntüsü görünür.', 'The game picture appears here while translation is on.'), textAlign: TextAlign.center, style: Txt.footnote.copyWith(color: Tokens.textSecondary)),
            ),
            Positioned(
              left: settings.regionValue('left') * constraints.maxWidth,
              top: settings.regionValue('top') * constraints.maxHeight,
              width: (settings.regionValue('right') - settings.regionValue('left')) * constraints.maxWidth,
              height: (settings.regionValue('bottom') - settings.regionValue('top')) * constraints.maxHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Tokens.accent, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                  color: Tokens.accent.withValues(alpha: 0.12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Terim sözlüğü düzenleyicisi: bilgisayardaki sözlük dosyalarıyla aynı JSON biçimi.
class GlossaryPage extends StatefulWidget {
  const GlossaryPage({super.key, required this.initial});

  final String initial;

  static const example = '{\n  "terms": {\n    "Leviathan Axe": "Leviathan Baltası"\n  },\n  "keep": ["Kratos", "Atreus"]\n}';

  /// Sözlük metnindeki terim ve korunan ad sayısı; okunamıyorsa üçüncü değer sorunu söyler.
  static (int, int, String?) inspect(String text) {
    if (text.trim().isEmpty) return (0, 0, null);
    try {
      final root = jsonDecode(text);
      if (root is! Map) return (0, 0, L.t('Sözlük { ... } biçiminde olmalı.', 'The glossary must be in { ... } form.'));
      final terms = root['terms'] is Map ? (root['terms'] as Map).values.whereType<String>().length : 0;
      final keep = root['keep'] is List ? (root['keep'] as List).whereType<String>().length : 0;
      return (terms, keep, null);
    } on FormatException {
      return (0, 0, L.t('Yazım hatası var: tırnak, virgül ve parantezleri kontrol et.', 'Syntax error: check the quotes, commas and brackets.'));
    }
  }

  @override
  State<GlossaryPage> createState() => _GlossaryPageState();
}

class _GlossaryPageState extends State<GlossaryPage> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (terms, keep, problem) = GlossaryPage.inspect(controller.text);
    final empty = controller.text.trim().isEmpty;
    return GlassScaffold(
      title: L.t('Terim Sözlüğü', 'Glossary'),
      actions: [
        TextButton(
          onPressed: problem == null ? () => Navigator.of(context).pop(controller.text.trim()) : null,
          child: Text(L.t('Kaydet', 'Save'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              L.t(
                'Çevirinin yanlış çevirdiği özel adları ve oyun terimlerini burada sabitleyebilirsin. '
                    '"terms" içindeki terimler yazdığın Türkçeyle çevrilir, "keep" içindeki adlar olduğu gibi kalır.',
                'Pin proper names and game terms that the translation gets wrong. '
                    'Terms under "terms" are translated with the Turkish you write; names under "keep" stay as they are.',
              ),
              style: Txt.subhead.copyWith(color: Tokens.textSecondary),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 10,
            maxLines: 22,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.45),
            decoration: InputDecoration(
              hintText: GlossaryPage.example,
              hintMaxLines: 8,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Tokens.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Tokens.border)),
            ),
          ),
          const SizedBox(height: 12),
          if (problem != null)
            Notice(icon: CupertinoIcons.exclamationmark_circle_fill, color: Tokens.danger, text: problem)
          else if (empty)
            Notice(
              icon: CupertinoIcons.wand_stars,
              text: L.t('Sözlük boş. Bir örnekle başlayıp kendi terimlerinle değiştirebilirsin.', 'The glossary is empty. Start from an example and replace it with your own terms.'),
              action: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                onPressed: () => setState(() => controller.text = GlossaryPage.example),
                child: Text(L.t('Örnek Ekle', 'Add Example')),
              ),
            )
          else
            Notice(icon: CupertinoIcons.checkmark_circle_fill, color: Tokens.success, text: L.t('$terms terim, $keep korunan ad okundu.', '$terms terms, $keep kept names read.')),
          GroupFooter(
            L.t(
              'Bilgisayardaki GameTranslator sözlük dosyalarıyla aynı biçimdir; oradaki dosyanın içeriğini buraya yapıştırabilirsin. '
                  'Yalnızca İngilizce → Türkçe çeviride kullanılır.',
              'Same format as the GameTranslator glossary files on the computer; you can paste the contents of that file here. '
                  'Used only for English → Turkish translation.',
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../artwork.dart';
import '../models.dart';
import '../perf.dart';
import '../store.dart';
import '../strings.dart';
import '../theme.dart';
import 'dpad.dart';
import 'screens.dart';
import 'tv.dart';
import 'widgets.dart';

/// Diagnostics dialog (startup, channel switch, rebuffering, UI frames, memory). No sensitive data.
Future<void> showDiagnostics(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = Pal.of(ctx);
      return AlertDialog(
        title: Text(t('Diagnostics')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in Perf.report())
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 5,
                            child: Text(e.key, style: TextStyle(color: p.muted))),
                        Expanded(
                            flex: 6,
                            child: Text(e.value,
                                style: const TextStyle(fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                Perf.reset();
                Navigator.of(ctx).pop();
              },
              child: Text(t('Reset'))),
          FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('OK'))),
        ],
      );
    },
  );
}

Future<String?> askPin(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 320,
        child: DpadTextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          decoration: InputDecoration(labelText: t('PIN')),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t('Cancel'))),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: Text(t('OK'))),
      ],
    ),
  ).whenComplete(c.dispose);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _tmdb;
  bool _unlocked = false;
  final TextEditingController _gatePin = TextEditingController();
  bool _wrongPin = false;

  @override
  void initState() {
    super.initState();
    _tmdb = TextEditingController(text: store.prefs.getString('tmdbKey') ?? '');
  }

  @override
  void dispose() {
    _tmdb.dispose();
    _gatePin.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ helpers

  Widget _section(Palette p, double s, String title) => Padding(
        padding: EdgeInsets.fromLTRB(4 * s, 26 * s, 4 * s, 8 * s),
        child: Text(title,
            style: TextStyle(
                fontSize: 22 * s, fontWeight: FontWeight.w800, color: p.accent)),
      );

  Widget _card(Palette p, double s, {required Widget child}) => Container(
        margin: EdgeInsets.symmetric(vertical: 4 * s),
        padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 14 * s),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(color: p.border),
        ),
        child: child,
      );

  Widget _label(Palette p, double s, String title, [String? sub]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 20 * s, fontWeight: FontWeight.w600, color: p.text)),
          if (sub != null)
            Padding(
              padding: EdgeInsets.only(top: 2 * s),
              child: Text(sub, style: TextStyle(fontSize: 15 * s, color: p.muted)),
            ),
        ],
      );

  /// A row that acts like a button.
  Widget _action(Palette p, double s,
      {required IconData icon,
      required String title,
      String? subtitle,
      Widget? trailing,
      required TapCb onTap}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * s),
      child: TvFocusable(
        radius: 14 * s,
        onTap: onTap,
        builder: (c, f) => Container(
          padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 14 * s),
          decoration: BoxDecoration(
            color: f ? p.accent.withValues(alpha: 0.14) : p.surface,
            borderRadius: BorderRadius.circular(14 * s),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28 * s, color: p.accent),
              SizedBox(width: 16 * s),
              Expanded(child: _label(p, s, title, subtitle)),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  /// Label + a row of single-choice chips (each chip is focusable).
  Widget _choice<T>(Palette p, double s,
      {required String title,
      String? subtitle,
      required List<(T, String)> options,
      required T selected,
      required void Function(T) onPick,
      Widget Function(T value, bool isSelected)? leading}) {
    return _card(
      p,
      s,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(p, s, title, subtitle),
          SizedBox(height: 12 * s),
          Wrap(
            spacing: 10 * s,
            runSpacing: 10 * s,
            children: [
              for (final o in options)
                TvFocusable(
                  radius: 22 * s,
                  onTap: () => onPick(o.$1),
                  builder: (c, f) {
                    final sel = o.$1 == selected;
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 10 * s),
                      decoration: BoxDecoration(
                        color: sel ? p.accent : p.bg,
                        borderRadius: BorderRadius.circular(22 * s),
                        border: Border.all(color: sel ? p.accent : p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (leading != null) ...[
                            leading(o.$1, sel),
                            SizedBox(width: 8 * s),
                          ],
                          Text(o.$2,
                              style: TextStyle(
                                  fontSize: 18 * s,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? p.onAccent : p.text)),
                          if (sel) ...[
                            SizedBox(width: 6 * s),
                            Icon(Icons.check_rounded, size: 20 * s, color: p.onAccent),
                          ],
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(Palette p, double s,
      {required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      required TapCb onTap}) {
    return _action(
      p,
      s,
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Container(
        width: 56 * s,
        height: 30 * s,
        padding: EdgeInsets.all(3 * s),
        alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: value ? p.accent : p.border,
          borderRadius: BorderRadius.circular(16 * s),
        ),
        child: Container(
          width: 24 * s,
          height: 24 * s,
          decoration: BoxDecoration(
              color: value ? p.onAccent : p.muted, shape: BoxShape.circle),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ actions

  Future<void> _toggleKids() async {
    if (store.kidsMode) {
      final pin = await askPin(context, t('Enter PIN'));
      if (pin == null || !mounted) return;
      if (store.checkPin(pin)) {
        store.setKidsMode(false);
      } else {
        _toast(t('Wrong PIN'));
      }
      return;
    }
    if (!store.hasPin) {
      final pin = await askPin(context, t('Create a 4-digit PIN'));
      if (pin == null || !mounted) return;
      if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
        _toast(t('Create a 4-digit PIN'));
        return;
      }
      store.setPin(pin);
    }
    store.setKidsMode(true);
  }

  void _toast(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(duration: const Duration(milliseconds: 1600), content: Text(text)));
  }

  Future<void> _confirmDelete(Source src) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Delete this source?')),
        content: Text(src.name),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: Text(t('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t('Delete'))),
        ],
      ),
    );
    if (ok == true) store.removeSource(src.id);
  }

  String _sourceStatus(Source s) {
    final reach = store.sourceReachable[s.id];
    final ok = store.sourceRefreshOk[s.id];
    if (reach == false || ok == false) return t('Source unreachable');
    if (reach == true || ok == true) return t('Source is available');
    return t('Not checked yet');
  }

  String _typeLabel(Source s) =>
      s.type == 'xtream' ? 'Xtream' : (s.type == 'm3u' ? 'M3U' : t('Demo'));

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final s = wide ? uiScale(context) : 1.0;
    return MediaQuery(
      data: wide
          ? MediaQuery.of(context).copyWith(textScaler: uiTextScaler())
          : MediaQuery.of(context),
      child: ListenableBuilder(
        listenable: Listenable.merge([store, themeController]),
        builder: (context, _) {
          final p = Pal.of(context);
          if (store.kidsMode && !_unlocked) return _gate(p, s);
          return SafeArea(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 36 * s, vertical: 16 * s),
              children: [
                Text(t('Settings'),
                    style: TextStyle(fontSize: 34 * s, fontWeight: FontWeight.w800, color: p.text)),
                ..._appearance(p, s),
                ..._playback(p, s),
                ..._sourcesSection(p, s),
                ..._languageAccess(p, s),
                ..._advanced(p, s),
                SizedBox(height: 30 * s),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _gate(Palette p, double s) {
    return Center(
      child: SizedBox(
        width: 420 * s,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 56 * s, color: p.accent),
            SizedBox(height: 12 * s),
            Text(t('Settings are locked in kids mode'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24 * s, fontWeight: FontWeight.w700, color: p.text)),
            SizedBox(height: 16 * s),
            DpadTextField(
              controller: _gatePin,
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _tryUnlock(),
              decoration: InputDecoration(
                labelText: t('PIN'),
                errorText: _wrongPin ? t('Wrong PIN') : null,
              ),
            ),
            SizedBox(height: 12 * s),
            TvButton(label: t('Unlock'), icon: Icons.lock_open_rounded, filled: true, onTap: _tryUnlock),
          ],
        ),
      ),
    );
  }

  void _tryUnlock() {
    if (store.checkPin(_gatePin.text.trim())) {
      setState(() {
        _unlocked = true;
        _wrongPin = false;
        _gatePin.clear();
      });
    } else {
      setState(() => _wrongPin = true);
    }
  }

  // ------------------------------------------------------------ sections

  List<Widget> _appearance(Palette p, double s) {
    final t0 = themeController;
    return [
      _section(p, s, t('Appearance')),
      _choice<AppThemeMode>(
        p,
        s,
        title: t('Theme'),
        options: [
          (AppThemeMode.night, t('Night')),
          (AppThemeMode.day, t('Day')),
          (AppThemeMode.auto, t('Auto (device)')),
        ],
        selected: t0.mode,
        onPick: t0.setMode,
      ),
      _choice<AppAccent>(
        p,
        s,
        title: t('Accent color'),
        options: [
          (AppAccent.blue, t('Blue')),
          (AppAccent.purple, t('Purple')),
          (AppAccent.teal, t('Teal')),
        ],
        selected: t0.accent,
        onPick: t0.setAccent,
        leading: (v, sel) => Container(
          width: 20 * s,
          height: 20 * s,
          decoration: BoxDecoration(
            color: Palette.accentFor(v, p.dark),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
      _card(
        p,
        s,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(p, s, t('Preview')),
            SizedBox(height: 12 * s),
            Container(
              padding: EdgeInsets.all(16 * s),
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(12 * s),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t('Sample title'),
                        style: TextStyle(
                            fontSize: 22 * s, fontWeight: FontWeight.w700, color: p.text)),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 8 * s),
                    decoration: BoxDecoration(
                        color: p.accent, borderRadius: BorderRadius.circular(10 * s)),
                    child: Text(t('Selected'),
                        style: TextStyle(
                            fontSize: 16 * s,
                            fontWeight: FontWeight.w700,
                            color: p.onAccent)),
                  ),
                  SizedBox(width: 12 * s),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 8 * s),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(10 * s),
                      border: Border.all(color: p.focus, width: 3),
                    ),
                    child: Text(t('Focused item'),
                        style: TextStyle(fontSize: 16 * s, color: p.text)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _playback(Palette p, double s) {
    final saved = store.prefs.getString('pref.aspect') ?? 'fit';
    return [
      _section(p, s, t('Playback')),
      _choice<String>(
        p,
        s,
        title: t('Default aspect ratio'),
        options: [
          ('fit', t('Fit')),
          ('fill', t('Fill')),
          ('original', t('Original')),
          ('stretch', t('Stretch')),
        ],
        selected: saved,
        onPick: (v) {
          store.prefs.setString('pref.aspect', v);
          setState(() {});
        },
      ),
      _action(
        p,
        s,
        icon: Icons.restart_alt_rounded,
        title: t('Reset audio and subtitle choices'),
        onTap: () {
          store.prefs.remove('pref.audio');
          store.prefs.remove('pref.sub');
          _toast(t('OK'));
          return null;
        },
      ),
    ];
  }

  List<Widget> _sourcesSection(Palette p, double s) {
    final active = store.activeSourceId;
    return [
      _section(p, s, t('Sources')),
      if (store.sources.length > 1)
        _choice<String>(
          p,
          s,
          title: t('Active source'),
          options: [
            ('', t('All sources')),
            for (final src in store.sources) (src.id, src.name),
          ],
          selected: active ?? '',
          onPick: (v) => store.setActiveSource(v.isEmpty ? null : v),
        ),
      for (final src in store.sources)
        _action(
          p,
          s,
          icon: src.type == 'xtream' ? Icons.dns_rounded : Icons.playlist_play_rounded,
          title: src.name,
          subtitle: '${_typeLabel(src)}  •  ${_sourceStatus(src)}',
          onTap: () => _confirmDelete(src),
          trailing: Icon(Icons.delete_outline_rounded, size: 26 * s, color: p.muted),
        ),
      _action(
        p,
        s,
        icon: Icons.add_circle_rounded,
        title: t('Add Source'),
        onTap: () => showAddSource(context),
      ),
      _action(
        p,
        s,
        icon: Icons.refresh_rounded,
        title: store.error != null ? t('Retry update') : t('Refresh'),
        subtitle: store.error != null ? t('Could not update the source') : null,
        onTap: store.refresh,
        trailing: store.loading
            ? SizedBox(
                width: 24 * s,
                height: 24 * s,
                child: const CircularProgressIndicator(strokeWidth: 2.5))
            : null,
      ),
    ];
  }

  List<Widget> _languageAccess(Palette p, double s) {
    return [
      _section(p, s, t('Language & access')),
      _choice<String>(
        p,
        s,
        title: t('Language'),
        options: [
          ('', t('Device language')),
          ('ar', t('Arabic')),
          ('en', t('English')),
        ],
        selected: themeController.lang ?? '',
        onPick: (v) => themeController.setLang(v.isEmpty ? null : v),
      ),
      _toggle(
        p,
        s,
        icon: Icons.format_size_rounded,
        title: t('Simple mode'),
        subtitle: t('Larger text and easier navigation'),
        value: themeController.simple,
        onTap: () => themeController.setSimple(!themeController.simple),
      ),
      _toggle(
        p,
        s,
        icon: Icons.child_care_rounded,
        title: t('Kids mode'),
        subtitle: t('Shows only kids content. A PIN is needed to leave it.'),
        value: store.kidsMode,
        onTap: _toggleKids,
      ),
    ];
  }

  List<Widget> _advanced(Palette p, double s) {
    return [
      _section(p, s, t('Advanced')),
      _card(
        p,
        s,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(p, s, t('TMDB key'), t('Artwork')),
            SizedBox(height: 8 * s),
            DpadTextField(
              controller: _tmdb,
              onChanged: (v) => store.prefs.setString('tmdbKey', v.trim()),
              decoration: InputDecoration(
                hintText: 'TMDB API key (optional)',
                helperText: 'Free key from themoviedb.org. Restart the app after adding it.',
                helperMaxLines: 2,
                filled: true,
                fillColor: p.bg,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      _action(
        p,
        s,
        icon: Icons.cleaning_services_rounded,
        title: t('Clear artwork cache'),
        onTap: () {
          ArtworkService.instance.clear();
          _toast(t('OK'));
          return null;
        },
      ),
      _action(
        p,
        s,
        icon: Icons.speed_rounded,
        title: t('Diagnostics'),
        subtitle: t('Startup, channel switch, rebuffering, UI frames, memory'),
        onTap: () => showDiagnostics(context),
      ),
      _action(
        p,
        s,
        icon: Icons.settings_backup_restore_rounded,
        title: t('Reset settings'),
        onTap: () async {
          await themeController.resetAll();
          _toast(t('OK'));
          return null;
        },
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(4 * s, 20 * s, 4 * s, 0),
        child: Text(
          t('RaM tv is a player only. It does not provide or include any channels, playlists or content. Use only sources you are authorized to access.'),
          style: TextStyle(fontSize: 14 * s, color: p.muted),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(4 * s, 8 * s, 4 * s, 0),
        child: Text(
          'This product uses the TMDB API but is not endorsed or certified by TMDB.   RaM tv 1.0',
          style: TextStyle(fontSize: 13 * s, color: p.muted),
        ),
      ),
    ];
  }
}

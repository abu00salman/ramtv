# iPhone 1.1 update

This update changes the native Swift iPhone app. Flutter app/ is unchanged.
The existing RaM tv name, icons, assets, com.ramzi.ramtv identity, iOS 16 minimum,
sources, favourites, resume, audio/subtitle selection and VLC fallback are retained.

Implemented:

* Settings → Appearance → Language: device language, العربية or English.
  Choice persists and updates strings, locale and RTL. The selected tab is
  preserved when language changes; tab navigation content is rebuilt to refresh
  manually translated strings.
* Live → layout menu: original rows or lazy adaptive square channel cards.
  Layout is also configurable in Settings and persists across launches.
  Cards use channel artwork, titles and separate favourite buttons.
* Native compatible playback uses AVPlayerViewController's actual Apple
  controls, AirPlay and system PiP. PiP retains its model, resume observer and
  delegate; screen dismissal happens after PiP actually starts. Restore reuses
  the held player/controller and acknowledges presentation when the screen
  appears. Failed PiP starts leave the screen's player running.
* Recognized Xtream /live/.../*.ts URLs first try the equivalent HLS URL and
  retain the original VLC fallback. The VLC toolbar offers an Apple-player
  attempt for compatible streams. VLC controls now have central play/pause and
  seek controls, with a separate material bottom panel for tracks/aspect/speed.
  VLC remains available for MKV, TS and unsupported AVPlayer sources.

PiP limitation: this implementation uses native AVPlayer PiP. It does not add a
VLC sample-buffer PiP bridge. A source that cannot play through AVPlayer/HLS
continues in VLC and has no PiP in this iteration. Square cards show static
channel artwork, not concurrent miniature streams.

Validation actually performed on Linux:

* Swift grammar parsing of all six changed/new Swift files: no syntax errors
  (isolated tree-sitter Swift parser, Node 20). This is not Swift type checking.
* XcodeGen project and workflow YAML parsed and checked.
* Shell syntax of tools/test_ios.sh and git diff --check passed.
* Compared app/ against current origin/main: no Flutter changes.

Six XCTest tests were added for language overrides, fallback, PiP object
ownership, HLS URL/query handling and retained MKV playback. They have not run
locally: Xcode, Apple SDKs and an iPhone simulator are unavailable. Actions now
runs these tests on an available iPhone simulator after building the unsigned
IPA. The release job requires the iOS job, including tests, to succeed.

Device review still required: Arabic and English selection/restart, all tabs,
rows/cards/filter/favourites, native HLS PiP start/background/close/restore,
AirPlay, VLC fallback, rotation, subtitle/audio menus and movie resume.
No tested IPA or successful remote Actions result is claimed for this update.

Changed source paths: RaMtv/Strings.swift, RaMtv/RaMtvApp.swift,
RaMtv/Screens.swift, RaMtv/ChannelGridCard.swift, RaMtv/Player.swift.
Build/test paths: project.yml, Podfile, RaMtvTests/PreferencesTests.swift,
tools/test_ios.sh and .github/workflows/build-ipa.yml.

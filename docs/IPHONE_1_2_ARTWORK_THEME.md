# iPhone 1.2 — artwork recovery and day/night appearance

Based on the same native 1.1 source currently published in origin/main
(85945674b86edd7eaef3e8f0b3a7bae940af09c3). Its previous all-platform Actions
run succeeded; that result does not validate the changes in this update.
Flutter app/, application identity and assets are unchanged.

## Artwork fixes

* A failed provider image now triggers a metadata fallback. Empty, invalid and
  unsupported URL schemes no longer prevent lookups.
* Relative Xtream image URLs resolve against that provider's server.
* Series lookup names remove episode/season/date suffixes. The repeated WWE
  titles shown in the supplied screenshots resolve to their series names.
* Channel lookup normalization removes quality suffixes such as -540/-720
  while preserving channel numbers. HD variants can reuse the correct logo.
* Cached empty results are discarded during migration. New misses expire after
  five minutes rather than being cached permanently.
* Clearing artwork cache notifies visible thumbnails, cancels older lookups
  and guards against their publishing obsolete results.
* A temporarily failed public logo-index request can retry after a minute.
  JSON status checks and parallel metadata requests improve failure handling;
  SVG URLs are excluded from preferred logos because AsyncImage cannot render
  SVG directly.
* Series search tries TMDB, then TVmaze, then iTunes. Failed TMDB authentication
  no longer blocks other providers. TVmaze calls are throttled and candidate
  names checked before using a poster; an attribution link is shown in Settings.
  APIs are used only for metadata/artwork, never channel streams.

Images that do not exist in provider/public metadata still use the original
placeholder. Cards do not invent or embed broadcaster assets.

## Appearance

Settings supports Night, Day and Follow system. The preference persists.
A sun/moon button in the navigation bar on each main screen provides immediate
switching. Page backgrounds, text, filter chips and channel cards adapt.
Cinema hero artwork and playback controls keep dark contrast while browsing
can use light appearance. Source rows show the host rather than the account URL.

## VLC PiP feasibility

Inspected VideoLAN's official source tags 3.6.0 and 3.7.4. The project uses
MobileVLCKit ~> 3.6, which remains within the stable 3.x series. Those public
headers do not contain VLCPictureInPictureDrawable or
VLCPictureInPictureWindowControlling.

Those APIs exist in the 4.x development source with a sample-buffer video
path, but this is not the current stable dependency. Direct VLC PiP was
therefore not added and no upgrade to an experimental VLC engine was made.
No snapshot polling, private libVLC player access or fake PiP button was added.
The existing AVPlayer PiP continues for compatible sources.

Completing VLC PiP requires a compatible supported VLC distribution, followed
by actual iPhone decoder/audio/subtitle/PiP lifecycle and memory tests. It is
not represented as complete in this update.

## Validation

Performed locally:

* Changed Swift files parsed with the isolated Swift grammar parser: no syntax
  errors. This is not a Swift compiler/type check.
* Project/workflow YAML, shell syntax and git diff --check verified.
* Public TVmaze WWE Friday Night SmackDown metadata returned a poster; its
  bytes were downloaded and decoded successfully. The user's IPTV provider,
  credentials and private streams were not contacted.
* Compared the native 1.1 baseline with current origin/main; differences were
  only upload instructions. Flutter source was compared and remains unchanged.

Five additional XCTest cases cover artwork normalization, season titles,
URL validation/relative resolution and appearance selection (eleven native
tests in total). They have not been executed here: no Xcode, Apple SDK or
iPhone simulator is available. Existing Actions will run them before release.
No successful 1.2 IPA build, remote release, screenshot or physical PiP test
is claimed.

After installing a successful 1.2 build, use Settings → Artwork → Clear artwork
cache once and refresh sources to pick up corrected relative cover URLs.
Review missing/failed provider logos, WWE series posters, numbered quality
variants, cache clearing, both appearances, Arabic RTL and native playback.

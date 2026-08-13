// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Controls the app's overall [Brightness] (light / dark).
///

@ProviderFor(ThemeController)
final themeControllerProvider = ThemeControllerProvider._();

/// Controls the app's overall [Brightness] (light / dark).
///
final class ThemeControllerProvider
    extends $NotifierProvider<ThemeController, Brightness> {
  /// Controls the app's overall [Brightness] (light / dark).
  ///
  ThemeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeControllerHash();

  @$internal
  @override
  ThemeController create() => ThemeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Brightness value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Brightness>(value),
    );
  }
}

String _$themeControllerHash() => r'd90847288d47d279d354fd29b3f5c98033905f1e';

/// Controls the app's overall [Brightness] (light / dark).
///

abstract class _$ThemeController extends $Notifier<Brightness> {
  Brightness build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Brightness, Brightness>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Brightness, Brightness>,
              Brightness,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

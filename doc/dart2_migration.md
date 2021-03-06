# Dart 2 Migration Guide

- [Background](#background)
- [Changes Required for Dart 2 Compatibility](#changes-required-for-dart-2-compatibility)
- [Migration From Dart 1 to Dart 2](#migration-from-dart-1-to-dart-2)
- [Temporary Transitional Boilerplate](#temporary-transitional-boilerplate)

## Background

As a part of the Dart SDK 2.0.0 release, support for transformers was removed and
builders were named the canonical replacement moving forward.

This library relied heavily on transformers to provide a developer experience
for building statically-typed React UI components in Dart with minimal overhead,
and we want to keep that promise moving forward.

If we set the migration process aside momentarily and look ahead to Dart 2, the
first takeaway is obviously that over_react needs to provide the same (or
similar) functionality provided by the Dart 1 transformer, but in the form of a
Dart 2-compatible builder. This process is not as straightforward as it may
seem, unfortunately, because the set of limitations imposed by the builder
pattern is more restrictive than with transformers ([for good reason][transformers-to-builders]).
In particular, builders are **not** allowed to transform/augment/modify code
_inline_; all outputs must be written to separate files. The over_react
transformer leveraged inline transformations for quite a lot:

- Initializing component factories
- Generating component factory registrations
- Replacing uninitialized props and state fields with concrete getters and
  setters that map to the underlying, untyped `Map`s used by ReactJS
- Generating wiring or implementations for a variety of APIs that require info
  about the component (i.e. cannot simply be inherited)
- etc.

A lot of this can be generated in a separate part file by a builder, but some of
the inline transformations are simply not possible with a builder approach.
Consequently, changes to the over_react component boilerplate are necessary in
order to support Dart 2.

## Changes Required for Dart 2 Compatibility

### Generated Part

For any file that includes a component definition, the builder will have to
generate code in a separate file which will have to be explicitly included.

```diff
  // foo.dart;
  library foo;

  import 'package:over_react/over_react.dart';

+ part 'foo.over_react.g.dart';

  @Factory() ...
  @Props() ...
  @Component() ...
```

### Component Factory

Previously, component factories were written as uninitialized top-level
variables. On Dart 2, the factory will need to be initialized to a symbol that
the builder will generate.

```diff
  @Factory()
- UiFactory<FooProps> Foo;
+ UiFactory<FooProps> Foo = _$Foo;
```

In this example, the implementation for `_$Foo` is generated by the over_react
builder.

### Props, State, AbstractProps, AbstractState

In order to support the generation of concrete getters/setters for props/state
fields while still maintaining the ability to extend props and state classes on
Dart 2, the classes you define will need to be named with a `_$` prefix. This
allows the builder to generate the public, un-prefixed version that will be used
everywhere else.

```diff
  @Props()
- class FooProps extends UiProps { ... }
+ class _$FooProps extends UiProps { ... }

  @State()
- class FooState extends UiState { ... }
+ class _$FooState extends UiState { ... }

  @AbstractProps()
- class AbstractFooProps extends UiProps { ... }
+ class _$AbstractFooProps extends UiProps { ... }

  @AbstractState()
- class AbstractFooState extends UiState { ... }
+ class _$AbstractFooState extends UiState { ... }
```

In this example, the builder would generate the `FooProps`, `FooState`,
`AbstractFooProps`, and `AbstractFooState` classes with concrete getters and
setters implemented. The `FooProps` class generated by the builder would look
like this:

```dart
class FooProps extends _$FooProps with _$FooPropsAccessorsMixin {}
```

Doing this allows for inheritence of Props and State classes to function as
expected. Since the public version of the class is generated and includes the
concrete getters and setters _as well_ as everything concrete that was defined
in the `_$` version, you or someone else can simply extend it. No additional
work by the builder is required. An example of this inheritence looks like so:

```dart
// super.dart
import 'package:over_react/over_react.dart';
part 'super.over_react.g.dart';

@Props()
class _$SuperProps extends UiProps { ... }
```

```dart
// super.over_react.g.dart (generated)
part of 'super.dart';

class SuperProps extends _$SuperProps ...
```

```dart
// sub.dart
import 'package:over_react/over_react.dart';
import 'super.dart';
part 'sub.over_react.g.dart';

@Props()
class _$SubProps extends SuperProps { ... }
```

### Props and State Mixins

Similar to the non-mixin Props and State classes, Props and State mixins will
need to be written with a `_$` prefix so that the builder can generate the
public, un-prefixed version that will be used everywhere else.

```diff
  @PropsMixin()
- class FooPropsMixin {}
+ class _$FooPropsMixin {}

  @StateMixin()
- class FooStateMixin {}
+ class _$FooStateMixin {}
```

This change looks like the same change as the one above for Props and State
classes, but the builder support behind the scenes is a bit different. This is
because Dart prohibits mixing in classes that extend anything other than
`Object`, meaning that the approach used above for Props and State classes does
not work for Props and State mixins. Instead of generating a public version of
these mixins that extend the consumer-defined version, the builder will generate
a separate class that implements the consumer-defined mixin. This generated
class will have concrete getters and setters implemented for all of the fields
and any additional concrete methods, getters, and setters that are defined in
the mixin will be copied over to the generated class.

An example:

```dart
@PropsMixin()
class _$FooPropsMixin {
  String foo;

  int get length => foo.length;
}

// generated by builder
class FooPropsMixin implements _$FooPropsMixin {
  String get foo => ...;
  set foo(String value) { ... };

  int get length => foo.length;
}
```

### `$Props()` and `$PropKeys()`

These two utility classes are provided by `over_react` as a way to obtain
metadata about a props class. `$Props()` acts as an iterable of the prop fields
defined by a given props class (most commonly used to populate the list of
`consumedProps` for a component), and `$PropKeys()` similarly acts as an
iterable of the string keys for these prop fields.

These utility classes are actually just proxy classes and the transformer
changes them inline to the appropriate formats. This does not work with builders
since inline transformations are disallowed.

This is solved by providing an alternative API to obtain the same information.
Because the builder is generating the public, un-prefixed versions of all the
Props and State classes and mixins, it can include a static `meta` field:

```dart
// generated by builder
class FooProps extends _$FooProps with _$FooPropsAccessorsMixin {
  static PropsMeta meta = _$metaForFooProps;
}

const PropsMeta _$metaForFooProps = const PropsMeta(
  fields: ...,
  keys: ...,
);
```

With this in place, existing usages of `$Props()` and `$PropKeys()` should be
migrated like so:

```diff
- const $Props(FooProps)
+ FooProps.meta

- const $PropKeys(FooProps)
+ FooProps.meta.keys
```

As an added bonus, this meta information becomes available for State classes as
well.

### Component Default Props

In some cases, obtaining the default props for a component can be useful. These
are defined via the component's `getDefaultProps()` method. The easiest way to
obtain these default props is to simply construct the component and call that
method. Unfortunately, constructing the component directly was never intended to
be a supported use case, and in Dart 2 this approach won't work because the
typed props factory implementation needs to be generated.

To work around around this, an alternative API for obtaining a component's
default props has been added:

```diff
- var defaultProps = new FooComponent().getDefaultProps();
+ var defaultProps = Foo().componentDefaultProps;
```

The `componentDefaultProps` getter returns the cached default props for the
component that the factory would eventually construct. One caveat: the getter is
typed as `Map`. If you need to obtain a component's default props typed as the
props class for that component, use the following utility:

```diff
- var defaultProps = new FooComponent().getDefaultProps();
+ var defaultProps = typedDefaultPropsFor(Foo);
```

## Migration From Dart 1 to Dart 2

> _The over_react codemod tool is in the process of being open-sourced, but
> until then the links below will not be publicly accessible._

Now that we've laid out the eventual destination, we need to explain how to get
there.

If you don't need to support a backwards-compatible migration path and just want
to get from Dart 1 to Dart 2 as quickly as possible, you have two options:

1. Update your code manually using the above diffs as a guide.
2. Use our [`over_react_codemod:dart2_upgrade` script][orcm]
   to automate the migration.

If, however, you do need to migrate your `over_react` code from Dart 1 to Dart 2
in a backwards- and forwards-compatible manner, you'll need to take a two-step
approach:

### 1. Migrate to the Forwards- and Backwards-compatible Setup

Use our [`over_react_codemod:dart2_upgrade --backwards-compat` script][orcm]
to update your code to a state that is compatible with both the Dart 1
transformer and the Dart 2 builder. _In this state, you will notice some extra
boilerplate and comments. This will be cleaned up when the transition to Dart 2
is completed and Dart 1 compatibility is no longer desired/needed, but is
necessary during the transition._

If the transition may take a while, you can use that same codemod script as a CI
check to prevent regressions – just add the `--fail-on-changes` flag.

While in this state, you should also update your package's `pubspec.yaml` to
include both the 1.x and 2.x versions of the Dart SDK:

```yaml
environment:
  sdk: ">=1.24.3 <3.0.0"
```

When running on Dart 2, the Dart 2-compatible version of over_react will be
installed and your over_react code will run with the builder.

When running on Dart 1, the Dart 1-compatible version of over_react will be
installed and your over_react code will run with the transformer as it currently
does.

### 2. Migrate to the Dart 2-only Setup

Use our [`over_react_codemod:dart2_upgrade` script][orcm] to update your code to
a state that is only compatible with Dart 2. This mostly involves cleaning up
the extra boilerplate that was required during the transition.

## Temporary Transitional Boilerplate

_Feel free to skip this section. It is included to show what the transitional
Dart1- and Dart2-compatible boilerplate looks like and the rationale behind
certain pieces._

### Ignoring the Generated Part

```diff
  // foo.dart;
  library foo;

  import 'package:over_react/over_react.dart';

+  // ignore: uri_has_not_been_generated
+  part 'foo.over_react.g.dart';

  @Factory() ...
  @Props() ...
  @Component() ...
```

This part directive is required for Dart 2 builder compatibility, but comes with
the caveat that the file does not actually exist by default.

- **Dart 1** - the file will never exist in the filesystem – it will only be
  created by the over_react transformer. As a result, the
  `// ignore: uri_has_not_been_generated` is needed to silence the static
  analysis error.
- **Dart 2** - the file will not exist until a build is run. Once Dart 1 support
  is dropped completely from over_react in our 2.0.0 release, a passing build
  will be a requirement for writing over_react code, at which point the
  `// ignore: ...` comment can be dropped.

### Ignoring the Undefined Factory Initializer

```diff
  @Factory()
- UiFactory<FooProps> Foo;
+ UiFactory<FooProps> Foo =
+     // ignore: undefined_identifier
+     _$Foo;
```

In this example, the implementation for `_$Foo` is generated by either the
over_react builder or transformer, but in both cases it does not exist by
default.

- **Dart 1** - the transformer inserts an implementation of `_$Foo`, but it is
  only available at runtime. Consequently, the `// ignore: undefined_identifier`
  comment is needed for a passing static analysis.
- **Dart 2** - the generated `foo.over_react.g.dart` file will contain the
  implementation of `_$Foo`. Again, once Dart 1 support is dropped completely
  in over_react 2.0.0, the `// ignore: ...` comment can be dropped.

### Accompanying Classes for Props, State, AbstractProps, AbstractState

```diff
  @Props()
- class FooProps extends UiProps { ... }
+ class _$FooProps extends UiProps { ... }
+
+ // This will be removed once the transition to Dart 2 is complete.
+ class FooProps extends _$FooProps
+     with
+         // ignore: mixin_of_non_class, undefined_class
+         _$FooPropsAccessorsMixin {
+   // ignore: undefined_identifier, undefined_class, const_initialized_with_non_constant_value
+   static const PropsMeta meta = _$metaForFooProps;
+ }
```

Once Dart 1 support is dropped, the `FooProps` class can be completely generated
by the builder. But on Dart 1, it has to be statically defined because it is
referenced in the factory and component and the analyzer needs to be able to
resolve the class fields in order to provide autocompletion of said fields.

While this example uses a `@Props()` class, this applies to `@State()`,
`@AbstractProps()`, and `@AbstractState()` classes as well.

### Props and State Mixin Static Meta Fields

Because we cannot have the builder generate the public props or state mixin
class while still supporting Dart 1, we have to temporarily add the static
`PropsMeta` or `StateMeta` field to all props and state mixin classes.

```diff
  @PropsMixin()
  abstract class FooPropsMixin implements UiProps {
+   // ignore: undefined_identifier, undefined_class, const_initialized_with_non_constant_value
+   static const PropsMeta meta = _$metaForFooPropsMixin;
  }
```

Again, an `// ignore: ...` comment is required for the analyzer because the
`_$metaForFooPropsMixin` implementation will only be provided by the transformer
or the builder. Once Dart 1 support is completely dropped, this consumer-defined
props mixin will be renamed to `_$FooPropsMixin` and the builder will handle
generating `FooPropsMixin` along with its static `meta` field.

### Props and State Mixin Usages

As explained above, mixins are unique in that we cannot extend them to provide
the concrete accessor implementations like we do for non-mixin props and state
classes. In order to make this work, we have to temporarily update all usages
of props and state mixins to actually be a "pair" of mixins – one being the
consumer-defined mixin and the second being a generated mixin that actually
includes the concrete accessor implementations.

```diff
  @PropsMixin()
  class _$FooProps extends UiProps
-     with BarPropsMixin {
+     with BarPropsMixin,
+          // ignore: mixin_of_non_class, undefined_class
+          $BarPropsMixin {
    ...
  }
```

Similar to the previous sections, an `// ignore: ...` comment is needed to
satisfy the analyzer because `$BarPropsMixin` does not exist statically; it is
either inserted by the transformer or generated by the builder.

Once Dart 1 support is dropped completely in over_react 2.0.0, these mixin usage
changes will be reverted and it will look like it originally did (only mixing
in `BarPropsMixin` in this example), because the mixin definition will be
renamed to `_$BarPropsMixin` and the builder will handle generating
`BarPropsMixin`.

[orcm]: https://github.com/Workiva/over_react_codemod
[transformers-to-builders]: https://github.com/dart-lang/build/blob/master/docs/from_barback_transformer.md
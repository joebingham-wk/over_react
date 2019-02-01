part of basic.library;

// ignore: mixin_of_non_class,undefined_class
class SuperPartOfLibProps extends _$SuperPartOfLibProps with _$SuperPartOfLibPropsAccessorsMixin {
  static const PropsMeta meta = _$metaForSuperPartOfLibProps;
}

@AbstractProps()
class _$SuperPartOfLibProps extends UiProps {
  String superProp;
}

@AbstractComponent()
abstract class SuperPartOfLibComponent<T extends SuperPartOfLibProps> extends UiComponent<T> {
  @override
  Map getDefaultProps() => newProps()..id = 'super';

  @override
  render() {
    return Dom.div()('SuperPartOfLib', {
      'props.superProp': props.superProp,
    }.toString());
  }
}

@Factory()
UiFactory<SubPartOfLibProps> SubPartOfLib = _$SubPartOfLib;

// ignore: mixin_of_non_class,undefined_class
class SubPartOfLibProps extends _$SubPartOfLibProps with _$SubPartOfLibPropsAccessorsMixin {
  static const PropsMeta meta = _$metaForSubPartOfLibProps;
}

@Props()
class _$SubPartOfLibProps extends SuperPartOfLibProps {
  String subProp;
}

@Component()
class SubPartOfLibComponent extends SuperPartOfLibComponent<SubPartOfLibProps> {
  @override
  Map getDefaultProps() => newProps()..id = 'sub';

  @override
  render() {
    return Dom.div()('SubPartOfLib', {
      'props.subProp': props.subProp,
      'props.superProp': props.superProp,
    }.toString());
  }
}

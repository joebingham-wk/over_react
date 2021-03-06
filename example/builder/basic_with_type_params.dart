import 'package:over_react/over_react.dart';

part 'basic_with_type_params.over_react.g.dart';

@Factory()
UiFactory<BasicProps> Basic = _$Basic;

@Props()
class _$BasicProps<T, U extends UiProps> extends UiProps {
  List<T> someGenericListProp;
  U somePropsClass;
}

@Component()
class BasicComponent extends UiComponent<BasicProps> {
  @override
  Map getDefaultProps() => newProps()..id = 'basic component';

  @override
  render() {
    return Dom.div()(
        Dom.div()('prop id: ${props.id}'),
    );
  }
}



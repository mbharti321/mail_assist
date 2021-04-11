import 'package:enough_mail_app/models/swipe.dart';
import 'package:enough_mail_app/services/navigation_service.dart';
import 'package:enough_mail_app/util/dialog_helper.dart';
import 'package:enough_mail_app/services/i18n_service.dart';
import 'package:enough_mail_app/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../locator.dart';
import 'base.dart';

class SettingsSwipeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = locator<SettingsService>().settings;
    final leftToRightAction = settings.swipeLeftToRightAction;
    final rightToLeftAction = settings.swipeRightToLeftAction;

    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    return Base.buildAppChrome(
      context,
      title: localizations.swipeSettingTitle,
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.swipeSettingLeftToRightLabel,
                  style: theme.textTheme.caption),
              _SwipeSetting(
                swipeAction: leftToRightAction,
                isLeftToRight: true,
              ),
              Divider(),
              Text(localizations.swipeSettingRightToLeftLabel,
                  style: theme.textTheme.caption),
              _SwipeSetting(
                swipeAction: rightToLeftAction,
                isLeftToRight: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeSetting extends StatefulWidget {
  final bool isLeftToRight;
  final SwipeAction swipeAction;

  const _SwipeSetting(
      {Key key, @required this.swipeAction, @required this.isLeftToRight})
      : super(key: key);

  @override
  _SwipeSettingState createState() => _SwipeSettingState();
}

class _SwipeSettingState extends State<_SwipeSetting> {
  SwipeAction _currentAction;

  @override
  void initState() {
    super.initState();
    _currentAction = widget.swipeAction;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Row(
      children: [
        TextButton(
          onPressed: _onPressed,
          child: _SwipeWidget(
            swipeAction: _currentAction,
          ),
        ),
        TextButton.icon(
          onPressed: _onPressed,
          icon: Icon(Icons.edit),
          label: Text(localizations.swipeSettingChangeAction),
        ),
      ],
    );
  }

  void _onPressed() async {
    final action = await selectSwipe(_currentAction);
    if (action != null) {
      setState(() {
        _currentAction = action;
      });
      final service = locator<SettingsService>();
      if (widget.isLeftToRight) {
        service.settings.swipeLeftToRightAction = action;
      } else {
        service.settings.swipeRightToLeftAction = action;
      }
      await locator<SettingsService>().save();
    }
  }

  Future<SwipeAction> selectSwipe(SwipeAction current) async {
    final localizations = AppLocalizations.of(context);

    final action = await DialogHelper.showWidgetDialog(
      context,
      widget.isLeftToRight
          ? localizations.swipeSettingLeftToRightLabel
          : localizations.swipeSettingRightToLeftLabel,
      SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          children: SwipeAction.values
              .map(
                (action) => TextButton(
                  child: Stack(
                    children: [
                      _SwipeWidget(
                        swipeAction: action,
                      ),
                      if (action == current) ...{
                        Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            decoration: new BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check,
                                color: Theme.of(context).accentColor),
                          ),
                        ),
                      },
                    ],
                  ),
                  onPressed: () {
                    locator<NavigationService>().pop(action);
                  },
                ),
              )
              .toList(),
        ),
      ),
      defaultActions: DialogActions.cancel,
    );
    return action;
  }
}

class _SwipeWidget extends StatelessWidget {
  final SwipeAction swipeAction;
  const _SwipeWidget({Key key, @required this.swipeAction}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          color: swipeAction.colorBackground,
          width: 128,
          height: 128,
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Icon(
                    swipeAction.icon,
                    color: swipeAction.colorIcon,
                  ),
                ),
                Text(
                  swipeAction.name(localizations),
                  style: TextStyle(color: swipeAction.colorForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

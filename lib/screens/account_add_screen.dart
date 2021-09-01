import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail_app/extensions/extensions.dart';
import 'package:enough_mail_app/locator.dart';
import 'package:enough_mail_app/models/account.dart';
import 'package:enough_mail_app/services/providers.dart';
import 'package:enough_mail_app/routes.dart';
import 'package:enough_mail_app/screens/base.dart';
import 'package:enough_mail_app/services/i18n_service.dart';
import 'package:enough_mail_app/services/mail_service.dart';
import 'package:enough_mail_app/services/navigation_service.dart';
import 'package:enough_mail_app/util/modal_bottom_sheet_helper.dart';
import 'package:enough_mail_app/util/validator.dart';
import 'package:enough_mail_app/widgets/account_provider_selector.dart';
import 'package:enough_mail_app/widgets/button_text.dart';
import 'package:enough_mail_app/widgets/password_field.dart';
import 'package:enough_platform_widgets/enough_platform_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AccountAddScreen extends StatefulWidget {
  final bool launchedFromWelcome;

  const AccountAddScreen({Key? key, this.launchedFromWelcome = false});

  @override
  _AccountAddScreenState createState() => _AccountAddScreenState();
}

class _AccountAddScreenState extends State<AccountAddScreen> {
  static const int _stepEmail = 0;
  static const int _stepPassword = 1;
  static const int _stepAccountSetup = 2;
  MailAccount _account = MailAccount();
  late int _availableSteps;
  int _currentStep = 0;
  int _progressedSteps = 0;
  bool _isContinueAvailable = false;
  bool? _isApplicationSpecificPasswordAcknowledged = false;
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  TextEditingController _accountNameController = TextEditingController();
  TextEditingController _userNameController = TextEditingController();

  bool _isProviderResolving = false;
  Provider? _provider;
  bool _isManualSettings = false;
  bool _isAccountVerifying = false;
  bool _isAccountVerified = false;
  List<AppExtension>? _extensions;
  MailClient? _mailClient;
  AppExtensionActionDescription? _extensionForgotPassword;

  Future<void> _navigateToManualSettings(
      BuildContext context, AppLocalizations localizations) async {
    Provider? selectedProvider;
    final result = await ModelBottomSheetHelper.showModalBottomSheet(
      context,
      localizations.accountProviderStepTitle,
      AccountProviderSelector(onSelected: (provider) {
        selectedProvider = provider;
        Navigator.of(context).pop(true);
      }),
      useScrollView: false,
      appBarActions: [],
    );
    if (!result) {
      return;
    }
    if (selectedProvider != null) {
      // a standard provider has been chosen, now query the password or start the oauth process:
      setState(() {
        _provider = selectedProvider;
      });
      _onProviderChanged(selectedProvider!, _emailController.text);
    } else {
      _account.incoming = MailServerConfig(
        authentication: PlainAuthentication('', ''),
        serverConfig: ServerConfig(),
      );
      _account.outgoing = MailServerConfig(
        authentication: PlainAuthentication('', ''),
        serverConfig: ServerConfig(),
      );

      final editResult = await locator<NavigationService>()
          .push(Routes.accountServerDetails, arguments: Account(_account));
      if (result is ConnectedAccount) {
        setState(() {
          _account = editResult.account;
          _mailClient = editResult.mailClient;
          _currentStep = 2;
          _isAccountVerified = true;
        });
      }
    }
  }

  @override
  void initState() {
    _availableSteps = 3;
    if (locator<MailService>().accounts.isNotEmpty) {
      _userNameController.text =
          locator<MailService>().accounts.first.userName!;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // print('build: current step=$_currentStep');
    final localizations = AppLocalizations.of(context)!;
    return Base.buildAppChrome(
      context,
      title: localizations.addAccountTitle,
      content: Column(
        children: [
          Expanded(
            child: PlatformStepper(
              type: StepperType.vertical,
              onStepContinue: _isContinueAvailable
                  ? () async {
                      var step = _currentStep + 1;
                      if (step < _availableSteps) {
                        setState(() {
                          _currentStep = step;
                          _isContinueAvailable = false;
                        });
                      }
                      _onStepProgressed(step);
                    }
                  : null,
              onStepCancel: () => Navigator.pop(context),
              currentStep: _currentStep,
              onStepTapped: (index) {
                if (index != _currentStep && index <= _progressedSteps) {
                  setState(() {
                    _currentStep = index;
                    _isContinueAvailable = true;
                  });
                }
              },
              steps: [
                _buildEmailStep(context, localizations),
                _buildPasswordStep(context, localizations),
                _buildAccountSetupStep(context, localizations),
              ],
            ),
          )
        ],
      ),
    );
  }

  Future<void> _onStepProgressed(int step) async {
    _progressedSteps = step;
    switch (step) {
      case _stepEmail + 1:
        await _discover(_account.email!);
        break;
      case _stepPassword + 1:
        await _verifyAccount();
        break;
      case _stepAccountSetup + 1:
        await _finalizeAccount();
        break;
    }
  }

  Future _discover(String email) async {
    // email address has been entered
    if (!_isProviderResolving) {
      setState(() {
        _isProviderResolving = true;
      });
    }
    print('discover settings for $email');
    final provider = await locator<ProviderService>().discover(email);
    if (!mounted) {
      // ignore if user has cancelled operation
      return;
    }
    print('done discovering settings: ${provider?.displayName}');
    if (provider?.appSpecificPasswordSetupUrl != null) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _isApplicationSpecificPasswordAcknowledged = false;
    final domainName = email.substring(email.lastIndexOf('@') + 1);
    _accountNameController.text = domainName;
    if (provider != null) {
      _onProviderChanged(provider, email);
    }

    setState(() {
      _isProviderResolving = false;
      _provider = provider;
      _isContinueAvailable =
          (provider != null) && _passwordController.text.isNotEmpty;
    });
  }

  Future _loginWithOAuth(Provider provider, String email) async {
    setState(() {
      _isAccountVerifying = true;
      _currentStep = _stepAccountSetup;
      _progressedSteps = _stepAccountSetup;
    });
    final token = await provider.oauthClient!.authenticate(email);

    // whenthe user either has cancelled the verification, not granted the scope or the verification failed for other reasons,
    // then token will be null
    if (token == null) {
      setState(() {
        _isAccountVerifying = false;
        _currentStep = _stepPassword;
        _progressedSteps = _stepAccountSetup;
      });
    } else {
      final mailAccount = MailAccount.fromDiscoveredSettingsWithAuth(
        email,
        email,
        OauthAuthentication(email, token),
        provider.clientConfig,
      );
      _mailClient = await locator<MailService>().connect(mailAccount);
      final isVerified = _mailClient?.isConnected ?? false;
      if (isVerified) {
        mailAccount.appExtensions = _extensions;
        _account = mailAccount;
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      setState(() {
        _isAccountVerifying = false;
        _isAccountVerified = isVerified;
        _isContinueAvailable =
            isVerified && _userNameController.text.isNotEmpty;
      });
    }
  }

  Future _verifyAccount() async {
    // password and possibly manual account details have been specified
    setState(() {
      _isAccountVerifying = true;
    });
    final mailAccount = MailAccount.fromDiscoveredSettings(
      _emailController.text,
      _emailController.text,
      _passwordController.text,
      _provider!.clientConfig,
    );
    _mailClient = await locator<MailService>().connect(mailAccount);

    final isVerified = _mailClient?.isConnected ?? false;
    if (isVerified) {
      mailAccount.appExtensions = _extensions;
      _account = mailAccount;
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
      _isAccountVerifying = false;
      _isAccountVerified = isVerified;
      _isContinueAvailable = isVerified && _userNameController.text.isNotEmpty;
    });
  }

  Future _finalizeAccount() async {
    // Account name has been specified
    _account.name = _accountNameController.text;
    _account.userName = _userNameController.text;
    final service = locator<MailService>();
    final added = await service.addAccount(_account, _mailClient!, context);
    if (added) {
      if (Platform.isIOS && widget.launchedFromWelcome) {
        locator<NavigationService>().push(Routes.appDrawer, clear: true);
      }
      locator<NavigationService>().push(
        Routes.messageSource,
        arguments: service.messageSource,
        clear: !Platform.isIOS && widget.launchedFromWelcome,
        replace: !widget.launchedFromWelcome,
        fade: true,
      );
    }
  }

  _buildEmailStep(BuildContext context, AppLocalizations localizations) {
    return Step(
      title: Text(localizations.addAccountEmailLabel +
          (_currentStep > 0 ? ' ${_account.email}' : '')),
      content: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          DecoratedPlatformTextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            cupertinoShowLabel: false,
            onChanged: (value) {
              final isValid = Validator.validateEmail(value);
              if (isValid) {
                _account.email = value;
              }
              if (isValid != _isContinueAvailable) {
                setState(() {
                  _isContinueAvailable = isValid;
                });
              }
            },
            decoration: InputDecoration(
              labelText: localizations.addAccountEmailLabel,
              hintText: localizations.addAccountEmailHint,
              icon: const Icon(Icons.email),
            ),
            autofocus: true,
          ),
        ],
      ),
      //state: StepState.editing,
      isActive: true,
    );
  }

  _buildPasswordStep(BuildContext context, AppLocalizations localizations) {
    final provider = _provider;

    return Step(
      title: Text(localizations.addAccountPasswordLabel),
      //state: StepState.complete,
      isActive: _currentStep >= 1,
      content: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (_isProviderResolving) ...{
            Row(
              children: [
                Container(
                    padding: EdgeInsets.all(8),
                    child: PlatformProgressIndicator()),
                Expanded(
                  child: Text(localizations
                      .addAccountResolvingSetingsLabel(_account.email!)),
                ),
              ],
            ),
          } else if (provider != null) ...{
            Column(
              children: [
                if (provider.hasOAuthClient) ...{
                  // The user can continue to sign in with the provider or by using an app-specific password
                  Text(
                    localizations.addAccountOauthOptionsText(
                        provider.displayName ?? '<unknown>'),
                  ),
                  provider.buildSignInButton(
                    context,
                    onPressed: () => _loginWithOAuth(provider, _account.email!),
                    isSignInButton: true,
                  ),
                  if (provider.appSpecificPasswordSetupUrl != null) ...{
                    Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                          localizations.addAccountOauthSignInWithAppPassword),
                    ),
                    PlatformTextButton(
                      onPressed: () async {
                        await launcher
                            .launch(provider.appSpecificPasswordSetupUrl!);
                      },
                      child: ButtonText(localizations
                          .addAccountApplicationPasswordRequiredButton),
                    ),
                    PlatformCheckboxListTile(
                      onChanged: (value) => setState(() =>
                          _isApplicationSpecificPasswordAcknowledged = value),
                      value: _isApplicationSpecificPasswordAcknowledged,
                      title: Text(localizations
                          .addAccountApplicationPasswordRequiredAcknowledged),
                    ),
                  },
                } else if (provider.appSpecificPasswordSetupUrl != null) ...{
                  Text(localizations.addAccountApplicationPasswordRequiredInfo),
                  PlatformTextButton(
                    onPressed: () async {
                      await launcher
                          .launch(provider.appSpecificPasswordSetupUrl!);
                    },
                    child: ButtonText(localizations
                        .addAccountApplicationPasswordRequiredButton),
                  ),
                  PlatformCheckboxListTile(
                    onChanged: (value) => setState(() =>
                        _isApplicationSpecificPasswordAcknowledged = value),
                    value: _isApplicationSpecificPasswordAcknowledged,
                    title: Text(localizations
                        .addAccountApplicationPasswordRequiredAcknowledged),
                  ),
                },
                if (provider.appSpecificPasswordSetupUrl == null ||
                    _isApplicationSpecificPasswordAcknowledged!) ...{
                  PasswordField(
                    controller: _passwordController,
                    cupertinoShowLabel: false,
                    onChanged: (value) {
                      bool isValid = value.isNotEmpty &&
                          (_provider?.clientConfig != null ||
                              _isManualSettings);
                      if (isValid != _isContinueAvailable) {
                        setState(() {
                          _isContinueAvailable = isValid;
                        });
                      }
                    },
                    autofocus: true,
                    labelText: localizations.addAccountPasswordLabel,
                    hintText: localizations.addAccountPasswordHint,
                  ),
                },
                PlatformTextButton(
                  onPressed: () =>
                      _navigateToManualSettings(context, localizations),
                  child: ButtonText(
                    localizations.addAccountResolvedSettingsWrongAction(
                        _provider?.displayName ?? '<unknown>'),
                  ),
                ),
                if (_extensionForgotPassword != null) ...{
                  PlatformTextButton(
                    onPressed: () {
                      final languageCode =
                          locator<I18nService>().locale!.languageCode;
                      var url = _extensionForgotPassword!.action!.url;
                      url = url
                        ..replaceAll('{user.email}', _account.email ?? '')
                        ..replaceAll('{language}', languageCode);
                      launcher.launch(url);
                    },
                    child: ButtonText(_extensionForgotPassword!
                        .getLabel(locator<I18nService>().locale!.languageCode)),
                  ),
                },
              ],
            ),
          } else ...{
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.addAccountResolvingSetingsFailedInfo(
                    _account.email ?? '')),
                PlatformElevatedButton(
                  child: ButtonText(localizations.addAccountEditManuallyAction),
                  onPressed: () =>
                      _navigateToManualSettings(context, localizations),
                )
              ],
            ),
          },
        ],
      ),
    );
  }

  _buildAccountSetupStep(BuildContext context, AppLocalizations localizations) {
    return Step(
      title: Text(_isAccountVerified
          ? localizations.addAccountSetupAccountStep
          : localizations.addAccountVerificationStep),
      content: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (_isAccountVerifying) ...{
            Row(
              children: [
                Container(
                    padding: EdgeInsets.all(8),
                    child: PlatformProgressIndicator()),
                Expanded(
                  child: Text(localizations
                      .addAccountVerifyingSettingsLabel(_account.email!)),
                ),
              ],
            ),
          } else if (_isAccountVerified) ...{
            Text(localizations.addAccountVerifyingSuccessInfo(_account.email!)),
            DecoratedPlatformTextField(
              controller: _userNameController,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.words,
              onChanged: (value) {
                bool isValid =
                    value.isNotEmpty && _accountNameController.text.isNotEmpty;
                if (isValid != _isContinueAvailable) {
                  setState(() {
                    _isContinueAvailable = isValid;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: localizations.addAccountNameOfUserLabel,
                hintText: localizations.addAccountNameOfUserHint,
                icon: const Icon(Icons.account_circle),
              ),
              autofocus: true,
              cupertinoAlignLabelOnTop: true,
            ),
            DecoratedPlatformTextField(
              controller: _accountNameController,
              keyboardType: TextInputType.text,
              onChanged: (value) {
                bool isValid =
                    value.isNotEmpty && _userNameController.text.isNotEmpty;
                if (isValid != _isContinueAvailable) {
                  setState(() {
                    _isContinueAvailable = isValid;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: localizations.addAccountNameOfAccountLabel,
                hintText: localizations.addAccountNameOfAccountHint,
                icon: const Icon(Icons.email),
              ),
              cupertinoAlignLabelOnTop: true,
            ),
          } else ...{
            Text(localizations
                .addAccountVerifyingFailedInfo(_account.email ?? '')),
            if (_provider?.manualImapAccessSetupUrl != null) ...{
              Padding(
                padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                    localizations.accountAddImapAccessSetuptMightBeRequired),
              ),
              PlatformTextButton(
                child: ButtonText(
                    localizations.addAccoutSetupImapAccessButtonLabel),
                onPressed: () =>
                    launcher.launch(_provider!.manualImapAccessSetupUrl!),
              ),
            },
          }
        ],
      ),
    );
  }

  void _onProviderChanged(Provider provider, String email) {
    final mailAccount = MailAccount.fromDiscoveredSettings(
      _emailController.text,
      _emailController.text,
      _passwordController.text,
      provider.clientConfig,
    );
    AppExtension.loadFor(mailAccount).then((value) {
      _extensions = value;
      final forgotPwUrl = mailAccount.appExtensionForgotPassword;
      if (forgotPwUrl != null) {
        setState(() {
          _extensionForgotPassword = forgotPwUrl;
        });
      }
    });
  }
}

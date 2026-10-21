import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/notification_preferences.dart';
import 'data/email_notifications_client.dart';
import 'main.dart' show storeProvider, brandedPageTitle;

final emailSettingsClientFactoryProvider =
    Provider<EmailNotificationsClient Function()>(
      (ref) =>
          () => EmailNotificationsClient(),
    );

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage>
    with WidgetsBindingObserver {
  final email = TextEditingController();
  final emailFocus = FocusNode();
  Timer? confirmationPoll;
  NotificationPreferences? preferences;
  bool android = false, emailConsent = false;
  bool results = true, prizes = true, expiry = true;
  bool busy = false;
  int leadDays = 7;
  String? error;
  String emailStatus = 'not_subscribed';
  String? notice;
  bool noticeError = false;
  bool dirty = false;

  void feedback(String text, {bool failure = false}) {
    if (!mounted) return;
    setState(() {
      notice = text;
      noticeError = failure;
      error = failure ? text : null;
    });
  }

  void changed(VoidCallback update, {bool announce = true}) {
    setState(() {
      update();
      dirty = true;
      noticeError = false;
      error = null;
      notice = null;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    emailFocus.addListener(() {
      if (!emailFocus.hasFocus) autoSaveEmail();
    });
    confirmationPoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (emailStatus == 'pending' &&
          !busy &&
          !dirty &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        refreshEmail(quiet: true);
      }
    });
    load();
  }

  Future<void> load() async {
    try {
      final value = await NotificationPreferences.load(ref.read(storeProvider));
      final allowed = value.android && await AndroidNotifications.enabled();
      final status = await ref.read(storeProvider).setting(emailStatusKey);
      if (!mounted) return;
      setState(() {
        preferences = value;
        email.text = value.email;
        android = allowed;
        emailConsent = value.emailConsent;
        results = value.results;
        prizes = value.prizes;
        expiry = value.expiry;
        leadDays = value.leadDays;
        emailStatus = status ?? 'not_subscribed';
      });
      if (emailConsent) unawaited(refreshEmail(quiet: true));
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível ler as preferências.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy && !dirty && emailConsent) {
      refreshEmail(quiet: true);
    }
  }

  Future<void> autoSaveEmail() async {
    if (!mounted ||
        busy ||
        !dirty ||
        !emailConsent ||
        !NotificationPreferences.validEmail(email.text.trim())) {
      return;
    }
    await save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    confirmationPoll?.cancel();
    emailFocus.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> setAndroid(bool value) async {
    setState(() => busy = true);
    try {
      final allowed = value ? await AndroidNotifications.request() : false;
      if (!value) await AndroidNotifications.cancelAll();
      if (!mounted) return;
      changed(() => android = allowed);
      if (value && !allowed) {
        feedback(
          'Notificações não autorizadas pelo Android. Pode alterar a autorização nas definições do dispositivo.',
          failure: true,
        );
      }
    } catch (_) {
      if (mounted) {
        feedback(
          'Não foi possível pedir autorização. Tente novamente.',
          failure: true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    final address = email.text.trim();
    if (emailConsent && !NotificationPreferences.validEmail(address)) {
      feedback(
        'Não foi possível guardar: introduza um endereço de email válido.',
        failure: true,
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    bool serverUpdated = false;
    bool localSaved = false;
    try {
      final value = NotificationPreferences(
        android: android && await AndroidNotifications.enabled(),
        emailConsent: emailConsent,
        email: address,
        results: results,
        prizes: prizes,
        expiry: expiry,
        leadDays: leadDays,
        emailConsentAt: emailConsent
            ? (preferences?.emailConsent == true &&
                      preferences?.email == address
                  ? preferences?.emailConsentAt
                  : DateTime.now().toUtc().toIso8601String())
            : null,
      );
      final client = ref.read(emailSettingsClientFactoryProvider)();
      String status;
      try {
        status = await client.configure(ref.read(storeProvider), value);
        serverUpdated = true;
      } finally {
        client.close();
      }
      await ref
          .read(storeProvider)
          .setSetting(notificationSettingsKey, jsonEncode(value.toJson()));
      localSaved = true;
      if (!value.android) {
        try {
          await AndroidNotifications.cancelAll();
        } catch (_) {
          // Preferences are saved even if the platform cannot clear old notices.
        }
      }
      if (!mounted) return;
      setState(() {
        preferences = value;
        emailStatus = status;
        dirty = false;
      });
      await synchronizeEmailWallet(ref.read(storeProvider));
      final problem = value.emailConsent
          ? await ref
                .read(storeProvider)
                .setting('notifications.email.lastSyncError')
          : null;
      final delivery = await ref.read(storeProvider).setting(emailDeliveryKey);
      if (status == 'pending' &&
          ['failed', 'uncertain', 'queued'].contains(delivery)) {
        feedback(
          'Preferências guardadas. O email ainda não foi enviado. Tente reenviar.',
          failure: true,
        );
      } else if (problem != null && problem.isNotEmpty) {
        feedback(
          'Preferências guardadas. A sincronização será repetida.',
          failure: true,
        );
      } else {
        feedback(
          status == 'pending'
              ? 'Preferências guardadas. Confirme o endereço no email.'
              : status == 'active'
              ? 'Definições guardadas com sucesso. Avisos por email ativos.'
              : 'Definições guardadas com sucesso. Avisos por email desativados.',
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        feedback(
          'Não foi possível guardar as alterações. ${e.message}',
          failure: true,
        );
      }
    } catch (_) {
      if (mounted) {
        feedback(
          localSaved
              ? 'As definições ficaram guardadas, mas não foi possível concluir a atualização dos avisos.'
              : serverUpdated
              ? 'O servidor recebeu a alteração, mas não foi possível guardá-la no dispositivo. Tente novamente.'
              : 'Não foi possível guardar as alterações. Verifique a ligação à Internet e tente novamente.',
          failure: true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refreshEmail({bool quiet = false}) async {
    if (dirty || busy) {
      if (quiet) return;
      feedback(
        'Guarde as alterações antes de verificar a confirmação do email.',
        failure: true,
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final client = ref.read(emailSettingsClientFactoryProvider)();
    try {
      final status = await client.refresh(ref.read(storeProvider));
      await synchronizeEmailWallet(ref.read(storeProvider));
      final problem = await ref
          .read(storeProvider)
          .setting('notifications.email.lastSyncError');
      if (mounted) {
        setState(() {
          emailStatus = status;
        });
        if (quiet) return;
        if (problem != null && problem.isNotEmpty) {
          feedback(
            'O estado do email foi atualizado, mas a carteira não foi sincronizada. Tente novamente.',
            failure: true,
          );
        } else {
          feedback(
            status == 'active'
                ? 'Email confirmado. Estado atualizado e carteira sincronizada.'
                : status == 'pending'
                ? 'O email ainda aguarda confirmação. Abra a ligação recebida na mensagem.'
                : status == 'revoked'
                ? 'A subscrição de email está cancelada.'
                : 'Não existe uma subscrição ativa. Guarde as preferências para a criar.',
          );
        }
      }
    } on FormatException catch (e) {
      if (mounted && !quiet) {
        feedback(
          'Não foi possível verificar o email. ${e.message}',
          failure: true,
        );
      }
    } catch (_) {
      if (mounted && !quiet) {
        feedback(
          'Não foi possível consultar a subscrição de email. Verifique a ligação à Internet e tente novamente.',
          failure: true,
        );
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: brandedPageTitle('Notificações')),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton(
        onPressed: busy || preferences == null ? null : save,
        child: Text(
          busy
              ? 'A atualizar…'
              : dirty
              ? 'Guardar alterações'
              : 'Guardar preferências',
        ),
      ),
    ),
    body: preferences == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : Text(error!),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (notice != null)
                Semantics(
                  liveRegion: true,
                  child: Card(
                    child: ListTile(
                      leading: Icon(
                        noticeError
                            ? Icons.error_outline
                            : dirty
                            ? Icons.edit_notifications_outlined
                            : Icons.check_circle_outline,
                      ),
                      title: Text(notice!),
                    ),
                  ),
                ),
              const Text('Os seus avisos'),
              SwitchListTile(
                title: const Text('Notificações no Android'),
                subtitle: const Text('Resultados e prémios no telemóvel'),
                value: android,
                onChanged: busy ? null : setAndroid,
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await AndroidNotifications.settings();
                      },
                child: const Text(
                  'Abrir definições de notificações do Android',
                ),
              ),
              SwitchListTile(
                title: const Text('Receber avisos por email'),
                subtitle: const Text(
                  'Receber os avisos selecionados e sincronizar as apostas para acompanhar prémios.',
                ),
                value: emailConsent,
                onChanged: busy
                    ? null
                    : (v) {
                        changed(() => emailConsent = v);
                        if (v) {
                          autoSaveEmail();
                        } else {
                          save();
                        }
                      },
              ),
              TextField(
                controller: email,
                focusNode: emailFocus,
                onSubmitted: (_) => autoSaveEmail(),
                textInputAction: TextInputAction.done,
                onChanged: (_) => changed(() {}, announce: false),
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Endereço de email',
                  helperText: 'Ao terminar, enviamos a ligação de confirmação.',
                  helperMaxLines: 2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  emailStatus == 'active'
                      ? 'Email confirmado · Avisos ativos'
                      : emailStatus == 'pending'
                      ? 'Confirme o endereço na ligação recebida por email.'
                      : 'Avisos por email desativados',
                ),
              ),
              if (emailConsent && emailStatus == 'pending')
                TextButton(
                  onPressed: busy ? null : save,
                  child: const Text('Reenviar email de confirmação'),
                ),
              if (emailConsent)
                OutlinedButton(
                  onPressed: busy ? null : refreshEmail,
                  child: const Text('Atualizar estado do email'),
                ),
              const Divider(),
              SwitchListTile(
                title: const Text('Resultados disponíveis'),
                value: results,
                onChanged: busy ? null : (v) => changed(() => results = v),
              ),
              SwitchListTile(
                title: const Text('Lembretes de prémios por levantar'),
                value: prizes,
                onChanged: busy ? null : (v) => changed(() => prizes = v),
              ),
              SwitchListTile(
                title: const Text('Prémios próximos do prazo de levantamento'),
                subtitle: const Text(
                  'Receber um lembrete antes do fim do prazo.',
                ),
                value: expiry,
                onChanged: busy ? null : (v) => changed(() => expiry = v),
              ),
              if (expiry)
                DropdownButtonFormField<int>(
                  initialValue: leadDays,
                  decoration: const InputDecoration(
                    labelText: 'Antecedência do aviso',
                  ),
                  items: [1, 3, 7, 14]
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text('$d dia(s) antes'),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => changed(() => leadDays = v!),
                ),
              const SizedBox(height: 16),
            ],
          ),
  );
}

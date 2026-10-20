import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/notification_preferences.dart';
import 'data/email_notifications_client.dart';
import 'main.dart' show storeProvider, brandedPageTitle;

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  final email = TextEditingController();
  NotificationPreferences? preferences;
  bool android = false, emailConsent = false;
  bool results = true, prizes = true, expiry = true;
  bool busy = false;
  int leadDays = 7;
  String? error;
  String emailStatus = 'not_subscribed';

  @override
  void initState() {
    super.initState();
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
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível ler as preferências.');
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> setAndroid(bool value) async {
    setState(() => busy = true);
    try {
      final allowed = value ? await AndroidNotifications.request() : false;
      if (!value) await AndroidNotifications.cancelAll();
      if (!mounted) return;
      setState(() => android = allowed);
      if (value && !allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notificações não autorizadas. Pode alterar a autorização nas definições do Android.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível pedir autorização.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final address = email.text.trim();
    if (emailConsent && !NotificationPreferences.validEmail(address)) {
      setState(() => error = 'Introduza um endereço de email válido.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
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
      final client = EmailNotificationsClient();
      String status;
      try {
        status = await client.configure(ref.read(storeProvider), value);
      } finally {
        client.close();
      }
      await ref
          .read(storeProvider)
          .setSetting(notificationSettingsKey, jsonEncode(value.toJson()));
      if (!value.android) await AndroidNotifications.cancelAll();
      if (!mounted) return;
      setState(() {
        preferences = value;
        emailStatus = status;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'pending'
                ? 'Pedido registado. Receberá um email para confirmar o endereço.'
                : status == 'active'
                ? 'Preferências guardadas. Avisos por email ativos.'
                : 'Preferências guardadas. Avisos por email desativados.',
          ),
        ),
      );
      await synchronizeEmailWallet(ref.read(storeProvider));
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível guardar as preferências.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refreshEmail() async {
    setState(() {
      busy = true;
      error = null;
    });
    final client = EmailNotificationsClient();
    try {
      final status = await client.refresh(ref.read(storeProvider));
      await synchronizeEmailWallet(ref.read(storeProvider));
      final problem = await ref
          .read(storeProvider)
          .setting('notifications.email.lastSyncError');
      if (mounted) {
        setState(() {
          emailStatus = status;
          error = problem == null || problem.isEmpty ? null : problem;
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Não foi possível consultar a subscrição de email.',
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
        child: const Text('Guardar preferências'),
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
              const Text(
                'Escolha como pretende receber avisos. Pode desativá-los a qualquer momento.',
              ),
              SwitchListTile(
                title: const Text('Notificações no Android'),
                subtitle: const Text(
                  'Pedir autorização para apresentar avisos no dispositivo.',
                ),
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
                  'Autorizo o envio dos avisos selecionados. Para avisos de prémios, '
                  'autorizo a sincronização das chaves, concursos e recebimentos com o servidor. '
                  'As fotografias não são enviadas.',
                ),
                value: emailConsent,
                onChanged: busy
                    ? null
                    : (v) => setState(() => emailConsent = v),
              ),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Endereço de email',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  emailStatus == 'active'
                      ? 'Email confirmado. Os avisos são enviados pelo servidor, mesmo com a app fechada.'
                      : emailStatus == 'pending'
                      ? 'Aguarda confirmação. Abra a ligação recebida por email e depois toque em Verificar confirmação.'
                      : 'Avisos por email desativados. Pode cancelar também pela ligação incluída em cada mensagem.',
                ),
              ),
              if (emailConsent)
                OutlinedButton(
                  onPressed: busy ? null : refreshEmail,
                  child: const Text('Verificar confirmação e sincronizar'),
                ),
              const Divider(),
              SwitchListTile(
                title: const Text('Resultados disponíveis'),
                value: results,
                onChanged: busy ? null : (v) => setState(() => results = v),
              ),
              SwitchListTile(
                title: const Text('Lembretes de prémios por levantar'),
                value: prizes,
                onChanged: busy ? null : (v) => setState(() => prizes = v),
              ),
              SwitchListTile(
                title: const Text('Prémios próximos do prazo de levantamento'),
                subtitle: const Text(
                  'Enviados por email apenas quando existir uma data-limite validada para o concurso.',
                ),
                value: expiry,
                onChanged: busy ? null : (v) => setState(() => expiry = v),
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
                  onChanged: busy ? null : (v) => setState(() => leadDays = v!),
                ),
              const SizedBox(height: 16),
              const Text(
                'Os avisos Android são verificados quando a app sincroniza. '
                'Os emails são processados pelo servidor. Mantenha os recebimentos '
                'atualizados na app para evitar lembretes de prémios já levantados.',
              ),
              if (error != null) Text(error!),
            ],
          ),
  );
}

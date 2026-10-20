import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/notification_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await NotificationPreferences.load(ref.read(storeProvider));
      final allowed = value.android && await AndroidNotifications.enabled();
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
      await ref
          .read(storeProvider)
          .setSetting(notificationSettingsKey, jsonEncode(value.toJson()));
      if (!value.android) await AndroidNotifications.cancelAll();
      if (!mounted) return;
      setState(() => preferences = value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preferências guardadas. O envio por email ainda não está ativo.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível guardar as preferências.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
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
                  'Autorizo o envio dos avisos selecionados para o meu email.',
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Email pendente de ativação: o endereço e a autorização ficam guardados apenas neste dispositivo. Ainda não são enviados emails.',
                ),
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
                  'Pendente: exige uma data-limite validada para cada prémio.',
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
                'Nesta versão, os avisos Android são verificados quando a app sincroniza. A verificação automática com a app fechada ainda não está ativa.',
              ),
              if (error != null) Text(error!),
            ],
          ),
  );
}

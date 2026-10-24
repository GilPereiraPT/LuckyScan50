import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'main.dart' show appServicesProvider, brandedPageTitle;

class AppPrivacyPage extends ConsumerStatefulWidget {
  const AppPrivacyPage({super.key});
  @override
  ConsumerState<AppPrivacyPage> createState() => _AppPrivacyPageState();
}

class _AppPrivacyPageState extends ConsumerState<AppPrivacyPage> {
  bool saving = false;
  @override
  Widget build(BuildContext context) {
    final service = ref.watch(appServicesProvider);
    return Scaffold(
      appBar: AppBar(title: brandedPageTitle('Privacidade')),
      body: FutureBuilder<void>(
        future: service.ready,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Estatísticas de utilização',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pode ajudar a melhorar o LuckyScan50 partilhando contagens de utilização. Esta opção está desligada por defeito.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Partilhar estatísticas técnicas'),
              value: service.consent,
              onChanged:
                  saving || snapshot.connectionState != ConnectionState.done
                  ? null
                  : (value) async {
                      setState(() => saving = true);
                      try {
                        await service.setConsent(value);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Não foi possível guardar a preferência. Tente novamente.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => saving = false);
                      }
                    },
            ),
            const Text(
              'Dados enviados: abertura da app (no máximo uma vez a cada 30 minutos), leituras pela câmara/importação, falhas de leitura e recibos guardados, versão da app e plataforma. Cada instalação tem um identificador aleatório, separado da ativação de proprietário.',
            ),
            const SizedBox(height: 12),
            const Text(
              'As fotografias, apostas, prémios, códigos M1lhão e endereços de email não fazem parte destas estatísticas. Os eventos são guardados por um máximo de 90 dias. As estatísticas representam apenas instalações com partilha ativada.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Ao desligar a partilha, a app deixa de enviar eventos e pede a eliminação dos dados desta instalação. Se não houver ligação, repete o pedido na próxima abertura. Os bilhetes continuam disponíveis no dispositivo.',
            ),
            if (service.deletionPending) ...[
              const SizedBox(height: 12),
              const Text(
                'Eliminação das estatísticas pendente de ligação à API.',
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          await service.setConsent(false);
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                child: const Text('Repetir eliminação'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Serviço: LuckyScan50 · Gil Pereira. A ligação HTTPS transmite o endereço IP ao servidor dos resultados e dos serviços facultativos. A API utiliza uma derivação diária do IP para limitar abusos, sem o guardar nos eventos de estatísticas. A identificação do alojamento e o tratamento dos registos técnicos constam da política de privacidade pública.',
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerActivationPage extends ConsumerStatefulWidget {
  const OwnerActivationPage({super.key});
  @override
  ConsumerState<OwnerActivationPage> createState() =>
      _OwnerActivationPageState();
}

class _OwnerActivationPageState extends ConsumerState<OwnerActivationPage> {
  final keyInput = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    keyInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(appServicesProvider);
    return Scaffold(
      appBar: AppBar(title: brandedPageTitle('Proprietário')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            service.premium
                ? 'Proprietário ativo · sem publicidade'
                : 'Ativar esta instalação',
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(height: 16),
          if (!service.premium) ...[
            TextField(
              controller: keyInput,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Chave de ativação'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final key = keyInput.text;
                      keyInput.clear();
                      try {
                        await service.activateOwner(key);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Modo proprietário ativado.'),
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Não foi possível ativar. Confirme a chave e a ligação à API.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('Ativar'),
            ),
          ] else
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await service.deactivateOwner();
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('Desativar neste dispositivo'),
            ),
        ],
      ),
    );
  }
}

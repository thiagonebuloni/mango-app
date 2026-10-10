import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/app_strings.dart';
import '../models/models.dart';

/// Hora local em que os lembretes de cartão chegam (9h: cedo o bastante para
/// agir na fatura, tarde o bastante para não ser notificação de madrugada).
const int horaLembreteCartao = 9;

/// Próxima ocorrência de [dia] (1..31; mês curto usa o último dia) às [hora]
/// que ainda está **depois** de [agora].
///
/// Ex.: `proximoLembrete(31, DateTime(2026, 1, 31, 10))` — o dia 31 às 9h já
/// passou, então cai em 28/02/2026 (fevereiro sem dia 31).
DateTime proximoLembrete(
  int dia,
  DateTime agora, {
  int hora = horaLembreteCartao,
}) {
  final alvo = dia.clamp(1, 31);
  var ano = agora.year;
  var mes = agora.month;
  // 14 meses cobrem jan→mar/abr com clamp (31 em fevereiro) + folga.
  for (var i = 0; i < 14; i++) {
    final ultimoDiaDoMes = DateTime(ano, mes + 1, 0).day;
    final d = alvo > ultimoDiaDoMes ? ultimoDiaDoMes : alvo;
    final quando = DateTime(ano, mes, d, hora);
    if (quando.isAfter(agora)) return quando;
    mes += 1;
    if (mes > 12) {
      mes = 1;
      ano += 1;
    }
  }
  throw StateError('nenhuma ocorrência futura para o dia $dia');
}

/// Destino de deep-link vindo do toque numa notificação.
///
/// Hoje só há lembretes de cartão (fechamento/pagamento da fatura), então o
/// destino é sempre o detalhe de um cartão. O formato permite estender no
/// futuro sem quebrar payloads já agendados: `cartao:<id>`.
class DestinoNotificacao {
  const DestinoNotificacao.cartao(this.cartaoId);

  /// Id do cartão cujo detalhe deve abrir.
  final int cartaoId;

  /// Texto gravado no `payload` da notificação agendada.
  String get payload => 'cartao:$cartaoId';

  /// Lê um payload gravado por [payload]. Devolve `null` para texto ausente,
  /// vazio ou em formato desconhecido — nesses casos o toque abre o app sem
  /// navegar para lugar nenhum.
  static DestinoNotificacao? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final partes = raw.split(':');
    if (partes.length != 2 || partes[0] != 'cartao') return null;
    final id = int.tryParse(partes[1]);
    if (id == null || id <= 0) return null;
    return DestinoNotificacao.cartao(id);
  }
}

/// Lembretes locais (nada de servidor — o app é offline) das datas de
/// **fechamento** e **pagamento** da fatura de cada cartão.
///
/// Toda chamada é blindada por `try/catch`: em plataforma sem suporte (web,
/// Windows) ou sem permissão, o lembrete simplesmente não é agendado — a tela
/// nunca quebra por causa de notificação.
///
/// O toque na notificação aparece em [toquePendente]: cada lembrete leva
/// no `payload` o id do cartão (`cartao:<id>`, ver [DestinoNotificacao]), e
/// a interface usa isso para abrir o detalhe do cartão certo. Payload
/// ausente ou inválido não publica nada — aí o app só abre, sem navegar.
class NotificacoesService {
  NotificacoesService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Idioma usado nos textos das notificações (não há `BuildContext` aqui).
  Locale _locale = const Locale('pt', 'BR');

  bool _inicializado = false;
  bool _fusoCarregado = false;

  static const String canalCartoes = 'cartoes';

  /// Último destino tocado e ainda não consumido pela interface.
  ///
  /// Vira um [ValueNotifier] (e não um callback direto) por dois motivos:
  /// o toque pode chegar com o app fechado — antes de existir `Navigator` —
  /// e pode chegar com o PIN trancando a tela — aí navegar na hora furaria
  /// o bloqueio. A interface observa, espera estar destravada e só então
  /// consome com [consumirToque].
  final ValueNotifier<DestinoNotificacao?> toquePendente =
      ValueNotifier<DestinoNotificacao?>(null);

  /// Marca um toque como consumido (chamado pela interface após navegar).
  void consumirToque(DestinoNotificacao destino) {
    if (toquePendente.value == destino) toquePendente.value = null;
  }

  AppStrings get _s => AppStrings.of(_locale);

  /// Id fixo por cartão e evento: reagendar substitui o alarme anterior em
  /// vez de acumular lembretes duplicados.
  static int _idFechamento(int cartaoId) => 1000000 + cartaoId * 10 + 1;

  static int _idPagamento(int cartaoId) => 1000000 + cartaoId * 10 + 2;

  /// Prepara o plugin e o fuso horário. [locale] define o idioma dos avisos.
  ///
  /// Registra o toque ([onDidReceiveNotificationResponse]) publicando o
  /// destino em [toquePendente], e lê o toque que abriu o app fechado
  /// ([getNotificationAppLaunchDetails]) para o mesmo lugar — a interface
  /// consome quando já dá para navegar.
  Future<void> inicializar(Locale locale) async {
    _locale = locale;
    if (kIsWeb) return;
    try {
      await _carregarFuso();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
        ),
        onDidReceiveNotificationResponse: (resposta) {
          final destino = DestinoNotificacao.parse(resposta.payload);
          if (destino != null) toquePendente.value = destino;
        },
      );
      final lancamento = await _plugin.getNotificationAppLaunchDetails();
      final destino = DestinoNotificacao.parse(
        lancamento?.notificationResponse?.payload,
      );
      if (destino != null) toquePendente.value = destino;
      _inicializado = true;
    } catch (e) {
      debugPrint('notificações indisponíveis: $e');
      _inicializado = false;
    }
  }

  /// Carrega a base do timezone e aponta `tz.local` para o fuso do aparelho —
  /// sem isso os alarmes sairiam em UTC e chegariam horas fora.
  Future<void> _carregarFuso() async {
    if (_fusoCarregado) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Sem nome de fuso (ou plugin indisponível) mantém o UTC; o `catch`
      // garante que a inicialização não aborte por causa disso.
      debugPrint('fuso horário não resolvido: $e');
    }
    _fusoCarregado = true;
  }

  NotificationDetails get _detalhes => const NotificationDetails(
    android: AndroidNotificationDetails(
      canalCartoes,
      'Cartões de crédito',
      channelDescription:
          'Lembretes de fechamento e pagamento da fatura de cartão',
      importance: Importance.high,
      priority: Priority.high,
      // Barra de status: silhueta branca da manga (`res/drawable`
      // `ic_notificacao.xml`) — o Android tinge o small icon de
      // monocromático, então o launcher colorido viraria ilegível.
      // Corpo expandido: arte do app em 192dp (`ic_notificacao_grande.png`,
      // gerado de `assets/icon/app_icon_master.png` via
      // `flutter test tool/gerar_icone_notificacao.dart`).
      icon: 'ic_notificacao',
      largeIcon: DrawableResourceAndroidBitmap('ic_notificacao_grande'),
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// Pede a permissão de notificação (Android 13+, iOS). Ocorre no momento do
  /// cadastro do cartão, quando o motivo está claro na tela.
  Future<void> solicitarPermissao() async {
    if (!_inicializado) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('permissão de notificação não concedida: $e');
    }
  }

  /// Agenda (ou reagenda) os lembretes de fechamento e pagamento de [cartao]
  /// para a próxima ocorrência de cada data.
  ///
  /// O `payload` leva o id do cartão: o toque abre o detalhe dele.
  Future<void> agendarLembretes(CartaoCredito cartao) async {
    final id = cartao.id;
    if (!_inicializado || id == null) return;
    final agora = DateTime.now();
    try {
      await _cancelarIds(id);
      final s = _s;
      final payload = DestinoNotificacao.cartao(id).payload;
      await _plugin.zonedSchedule(
        _idFechamento(id),
        s.fechamentoFatura,
        s.lembreteFechamento(cartao.nome),
        _tz(proximoLembrete(cartao.diaFechamento, agora)),
        _detalhes,
        androidScheduleMode: AndroidScheduleMode.inexact,
        payload: payload,
      );
      await _plugin.zonedSchedule(
        _idPagamento(id),
        s.pagamentoFatura,
        s.lembretePagamento(cartao.nome),
        _tz(proximoLembrete(cartao.diaPagamento, agora)),
        _detalhes,
        androidScheduleMode: AndroidScheduleMode.inexact,
        payload: payload,
      );
    } catch (e) {
      debugPrint('lembretes do cartão não agendados: $e');
    }
  }

  /// Reagenda os lembretes de todos os cartões (abertura do app). Não pede
  /// permissão: isso só acontece quando o usuário cadastra um cartão.
  Future<void> agendarTodos(List<CartaoCredito> cartoes) async {
    for (final c in cartoes) {
      await agendarLembretes(c);
    }
  }

  /// Cancela os dois lembretes de um cartão (exclusão).
  Future<void> cancelarLembretes(int cartaoId) async {
    if (!_inicializado) return;
    try {
      await _cancelarIds(cartaoId);
    } catch (e) {
      debugPrint('lembretes não cancelados: $e');
    }
  }

  Future<void> _cancelarIds(int cartaoId) async {
    await _plugin.cancel(_idFechamento(cartaoId));
    await _plugin.cancel(_idPagamento(cartaoId));
  }

  /// Simula o toque numa notificação com [payload] (só para teste).
  ///
  /// Replica o que o `onDidReceiveNotificationResponse` do [inicializar] faz
  /// com um toque real: publica o destino em [toquePendente], ou ignora
  /// quando o payload é inválido.
  @visibleForTesting
  void simularToque(String? payload) {
    final destino = DestinoNotificacao.parse(payload);
    if (destino != null) toquePendente.value = destino;
  }

  /// Libera o [toquePendente] (só para teste).
  void dispose() => toquePendente.dispose();

  tz.TZDateTime _tz(DateTime d) =>
      tz.TZDateTime(tz.local, d.year, d.month, d.day, d.hour, d.minute);
}

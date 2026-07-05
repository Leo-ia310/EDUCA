import 'package:uuid/uuid.dart';

import '../domain/entities.dart';

const _uuid = Uuid();

DateTime _minsAgo(int m) => DateTime.now().subtract(Duration(minutes: m));
DateTime _hoursAgo(int h) => DateTime.now().subtract(Duration(hours: h));

/// Seed inicial. Se personaliza al arrancar según el rol del usuario actual
/// para que las conversaciones tengan sentido:
///
/// - Padre: chats con maestros del hijo + coordinación.
/// - Estudiante: chats con maestros.
/// - Maestro: chats con padres + admin.
/// - Admin/Coordinador: chats con maestros + comunicados.
class ChatMockSeed {
  ChatMockSeed._();

  /// Devuelve las conversaciones iniciales relativas a `meId` (el usuario
  /// autenticado). Los otros participantes son personajes fijos.
  static List<Conversation> initialConversations({
    required String meId,
    required String myName,
    required String myRoleCode,
  }) {
    switch (myRoleCode) {
      case 'teacher':
        return _teacherSeed(meId, myName);
      case 'parent':
        return _parentSeed(meId, myName);
      case 'admin':
      case 'coordinator':
      case 'director':
        return _adminSeed(meId, myName);
      case 'student':
      default:
        return _studentSeed(meId, myName);
    }
  }

  // ---------- Estudiante ----------
  static List<Conversation> _studentSeed(String meId, String myName) {
    final me = ChatParticipant(
      userId: meId,
      name: myName,
      role: 'student',
      isMe: true,
    );
    final elena = _p('u-elena', 'Prof. Elena Ramírez', 'teacher', online: true);
    final carlos = _p('u-carlos', 'Prof. Carlos Mendoza', 'teacher');
    final sara = _p('u-sara', 'Prof. Sara Núñez', 'teacher');
    return [
      _mkConv(
        id: 'c-elena',
        kind: ConversationKind.individual,
        title: elena.name,
        participants: [me, elena],
        lastText: 'Recuerda subir la práctica antes del viernes.',
        lastFromId: elena.userId,
        lastFromName: elena.name,
        ago: _minsAgo(9),
        unread: 2,
      ),
      _mkConv(
        id: 'c-carlos',
        kind: ConversationKind.individual,
        title: carlos.name,
        participants: [me, carlos],
        lastText: 'Nota de tu proyecto: 8.5. ¡Excelente!',
        lastFromId: carlos.userId,
        lastFromName: carlos.name,
        ago: _hoursAgo(3),
      ),
      _mkConv(
        id: 'c-sara',
        kind: ConversationKind.individual,
        title: sara.name,
        participants: [me, sara],
        lastText: 'Gracias por el ensayo.',
        lastFromId: meId,
        lastFromName: myName,
        ago: _hoursAgo(26),
      ),
    ];
  }

  // ---------- Padre ----------
  static List<Conversation> _parentSeed(String meId, String myName) {
    final me = ChatParticipant(
      userId: meId,
      name: myName,
      role: 'parent',
      isMe: true,
    );
    final elena = _p('u-elena', 'Prof. Elena Ramírez', 'teacher', online: true);
    final sara = _p('u-sara', 'Prof. Sara Núñez', 'teacher');
    final coord = _p('u-coord', 'Coordinación Académica', 'coordinator');
    return [
      _mkConv(
        id: 'c-elena',
        kind: ConversationKind.individual,
        title: elena.name,
        participants: [me, elena],
        lastText: 'Buenas tardes, Mateo tuvo excelente participación hoy.',
        lastFromId: elena.userId,
        lastFromName: elena.name,
        ago: _minsAgo(14),
        unread: 1,
      ),
      _mkConv(
        id: 'c-sara',
        kind: ConversationKind.individual,
        title: sara.name,
        participants: [me, sara],
        lastText: '¿Podrían agendar una tutoría para Mateo?',
        lastFromId: meId,
        lastFromName: myName,
        ago: _hoursAgo(2),
      ),
      _mkConv(
        id: 'c-coord',
        kind: ConversationKind.individual,
        title: coord.name,
        participants: [me, coord],
        lastText: 'Le confirmamos la reunión para el viernes.',
        lastFromId: coord.userId,
        lastFromName: coord.name,
        ago: _hoursAgo(18),
      ),
    ];
  }

  // ---------- Maestro ----------
  static List<Conversation> _teacherSeed(String meId, String myName) {
    final me = ChatParticipant(
      userId: meId,
      name: myName,
      role: 'teacher',
      isMe: true,
    );
    final marta = _p('u-marta', 'Marta Hernández (madre)', 'parent', online: true);
    final javier =
        _p('u-javier', 'Javier Rojas (padre)', 'parent', online: false);
    final director = _p('u-director', 'Dir. Roberto Castillo', 'director');
    final grupo = ChatParticipant(
      userId: 'u-group-4a',
      name: 'Padres 4°A',
      role: 'group',
    );

    return [
      _mkConv(
        id: 'c-marta',
        kind: ConversationKind.individual,
        title: marta.name,
        participants: [me, marta],
        lastText: 'Gracias profe, lo revisaremos con Mateo.',
        lastFromId: marta.userId,
        lastFromName: marta.name,
        ago: _minsAgo(8),
        unread: 3,
      ),
      _mkConv(
        id: 'c-group',
        kind: ConversationKind.group,
        title: 'Padres 4°A',
        participants: [me, marta, javier, grupo],
        lastText: 'Recordatorio: reunión el jueves 6pm.',
        lastFromId: meId,
        lastFromName: myName,
        ago: _hoursAgo(1),
      ),
      _mkConv(
        id: 'c-director',
        kind: ConversationKind.individual,
        title: director.name,
        participants: [me, director],
        lastText: 'Perfecto, gracias por la coordinación.',
        lastFromId: director.userId,
        lastFromName: director.name,
        ago: _hoursAgo(20),
      ),
      _mkConv(
        id: 'c-javier',
        kind: ConversationKind.individual,
        title: javier.name,
        participants: [me, javier],
        lastText: '¿Cuál fue la nota final del bimestre?',
        lastFromId: javier.userId,
        lastFromName: javier.name,
        ago: _hoursAgo(28),
        unread: 1,
      ),
    ];
  }

  // ---------- Admin ----------
  static List<Conversation> _adminSeed(String meId, String myName) {
    final me = ChatParticipant(
      userId: meId,
      name: myName,
      role: 'admin',
      isMe: true,
    );
    final claustro = ChatParticipant(
      userId: 'u-group-claustro',
      name: 'Claustro docente',
      role: 'group',
    );
    final elena = _p('u-elena', 'Prof. Elena Ramírez', 'teacher', online: true);
    final carlos = _p('u-carlos', 'Prof. Carlos Mendoza', 'teacher');
    return [
      _mkConv(
        id: 'c-claustro',
        kind: ConversationKind.group,
        title: 'Claustro docente',
        participants: [me, elena, carlos, claustro],
        lastText: 'Reunión trimestral programada para el jueves.',
        lastFromId: meId,
        lastFromName: myName,
        ago: _minsAgo(24),
      ),
      _mkConv(
        id: 'c-elena',
        kind: ConversationKind.individual,
        title: elena.name,
        participants: [me, elena],
        lastText: 'Reporte del bimestre está listo.',
        lastFromId: elena.userId,
        lastFromName: elena.name,
        ago: _hoursAgo(2),
        unread: 1,
      ),
      _mkConv(
        id: 'c-carlos',
        kind: ConversationKind.individual,
        title: carlos.name,
        participants: [me, carlos],
        lastText: 'Confirmado, enviaré los datos.',
        lastFromId: carlos.userId,
        lastFromName: carlos.name,
        ago: _hoursAgo(14),
      ),
    ];
  }

  // ---------- Historial de mensajes por conversación ----------
  static List<Message> initialMessages({
    required String conversationId,
    required String meId,
    required String myName,
    required List<ChatParticipant> participants,
    required Message? lastMessage,
  }) {
    final other =
        participants.where((p) => !p.isMe).cast<ChatParticipant?>().firstOrNull;
    final result = <Message>[];
    if (other == null) return [if (lastMessage != null) lastMessage];

    // Historial simple: alternamos 6 mensajes hacia atrás desde el último.
    final base = lastMessage?.sentAt ?? _minsAgo(30);
    final samplePairs = <List<String>>[
      ['Buenas tardes profe, ¿podría explicarme la actividad?', 'Claro, con gusto. ¿Cuál parte no quedó clara?'],
      ['La parte 3 sobre derivadas.', 'Perfecto, te mando un ejemplo resuelto.'],
      ['Gracias profe.', 'A la orden.'],
    ];
    for (var i = 0; i < samplePairs.length; i++) {
      final pair = samplePairs[i];
      result.add(Message(
        id: 'm-${conversationId}-${i}a',
        uuid: _uuid.v4(),
        conversationId: conversationId,
        senderId: meId,
        senderName: myName,
        sentAt: base.subtract(Duration(minutes: (samplePairs.length - i) * 15 + 8)),
        content: pair[0],
        status: MessageDeliveryStatus.read,
      ));
      result.add(Message(
        id: 'm-${conversationId}-${i}b',
        uuid: _uuid.v4(),
        conversationId: conversationId,
        senderId: other.userId,
        senderName: other.name,
        senderAvatarUrl: other.avatarUrl,
        sentAt: base.subtract(Duration(minutes: (samplePairs.length - i) * 15 + 2)),
        content: pair[1],
        status: MessageDeliveryStatus.read,
      ));
    }
    if (lastMessage != null) result.add(lastMessage);
    return result;
  }

  // ---------- Helpers ----------
  static ChatParticipant _p(
    String id,
    String name,
    String role, {
    bool online = false,
  }) {
    return ChatParticipant(
      userId: id,
      name: name,
      role: role,
      isOnline: online,
      lastSeen: online ? null : _hoursAgo(2),
    );
  }

  static Conversation _mkConv({
    required String id,
    required ConversationKind kind,
    required String title,
    required List<ChatParticipant> participants,
    required String lastText,
    required String lastFromId,
    required String lastFromName,
    required DateTime ago,
    int unread = 0,
  }) {
    final last = Message(
      id: 'm-$id-last',
      uuid: _uuid.v4(),
      conversationId: id,
      senderId: lastFromId,
      senderName: lastFromName,
      sentAt: ago,
      content: lastText,
      status: unread > 0
          ? MessageDeliveryStatus.delivered
          : MessageDeliveryStatus.read,
    );
    return Conversation(
      id: id,
      kind: kind,
      title: title,
      participants: participants,
      updatedAt: ago,
      lastMessage: last,
      unreadCount: unread,
    );
  }
}

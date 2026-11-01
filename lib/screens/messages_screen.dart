// FILE: screens/messages_screen.dart
// SCREEN: Messages — only the customers who have actually sent a message.
// Tap a customer to open the chat of the booking that has the messages.
//
// APIs used:
//   GET /artists/bookings/get_all/     (bookings → customers)
//   GET /chat/messages/get_all/        (per booking: does the customer have messages?)
//   GET user profile                   (customer name)

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import '../models/booking/booking.dart';
import '../models/chat/chat_message.dart';
import '../theme/tokens.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

class _Thread {
  final int customerId;
  final int bookingId; // the booking whose chat holds the newest customer message
  final String bookingDate;
  final String lastText;
  final String lastAt;
  final bool lastFromCustomer;
  String name;
  _Thread({
    required this.customerId,
    required this.bookingId,
    required this.bookingDate,
    required this.lastText,
    required this.lastAt,
    required this.lastFromCustomer,
    this.name = 'Customer',
  });
}

/// Result of checking one booking's chat.
class _CheckResult {
  final _Thread? thread;
  final bool failed; // the chat could not be checked (network / server problem)
  const _CheckResult({this.thread, this.failed = false});
}

/// SCREEN: Messages list (one row per customer who has messaged).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  bool _loading = true;
  String? _error;
  List<_Thread> _threads = [];
  int _failed = 0; // chats that could not be checked on the last load

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// For every booking, checks its chat. A customer is listed only if they sent at least one message.
  /// API: bookingService.getAllBookings, chatService.getMessages, userService.getProfile
  ///
  /// Scope (no time limit — only these size limits): the artist's newest 200 paid bookings are read, the newest 60
  /// of them with a customer are checked (8 at a time so a slow server does not time everything out), and the
  /// last 20 messages of each chat are looked at. Unpaid bookings are hidden by the server, so their chats are not here.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _failed = 0;
    });
    try {
      final bookings = await ServiceLocator.bookingService.getAllBookings(limit: 200);
      // Newest bookings first.
      final sorted = [...bookings]..sort((a, b) => '${b.bookingDate} ${b.startTime}'.compareTo('${a.bookingDate} ${a.startTime}'));
      final toCheck = sorted.where((b) => b.customerId != 0).take(60).toList();

      final results = <_CheckResult>[];
      for (var i = 0; i < toCheck.length; i += 8) {
        results.addAll(await Future.wait(toCheck.skip(i).take(8).map(_check)));
      }
      final failed = results.where((r) => r.failed).length;

      // Keep the booking with the newest customer message per customer.
      final best = <int, _Thread>{};
      for (final t in results.map((r) => r.thread).whereType<_Thread>()) {
        final cur = best[t.customerId];
        if (cur == null || t.lastAt.compareTo(cur.lastAt) > 0) best[t.customerId] = t;
      }

      await Future.wait(best.values.map((t) async {
        try {
          final p = await ServiceLocator.userService.getProfile(t.customerId);
          if (p.name.trim().isNotEmpty) t.name = p.name.trim();
        } catch (_) {}
      }));

      final list = best.values.toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));
      if (kDebugMode) {
        debugPrint('[Messages] paid bookings=${bookings.length}, chats checked=${toCheck.length}, '
            'customers with messages=${list.length}, chats that could not be checked=$failed');
      }
      if (!mounted) return;
      setState(() {
        _threads = list;
        _failed = failed;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could Not Load Messages. Please Try Again.';
          _loading = false;
        });
      }
    }
  }

  /// Checks one booking's chat. "Conversation not found" just means this booking has no chat (normal);
  /// any other problem (network, server) is reported as [failed] instead of silently looking like "no messages".
  Future<_CheckResult> _check(Booking b) async {
    try {
      final res = await ServiceLocator.chatService.getMessages(b.bookingId, limit: 20, sortOrder: 'desc');
      final msgs = res.data;
      if (msgs.isEmpty) return const _CheckResult();
      final fromCustomer = msgs.where((m) => m.senderId == b.customerId).toList();
      if (fromCustomer.isEmpty) return const _CheckResult(); // artist wrote, customer never replied
      final ChatMessage last = msgs.first; // sort_order desc → newest first
      return _CheckResult(
        thread: _Thread(
          customerId: b.customerId,
          bookingId: b.bookingId,
          bookingDate: b.bookingDate,
          lastText: last.content,
          lastAt: last.createdAt,
          lastFromCustomer: last.senderId == b.customerId,
        ),
      );
    } catch (e) {
      final m = e.toString().toLowerCase();
      if (m.contains('conversation not found') || m.contains('not found')) return const _CheckResult();
      return const _CheckResult(failed: true);
    }
  }

  Widget _empty(String msg, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.chat_bubble_outline_rounded, size: 44, color: AiraColors.rose),
        const SizedBox(height: 12),
        Text(msg,
            textAlign: TextAlign.center,
            style: AiraText.sans(fontSize: 15, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
        if (retry) TextButton(onPressed: _load, child: const Text('Retry')),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(children: [
                  SunndariAppBar(onBack: () => Navigator.of(context).pop()),
                  const SunndariPageHeading(title: 'Messages', subtitle: 'Chat With Your Customers.'),
                  const SizedBox(height: 10),
                ]),
              ),
              if (!_loading && _error == null && _failed > 0 && _threads.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Some chats could not be loaded. Pull down to refresh.',
                      style: AiraText.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AiraColors.charcoalSoft)),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                    : _error != null
                    ? _empty(_error!, retry: true)
                    : _threads.isEmpty
                    ? (_failed > 0
                        ? _empty('Could Not Load Some Chats. Please Check Your Internet And Retry.', retry: true)
                        : _empty('No Messages Yet. Customers Who Message You Will Appear Here.'))
                    : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: _threads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final t = _threads[i];
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ChatScreen(bookingId: t.bookingId, title: t.name))),
                        child: AiraCard(
                          child: Row(children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AiraColors.pinkFill,
                              child: Text(t.name.isEmpty ? '?' : t.name[0].toUpperCase(),
                                  style: AiraText.sans(
                                      fontSize: 18, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AiraText.sans(
                                          fontSize: 16, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                                  const SizedBox(height: 3),
                                  Text(t.lastFromCustomer ? t.lastText : 'You: ${t.lastText}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AiraText.sans(fontSize: 13.5, color: AiraColors.charcoalSoft)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AiraColors.rose),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
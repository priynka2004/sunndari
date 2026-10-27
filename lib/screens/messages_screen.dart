// FILE: screens/messages_screen.dart
// SCREEN: Messages — only the customers who have actually sent a message.
// Tap a customer to open the chat of the booking that has the messages.
//
// APIs used:
//   GET /artists/bookings/get_all/     (bookings → customers)
//   GET /chat/messages/get_all/        (per booking: does the customer have messages?)
//   GET user profile                   (customer name)

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// For every booking, checks its chat. A customer is listed only if they sent at least one message.
  /// API: bookingService.getAllBookings, chatService.getMessages, userService.getProfile
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await ServiceLocator.bookingService.getAllBookings(limit: 100);
      // Newest bookings first; cap the number of chats we check.
      final sorted = [...bookings]..sort((a, b) => '${b.bookingDate} ${b.startTime}'.compareTo('${a.bookingDate} ${a.startTime}'));
      final toCheck = sorted.where((b) => b.customerId != 0).take(40).toList();

      final found = await Future.wait(toCheck.map(_check));
      // Keep the booking with the newest customer message per customer.
      final best = <int, _Thread>{};
      for (final t in found.whereType<_Thread>()) {
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
      if (!mounted) return;
      setState(() {
        _threads = list;
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

  /// Returns a thread if this booking's chat has a message sent by the customer, else null.
  Future<_Thread?> _check(Booking b) async {
    try {
      final res = await ServiceLocator.chatService.getMessages(b.bookingId, limit: 20, sortOrder: 'desc');
      final msgs = res.data;
      if (msgs.isEmpty) return null;
      final fromCustomer = msgs.where((m) => m.senderId == b.customerId).toList();
      if (fromCustomer.isEmpty) return null; // artist wrote, customer never replied
      final ChatMessage last = msgs.first; // sort_order desc → newest first
      return _Thread(
        customerId: b.customerId,
        bookingId: b.bookingId,
        bookingDate: b.bookingDate,
        lastText: last.content,
        lastAt: last.createdAt,
        lastFromCustomer: last.senderId == b.customerId,
      );
    } catch (_) {
      return null; // "Conversation not found" → no chat on this booking
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
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                    : _error != null
                    ? _empty(_error!, retry: true)
                    : _threads.isEmpty
                    ? _empty('No Messages Yet. Customers Who Message You Will Appear Here.')
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
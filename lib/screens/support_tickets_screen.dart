// FILE: screens/support_tickets_screen.dart
// SCREEN: Support tickets — raise an issue (with optional booking + attachments), see status, close it.
//
// APIs used:
//   GET  /help_center/tickets/get_all/
//   POST /help_center/tickets/create/        (multipart, up to 5 attachments, max 10 open tickets)
//   GET  /help_center/tickets/get/
//   PUT  /help_center/tickets/close/
//   GET  /help_center/tickets/attachment/    (private bytes — Bearer header)

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/artist/artist_extras.dart';
import '../theme/tokens.dart';
import '../utils/app_feedback.dart';
import '../utils/service_locator.dart';
import '../widgets/common.dart';

const _issueTypes = {
  'booking': 'Booking',
  'payment': 'Payment',
  'service_quality': 'Service Quality',
  'account': 'Account',
  'technical': 'Technical',
  'other': 'Other',
};

/// SCREEN: Support tickets list.
class SupportTicketsScreen extends StatefulWidget {
  final int? bookingId;
  const SupportTicketsScreen({super.key, this.bookingId});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  bool _loading = true;
  String? _error;
  List<SupportTicket> _tickets = [];
  String _sort = 'newest'; // newest | oldest | open

  DateTime? _when(SupportTicket t) => t.createdAt == null ? null : DateTime.tryParse(t.createdAt!);

  String _date(SupportTicket t) {
    final d = _when(t)?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  /// Tickets in the order chosen by the sort chips (newest first by default).
  List<SupportTicket> get _sorted {
    final list = [..._tickets];
    int byNew(SupportTicket a, SupportTicket b) {
      final x = _when(a), y = _when(b);
      if (x != null && y != null) {
        final c = y.compareTo(x);
        if (c != 0) return c;
      }
      return b.ticketId.compareTo(a.ticketId);
    }
    switch (_sort) {
      case 'oldest':
        list.sort((a, b) => byNew(b, a));
      case 'open':
        list.sort((a, b) {
          if (a.isClosed != b.isClosed) return a.isClosed ? 1 : -1;
          return byNew(a, b);
        });
      default:
        list.sort(byNew);
    }
    return list;
  }

  Widget _sortChips() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Wrap(spacing: 8, children: [
          for (final e in {'newest': 'Newest', 'oldest': 'Oldest', 'open': 'Open First'}.entries)
            ChoiceChip(
              label: Text(e.value,
                  style: AiraText.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _sort == e.key ? Colors.white : AiraColors.roseDeep)),
              selected: _sort == e.key,
              selectedColor: AiraColors.roseDeep,
              backgroundColor: AiraColors.pinkFill,
              showCheckmark: false,
              onSelected: (_) => setState(() => _sort = e.key),
            ),
        ]),
      );

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.bookingId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _create());
  }

  /// API: artistBusiness.getTickets → GET /help_center/tickets/get_all/
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await ServiceLocator.artistBusiness.getTickets(limit: 50);
      if (mounted) setState(() => _tickets = t);
    } catch (e) {
      if (mounted) setState(() => _error = AppFeedback.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _NewTicketScreen(bookingId: widget.bookingId)),
    );
    if (ok == true) _load();
  }

  Color _statusColor(String s) => switch (s) {
        'open' => const Color(0xFFB4780A),
        'in_progress' => const Color(0xFF2B6CB0),
        'resolved' => const Color(0xFF1F9254),
        _ => AiraColors.charcoalSoft,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AiraColors.rose,
        onPressed: _create,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('New Ticket', style: AiraText.sans(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SunndariBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SunndariAppBar(onBack: () => Navigator.of(context).pop()),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SunndariPageHeading(title: 'Support Tickets', subtitle: 'Track Your Requests To The Sunndari Team.'),
              ),
              if (!_loading && _error == null && _tickets.length > 1) _sortChips(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
                    : _error != null
                        ? Center(child: Text(_error!, style: AiraText.sans(color: AiraColors.errorText)))
                        : _tickets.isEmpty
                            ? Center(child: Text('No Tickets Yet.', style: AiraText.sans(color: AiraColors.charcoalSoft)))
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                                  itemCount: _sorted.length,
                                  itemBuilder: (_, i) {
                                    final t = _sorted[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () async {
                                          await Navigator.of(context).push(
                                              MaterialPageRoute(builder: (_) => _TicketDetailScreen(ticketId: t.ticketId)));
                                          _load();
                                        },
                                        child: AiraCard(
                                          padding: const EdgeInsets.all(14),
                                          child: Row(children: [
                                            Expanded(
                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Text('#${t.ticketId}${_date(t).isEmpty ? '' : '  •  ${_date(t)}'}',
                                                    style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AiraColors.rose)),
                                                const SizedBox(height: 3),
                                                Text(t.subject.trim().isEmpty ? '(No Subject)' : t.subject,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: AiraText.sans(fontSize: 15.5, fontWeight: FontWeight.w800, color: AiraColors.roseDeep)),
                                                const SizedBox(height: 3),
                                                Text(_issueTypes[t.issueType] ?? t.issueType,
                                                    style: AiraText.sans(fontSize: 12.5, color: AiraColors.charcoalSoft)),
                                              ]),
                                            ),
                                            Text(t.status.replaceAll('_', ' '),
                                                style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(t.status))),
                                          ]),
                                        ),
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

class _NewTicketScreen extends StatefulWidget {
  final int? bookingId;
  const _NewTicketScreen({this.bookingId});

  @override
  State<_NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<_NewTicketScreen> {
  String _type = 'other';
  final _subject = TextEditingController();
  final _desc = TextEditingController();
  final List<XFile> _files = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_files.length >= 5) {
      AppFeedback.showInfo(context, 'You Can Attach Up To 5 Files.');
      return;
    }
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) setState(() => _files.add(f));
  }

  /// API: artistBusiness.createTicket → POST /help_center/tickets/create/
  Future<void> _submit() async {
    if (_subject.text.trim().isEmpty || _desc.text.trim().isEmpty) {
      setState(() => _error = 'Please Add A Subject And Describe The Issue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ServiceLocator.artistBusiness.createTicket(
        issueType: _type,
        subject: _subject.text.trim(),
        description: _desc.text.trim(),
        bookingId: widget.bookingId,
        attachments: _files,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = AppFeedback.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Row(children: [
              SunndariBackChip(onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 12),
              Text('New Ticket', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _issueTypes.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _type == e.key,
                    onSelected: (_) => setState(() => _type = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(controller: _subject, maxLength: 150, decoration: const InputDecoration(labelText: 'Subject')),
            const SizedBox(height: 8),
            TextField(controller: _desc, maxLength: 2000, maxLines: 5, decoration: const InputDecoration(labelText: 'Describe The Issue')),
            if (widget.bookingId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Linked To Booking #${widget.bookingId}',
                    style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.attach_file_rounded),
              label: Text('Attach Image (${_files.length}/5)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AiraText.sans(fontSize: 12.5, color: AiraColors.errorText)),
            ],
            const SizedBox(height: 16),
            PrimaryButton(label: _busy ? 'Sending…' : 'Submit Ticket', expand: true, onTap: _busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class _TicketDetailScreen extends StatefulWidget {
  final int ticketId;
  const _TicketDetailScreen({required this.ticketId});

  @override
  State<_TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<_TicketDetailScreen> {
  SupportTicket? _t;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// API: artistBusiness.getTicket → GET /help_center/tickets/get/
  Future<void> _load() async {
    try {
      final t = await ServiceLocator.artistBusiness.getTicket(widget.ticketId);
      if (mounted) setState(() => _t = t);
    } catch (e) {
      if (mounted) setState(() => _error = AppFeedback.friendlyMessage(e));
    }
  }

  /// API: artistBusiness.closeTicket → PUT /help_center/tickets/close/
  Future<void> _close() async {
    setState(() => _busy = true);
    try {
      await ServiceLocator.artistBusiness.closeTicket(widget.ticketId);
      await _load();
    } catch (e) {
      if (mounted) AppFeedback.showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: t == null
            ? Center(
                child: _error != null
                    ? Text(_error!, style: AiraText.sans(color: AiraColors.errorText))
                    : const CircularProgressIndicator(strokeWidth: 2.4, color: AiraColors.rose))
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  Row(children: [
                    SunndariBackChip(onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Ticket #${t.ticketId}', style: AiraText.serif(fontSize: 19, fontWeight: FontWeight.w600))),
                    Text(t.status.replaceAll('_', ' '), style: AiraText.sans(fontWeight: FontWeight.w700, color: AiraColors.rose)),
                  ]),
                  const SizedBox(height: 18),
                  Text(t.subject, style: AiraText.serif(fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(_issueTypes[t.issueType] ?? t.issueType, style: AiraText.sans(fontSize: 12, color: AiraColors.charcoalSoft)),
                  const SizedBox(height: 12),
                  Text(t.description ?? '', style: AiraText.sans(fontSize: 14, height: 1.45)),
                  if ((t.resolutionNote ?? '').isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(12)),
                      child: Text('Resolution: ${t.resolutionNote}', style: AiraText.sans(fontSize: 13, height: 1.4)),
                    ),
                  ],
                  if (t.attachments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Attachments', style: AiraText.sans(fontSize: 12, fontWeight: FontWeight.w700, color: AiraColors.charcoalSoft)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final a in t.attachments) _Thumb(a)]),
                  ],
                  const SizedBox(height: 24),
                  if (!t.isClosed)
                    PrimaryButton(label: _busy ? 'Closing…' : 'Close Ticket', expand: true, onTap: _busy ? null : _close),
                ],
              ),
      ),
    );
  }
}

/// Attachment thumbnail — bytes come from the private endpoint (Bearer header).
class _Thumb extends StatelessWidget {
  final TicketAttachment a;
  const _Thumb(this.a);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      // API call: artistBusiness.getTicketAttachment → GET /help_center/tickets/attachment/
      future: ServiceLocator.artistBusiness.getTicketAttachment(a.attachmentId),
      builder: (_, snap) => Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: AiraColors.blush, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: snap.hasData
            ? Image.memory(snap.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.insert_drive_file_outlined))
            : const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
    );
  }
}

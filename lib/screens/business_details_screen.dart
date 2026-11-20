// FILE: screens/business_details_screen.dart
// SCREEN: Business — tabs: Locations | Salons | Portfolio | KYC.  +  SCREEN: Edit & Add Service — Services & Pricing only.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'business_setup_screen.dart';
import 'kyc_bank_details_screen.dart';
import 'portfolio_manage_screen.dart';
import 'salon_addresses_screen.dart';
import 'onboarding/artist_page_services_steps.dart' show ExtraServicesStep, ExtraServicesStepState;
import '../utils/app_feedback.dart';

/// SCREEN: Business — tabs: Locations | Portfolio | KYC. (initialTab 'package' opens Edit & Add Service.)
class BusinessDetailsScreen extends StatefulWidget {
  final String initialTab;
  const BusinessDetailsScreen({super.key, this.initialTab = 'setup'});

  @override
  State<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

/// State of [BusinessDetailsScreen] — holds the screen data and logic.
class _BusinessDetailsScreenState extends State<BusinessDetailsScreen> {
  late String _tab = widget.initialTab == 'package' ? 'setup' : widget.initialTab;

  static const _keys = ['setup', 'salons', 'portfolio', 'kyc'];

  /// Builds the UI.
  @override
  Widget build(BuildContext context) {
    // Old links that pointed at packages now open Edit & Add Service.
    if (widget.initialTab == 'package') return const EditAddServiceScreen();
    final index = _keys.indexOf(_tab).clamp(0, _keys.length - 1);
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiraScreenHeader(title: 'Business', onBack: () => Navigator.of(context).pop()),
            AiraSegTabs(
              tabs: const [
                SegTabItem('setup', 'Locations'),
                SegTabItem('salons', 'Salons'),
                SegTabItem('portfolio', 'Portfolio'),
                SegTabItem('kyc', 'KYC'),
              ],
              active: _tab,
              onSelect: (t) => setState(() => _tab = t),
            ),
            Expanded(
              child: IndexedStack(
                index: index,
                children: const [
                  BusinessSetupScreen(embedded: true, only: 'locations'),
                  SalonAddressesScreen(embedded: true),
                  PortfolioManageScreen(embedded: true),
                  KycBankDetailsScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SCREEN: Edit & Add Service — tabs: Services (list, edit, add) | Optional Services (add-ons: add, edit, delete).
class EditAddServiceScreen extends StatefulWidget {
  const EditAddServiceScreen({super.key});

  @override
  State<EditAddServiceScreen> createState() => _EditAddServiceScreenState();
}

class _EditAddServiceScreenState extends State<EditAddServiceScreen> {
  String _tab = 'services';
  final _extrasKey = GlobalKey<ExtraServicesStepState>();
  bool _saving = false;

  Future<void> _saveAddOn() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await _extrasKey.currentState?.save() ?? false;
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) AppFeedback.showSuccess(context, 'Optional Service Saved ✓');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiraColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AiraScreenHeader(title: 'Edit & Add Service', onBack: () => Navigator.of(context).pop()),
            AiraSegTabs(
              tabs: const [
                SegTabItem('services', 'Services'),
                SegTabItem('extras', 'Optional Services'),
              ],
              active: _tab,
              onSelect: (t) => setState(() => _tab = t),
            ),
            Expanded(
              child: _tab == 'services'
                  ? const BusinessSetupScreen(embedded: true, only: 'services')
                  : Column(
                children: [
                  Expanded(child: ExtraServicesStep(key: _extrasKey, standalone: true)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: PrimaryButton(
                      label: _saving ? 'Please Wait…' : 'Save Optional Service',
                      expand: true,
                      onTap: _saving ? null : _saveAddOn,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
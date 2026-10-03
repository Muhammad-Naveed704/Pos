import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_info.dart';
import '../../../core/ui/ui_kit.dart';

/// Support contact shown in the app and in the store listing.
abstract final class SupportContact {
  static const email = 'mnaveed2862@gmail.com';
  static const phone = '+92 344 2862704';
  static const phoneLocal = '0344 2862704';
  static const whatsapp = 'https://wa.me/923442862704';
  static const hours = 'Monday–Saturday, 10:00–19:00 (PKT)';
}

/// Opens a mailto:/https: link with the Windows shell (no network needed by
/// the app itself; the user's mail app or browser handles it).
Future<void> openExternal(String uri) async {
  if (!Platform.isWindows) return;
  await Process.start('rundll32', ['url.dll,FileProtocolHandler', uri]);
}

Future<void> showHelpDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
            child: Row(
              children: [
                Text(
                  'Help & support',
                  style: context.text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Expanded(child: HelpSupportView(padding: EdgeInsets.all(24))),
        ],
      ),
    ),
  ),
);

class HelpSupportView extends StatelessWidget {
  const HelpSupportView({
    this.padding = const EdgeInsets.symmetric(vertical: 20),
    super.key,
  });
  final EdgeInsets padding;

  static const _steps = [
    (
      Icons.storefront_rounded,
      'Business & store',
      'Settings → Business & regional: name, currency, number format. Add branches in Stores.',
    ),
    (
      Icons.category_rounded,
      'Categories',
      'Create parent categories (e.g. Grocery) and sub-categories (Rice, Oil) in Categories.',
    ),
    (
      Icons.inventory_2_rounded,
      'Products',
      'Products → New product, or Import / Export to load a CSV. Add a photo, price, stock and barcode.',
    ),
    (
      Icons.people_alt_rounded,
      'Users & roles',
      'Create a login for each cashier and choose what their role may do.',
    ),
    (
      Icons.receipt_long_rounded,
      'Receipt & printer',
      'Settings → Receipt designer: paper size, logo, footer; pick the printer and use Test print.',
    ),
    (
      Icons.point_of_sale_rounded,
      'Sell',
      'Point of Sale: scan or search, F7 to take payment, F8 for exact cash. Credit sales need a customer.',
    ),
    (
      Icons.backup_rounded,
      'Back up',
      'Settings → Data & backup: create a backup now and turn on automatic backups.',
    ),
  ];

  static const _shortcuts = [
    ('F2', 'Search products (press again for the camera scanner)'),
    ('F3', 'Choose customer'),
    ('F4', 'Hold sale'),
    ('F6', 'Sale discount'),
    ('F7', 'Take payment'),
    ('F8', 'Exact cash checkout'),
    ('F9', 'Held sales'),
    ('F10 / Ctrl+Enter', 'Complete payment'),
    ('Ctrl+R', 'Return items'),
    ('Ctrl+N', 'New sale'),
    ('Ctrl+Shift+P', 'Receive a customer payment'),
    ('Ctrl+B', 'Collapse sidebar'),
    ('Ctrl+L', 'Lock'),
  ];

  @override
  Widget build(BuildContext context) => ListView(
    padding: padding,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: SectionCard(
              title: 'Contact support',
              subtitle: SupportContact.hours,
              icon: Icons.support_agent_rounded,
              child: Column(
                children: [
                  _ContactRow(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: SupportContact.email,
                    action: TextButton.icon(
                      onPressed: () => openExternal(
                        'mailto:${SupportContact.email}?subject=StoreFlow%20POS%20support%20(v${AppInfo.appVersion})',
                      ),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Write email'),
                    ),
                  ),
                  _ContactRow(
                    icon: Icons.call_outlined,
                    label: 'Phone / WhatsApp',
                    value:
                        '${SupportContact.phoneLocal}  ·  ${SupportContact.phone}',
                    action: TextButton.icon(
                      onPressed: () => openExternal(SupportContact.whatsapp),
                      icon: const Icon(Icons.chat_outlined, size: 16),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When asking for help, mention the app version and what you were doing. '
                    'Never share your password or recovery key.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: SectionCard(
              title: 'About',
              icon: Icons.info_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 48),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppInfo.name,
                            style: context.text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text('Version ${AppInfo.appVersion}'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Works fully offline. Your business data stays on this computer; '
                    'nothing is sent to any server.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Getting started',
        subtitle: 'Set up a new shop in this order',
        icon: Icons.rocket_launch_outlined,
        child: Column(
          children: [
            for (var i = 0; i < _steps.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: context.colors.primaryContainer,
                  foregroundColor: context.colors.primary,
                  child: Icon(_steps[i].$1, size: 18),
                ),
                title: Text(
                  '${i + 1}. ${_steps[i].$2}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_steps[i].$3),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Keyboard shortcuts',
        icon: Icons.keyboard_rounded,
        child: Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            for (final (keys, action) in _shortcuts)
              SizedBox(
                width: 340,
                child: Row(
                  children: [
                    SizedBox(
                      width: 128,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: KeyHint(keys),
                      ),
                    ),
                    Expanded(child: Text(action)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.action,
  });
  final IconData icon;
  final String label;
  final String value;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: context.colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.labelMedium),
              SelectableText(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            Toast.success(context, 'Copied');
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
        ),
        action,
      ],
    ),
  );
}

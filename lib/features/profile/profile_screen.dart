import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import '../admin/admin_panel_screen.dart';
import '../admin/data/admin_repo.dart';
import '../certificates/my_certificates_screen.dart';
import '../courses/favorites_screen.dart';
import '../library/library_screen.dart';
import '../support/support_screen.dart';
import '../settings/settings_screen.dart';
import '../tenancy/select_tenant_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<Map<String, dynamic>?> _load() async {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('full_name, email, avatar_url')
        .eq('id', uid)
        .maybeSingle();
    final admin = await AdminRepository.hasAdminAccess();
    return {...?profile, '_is_admin': admin};
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data;
          final name = profile?['full_name'] as String? ?? '';
          final email = profile?['email'] as String? ?? '';
          final isAdmin = profile?['_is_admin'] == true;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Gradient identity header (reference: profile header cards).
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [scheme.primary, const Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .3),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: _ProfileAvatar(
                          avatarUrl: profile?['avatar_url'] as String?),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .85),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(s.t('edit_profile')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: TenantContext.instance.currentName,
                builder: (context, tenantName, _) => ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: Text(s.t('tenant_label')),
                  subtitle: Text(tenantName),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SelectTenantScreen()),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: Text(s.t('favorites')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(s.t('my_certificates')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MyCertificatesScreen()),
                ),
              ),
              if (isAdmin)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Card(
                    color: Theme.of(context).colorScheme.primary,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Icon(Icons.admin_panel_settings,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 32),
                      title: Text(
                        s.t('admin_panel'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      trailing: Icon(Icons.arrow_forward_ios,
                          color: Theme.of(context).colorScheme.onPrimary),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AdminPanelScreen()),
                      ),
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(s.t('library_label')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LibraryScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.support_agent),
                title: Text(s.t('support')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SupportScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(s.t('settings')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(s.t('logout')),
                onTap: () => Supabase.instance.client.auth.signOut(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Avatar with a camera badge. Tapping opens a gallery/camera sheet, uploads
/// to the public `avatars` bucket under the user's own folder, and saves the
/// public URL (with a cache buster) on profiles.avatar_url.
class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({this.avatarUrl});

  final String? avatarUrl;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  String? _url;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url = widget.avatarUrl;
  }

  Future<void> _pick(ImageSource source) async {
    Navigator.of(context).pop(); // close the sheet
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    final s = S.of(context);
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      final bytes = await file.readAsBytes();
      final path = '$uid/avatar.jpg';
      await client.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
      final base = client.storage.from('avatars').getPublicUrl(path);
      final url =
          '$base?v=${DateTime.now().millisecondsSinceEpoch}';
      await client
          .from('profiles')
          .update({'avatar_url': url}).eq('id', uid);
      if (mounted) {
        setState(() => _url = url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('photo_updated'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('photo_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _chooseSource() {
    final s = S.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.t('photo_gallery')),
              onTap: () => _pick(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.t('photo_camera')),
              onTap: () => _pick(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final url = _url;
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundImage: url != null ? NetworkImage(url) : null,
            child: _busy
                ? const CircularProgressIndicator()
                : (url == null
                    ? const Icon(Icons.person, size: 44)
                    : null),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: s.t('change_photo'),
              child: InkWell(
                onTap: _busy ? null : _chooseSource,
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: const Icon(Icons.photo_camera_outlined,
                      size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

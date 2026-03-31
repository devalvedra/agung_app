import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _iduserController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String _defaultBaseUrl = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _iduserController.dispose();
    super.dispose();
  }

  /// Load current settings from database
  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final currentUrl = await SettingsService.instance.getBaseUrl();
      final currentIduser = await SettingsService.instance.getIduser();
      _defaultBaseUrl = SettingsService.instance.getDefaultBaseUrl();
      _baseUrlController.text = currentUrl;
      _iduserController.text = currentIduser ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading settings: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Save settings to database
  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await SettingsService.instance.setBaseUrl(_baseUrlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Base URL saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving base URL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Reset base URL to default value
  Future<void> _resetToDefault() async {
    setState(() => _isSaving = true);
    try {
      await SettingsService.instance.resetToDefault();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Base URL reset to default'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resetting base URL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.purple,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'API Configuration',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _baseUrlController,
                      decoration: InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'http://localhost:8000',
                        border: const OutlineInputBorder(),
                        helperText: 'Enter the base URL for the API server',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _isSaving ? null : _resetToDefault,
                          tooltip: 'Reset to default',
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Base URL is required';
                        }
                        if (!value.trim().startsWith('http://') &&
                            !value.trim().startsWith('https://')) {
                          return 'URL must start with http:// or https://';
                        }
                        return null;
                      },
                      enabled: !_isSaving,
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Default: $_defaultBaseUrl',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _iduserController,
                      decoration: const InputDecoration(
                        labelText: 'User ID',
                        hintText: 'Enter your user ID',
                        border: OutlineInputBorder(),
                        helperText: 'User ID sent with API requests (optional)',
                        prefixIcon: Icon(Icons.person),
                      ),
                      enabled: !_isSaving,
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveSettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• The base URL is used for all API requests\n'
                      '• User ID is included when updating pickup items\n'
                      '• If no custom URL is saved, the default from .env file is used\n'
                      '• Click the refresh icon to reset to the default value\n'
                      '• Changes take effect immediately after saving',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

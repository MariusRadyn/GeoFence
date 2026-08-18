import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geofence/utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _maxChars = 1000;
const String _draftPrefsKey = 'contact_us_draft';

/// Fractions of the *fitted* background where the glowing message square sits.
const double _boxLeft = 0.07;
const double _boxRight = 0.07;
const double _boxTop = 0.545;
const double _boxBottom = 0.095;

/// Policy copy sits under "YOUR IMAGINATION" and above the message frame.
const double _policyTop = 0.135;
const double _policyBottom = 0.48;
const double _policySide = 0.16;

const String _policyText =
    'Have an idea? Need an IoT solution?\n'
    'We’re here to help.\n'
    '\n'
    'Our IoT solutions service is free,\n'
    'provided the required unit is viable for us.\n'
    '\n'
    'We cover all development costs,\n'
    'including final hardware and software.\n'
    '\n'
    'Terms and conditions apply.\n'
    '\n'
    'Drop us a message about anything —\n'
    'a business idea, a question,\n'
    'feedback, or just to say hello.\n'
    'We’d love to hear from you.';

Size _containSize(Size source, Size max) {
  if (source.width <= 0 || source.height <= 0) return max;
  final scale = (max.width / source.width < max.height / source.height)
      ? max.width / source.width
      : max.height / source.height;
  return Size(source.width * scale, source.height * scale);
}

class ContactUsPage extends StatefulWidget {
  const ContactUsPage({super.key});

  @override
  State<ContactUsPage> createState() => _ContactUsPageState();
}

class _ContactUsPageState extends State<ContactUsPage> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _draftTimer;
  bool _submitting = false;
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveImageSize());
    _focusNode.addListener(_onFocusChange);
    _messageController.addListener(_onMessageChanged);
    unawaited(_restoreDraft());
  }

  void _onMessageChanged() {
    if (!mounted) return;
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _persistDraft);
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = prefs.getString(_draftPrefsKey);
      if (!mounted || draft == null || draft.isEmpty) return;
      if (_messageController.text.isNotEmpty) return;
      _messageController.text = draft;
      _messageController.selection =
          TextSelection.collapsed(offset: draft.length);
    } catch (_) {
      // Draft restore is best-effort.
    }
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = _messageController.text;
      if (text.isEmpty) {
        await prefs.remove(_draftPrefsKey);
      } else {
        await prefs.setString(_draftPrefsKey, text);
      }
    } catch (_) {
      // Draft save is best-effort.
    }
  }

  Future<void> _clearDraft() async {
    _draftTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftPrefsKey);
    } catch (_) {}
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) return;
    // Scroll the message box into view above the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _resolveImageSize() {
    final stream =
        const AssetImage(iconContactUs).resolve(const ImageConfiguration());
    _imageStream = stream;
    _imageListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    }, onError: (_, __) {
      if (!mounted) return;
      setState(() => _imageSize = const Size(1080, 1920));
    });
    stream.addListener(_imageListener!);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _messageController.removeListener(_onMessageChanged);
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final message = _messageController.text.trim();
    final chars = message.length;
    if (chars == 0) {
      MyGlobalMessage.show(
        'Message required',
        'Please type your message in the box before sending.',
        MyMessageType.warning,
      );
      return;
    }
    if (chars > _maxChars) {
      MyGlobalMessage.show(
        'Message too long',
        'Please limit your message to $_maxChars characters.',
        MyMessageType.warning,
      );
      return;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      MyGlobalMessage.show(
        'Sign in required',
        'Please sign in before sending a message.',
        MyMessageType.warning,
      );
      return;
    }

    final profile = context.read<UserDataService>().userdata;
    final userName = (profile != null && profile.displayName.trim().isNotEmpty)
        ? profile.displayName.trim()
        : (authUser.displayName?.trim().isNotEmpty == true
            ? authUser.displayName!.trim()
            : 'Unknown user');
    final userEmail = (authUser.email?.trim().isNotEmpty == true)
        ? authUser.email!.trim()
        : (profile?.email != null && profile!.email!.trim().isNotEmpty
            ? profile.email!.trim()
            : 'Not provided');

    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();

    try {
      // Fast durable queue write — email is sent by Cloud Function onCreate.
      // Message stays on screen until this succeeds; draft is kept on failure.
      await FirebaseFirestore.instance
          .collection(collectionContactMessages)
          .add({
        'userName': userName,
        'userEmail': userEmail,
        'userId': authUser.uid,
        'message': message,
        'status': 'queued',
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 20));

      await _clearDraft();
      if (!mounted) return;
      _messageController.clear();
      Navigator.of(context).pop();
      MyGlobalMessage.show(
        'Message received',
        'Thanks you for your message — we’ll get back to you as soon as possible.',
        MyMessageType.success,
      );
    } on TimeoutException {
      if (!mounted) return;
      MyGlobalMessage.show(
        'Still saving…',
        'Network is slow. Your message is still in the box — tap Send again.',
        MyMessageType.warning,
      );
    } catch (e) {
      if (!mounted) return;
      MyGlobalMessage.show(
        'Could not send',
        'Your message is still in the box. Check your connection and try again.\n$e',
        MyMessageType.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chars = _messageController.text.length;
    final canSend = _messageController.text.trim().isNotEmpty &&
        chars <= _maxChars &&
        !_submitting;
    final atLimit = chars >= _maxChars;
    final media = MediaQuery.of(context);
    final dpr = media.devicePixelRatio;
    final keyboard = media.viewInsets.bottom;

    // Fit to the full screen (ignore keyboard height) so the art doesn't shrink.
    final bodyMax = Size(
      media.size.width,
      media.size.height -
          media.padding.top -
          media.padding.bottom -
          kToolbarHeight,
    );
    final source = _imageSize ?? const Size(1080, 1920);
    final fitted = _containSize(source, bodyMax);
    final cacheW = (fitted.width * dpr).round().clamp(1, 2048);
    final cacheH = (fitted.height * dpr).round().clamp(1, 4096);

    final boxLeft = fitted.width * _boxLeft;
    final boxRight = fitted.width * _boxRight;
    final boxTop = fitted.height * _boxTop;
    final boxBottom = fitted.height * _boxBottom;

    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_submitting) return;
        MyGlobalMessage.show(
          'Please wait',
          'Your message is still being saved. Don’t leave until it finishes.',
          MyMessageType.warning,
        );
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF020B18),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF020B18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Contact Us'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(bottom: keyboard > 0 ? 8 : 0),
                child: SizedBox(
                  width: bodyMax.width,
                  height: fitted.height,
                  child: Center(
                    child: SizedBox(
                      width: fitted.width,
                      height: fitted.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            iconContactUs,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            gaplessPlayback: true,
                            cacheWidth: cacheW,
                            cacheHeight: cacheH,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => const ColoredBox(
                              color: Color(0xFF020B18),
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white38,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                          // Policy text — top center under "YOUR IMAGINATION".
                          Positioned(
                            left: fitted.width * _policySide,
                            right: fitted.width * _policySide,
                            top: fitted.height * _policyTop,
                            bottom: fitted.height * (1 - _policyBottom),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: Text(
                                _policyText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      blurRadius: 6,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: boxLeft,
                            right: boxRight,
                            top: boxTop,
                            bottom: boxBottom + 48,
                            child: TextFormField(
                              controller: _messageController,
                              focusNode: _focusNode,
                              maxLines: null,
                              expands: true,
                              maxLength: _maxChars,
                              maxLengthEnforcement:
                                  MaxLengthEnforcement.enforced,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(_maxChars),
                              ],
                              textAlignVertical: TextAlignVertical.top,
                              autocorrect: true,
                              enableSuggestions: true,
                              enabled: !_submitting,
                              cursorColor: const Color(0xFF5EC8FF),
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.4,
                                fontSize: 14,
                              ),
                              buildCounter: (
                                context, {
                                required currentLength,
                                required isFocused,
                                required maxLength,
                              }) =>
                                  null,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding:
                                    EdgeInsets.fromLTRB(16, 36, 16, 12),
                              ),
                              validator: (value) {
                                final text = (value ?? '').trim();
                                if (text.isEmpty) {
                                  return 'Please enter a message';
                                }
                                if (text.length > _maxChars) {
                                  return 'Maximum $_maxChars characters';
                                }
                                return null;
                              },
                            ),
                          ),
                          // Char counter — top right of the message frame.
                          Positioned(
                            right: boxRight + 12,
                            top: boxTop + 10,
                            child: Text(
                              '$chars / $_maxChars',
                              style: TextStyle(
                                color: atLimit
                                    ? colorOrange
                                    : Colors.white.withValues(alpha: 0.75),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Positioned(
                            left: boxLeft,
                            right: boxRight,
                            bottom: boxBottom * 0.25,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorOrange,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.white24,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: canSend ? _submit : null,
                                  child: _submitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Send',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_submitting)
              const ModalBarrier(
                dismissible: false,
                color: Color(0x66000000),
              ),
          ],
        ),
      ),
    ),
    );
  }
}

import 'package:flutter/material.dart';

/// Central translation system. Every UI string goes through [S.of].
/// Arabic is the default launch language; English is the fallback.
class S {
  S(this.locale);

  final Locale locale;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S) ?? S(const Locale('ar'));
  }

  static const supportedLocales = [Locale('ar'), Locale('en')];

  static const _values = <String, Map<String, String>>{
    'app_name': {'ar': 'EduSpace', 'en': 'EduSpace'},
    'login': {'ar': 'تسجيل الدخول', 'en': 'Log in'},
    'signup': {'ar': 'إنشاء حساب', 'en': 'Sign up'},
    'email': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
    'password': {'ar': 'كلمة المرور', 'en': 'Password'},
    'confirm_password': {'ar': 'تأكيد كلمة المرور', 'en': 'Confirm password'},
    'full_name': {'ar': 'الاسم الكامل', 'en': 'Full name'},
    'forgot_password': {'ar': 'نسيت كلمة المرور؟', 'en': 'Forgot password?'},
    'no_account': {'ar': 'لسه معندكش حساب؟', 'en': "Don't have an account?"},
    'have_account': {'ar': 'عندك حساب بالفعل؟', 'en': 'Already have an account?'},
    'send_reset_link': {'ar': 'إرسال رابط الاستعادة', 'en': 'Send reset link'},
    'reset_link_sent': {
      'ar': 'لو البريد ده مسجل، هيوصلك رابط الاستعادة خلال دقائق.',
      'en': 'If this email is registered, a reset link will arrive shortly.',
    },
    'check_email_title': {'ar': 'راجع بريدك', 'en': 'Check your email'},
    'check_email_body': {
      'ar': 'بعننا لك رابط تحقق على بريدك. افتحه وبعدين سجل دخولك.',
      'en': 'We sent you a verification link. Open it, then log in.',
    },
    'resend': {'ar': 'إعادة الإرسال', 'en': 'Resend'},
    'back_to_login': {'ar': 'رجوع لتسجيل الدخول', 'en': 'Back to login'},
    'account_pending': {
      'ar': 'حسابك قيد المراجعة',
      'en': 'Your account is under review',
    },
    'account_rejected': {'ar': 'حسابك مرفوض', 'en': 'Your account was rejected'},
    'account_suspended': {
      'ar': 'حسابك موقوف',
      'en': 'Your account is suspended',
    },
    'contact_support': {'ar': 'تواصل مع الدعم', 'en': 'Contact support'},
    'logout': {'ar': 'تسجيل الخروج', 'en': 'Log out'},
    'tab_home': {'ar': 'الرئيسية', 'en': 'Home'},
    'tab_courses': {'ar': 'الكورسات', 'en': 'Courses'},
    'tab_exams': {'ar': 'الامتحانات', 'en': 'Exams'},
    'tab_account': {'ar': 'حسابي', 'en': 'Account'},
    'welcome': {'ar': 'أهلاً', 'en': 'Welcome'},
    'coming_soon': {'ar': 'القسم ده لسه جاي في المرحلة الجاية', 'en': 'This section is coming in the next stage'},
    'profile': {'ar': 'الملف الشخصي', 'en': 'Profile'},
    'edit_profile': {'ar': 'تعديل الملف الشخصي', 'en': 'Edit profile'},
    'save': {'ar': 'حفظ', 'en': 'Save'},
    'cancel': {'ar': 'إلغاء', 'en': 'Cancel'},
    'settings': {'ar': 'الإعدادات', 'en': 'Settings'},
    'language': {'ar': 'اللغة', 'en': 'Language'},
    'theme': {'ar': 'المظهر', 'en': 'Theme'},
    'theme_light': {'ar': 'نهاري', 'en': 'Light'},
    'theme_dark': {'ar': 'ليلي', 'en': 'Dark'},
    'theme_system': {'ar': 'اتباع النظام', 'en': 'System'},
    'my_payments': {'ar': 'مدفوعاتي', 'en': 'My payments'},
    'my_certificates': {'ar': 'شهاداتي', 'en': 'My certificates'},
    'required_field': {'ar': 'الحقل ده مطلوب', 'en': 'This field is required'},
    'invalid_email': {'ar': 'البريد ده مش صحيح', 'en': 'This email is not valid'},
    'password_short': {
      'ar': 'كلمة المرور لازم 6 أحرف على الأقل',
      'en': 'Password must be at least 6 characters',
    },
    'passwords_mismatch': {
      'ar': 'كلمتا المرور مش متطابقتين',
      'en': 'Passwords do not match',
    },
    'generic_error': {
      'ar': 'حصل خطأ. حاول تاني.',
      'en': 'Something went wrong. Try again.',
    },
    'saved_ok': {'ar': 'تم الحفظ', 'en': 'Saved'},
    'missing_config': {
      'ar': 'إعدادات الاتصال ناقصة. شغّل التطبيق بمفاتيح Supabase زي ما في الملف التعريفي.',
      'en': 'Missing connection config. Run the app with the Supabase keys as described in the README.',
    },
  };

  String t(String key) {
    final entry = _values[key];
    if (entry == null) return key;
    return entry[locale.languageCode] ?? entry['en'] ?? key;
  }
}

class SDelegate extends LocalizationsDelegate<S> {
  const SDelegate();

  @override
  bool isSupported(Locale locale) =>
      S.supportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<S> load(Locale locale) async => S(locale);

  @override
  bool shouldReload(SDelegate old) => false;
}

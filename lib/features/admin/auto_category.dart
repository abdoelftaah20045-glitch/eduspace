import '../../core/search_norm.dart';

/// Free, rule-based classifier (no paid AI, no internet service).
/// Order of decisions:
///  1. a category that already exists and whose words appear in the text
///     (so the same topic always lands in the same category);
///  2. a built-in topic list (Arabic + English keywords);
///  3. the word that repeats most across the video titles (2 or more
///     videos on the same subject make a new category);
///  4. otherwise the course goes to "متنوع".
/// The admin can rename or move anything afterwards.
class AutoCategory {
  AutoCategory._();

  static const fallback = 'متنوع';

  static const Map<String, List<String>> topics = {
    'البرمجة': ['برمجه', 'برمج', 'programming', 'python', 'java', 'javascript', 'c++', 'c#', 'kotlin', 'dart', 'flutter', 'php', 'sql', 'coding', 'algorithm', 'خوارزم', 'بايثون', 'جافا', 'فلاتر', 'software'],
    'تطوير الويب': ['web development', 'html', 'css', 'react', 'angular', 'vue', 'node', 'frontend', 'backend', 'تطوير المواقع', 'تطوير الويب', 'مواقع', 'wordpress', 'وورد بريس', 'laravel'],
    'تطبيقات الموبايل': ['android', 'ios', 'mobile app', 'اندرويد', 'تطبيقات الموبايل', 'تطبيقات الجوال', 'swift'],
    'الذكاء الاصطناعي وعلوم البيانات': ['artificial intelligence', 'machine learning', 'deep learning', 'data science', 'data analysis', 'ذكاء اصطناعي', 'تعلم الاله', 'علم البيانات', 'تحليل البيانات', 'chatgpt', 'power bi', 'tableau', 'pandas'],
    'الأمن السيبراني والشبكات': ['cyber', 'security', 'hacking', 'network', 'ccna', 'اختراق', 'امن المعلومات', 'الامن السيبراني', 'شبكات', 'linux', 'لينكس'],
    'التصميم والجرافيك': ['design', 'photoshop', 'illustrator', 'figma', 'ui/ux', 'ui ux', 'تصميم', 'فوتوشوب', 'اليستريتور', 'جرافيك', 'canva', 'كانفا', 'after effects', 'premiere', 'مونتاج', 'montage'],
    'الأوفيس والإنتاجية': ['excel', 'word', 'powerpoint', 'office', 'اكسل', 'اكسيل', 'وورد', 'بوربوينت', 'اوفيس', 'access', 'outlook'],
    'اللغة الإنجليزية': ['english', 'ielts', 'toefl', 'انجليزي', 'الانجليزيه', 'انجليزيه', 'grammar', 'vocabulary'],
    'اللغة الألمانية': ['german', 'deutsch', 'الماني', 'المانيه', 'الالمانيه'],
    'اللغة الفرنسية': ['french', 'francais', 'فرنسي', 'الفرنسيه', 'فرنسيه'],
    'اللغة الإسبانية': ['spanish', 'espanol', 'اسباني', 'الاسبانيه', 'اسبانيه'],
    'اللغة العربية': ['نحو', 'صرف', 'بلاغه', 'اللغه العربيه', 'اعراب', 'املاء', 'arabic grammar'],
    'اللغات الأخرى': ['turkish', 'تركي', 'التركيه', 'italian', 'ايطالي', 'japanese', 'ياباني', 'korean', 'كوري', 'chinese', 'صيني', 'russian', 'روسي'],
    'التسويق': ['marketing', 'seo', 'تسويق', 'اعلانات', 'سوشيال ميديا', 'social media', 'facebook ads', 'google ads', 'branding', 'المبيعات', 'sales'],
    'إدارة الأعمال': ['business', 'management', 'ادارة', 'ريادة', 'entrepreneur', 'startup', 'قياده', 'leadership', 'مشاريع', 'project management', 'pmp', 'hr', 'الموارد البشريه'],
    'المحاسبة والمالية': ['accounting', 'finance', 'محاسبه', 'ماليه', 'تمويل', 'ضرائب', 'audit', 'مراجعه', 'استثمار', 'investment', 'بورصه', 'trading', 'تداول'],
    'الاقتصاد': ['economics', 'اقتصاد', 'economy'],
    'الرياضيات': ['math', 'calculus', 'algebra', 'رياضيات', 'تفاضل', 'تكامل', 'جبر', 'هندسه', 'احصاء', 'statistics'],
    'الفيزياء': ['physics', 'فيزياء', 'ميكانيكا', 'كهرباء'],
    'الكيمياء': ['chemistry', 'كيمياء'],
    'الأحياء': ['biology', 'احياء', 'جينات', 'خليه'],
    'الطب والتمريض': ['medicine', 'medical', 'nursing', 'anatomy', 'طب', 'تمريض', 'تشريح', 'صيدله', 'pharmacy', 'اسنان', 'dentist', 'علاج طبيعي'],
    'الهندسة': ['engineering', 'autocad', 'revit', 'هندسه', 'ميكانيكا', 'مدني', 'معماري', 'solidworks', 'plc', 'الكترونيات', 'electronics', 'arduino'],
    'علم النفس وتطوير الذات': ['psychology', 'علم النفس', 'تطوير الذات', 'self development', 'productivity', 'مهارات', 'soft skills', 'تحفيز', 'motivation', 'عادات'],
    'القانون': ['law', 'legal', 'قانون', 'محاماه', 'تشريع'],
    'الدين والثقافة الإسلامية': ['quran', 'islam', 'قران', 'تجويد', 'فقه', 'حديث', 'تفسير', 'سيره', 'اسلام', 'عقيده'],
    'الفنون والموسيقى': ['music', 'guitar', 'piano', 'موسيقى', 'جيتار', 'بيانو', 'عود', 'غناء', 'رسم', 'drawing', 'art'],
    'التصوير والفيديو': ['photography', 'video editing', 'تصوير', 'camera', 'كاميرا', 'سينما'],
    'الطبخ': ['cooking', 'recipe', 'طبخ', 'وصفات', 'حلويات', 'chef', 'مطبخ'],
    'الرياضة واللياقة': ['fitness', 'workout', 'gym', 'رياضه', 'لياقه', 'تمارين', 'yoga', 'يوجا', 'diet', 'تغذيه'],
    'الأطفال والتربية': ['kids', 'children', 'اطفال', 'تربيه', 'حضانه', 'parenting', 'مونتيسوري'],
    'التعليم والتدريس': ['teaching', 'education', 'تدريس', 'تعليم', 'معلم', 'مناهج', 'teacher'],
    'الألعاب': ['game', 'gaming', 'unity', 'unreal', 'العاب', 'جيمنج'],
    'السفر والسياحة': ['travel', 'tourism', 'سفر', 'سياحه', 'هجره'],
    'الصناعة والحرف': ['carpentry', 'نجاره', 'سباكه', 'خياطه', 'تفصيل', 'حرف', 'crafts', 'handmade'],
  };

  static const _stop = {
    'كورس', 'شرح', 'دوره', 'دورة', 'كامل', 'كاملة', 'محاضره', 'محاضرة', 'الدرس', 'درس', 'من', 'في', 'على', 'عن', 'مع', 'الى', 'الي', 'هذا', 'هذه', 'ال', 'و', 'كيف', 'ما', 'ماذا', 'لل', 'للمبتدئين', 'مجانا', 'مجاني', 'جديد', 'جزء', 'الجزء', 'الحلقه', 'حلقه', 'part', 'lesson', 'lecture', 'course', 'full', 'complete', 'tutorial', 'the', 'and', 'for', 'with', 'from', 'how', 'to', 'in', 'of', 'on', 'a', 'an', 'is', 'beginners', 'beginner', 'learn', 'learning', 'free', 'class', 'series', 'episode', 'مقدمه', 'تعلم', 'اساسيات', 'احتراف', 'باحتراف', 'بالعربي', 'بالعربيه', 'arabic', 'hd', 'new', 'basics', 'introduction', 'intro', 'advanced', 'level', 'مستوي',
  };

  static bool _has(String hay, String kw) {
    final k = normSearch(kw);
    if (k.isEmpty) return false;
    if (k.length <= 3 && RegExp(r'^[a-z+#/ ]+$').hasMatch(k)) {
      // short latin words must match as whole words (css, sql, hr ...)
      return RegExp('(^|[^a-z0-9])${RegExp.escape(k)}([^a-z0-9]|\$)').hasMatch(hay);
    }
    return hay.contains(k);
  }

  static List<String> _words(String t) => normSearch(t)
      .split(RegExp(r'[^a-z0-9\u0600-\u06FF+#]+'))
      .where((w) => w.length >= 3 && !_stop.contains(w) && !RegExp(r'^\d+$').hasMatch(w))
      .toList();

  /// Picks the category name for one course (playlist / row).
  /// [existing] = names of the categories that already exist.
  static String pick({
    required String title,
    String description = '',
    List<String> videoTitles = const [],
    List<String> existing = const [],
    String channel = '',
  }) {
    final head = normSearch('$title ${videoTitles.take(60).join(' ')}');
    final all = normSearch('$title $description ${videoTitles.take(60).join(' ')} $channel');

    // 1) an existing category whose name (or main words) is in the text
    String? best;
    var bestScore = 0;
    for (final c in existing) {
      final n = normSearch(c);
      if (n.isEmpty || n == normSearch(fallback)) continue;
      var score = 0;
      if (_has(head, n)) {
        score = 100 + n.length;
      } else {
        final ws = _words(c);
        if (ws.isEmpty) continue;
        final hit = ws.where((w) => head.contains(w)).length;
        if (hit == ws.length) score = 60 + hit;
        else if (hit > 0 && ws.length > 2 && hit * 2 >= ws.length) score = 30 + hit;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best != null && bestScore >= 30) return best;

    // 2) built-in topics, strongest evidence wins (title counts triple)
    String? topic;
    var topicScore = 0;
    topics.forEach((name, kws) {
      var sc = 0;
      for (final k in kws) {
        if (_has(normSearch(title), k)) sc += 3;
        if (_has(head, k)) sc += 2;
        if (_has(all, k)) sc += 1;
      }
      if (sc > topicScore) {
        topicScore = sc;
        topic = name;
      }
    });
    if (topic != null && topicScore >= 3) {
      // reuse an existing category that is the same topic
      for (final c in existing) {
        if (normSearch(c) == normSearch(topic!)) return c;
      }
      return topic!;
    }

    // 3) the word that repeats across the video titles
    final freq = <String, int>{};
    for (final v in videoTitles) {
      for (final w in _words(v).toSet()) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    String? word;
    var wc = 0;
    freq.forEach((w, c) {
      if (c > wc || (c == wc && word != null && w.length > word!.length)) {
        word = w;
        wc = c;
      }
    });
    if (word != null && wc >= 2 && wc * 3 >= videoTitles.length) {
      return _pretty(word!, title, videoTitles);
    }
    final tw = _words(title);
    if (tw.isNotEmpty) return _pretty(tw.first, title, videoTitles);
    return fallback;
  }

  // Gives the word back with its original spelling.
  static String _pretty(String w, String title, List<String> videos) {
    for (final src in [title, ...videos]) {
      for (final raw in src.split(RegExp(r'\s+'))) {
        if (normSearch(raw).replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF+#]'), '') == w) {
          final r = raw.replaceAll(RegExp(r'[^\w\u0600-\u06FF+#]'), '');
          if (r.isNotEmpty) {
            return RegExp(r'^[a-z]').hasMatch(r)
                ? r[0].toUpperCase() + r.substring(1)
                : r;
          }
        }
      }
    }
    return w;
  }
}

import '../../core/search_norm.dart';

/// Result of the classifier.
class CategoryPick {
  const CategoryPick(this.name, this.parent);
  final String name;
  final String? parent; // main subject the name belongs to (may be null)
}

/// Free, offline, rule-based classifier (no paid AI).
/// Only real subjects from a curated taxonomy are ever used: the words of a
/// title never become a category. When the evidence is not clear the result
/// is null and the course stays "needs review" until the admin picks one.
/// Decisions:
///  1. an existing category whose own name appears in the text;
///  2. the best sub-subject of the taxonomy, only with clear evidence
///     (a keyword in the course title, or several in the videos) and a
///     clear lead over the next subject.
class AutoCategory {
  AutoCategory._();

  static const Map<String, Map<String, List<String>>> taxonomy = {
    'البرمجة وتطوير البرمجيات': {
      'بايثون': ['python', 'بايثون', 'django', 'flask', 'pandas'],
      'جافا': ['java', 'جافا', 'spring boot'],
      'جافاسكريبت': ['javascript', 'جافاسكريبت', 'typescript', 'node.js', 'nodejs'],
      'C / C++ / C#': ['c++', 'c#', 'سي بلس', 'سي شارب', '.net', 'unity c#'],
      'تطوير الويب': ['html', 'css', 'react', 'angular', 'vue', 'frontend', 'backend', 'تطوير المواقع', 'تطوير الويب', 'wordpress', 'وورد بريس', 'laravel', 'php', 'بي اتش بي', 'web development'],
      'تطبيقات الموبايل': ['flutter', 'فلاتر', 'android development', 'اندرويد', 'ios development', 'swift', 'kotlin', 'react native', 'تطبيقات الموبايل', 'تطبيقات الجوال', 'mobile app'],
      'قواعد البيانات': ['sql', 'mysql', 'postgres', 'mongodb', 'قواعد البيانات', 'database', 'اوراكل', 'oracle'],
      'هياكل البيانات والخوارزميات': ['data structures', 'algorithm', 'خوارزميات', 'هياكل البيانات', 'competitive programming', 'leetcode'],
      'أساسيات البرمجة': ['برمجه', 'programming', 'coding', 'مقدمه في البرمجه', 'أساسيات البرمجة'],
    },
    'الذكاء الاصطناعي وعلوم البيانات': {
      'الذكاء الاصطناعي': ['artificial intelligence', 'ذكاء اصطناعي', 'chatgpt', 'prompt', 'llm', 'generative ai', 'الذكاء الاصطناعي'],
      'تعلم الآلة': ['machine learning', 'deep learning', 'تعلم الاله', 'تعلم الالة', 'neural network', 'tensorflow', 'pytorch'],
      'تحليل البيانات': ['data analysis', 'data science', 'تحليل البيانات', 'علم البيانات', 'power bi', 'tableau', 'data analytics'],
    },
    'الأمن السيبراني والشبكات': {
      'الأمن السيبراني': ['cyber', 'hacking', 'اختراق', 'امن المعلومات', 'الامن السيبراني', 'ethical hacking', 'penetration'],
      'الشبكات': ['ccna', 'networking', 'شبكات', 'network+', 'mikrotik', 'cisco'],
      'أنظمة التشغيل': ['linux', 'لينكس', 'windows server', 'نظم التشغيل', 'operating system'],
    },
    'التصميم والوسائط': {
      'التصميم الجرافيكي': ['photoshop', 'illustrator', 'فوتوشوب', 'اليستريتور', 'جرافيك', 'graphic design', 'canva', 'كانفا', 'تصميم جرافيك', 'branding design'],
      'تصميم واجهات المستخدم UI/UX': ['ui/ux', 'ui ux', 'figma', 'فيجما', 'تجربه المستخدم', 'user experience'],
      'المونتاج والفيديو': ['premiere', 'after effects', 'مونتاج', 'video editing', 'davinci', 'كاب كات', 'capcut', 'motion graphics', 'موشن جرافيك'],
      'التصوير الفوتوغرافي': ['photography', 'تصوير فوتوغرافي', 'lightroom', 'لايت روم', 'كاميرا'],
      'التصميم ثلاثي الأبعاد': ['blender', '3d max', '3ds max', 'maya', 'ثلاثي الابعاد', '3d modeling', 'zbrush'],
    },
    'الأوفيس والإنتاجية': {
      'إكسل': ['excel', 'اكسل', 'اكسيل', 'vlookup', 'pivot'],
      'وورد وبوربوينت': ['powerpoint', 'بوربوينت', 'microsoft word', 'وورد للمبتدئين'],
      'مهارات الحاسب': ['ICDL', 'icdl', 'مهارات الحاسب', 'اساسيات الحاسب', 'computer skills', 'google sheets', 'google workspace'],
    },
    'اللغات': {
      'اللغة الإنجليزية': ['english', 'ielts', 'toefl', 'انجليزي', 'الانجليزيه', 'انجليزيه', 'grammar', 'vocabulary', 'conversation english'],
      'اللغة الألمانية': ['german', 'deutsch', 'الماني', 'المانيه', 'الالمانيه'],
      'اللغة الفرنسية': ['french', 'francais', 'فرنسي', 'الفرنسيه', 'فرنسيه'],
      'اللغة الإسبانية': ['spanish', 'espanol', 'اسباني', 'الاسبانيه', 'اسبانيه'],
      'اللغة التركية': ['turkish', 'تركي', 'التركيه', 'تركيه'],
      'اللغة الإيطالية': ['italian', 'ايطالي', 'الايطاليه'],
      'اللغة اليابانية': ['japanese', 'ياباني', 'اليابانيه', 'jlpt'],
      'اللغة الكورية': ['korean', 'كوري', 'الكوريه'],
      'اللغة الصينية': ['chinese', 'صيني', 'الصينيه', 'mandarin'],
      'اللغة العربية': ['نحو', 'صرف', 'بلاغه', 'اللغه العربيه', 'اعراب', 'املاء', 'arabic grammar', 'خط عربي'],
    },
    'الأعمال والإدارة': {
      'التسويق الرقمي': ['marketing', 'seo', 'تسويق', 'اعلانات ممولة', 'social media', 'سوشيال ميديا', 'facebook ads', 'google ads', 'tiktok ads', 'content marketing', 'email marketing'],
      'المبيعات': ['sales', 'مبيعات', 'التفاوض', 'negotiation'],
      'إدارة المشاريع': ['project management', 'pmp', 'ادارة المشاريع', 'agile', 'scrum'],
      'ريادة الأعمال': ['entrepreneur', 'ريادة الاعمال', 'startup', 'شركات ناشئه', 'business plan', 'خطة عمل'],
      'الموارد البشرية': ['human resources', 'الموارد البشريه', 'hr ', 'التوظيف', 'recruitment'],
      'القيادة والإدارة': ['leadership', 'القياده', 'ادارة الاعمال', 'business administration', 'ادارة الوقت', 'time management'],
    },
    'المحاسبة والمالية': {
      'المحاسبة': ['accounting', 'محاسبه', 'قيود', 'ميزانيه', 'cost accounting', 'محاسبة'],
      'التمويل والاستثمار': ['finance', 'تمويل', 'investment', 'استثمار', 'بورصه', 'stock market', 'تداول', 'forex', 'فوركس', 'crypto', 'عملات رقمية'],
      'الضرائب والمراجعة': ['ضرائب', 'tax', 'audit', 'مراجعه'],
      'الاقتصاد': ['economics', 'اقتصاد', 'economy', 'الاقتصاد'],
    },
    'العلوم والرياضيات': {
      'الرياضيات': ['math', 'calculus', 'algebra', 'رياضيات', 'تفاضل', 'تكامل', 'جبر', 'هندسه تحليليه', 'احصاء', 'statistics', 'trigonometry', 'حساب المثلثات'],
      'الفيزياء': ['physics', 'فيزياء'],
      'الكيمياء': ['chemistry', 'كيمياء'],
      'الأحياء': ['biology', 'احياء', 'genetics', 'علم الوراثه'],
    },
    'الطب والصحة': {
      'الطب والتشريح': ['anatomy', 'تشريح', 'طب بشري', 'medicine', 'physiology', 'فسيولوجي', 'pathology'],
      'التمريض': ['nursing', 'تمريض'],
      'الصيدلة': ['pharmacy', 'صيدله', 'pharmacology'],
      'طب الأسنان': ['dentistry', 'اسنان', 'dental'],
      'التغذية واللياقة': ['nutrition', 'تغذيه', 'diet', 'fitness', 'لياقه', 'workout', 'gym', 'تمارين رياضيه', 'yoga', 'يوجا'],
      'الإسعافات الأولية': ['first aid', 'اسعافات اوليه', 'cpr'],
    },
    'الهندسة': {
      'الهندسة المدنية والمعمارية': ['autocad', 'revit', 'civil engineering', 'هندسه مدنيه', 'معماري', 'architecture', 'انشائي', 'structural', 'etabs', 'sap2000'],
      'الهندسة الكهربائية والإلكترونيات': ['electrical', 'كهرباء', 'electronics', 'الكترونيات', 'arduino', 'plc', 'embedded', 'دوائر كهربائيه'],
      'الهندسة الميكانيكية': ['mechanical engineering', 'هندسه ميكانيكيه', 'solidworks', 'hvac', 'تكييف'],
    },
    'تطوير الذات والمهارات': {
      'علم النفس': ['psychology', 'علم النفس', 'نفسي'],
      'تطوير الذات': ['self development', 'تطوير الذات', 'motivation', 'تحفيز', 'عادات', 'habits', 'productivity', 'soft skills', 'مهارات ناعمه'],
      'مهارات التواصل والإلقاء': ['public speaking', 'الالقاء', 'مهارات التواصل', 'communication skills', 'فن الحوار'],
    },
    'القانون': {
      'القانون': ['law', 'قانون', 'محاماه', 'legal', 'تشريعات'],
    },
    'الدراسات الإسلامية': {
      'القرآن وعلومه': ['quran', 'قران', 'تجويد', 'تفسير', 'القراءات', 'حفظ القران'],
      'الفقه والحديث': ['فقه', 'حديث', 'اصول الفقه', 'مصطلح الحديث'],
      'العقيدة والسيرة': ['عقيده', 'سيره نبويه', 'السيره', 'islamic studies', 'سيرة'],
    },
    'الفنون والهوايات': {
      'الموسيقى': ['music', 'guitar', 'piano', 'موسيقى', 'جيتار', 'بيانو', 'عود', 'solfege'],
      'الرسم': ['drawing', 'رسم', 'sketch', 'painting', 'تلوين'],
      'الطبخ': ['cooking', 'recipe', 'طبخ', 'وصفات', 'حلويات', 'baking'],
      'الحرف اليدوية': ['handmade', 'crochet', 'كروشيه', 'خياطه', 'نجاره', 'crafts', 'تطريز'],
    },
    'التعليم والتربية': {
      'التدريس وطرق التعليم': ['teaching', 'تدريس', 'طرق التدريس', 'مناهج', 'teacher training'],
      'تربية الأطفال': ['parenting', 'تربيه الاطفال', 'kids', 'اطفال', 'حضانه', 'montessori'],
    },
    'الألعاب': {
      'تطوير الألعاب': ['game development', 'unity', 'unreal', 'godot', 'تطوير الالعاب'],
    },
  };

  /// Main subject of a sub-subject name (null when unknown).
  static String? parentOf(String name) {
    final n = normSearch(name);
    for (final e in taxonomy.entries) {
      if (normSearch(e.key) == n) return null;
      for (final s in e.value.keys) {
        if (normSearch(s) == n) return e.key == s ? null : e.key;
      }
    }
    return null;
  }

  /// Every curated name (main subjects and sub-subjects) for pickers.
  static List<String> allNames() => [
        for (final e in taxonomy.entries) ...[
          e.key,
          for (final s in e.value.keys)
            if (s != e.key) s,
        ]
      ];

  static bool _has(String hay, String kw) {
    final k = normSearch(kw);
    if (k.isEmpty) return false;
    if (k.length <= 4 && RegExp(r'^[a-z+#/. ]+$').hasMatch(k)) {
      return RegExp('(^|[^a-z0-9])${RegExp.escape(k)}([^a-z0-9]|\$)').hasMatch(hay);
    }
    return hay.contains(k);
  }

  /// Picks the category for one course, or null when not sure.
  static CategoryPick? pick({
    required String title,
    String description = '',
    List<String> videoTitles = const [],
    List<String> existing = const [],
    String channel = '',
  }) {
    final t = normSearch(title);
    final head = normSearch('$title ${videoTitles.take(80).join(' ')}');
    final all = normSearch('$title $description ${videoTitles.take(80).join(' ')}');

    // 1) an existing category (made by the admin) named in the text
    String? best;
    var bestLen = 0;
    for (final c in existing) {
      final n = normSearch(c);
      if (n.length < 3) continue;
      if (_has(t, n) && n.length > bestLen) {
        best = c;
        bestLen = n.length;
      }
    }
    if (best != null) return CategoryPick(best, parentOf(best));

    // 2) curated taxonomy
    final scores = <String, int>{};
    final where = <String, String>{};
    taxonomy.forEach((par, subs) {
      subs.forEach((sub, kws) {
        var sc = 0;
        for (final k in kws) {
          if (_has(t, k)) sc += 4;
          if (_has(head, k)) sc += 2;
          if (_has(all, k)) sc += 1;
        }
        if (sc > 0) {
          scores[sub] = sc;
          where[sub] = par;
        }
      });
    });
    if (scores.isEmpty) return null;
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    if (top.value < 6) return null; // not enough evidence
    if (ranked.length > 1) {
      final second = ranked[1];
      final sameMain = where[second.key] == where[top.key];
      if (second.value * 10 > top.value * 7) {
        // too close: give the main subject if both belong to it, else unsure
        if (sameMain) return CategoryPick(where[top.key]!, null);
        return null;
      }
    }
    final par = where[top.key]!;
    return CategoryPick(top.key, par == top.key ? null : par);
  }
}

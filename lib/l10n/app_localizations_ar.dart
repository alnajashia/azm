// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'عزم';

  @override
  String get loadingDefault => 'جارٍ التحميل…';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get close => 'إغلاق';

  @override
  String get confirm => 'تأكيد';

  @override
  String get continueAction => 'متابعة';

  @override
  String get undo => 'تراجع';

  @override
  String errorCodeLine(String code) {
    return 'رمز الخطأ: $code';
  }

  @override
  String errorCodeExitLine(String code, int exitCode) {
    return 'رمز الخطأ: $code · الخروج $exitCode';
  }

  @override
  String get errUnavailable =>
      'طبقة خدمات أندرويد غير متاحة هنا (يحدث هذا في الاختبارات أو خارج الجهاز). لم تُنفَّذ أي عملية.';

  @override
  String get errShizukuNotInstalled =>
      'تطبيق Shizuku غير مثبّت على هذا الجهاز.';

  @override
  String get errShizukuNotRunning =>
      'تطبيق Shizuku مثبّت لكن خادمه لا يعمل. شغّله من تطبيق Shizuku ثم أعد المحاولة.';

  @override
  String get errShizukuNoPermission => 'لم يُمنح عزم إذن Shizuku بعد.';

  @override
  String get errShizukuPreV11 =>
      'خادم Shizuku هذا أقدم من الإصدار 11. حدّث Shizuku ثم أعد المحاولة.';

  @override
  String get errShizukuBinderDead =>
      'انقطع اتصال Shizuku أثناء العملية. نتيجتها غير معروفة — تحقق من الحالة الحالية قبل إعادة المحاولة.';

  @override
  String get errShellFailed => 'فشل أحد أوامر النظام.';

  @override
  String errShellFailedExit(int exitCode) {
    return 'فشل أحد أوامر النظام (رمز الخروج $exitCode).';
  }

  @override
  String get errProvisioningFailed =>
      'فشل تجهيز مالك الجهاز في المسار المباشر والاحتياطي معاً. راجع التشخيصات في شاشة الإعداد.';

  @override
  String get errDpmNotOwner =>
      'تطبيق عزم ليس مالك الجهاز، لذا هذه العملية غير متاحة. أكمل الإعداد أولاً.';

  @override
  String get errDpmFailed =>
      'رفض النظام هذا التغيير أو تعذّر التحقق منه. لم يُبلَّغ عن أي نجاح.';

  @override
  String get errPackageNotFound => 'هذا التطبيق غير مثبّت على هذا الجهاز.';

  @override
  String get errPermissionDenied => 'أحد الأذونات المطلوبة غير ممنوح.';

  @override
  String get errUnsupportedAndroid => 'إصدار أندرويد هذا لا يدعم هذه العملية.';

  @override
  String get errTimeout => 'انتهت مهلة العملية ولم يُبلَّغ عن نجاحها.';

  @override
  String errInvalidArgument(String message) {
    return 'إدخال غير صالح: $message';
  }

  @override
  String get errNotImplemented => 'هذا غير منفّذ في هذا الإصدار.';

  @override
  String get noLimit => 'بلا حد';

  @override
  String minutesOnly(int count) {
    return '$count دقيقة';
  }

  @override
  String hoursOnly(int count) {
    return '$count ساعة';
  }

  @override
  String hoursMinutes(int hours, int minutes) {
    return '$hours ساعة و$minutes دقيقة';
  }

  @override
  String durationHoursMinutes(String hours, String minutes) {
    return '$hours س $minutes د';
  }

  @override
  String durationMinutesSeconds(String minutes, String seconds) {
    return '$minutes د $seconds ث';
  }

  @override
  String durationSecondsOnly(String seconds) {
    return '$seconds ث';
  }

  @override
  String get chipV11 => 'v1.1';

  @override
  String get sessionRemaining => 'جلسة الاسترداد';

  @override
  String get renewSession => 'تجديد';

  @override
  String get endSession => 'إنهاء الجلسة';

  @override
  String get wordYes => 'نعم';

  @override
  String get wordNo => 'لا';

  @override
  String get startingDominanter => 'جارٍ بدء عزم…';

  @override
  String get unknownStartupError => 'خطأ غير معروف عند البدء';

  @override
  String get tabStatus => 'الحالة';

  @override
  String get tabRestrictions => 'القيود';

  @override
  String get tabApps => 'التطبيقات';

  @override
  String get tabConfig => 'الإعدادات';

  @override
  String get lockTitle => 'تطبيق عزم مقفل';

  @override
  String get panicButton => 'أشعر بنزوات';

  @override
  String get accessApp => 'فتح التطبيق';

  @override
  String get viewLimits => 'عرض الحدود';

  @override
  String get lockHelperBiometric =>
      'استخدم بصمتك أو وجهك أو رمز PIN لفتح التطبيق.';

  @override
  String get lockHelperWithPassword =>
      'استخدم بصمتك أو وجهك أو رمز PIN — أو كلمة مرور التطبيق.';

  @override
  String get usePasswordInstead => 'استخدم كلمة المرور بدلاً من ذلك';

  @override
  String versionFooter(String version) {
    return 'عزم $version';
  }

  @override
  String get impulseBlockActive => 'قفل النزوات مفعّل';

  @override
  String impulseStartedSuspended(int minutes) {
    return 'بدأ قفل النزوات؛ عُلّقت التطبيقات المختارة لمدة $minutes دقيقة.';
  }

  @override
  String impulseStarted(int minutes) {
    return 'بدأ قفل النزوات لمدة $minutes دقيقة.';
  }

  @override
  String focusPhaseFocusOf(int current, int total) {
    return 'تركيز $current/$total';
  }

  @override
  String get focusPhaseShortBreak => 'استراحة قصيرة';

  @override
  String get focusPhaseLongBreak => 'استراحة طويلة';

  @override
  String get focusPhaseBreakOver => 'انتهت الاستراحة';

  @override
  String get focusPhaseMode => 'وضع التركيز';

  @override
  String focusPausedTitle(String title) {
    return '$title · متوقف مؤقتاً';
  }

  @override
  String focusConfigSummary(int minutes) {
    return '$minutes دقيقة من التركيز، مع تعليق التطبيقات المختارة';
  }

  @override
  String focusPeriodsCompleted(int done, int total) {
    return 'فترات التركيز المكتملة: $done/$total';
  }

  @override
  String get focusStart => 'بدء التركيز';

  @override
  String get focusResume => 'استئناف';

  @override
  String get focusSkipBreak => 'تخطي الاستراحة';

  @override
  String get focusPause => 'إيقاف مؤقت';

  @override
  String get focusEndSession => 'إنهاء الجلسة';

  @override
  String get todaysUsage => 'استخدام اليوم';

  @override
  String get loadingUsageLimits => 'جارٍ تحميل حدود الاستخدام…';

  @override
  String get noLimitsSet => 'لا توجد حدود زمنية مضبوطة للتطبيقات أو المجموعات.';

  @override
  String get sectionGroups => 'المجموعات';

  @override
  String get sectionApps => 'التطبيقات';

  @override
  String groupPrefix(String name) {
    return 'المجموعة: $name';
  }

  @override
  String usageOf(String used, String limit) {
    return '$used من $limit';
  }

  @override
  String get limitReached => 'تم بلوغ الحد';

  @override
  String timeLeft(String time) {
    return 'تبقّى $time';
  }

  @override
  String overviewMinutes(int count) {
    return '$count د';
  }

  @override
  String overviewHours(int count) {
    return '$count س';
  }

  @override
  String overviewHoursMinutes(int hours, int minutes) {
    return '$hours س $minutes د';
  }

  @override
  String get noDeviceLockTitle => 'لا يوجد قفل مضبوط على الجهاز';

  @override
  String get noDeviceLockBody =>
      'لا توجد بصمة أو بيانات قفل شاشة مسجّلة على هذا الجهاز، فلا يوجد ما يمكن التحقق مقابله. يُسمح بالدخول — تماماً كما يتصرف التطبيق الأصلي في هذه الحالة. فكّر في تعيين رمز PIN للجهاز.';

  @override
  String get unlockReason => 'فتح عزم';

  @override
  String get authNotCompleted => 'لم تكتمل المصادقة.';

  @override
  String authFailed(String message) {
    return 'فشلت المصادقة: $message';
  }

  @override
  String authCouldNotStart(String error) {
    return 'تعذّر بدء المصادقة: $error';
  }

  @override
  String get passwordPromptTitle => 'أدخل كلمة مرور التطبيق';

  @override
  String get passwordFieldLabel => 'كلمة مرور التطبيق';

  @override
  String get passwordUnlock => 'فتح';

  @override
  String get passwordWrong => 'كلمة المرور غير صحيحة.';

  @override
  String passwordRetryIn(int seconds) {
    return 'أعد المحاولة بعد $seconds ث';
  }

  @override
  String get passwordChecking => 'جارٍ التحقق…';

  @override
  String get appEntrySection => 'الدخول إلى التطبيق';

  @override
  String get appEntryExplanation =>
      'عيّن كلمة مرور للتطبيق كطريقة إضافية لفتح عزم من شاشة القفل. كلمة المرور تفتح التطبيق فقط — تخفيف القيود أو إزالة مالك الجهاز ما زال يتطلب رمز الاسترداد.';

  @override
  String get appEntryStatusSet => 'كلمة مرور التطبيق معيّنة.';

  @override
  String get appEntryStatusUnset => 'لا توجد كلمة مرور للتطبيق.';

  @override
  String get appEntrySet => 'تعيين كلمة المرور';

  @override
  String get appEntryChange => 'تغيير كلمة المرور';

  @override
  String get appEntryRemove => 'إزالة كلمة المرور';

  @override
  String get passwordNewLabel => 'كلمة المرور الجديدة';

  @override
  String get passwordConfirmLabel => 'أعد كلمة المرور';

  @override
  String passwordMinLength(int count) {
    return 'استخدم $count أحرف على الأقل.';
  }

  @override
  String get passwordMismatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get passwordSetDone => 'عُيّنت كلمة مرور التطبيق.';

  @override
  String get passwordRemovedDone => 'أُزيلت كلمة مرور التطبيق.';

  @override
  String get passwordRemoveTitle => 'إزالة كلمة مرور التطبيق؟';

  @override
  String get passwordRemoveBody =>
      'ستفتح التطبيق ببصمتك أو بيانات قفل الجهاز من جديد. هذا لا يغيّر رمز الاسترداد.';

  @override
  String get passwordRemoveConfirm => 'إزالة';

  @override
  String get passwordShow => 'إظهار كلمة المرور';

  @override
  String get passwordHide => 'إخفاء كلمة المرور';

  @override
  String get recoveryCodeLabel => 'رمز الاسترداد';

  @override
  String get wizardSetupTitle => 'إعداد رمز الاسترداد';

  @override
  String get wizardChangeTitle => 'تغيير رمز الاسترداد';

  @override
  String stepOf(int step, int total) {
    return 'الخطوة $step من $total';
  }

  @override
  String get grabPaper => 'أحضر قلماً وورقة قبل المتابعة.';

  @override
  String get back => 'رجوع';

  @override
  String get next => 'التالي';

  @override
  String get finish => 'إنهاء';

  @override
  String get wizardIntroTitle => 'رمز الاسترداد الخاص بك';

  @override
  String get howItWorks => 'كيف يعمل';

  @override
  String get tipGenerates => 'يولّد عزم رمزاً من 16 حرفاً';

  @override
  String get tipWrite => 'اكتب الرمز على ورقة';

  @override
  String get tipTypeBack => 'اكتبه مجدداً للتأكد من صحته';

  @override
  String get tipStorePaper => 'احفظ الورقة في مكان آمن';

  @override
  String get wizardIntroBody =>
      'سيُطلب الرمز كلما غيّرت إعدادات عزم. بدونه قد تُحجب عن الميزات المحظورة. يُحفظ الرمز على هذا الجهاز فقط على صورة تجزئة مملّحة — لا يمكن إظهاره بعد هذا المعالج، ولا توجد نسخة حساب أو سحابة.';

  @override
  String get writeTitle => 'اكتبه على الورق';

  @override
  String get writeBody =>
      'انسخ الأحرف الستة عشر تماماً كما تظهر. لا تلتقط صورة شاشة ولا تحفظه على هاتفك — النسخة القريبة سهلة الاستخدام في لحظة نزوة.';

  @override
  String get generatingCode => 'جارٍ توليد الرمز…';

  @override
  String get showCode => 'إظهار الرمز';

  @override
  String get wroteOnPaper => 'كتبت الرمز على الورق';

  @override
  String get confirmTitle => 'تحقق مما كتبت';

  @override
  String get confirmBody =>
      'الرمز مخفي الآن. اكتبه من ورقتك للتأكد من صحة كل حرف.';

  @override
  String get codeCorrect => 'الرمز صحيح';

  @override
  String get codeMismatchBack => 'غير متطابق. ارجع وقارنه بورقتك.';

  @override
  String codeCountOf(int count) {
    return '$count/16';
  }

  @override
  String get storeTitle => 'احفظه في مكان آمن';

  @override
  String get storeBody =>
      'الورقة الآن هي النسخة الوحيدة من رمزك. اختر بعناية أين تحتفظ بها.';

  @override
  String get tipAway => 'بعيداً عن هاتفك، في مكان لن تصل إليه عند النزوة';

  @override
  String get tipEasyFind =>
      'سهل الوصول عندما تحتاجه فعلاً — درج أو مجلد أو لدى شخص تثق به';

  @override
  String get tipNoPhotos => 'لا صور ولا نسخ رقمية';

  @override
  String get tipThrowOld => 'تخلّص من الورقة ذات الرمز القديم';

  @override
  String get storedPaperCheckbox => 'حفظت الورقة في مكان آمن';

  @override
  String get codeMismatchStore =>
      'هذا لا يطابق الرمز المعروض. تحقق من نسختك الورقية وأعد المحاولة.';

  @override
  String get codeNotStored => 'لم يُحفظ الرمز. لم يتغيّر شيء.';

  @override
  String get firstRunTitle => 'عزم — التشغيل الأول';

  @override
  String get gateChallengesTitle => 'تحديات الوصول';

  @override
  String get gateCodeTitle => 'أدخل رمز الاسترداد';

  @override
  String get gateIntroText => 'أدخل رمز الاسترداد لفتح جلسة مدتها 10 دقائق.';

  @override
  String get gateEnterCodeError =>
      'أدخل الرمز المكوّن من 16 حرفاً من نسختك الورقية.';

  @override
  String get gateWrongCode => 'هذا الرمز غير متطابق. لم يُفتح أي شيء.';

  @override
  String get preparingGate => 'جارٍ تجهيز البوابة…';

  @override
  String get undoWindowPassed => 'انتهت مهلة التراجع؛ التغيير قائم.';

  @override
  String mathSolveTitle(int count) {
    return 'حل $count مسائل';
  }

  @override
  String get mathNotQuite => 'ليس تماماً — حاول مجدداً.';

  @override
  String get answerLabel => 'الإجابة';

  @override
  String get check => 'تحقق';

  @override
  String get wordsTypeTitle => 'اكتب الكلمات';

  @override
  String wordsCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get typeWordLabel => 'اكتب الكلمة';

  @override
  String readingTitle(int current, int total, String title) {
    return 'اقرأ ببطء — المقطع $current من $total: $title';
  }

  @override
  String get readingFinish => 'إنهاء';

  @override
  String get readingNextPassage => 'المقطع التالي';

  @override
  String get tetrisSkippedNote =>
      'ملاحظة: تحدي Tetris غير متاح في هذا الإصدار (v1.1) وتم تخطيه — لم يُحاكَ.';

  @override
  String get passageOnWaiting => 'عن الانتظار';

  @override
  String get passageOnFutureSelf => 'عن ذاتك في المستقبل';

  @override
  String get passageOnAttention => 'عن الانتباه';

  @override
  String get passageOnBeginningAgain => 'عن البدء من جديد';

  @override
  String get passageOnPatience => 'عن الصبر';

  @override
  String get yourPhrase => 'عبارتك';

  @override
  String get challengeMath => 'مسائل رياضية';

  @override
  String get challengeWords => 'كتابة كلمات';

  @override
  String get challengeTetris => 'Tetris';

  @override
  String get challengeReading => 'قراءة تأملية';

  @override
  String get checkingSetupState => 'جارٍ التحقق من حالة الإعداد…';

  @override
  String get iUnderstand => 'فهمت';

  @override
  String get details => 'التفاصيل';

  @override
  String get shizukuNotInstalledTitle => 'Shizuku: غير مثبّت';

  @override
  String get shizukuNotInstalledBody =>
      'ثبّت Shizuku (moe.shizuku.privileged.api) من متجر Play أو موقعه الرسمي، ثم عد إلى هنا.';

  @override
  String get shizukuNotRunningTitle => 'Shizuku: لا يعمل';

  @override
  String get shizukuNotRunningBody =>
      'تطبيق Shizuku مثبّت لكن خادمه لا يعمل. لا يستطيع عزم تشغيله — افتح تطبيق Shizuku وشغّل الخادم (عبر التصحيح اللاسلكي أو ADB)، ثم اسحب للتحديث.';

  @override
  String get shizukuPreV11Title => 'Shizuku: قديم جداً (قبل v11)';

  @override
  String get shizukuPreV11Body =>
      'خادم Shizuku هذا أقدم من الإصدار 11 ولا يستطيع تنفيذ الأوامر. حدّث Shizuku وأعد تشغيل خادمه ثم حدّث هذه الشاشة.';

  @override
  String get shizukuNoPermissionTitle => 'Shizuku: الإذن مطلوب';

  @override
  String get shizukuNoPermissionBody =>
      'الخادم يعمل. امنح عزم الإذن في Shizuku لمتابعة الإعداد.';

  @override
  String get shizukuGrantedTitle => 'Shizuku: متصل وممنوح';

  @override
  String get shizukuGrantedBody =>
      'عمليات الإعداد متاحة. الإنفاذ اليومي لا يحتاج Shizuku بعد التجهيز.';

  @override
  String get shizukuUnknownTitle => 'Shizuku: حالة غير معروفة';

  @override
  String get shizukuUnknownBody => 'أعادت الطبقة الأصلية حالة غير معروفة.';

  @override
  String serverVersionLine(int version, int uid) {
    return 'إصدار الخادم $version، UID $uid';
  }

  @override
  String diagnosticLine(String text) {
    return 'التشخيص: $text';
  }

  @override
  String get installShizuku => 'تثبيت Shizuku';

  @override
  String get waitingShizukuAppear => 'بانتظار ظهور Shizuku…';

  @override
  String get requestShizukuPermission => 'طلب إذن Shizuku';

  @override
  String get waitingShizukuAnswer => 'بانتظار رد Shizuku…';

  @override
  String get shizukuPermissionGrantedMsg =>
      'مُنح إذن Shizuku — التجهيز مفتوح الآن.';

  @override
  String get permissionNotGrantedYetMsg =>
      'لم يُمنح الإذن بعد. وافق على عزم في Shizuku ثم اضغط طلب مجدداً.';

  @override
  String get noStoreOpenedMsg => 'تعذّر فتح أي متجر أو متصفح لصفحة Shizuku.';

  @override
  String get shizukuDetectedMsg => 'تم اكتشاف Shizuku.';

  @override
  String get deviceOwnerTitle => 'مالك الجهاز';

  @override
  String get deviceOwnerYes => 'تطبيق عزم هو مالك هذا الجهاز.';

  @override
  String deviceOwnerNo(String admin) {
    return 'غير مجهّز. معظم القيود تحتاج مالك الجهاز. المسؤول نشط: $admin.';
  }

  @override
  String accountsNote(int count) {
    return 'ملاحظة: تم اكتشاف $count حساب. التجهيز عبر Shizuku يعمل عادةً رغم ذلك، لكن إزالة الحسابات أولاً هي المسار الذي يوصي به التطبيق الأصلي.';
  }

  @override
  String get becomeDeviceOwner => 'كن مالك الجهاز عبر Shizuku';

  @override
  String get provisioningUnlocksNote =>
      'يُفتح التجهيز عندما يعمل Shizuku ويُمنح الإذن.';

  @override
  String pathUsed(String path) {
    return 'المسار المستخدم: $path';
  }

  @override
  String get accessibilityService => 'خدمة إمكانية الوصول';

  @override
  String get a11yUnknown => 'غير معروف';

  @override
  String get a11yRunning => 'مُفعّلة وتعمل — الإنفاذ جارٍ.';

  @override
  String get a11yBinding => 'مُفعّلة لكنها لا تعمل بعد (جارٍ الربط).';

  @override
  String get a11yOff =>
      'مُعطّلة. إيقافها لاحقاً يعلّق كل تطبيق خاضع للتحكم (إغلاق مضاد للتجاوز).';

  @override
  String get wssTitle => 'إذن نظام إضافي';

  @override
  String get wssGrantedText => 'ممنوح (تم التحقق بإعادة الفحص).';

  @override
  String get wssPurpose =>
      'يمنح إذن WRITE_SECURE_SETTINGS اللازم لأوضاع الألوان (v1.1). يُمنح عبر Shizuku ويُتحقق منه بإعادة الفحص؛ الحالة المعروضة هنا تُقرأ عند كل تحديث.';

  @override
  String get granted => 'ممنوح';

  @override
  String get granting => 'جارٍ المنح…';

  @override
  String get grant => 'منح';

  @override
  String get wssGrantedMsg => 'إذن WRITE_SECURE_SETTINGS ممنوح.';

  @override
  String get wssStillNotGrantedMsg =>
      'إذن WRITE_SECURE_SETTINGS ما زال غير ممنوح. يجب أن يعمل Shizuku مع منح الإذن أولاً.';

  @override
  String get diagnosticsTitle => 'تشخيصات التجهيز';

  @override
  String get diagnosticsSubtitle =>
      'الحسابات والمستخدمون الإضافيون ومالك الجهاز الحالي — هذه قد تمنع التجهيز.';

  @override
  String get runDiagnostics => 'تشغيل التشخيصات';

  @override
  String diagAccounts(int count) {
    return 'الحسابات ($count)';
  }

  @override
  String get diagNoAccounts => 'لم يتم العثور على حسابات — جيد للتجهيز.';

  @override
  String diagUsers(int count) {
    return 'المستخدمون ($count)';
  }

  @override
  String get diagOnlyPrimaryUser => 'المستخدم الرئيسي فقط.';

  @override
  String get diagCurrentOwner => 'مالك الجهاز الحالي';

  @override
  String get diagNone => 'لا شيء';

  @override
  String get blockerExtraUsersTitle => 'التجهيز محظور: مستخدمون إضافيون';

  @override
  String blockerExtraUsersBody(String names) {
    return 'يحتوي هذا الجهاز على مستخدمين أو ملفات إضافية: $names.\n\nلا يستطيع أندرويد تجهيز مالك جهاز أثناء وجود مستخدمين آخرين. أزل المستخدمين/الملفات الإضافية (الإعدادات ← المستخدمون)، ثم عد إلى هنا وحدّث. يطابق هذا التطبيق الأصلي الذي يستبدل زر التجهيز بهذا التحذير.';
  }

  @override
  String get blockerOtherOwnerTitle => 'التجهيز محظور: مالك جهاز آخر';

  @override
  String blockerOtherOwnerBody(String packageName, String receiver) {
    return 'تطبيق $packageName هو مالك هذا الجهاز بالفعل ($receiver).\n\nلا يمكن أن يكون للجهاز أكثر من مالك واحد. يجب أن يتنازل ذلك التطبيق عن الملكية (أو إعادة ضبط الجهاز إلى المصنع) قبل أن يمكن تجهيز عزم. يطابق هذا التطبيق الأصلي الذي يستبدل زر التجهيز بهذا التحذير.';
  }

  @override
  String userIdSuffix(String name, int id) {
    return '$name (المعرّف $id)';
  }

  @override
  String get setupAppBarTitle => 'الإعداد';

  @override
  String get setupTileTitle => 'الإعداد ومالك الجهاز';

  @override
  String get checking => 'جارٍ التحقق…';

  @override
  String get provisionedAsOwner => 'مجهّز كمالك للجهاز';

  @override
  String get notOwnerOpenSetup => 'ليس مالك الجهاز — افتح الإعداد';

  @override
  String get privateDns => 'DNS الخاص';

  @override
  String get dnsCouldNotRead => 'تعذّرت قراءة حالة DNS الحالية';

  @override
  String get dnsRequiresOwner => 'يتطلب مالك الجهاز';

  @override
  String dnsForcedHost(String host) {
    return 'المضيف المفروض: $host';
  }

  @override
  String dnsMode(String mode) {
    return 'الوضع: $mode';
  }

  @override
  String get dnsRequiresOwnerSnack =>
      'يتطلب DNS الخاص مالك الجهاز — أكمل الإعداد أولاً.';

  @override
  String get browserRestrictions => 'قيود المتصفح';

  @override
  String get browserRestrictionsSub =>
      'قوائم حظر URL وبحث آمن في المتصفحات الداعمة';

  @override
  String get blockedWords => 'الكلمات المحظورة';

  @override
  String get blockedWordsSub => 'حظر كلمات نشط وعلى الشاشة لكل تطبيق';

  @override
  String get impulseLock => 'قفل النزوات';

  @override
  String get impulseLockSub =>
      'قفل الذعر والتحديات وخيارات لوحة مفاتيح الاسترداد';

  @override
  String get focusMode => 'وضع التركيز';

  @override
  String get focusModeSub => 'جلسات بومودورو تعلّق التطبيقات المختارة';

  @override
  String get usageWarnings => 'تحذيرات الاستخدام';

  @override
  String get usageWarningsSub => 'تحذيرات متدرجة قبل انتهاء الحد الزمني';

  @override
  String get suspensionLogs => 'سجلات التعليق';

  @override
  String get suspensionLogsSub => 'سجل تدقيق لكل عملية تعليق';

  @override
  String get colourModes => 'أوضاع الألوان';

  @override
  String get colourModesNote =>
      'التدرج الرمادي المجدول والإضاءة الليلية والتعتيم الإضافي قادمة في v1.1 (منح WRITE_SECURE_SETTINGS اللازم لها موجود في شاشة الإعداد).';

  @override
  String get activityBlocker => 'حاجب الأنشطة';

  @override
  String get activityBlockerNote => 'حظر شاشات نشاط محددة قادم في v1.1.';

  @override
  String get language => 'اللغة';

  @override
  String get languageDialogTitle => 'اللغة';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageSaved => 'تم حفظ اللغة.';

  @override
  String get theme => 'المظهر';

  @override
  String get themeSystem => 'افتراضي النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get changeRecoveryCode => 'تغيير رمز الاسترداد';

  @override
  String get changeRecoveryCodeSub =>
      'يتطلب جلسة استرداد؛ الرمز القديم يتوقف عن العمل';

  @override
  String get recoveryCodeChanged => 'تم تغيير رمز الاسترداد.';

  @override
  String get dangerZone => 'منطقة الخطر';

  @override
  String get removeOwnerNow => 'إزالة مالك الجهاز الآن';

  @override
  String get removeOwnerNowSub =>
      'إزالة فورية، داخل جلسة استرداد — كل قيد يفرضه هذا التطبيق يتوقف فوراً.';

  @override
  String get forcedRemoval48 => 'الإزالة القسرية بعد 48 ساعة';

  @override
  String get forcedIdleSub =>
      'المخرج الوحيد بلا رمز: بعد 48 ساعة يمكن إزالة مالك الجهاز دون رمز الاسترداد.';

  @override
  String get forcedCompleteSub => 'اكتمل — يمكن إنهاء الإزالة الآن دون رمز.';

  @override
  String forcedProgressSub(String remaining) {
    return 'جارٍ — تبقّى $remaining (يتقدم أثناء عمل التطبيق)';
  }

  @override
  String get startForcedRemoval => 'بدء الإزالة القسرية';

  @override
  String get cancelForcedRemoval => 'إلغاء الإزالة القسرية';

  @override
  String get finishRemoval => 'إنهاء الإزالة';

  @override
  String get startForcedTitle => 'بدء الإزالة القسرية؟';

  @override
  String get startForcedBody =>
      'يبدأ هذا عدًّا تنازليًا مدته 48 ساعة. عند انتهائه يمكن إزالة مالك الجهاز — ومعه كل قيد يفرضه هذا التطبيق — دون رمز الاسترداد. إنه المهرب الوحيد دون رمز، ويمكن إلغاؤه في أي وقت قبل اكتماله.';

  @override
  String get cancelForcedTitle => 'إلغاء الإزالة القسرية؟';

  @override
  String get cancelForcedBody =>
      'سيتم التخلص من العد التنازلي لـ 48 ساعة. ستتطلب إزالة مالك الجهاز رمز الاسترداد من جديد.';

  @override
  String get finishForcedTitle => 'إنهاء الإزالة القسرية؟';

  @override
  String get finishForcedBody =>
      'اكتمل انتظار 48 ساعة. إزالة مالك الجهاز الآن ترفع كل قيد يفرضه هذا التطبيق على هذا الجهاز.';

  @override
  String get understandRemovesAll => 'أفهم أن هذا يزيل كل الحماية';

  @override
  String get removeDeviceOwnerAction => 'إزالة مالك الجهاز';

  @override
  String get deviceOwnerRemovedVerified => 'تمت إزالة مالك الجهاز (تم التحقق).';

  @override
  String get removalCompleteTitle => 'أُزيلت الحماية بالكامل';

  @override
  String get removalCompleteBody =>
      'أُزيلت حماية عزم بالكامل: لم تبقَ أي قيود، ولا يوجد تطبيق موقوف أو مخفي بواسطة عزم، ولا شيء من عزم ما زال يعمل. يمكنك الآن إلغاء التثبيت بشكل طبيعي من إعدادات النظام.';

  @override
  String get removalPartialTitle => 'أُزيلت الحماية مع تنبيهات';

  @override
  String get removalPartialBody =>
      'أُزيل مالك الجهاز، لكن بعض خطوات التنظيف لم تكتمل. يمكنك إعادة المحاولة، أو إلغاء التثبيت بشكل طبيعي — إذ يتخلّص أندرويد من أي سياسات متبقية لمالك الجهاز عند إلغاء تثبيت التطبيق.';

  @override
  String get removalStepDisarm => 'تعطيل وسائل الحماية';

  @override
  String get removalStepFocus => 'إيقاف وضع التركيز';

  @override
  String get removalStepUnsuspend => 'إلغاء إيقاف التطبيقات';

  @override
  String get removalStepRestrictions => 'مسح القيود';

  @override
  String get removalStepUnhide => 'إظهار التطبيقات';

  @override
  String get removalStepUninstallBlocks => 'رفع حظر إلغاء التثبيت';

  @override
  String get removalStepAppRestrictions => 'مسح قيود التطبيقات';

  @override
  String get removalStepClearOwner => 'إزالة مالك الجهاز';

  @override
  String get dnsSettingsTitle => 'إعدادات DNS الخاص';

  @override
  String get dnsCustom => 'مخصص';

  @override
  String get dnsHostnameLabel => 'اسم مضيف DNS';

  @override
  String get dnsHostnameHint => 'dns.example.com';

  @override
  String get dnsInvalidHostname => 'اسم مضيف DNS غير صالح';

  @override
  String get apply => 'تطبيق';

  @override
  String get dnsTimeoutError =>
      'انتهت مهلة تطبيق مضيف DNS. تحقق من حالة DNS الحالية قبل إعادة المحاولة.';

  @override
  String get dnsNotServingError => 'مضيف DNS المختار لا يخدم. اختر مضيفاً آخر.';

  @override
  String get dnsApplyFailedError => 'فشل تطبيق مضيف DNS الخاص.';

  @override
  String dnsAppliedVerified(String host) {
    return 'فُرض DNS الخاص إلى $host (تم التحقق).';
  }

  @override
  String get newBlocklist => 'قائمة حظر جديدة';

  @override
  String get editBlocklist => 'تحرير قائمة الحظر';

  @override
  String get titleLabel => 'العنوان';

  @override
  String get sitesLabel => 'المواقع، واحد في كل سطر (مثال: example.com)';

  @override
  String appliedToBrowsers(int count) {
    return 'تم التطبيق على $count متصفح وتم التحقق.';
  }

  @override
  String get supportingBrowsers => 'المتصفحات الداعمة';

  @override
  String get noSupportingBrowser =>
      'لا يصرّح أي متصفح مثبّت بـ URLBlocklist في قيوده المُدارة، فلا توجد سياسة لدفعها. المتصفحات غير الداعمة تُعالج بقواعد التعليق (التعليق التلقائي v1.1).';

  @override
  String get blocklists => 'قوائم الحظر';

  @override
  String get noBlocklists =>
      'لا توجد قوائم حظر بعد. أنشئ واحدة لبدء حظر المواقع.';

  @override
  String sitesCount(int count) {
    return '$count موقع';
  }

  @override
  String get applyBlocklists => 'تطبيق قوائم الحظر على المتصفحات';

  @override
  String get loadingBlocklists => 'جارٍ تحميل قوائم الحظر…';

  @override
  String get activeBlockingWords => 'كلمات الحظر النشطة';

  @override
  String get oneWordPerLine => 'كلمة أو عبارة في كل سطر';

  @override
  String get appsWhereWordsBlock => 'التطبيقات التي تحظر فيها الكلمات النشطة';

  @override
  String onScreenWordsFor(String app) {
    return 'كلمات الشاشة لتطبيق $app';
  }

  @override
  String get loadingBlockedWords => 'جارٍ تحميل الكلمات المحظورة…';

  @override
  String get activeBlockingSection => 'الحظر النشط (F14)';

  @override
  String get activeBlockingBody =>
      'عندما توجد كلمة في حقل نص تطبيق مختار وتنتهي الكتابة، يخرج التطبيق منه وتظهر شاشة حظر.';

  @override
  String wordsCount(int count) {
    return '$count كلمة';
  }

  @override
  String targetAppsCount(int count) {
    return '$count تطبيق مستهدف';
  }

  @override
  String get passiveBlockingSection => 'الحظر السلبي (F15)';

  @override
  String get passiveBlockingBody =>
      'كلمات تظهر في أي مكان على الشاشة في تطبيق محدد.';

  @override
  String get noPerAppLists => 'لا توجد قوائم لكل تطبيق بعد.';

  @override
  String get addTargetAppsFirst =>
      'أضف التطبيقات المستهدفة أعلاه أولاً — القوائم السلبية ترتبط بها في v1.';

  @override
  String get addPerAppList => 'إضافة قائمة لكل تطبيق';

  @override
  String get loadingWarningStages => 'جارٍ تحميل مراحل التحذير…';

  @override
  String get stagedWarningsTitle => 'تحذيرات متدرجة قبل انتهاء الحد';

  @override
  String get warningsBody =>
      'تحذّر كل مرحلة مرة واحدة، قبل نفاد حد التطبيق اليومي بعدد الدقائق المضبوط. تُحفظ المراحل لتشغّلها خدمة إمكانية الوصول؛ توصيل الإشعارات يعتمد على المنبّه الأصلي.';

  @override
  String get noWarningStages =>
      'لا توجد مراحل تحذير. أضف مرحلة واحدة على الأقل وإلا فلن تظهر أي تحذيرات.';

  @override
  String get addStage => 'إضافة مرحلة';

  @override
  String get minutesBeforeLabel => 'الدقائق قبل';

  @override
  String get removeStage => 'إزالة المرحلة';

  @override
  String get silent => 'صامت';

  @override
  String get sound => 'صوت';

  @override
  String get vibrate => 'اهتزاز';

  @override
  String get vibrationCount => 'عدد الاهتزازات';

  @override
  String get clearLogsTooltip => 'مسح السجلات (تتطلب جلسة استرداد)';

  @override
  String get searchLogs => 'بحث في السجلات';

  @override
  String get loadingLogs => 'جارٍ تحميل السجلات…';

  @override
  String get noSuspensionsLogged => 'لم تُسجَّل أي عمليات تعليق.';

  @override
  String get impulseLockTitle => 'قفل الاندفاع';

  @override
  String get loadingImpulseLock => 'جارٍ تحميل قفل النزوات…';

  @override
  String impulseActiveTitle(String remaining) {
    return 'قفل النزوات مفعّل — تبقّى $remaining';
  }

  @override
  String get impulseActiveBody =>
      'كما في الأصل، لا إيقاف مبكر للقفل: ينتهي من تلقاء نفسه بنفاد المؤقّت، وتُحرَّر التطبيقات التي علّقها عندها.';

  @override
  String startImpulseLockFor(int minutes) {
    return 'بدء قفل النزوات ($minutes دقيقة)';
  }

  @override
  String get settingsLockedTitle => 'الإعدادات مقفلة';

  @override
  String get settingsLockedBody =>
      'لا يمكن تغيير إعدادات قفل النزوات إلا أثناء جلسة استرداد. اضغط لفتح واحدة.';

  @override
  String get configurationSection => 'الضبط';

  @override
  String get durationLabel => 'المدة';

  @override
  String durationSubtitle(int minutes) {
    return '$minutes دقيقة (15–360)';
  }

  @override
  String minutesSliderLabel(int minutes) {
    return '$minutes د';
  }

  @override
  String get timerOnly => 'مؤقّت فقط';

  @override
  String get timerAndSuspend => 'مؤقّت + تعليق التطبيقات المختارة';

  @override
  String appsToSuspendCount(int count) {
    return '$count تطبيق للتعليق';
  }

  @override
  String get accessChallengesTitle => 'تحديات الوصول';

  @override
  String get accessChallengesBody =>
      'هذه التحديات تخصّ قفل الاندفاع فقط. رمز الاسترداد وحده يفتح جلسة الاسترداد — ولا تُطلب أي تحديات بعده.';

  @override
  String get challengeUnavailableNote =>
      'غير متاح في هذا الإصدار — v1.1. يمكن اختياره في الضبط المحفوظ لكنه يُتخطى، ولا يُحاكى أبداً.';

  @override
  String get shuffledKeypadTitle => 'لوحة مفاتيح مخلوطة لرمز الاسترداد';

  @override
  String get shuffledKeypadSub =>
      'حتى لا يُتعلَّم الرمز من مواضع الأصابع (F24).';

  @override
  String customPhrasesCount(int count) {
    return '$count عبارة قراءة مخصصة';
  }

  @override
  String get customPhrasesSub => 'تُضاف إلى مقاطع القراءة المدمجة';

  @override
  String get customReadingPhrases => 'عبارات قراءة مخصصة';

  @override
  String get onePhrasePerLine => 'عبارة في كل سطر (كلماتك الخاصة)';

  @override
  String get appsSuspendedDuringImpulse =>
      'التطبيقات المعلّقة أثناء قفل النزوات';

  @override
  String get focusModeTitle => 'وضع التركيز';

  @override
  String get loadingFocusMode => 'جارٍ تحميل وضع التركيز…';

  @override
  String get phaseNotStarted => 'لم يبدأ';

  @override
  String get phaseFocusing => 'جارٍ التركيز';

  @override
  String get phaseBreak => 'استراحة';

  @override
  String get phaseLongBreak => 'استراحة طويلة';

  @override
  String get phaseWaiting => 'بانتظار';

  @override
  String get phasePaused => 'متوقف مؤقتاً';

  @override
  String get phaseDone => 'انتهى';

  @override
  String ringIdleSummary(int focus, int breakTime) {
    return 'تركيز $focus د · استراحة $breakTime د';
  }

  @override
  String get waitingNextFocus => 'بانتظار بدء التركيز التالي';

  @override
  String cycleOf(int current, int total) {
    return 'الدورة $current من $total';
  }

  @override
  String completedFocusPeriods(int count) {
    return 'فترات التركيز المكتملة: $count';
  }

  @override
  String get start => 'بدء';

  @override
  String get startFocusBtn => 'بدء التركيز';

  @override
  String get endSessionBtn => 'إنهاء الجلسة';

  @override
  String get pauseBtn => 'إيقاف مؤقت';

  @override
  String get endRecoveryBtn => 'إنهاء (الاسترداد)';

  @override
  String get resumeBtn => 'استئناف';

  @override
  String get skipBreakBtn => 'تخطي الاستراحة';

  @override
  String get focusWaitingBody =>
      'انتهت الاستراحة. لا شيء معلّق أثناء الانتظار — ابدأ التركيز التالي عندما تكون جاهزاً، أو أنهِ الجلسة.';

  @override
  String get focusFocusBody =>
      'الإيقاف المؤقت مجاني ما دامت التطبيقات معلّقة. اضغط طويلاً على إيقاف مؤقت لتحريرها بدلاً من ذلك (تتطلب جلسة استرداد).';

  @override
  String get focusDefaultBody =>
      'تحتفظ خدمة التركيز الأصلية بالجلسة: تنجو من إغلاق هذا التطبيق، وتحتفظ بتعليقاتها بين المراحل، وهذه الشاشة تعكسها.';

  @override
  String get durationsSection => 'المدد';

  @override
  String get focusMinutesLabel => 'دقائق التركيز';

  @override
  String get breakMinutesLabel => 'دقائق الاستراحة';

  @override
  String get longBreakMinutesLabel => 'دقائق الاستراحة الطويلة';

  @override
  String get cyclesLabel => 'الدورات قبل الاستراحة الطويلة';

  @override
  String get autoStartTitle => 'بدء التركيز التالي تلقائياً';

  @override
  String get autoStartSub =>
      'بدء مرحلة التركيز التالية من تلقاء نفسها عند انتهاء الاستراحة؛ وإلا تنتظر الجلسة. إيقافه تخفيف.';

  @override
  String get soundTitle => 'الصوت';

  @override
  String get soundSub => 'تشغيل صوت عند تغيّر المراحل.';

  @override
  String get vibrationTitle => 'الاهتزاز';

  @override
  String get vibrationSub => 'الاهتزاز عند تغيّر المراحل.';

  @override
  String get suspendedWhileFocusing => 'المعلّق أثناء التركيز';

  @override
  String appsSuspendedWhileFocusing(int count) {
    return '$count تطبيق معلّق أثناء التركيز';
  }

  @override
  String groupsSuspendedWhileFocusing(int count) {
    return '$count مجموعة معلّقة أثناء التركيز';
  }

  @override
  String restrictionsAppliedWhileFocusing(int count) {
    return '$count قيد مطبّق أثناء التركيز';
  }

  @override
  String get focusSchedulesTitle => 'جداول التركيز والتذكيرات';

  @override
  String get focusSchedulesNote =>
      'الجلسات ذات البدء التلقائي المجدول ليست في هذا الإصدار.';

  @override
  String get appsToSuspendWhileFocusing => 'التطبيقات المُعلّقة أثناء التركيز';

  @override
  String get groupsToSuspendWhileFocusing => 'المجموعات المعلّقة أثناء التركيز';

  @override
  String get noGroupsYet => 'لا توجد مجموعات بعد';

  @override
  String groupAppsCount(int count) {
    return '$count تطبيق';
  }

  @override
  String get restrictionsDuringFocus => 'القيود أثناء التركيز';

  @override
  String get noDeviceOwnerPrivileges => 'لا توجد صلاحيات مالك الجهاز';

  @override
  String get noOwnerBody =>
      'تعمل قيود النظام فقط بينما عزم هو مالك الجهاز. أكمل تدفق الإعداد أولاً — القيود لا تُزيَّف بدونه.';

  @override
  String get openSetup => 'فتح الإعداد';

  @override
  String get restrictionsUpdatedVerified => 'تم تحديث القيود والتحقق منها.';

  @override
  String get searchRestrictions => 'بحث في القيود';

  @override
  String get loadingRestrictions => 'جارٍ تحميل القيود…';

  @override
  String get recommendedSection => 'موصى بها';

  @override
  String get otherRestrictionsSection => 'قيود أخرى';

  @override
  String get changedNotApplied => 'تم التغيير — لم يُطبَّق بعد';

  @override
  String get applying => 'جارٍ التطبيق…';

  @override
  String get applyChanges => 'تطبيق التغييرات';

  @override
  String get activeBadge => 'نشط';

  @override
  String get searchApps => 'بحث في التطبيقات';

  @override
  String get includeSystemApps => 'تضمين تطبيقات النظام';

  @override
  String get appGroups => 'مجموعات التطبيقات';

  @override
  String get appGroupsSub => 'حدود ونوافذ مشتركة لمجموعة تطبيقات';

  @override
  String get loadingInstalledApps => 'جارٍ تحميل التطبيقات المثبّتة…';

  @override
  String get noAppsMatch =>
      'لا توجد تطبيقات مطابقة. جرّب بحثاً مختلفاً، أو ضمّن تطبيقات النظام.';

  @override
  String get stateSystem => 'نظام';

  @override
  String get stateHidden => 'مخفي';

  @override
  String get stateSuspended => 'معلّق';

  @override
  String get stateUninstallBlocked => 'إلغاء التثبيت محظور';

  @override
  String usedTodaySuffix(String duration) {
    return 'استُخدم $duration اليوم';
  }

  @override
  String get suspendedTitle => 'معلّق';

  @override
  String get suspendedSub => 'لا يمكن فتح التطبيق أثناء تعليقه.';

  @override
  String get hiddenTitle => 'مخفي';

  @override
  String get hiddenSub => 'مُزال من المشغّل وقائمة التطبيقات.';

  @override
  String get uninstallBlockedTitle => 'إلغاء التثبيت محظور';

  @override
  String suspensionEnabledFor(String app) {
    return 'تم تفعيل التعليق لتطبيق $app';
  }

  @override
  String hidingEnabledFor(String app) {
    return 'تم تفعيل الإخفاء لتطبيق $app';
  }

  @override
  String uninstallBlockEnabledFor(String app) {
    return 'تم تفعيل حظر إلغاء التثبيت لتطبيق $app';
  }

  @override
  String timeLimitUpdatedFor(String app) {
    return 'تم تحديث الحد الزمني لتطبيق $app';
  }

  @override
  String timeWindowsUpdatedFor(String app) {
    return 'تم تحديث النوافذ الزمنية لتطبيق $app';
  }

  @override
  String groupMembersUpdated(String group) {
    return 'تم تحديث أعضاء $group';
  }

  @override
  String groupLimitUpdated(String group) {
    return 'تم تحديث حد $group';
  }

  @override
  String restrictionsUpdatedFor(String app) {
    return 'تم تحديث القيود لتطبيق $app';
  }

  @override
  String get timeLimitTile => 'الحد الزمني';

  @override
  String get loadingEllipsis => 'جارٍ التحميل…';

  @override
  String todayLimit(String limit) {
    return 'اليوم: $limit';
  }

  @override
  String get perWeekdaySuffix => ' (لكل يوم)';

  @override
  String get noLimitSet => 'لا يوجد حد مضبوط';

  @override
  String get allowedWindowsTile => 'النوافذ الزمنية المسموحة';

  @override
  String windowsCount(int count) {
    return '$count نافذة';
  }

  @override
  String get usableAnyTime => 'قابل للاستخدام في أي وقت';

  @override
  String get managedRestrictionsTile => 'القيود المُدارة';

  @override
  String get managedRestrictionsSub =>
      'تحرير ضبط هذا التطبيق المُدار المُصرّح به';

  @override
  String get timeLimitDialogTitle => 'الحد الزمني (بالدقائق)';

  @override
  String get dailySegment => 'يومي';

  @override
  String get perWeekdaySegment => 'لكل يوم';

  @override
  String get minutesPerDayLabel => 'الدقائق في اليوم (0 = بلا حد)';

  @override
  String dayNoLimit(String day) {
    return '$day (0 = بلا حد)';
  }

  @override
  String get reopenLabel =>
      'مهلة إعادة الفتح، بالثواني (تُحفظ؛ الإنفاذ في v1.1)';

  @override
  String get dayMon => 'الإثنين';

  @override
  String get dayTue => 'الثلاثاء';

  @override
  String get dayWed => 'الأربعاء';

  @override
  String get dayThu => 'الخميس';

  @override
  String get dayFri => 'الجمعة';

  @override
  String get daySat => 'السبت';

  @override
  String get daySun => 'الأحد';

  @override
  String get allowedWindowsTitle => 'النوافذ المسموحة (يومياً)';

  @override
  String get windowsBody =>
      'خارج هذه النوافذ يكون التطبيق محظوراً. القائمة الفارغة تعني قابلاً للاستخدام في أي وقت.';

  @override
  String get noWindowsSet => 'لا توجد نوافذ مضبوطة.';

  @override
  String get addWindow => 'إضافة نافذة';

  @override
  String get windowStartHelp => 'بداية النافذة';

  @override
  String get windowEndHelp => 'نهاية النافذة (قد تكون في اليوم التالي)';

  @override
  String get appGroupsTitle => 'مجموعات التطبيقات';

  @override
  String get newGroupTooltip => 'مجموعة جديدة';

  @override
  String get loadingGroups => 'جارٍ تحميل المجموعات…';

  @override
  String get noGroupsYetEmpty =>
      'لا توجد مجموعات بعد. أنشئ واحدة لمشاركة حد عبر التطبيقات.';

  @override
  String get newGroup => 'مجموعة جديدة';

  @override
  String get groupNameLabel => 'اسم المجموعة';

  @override
  String get create => 'إنشاء';

  @override
  String get renameGroup => 'إعادة تسمية المجموعة';

  @override
  String groupAppsLimitLine(int count, String limit) {
    return '$count تطبيق · الحد $limit';
  }

  @override
  String get editMembers => 'تحرير الأعضاء';

  @override
  String get editLimit => 'تحرير الحد';

  @override
  String get renameGroupAction => 'إعادة تسمية المجموعة';

  @override
  String get deleteGroup => 'حذف المجموعة';

  @override
  String membersOf(String group) {
    return 'أعضاء $group';
  }

  @override
  String restrictionsForApp(String app) {
    return 'القيود — $app';
  }

  @override
  String get loadingDeclaredRestrictions => 'جارٍ تحميل القيود المُصرّح بها…';

  @override
  String noRestrictionsForApp(String app) {
    return 'لا توجد قيود متاحة لتطبيق $app. هذا التطبيق لا يصرّح بأي قيود مُدارة.';
  }

  @override
  String get clearAllRestrictions => 'مسح كل القيود';

  @override
  String clearAllBody(String app) {
    return 'إزالة كل قيد مُدار لتطبيق $app؟ هذا يحرّر المسودة فقط — اضغط حفظ للتطبيق.';
  }

  @override
  String get unsavedChangesTitle => 'تغييرات غير محفوظة';

  @override
  String get unsavedChangesBody => 'لديك تغييرات قيود غير محفوظة. أتهملها؟';

  @override
  String get keepEditing => 'متابعة التحرير';

  @override
  String get discard => 'إهمال';

  @override
  String get allFilter => 'الكل';

  @override
  String activeFilterCount(int count) {
    return 'نشط ($count)';
  }

  @override
  String defaultFilterCount(int count) {
    return 'افتراضي ($count)';
  }

  @override
  String noRestrictionsMatching(String query) {
    return 'لا قيود مطابقة لـ \"$query\"';
  }

  @override
  String noRestrictionsAvailableFor(String app) {
    return 'لا توجد قيود متاحة لتطبيق $app';
  }

  @override
  String get savingEllipsis => 'جارٍ الحفظ…';

  @override
  String get saveRestrictions => 'حفظ القيود';

  @override
  String get seeMore => 'عرض المزيد';

  @override
  String get seeLess => 'عرض أقل';

  @override
  String get enabledLabel => 'مفعّل';

  @override
  String get disabledLabel => 'معطّل';

  @override
  String unsupportedRestrictionType(String type) {
    return 'نوع قيد غير مدعوم: $type';
  }

  @override
  String get removeValue => 'إزالة القيمة';

  @override
  String get addValueLabel => 'إضافة قيمة';

  @override
  String get addValueTooltip => 'إضافة قيمة';

  @override
  String itemNumber(int number) {
    return 'عنصر $number';
  }

  @override
  String get removeItem => 'إزالة العنصر';

  @override
  String get addItem => 'إضافة عنصر';

  @override
  String get brandTagline => 'اكسر القيد';

  @override
  String get lockedTitle => 'عزم مقفل';

  @override
  String get startFocusAction => 'بدء التركيز';

  @override
  String get skipBreakAction => 'تخطي الاستراحة';

  @override
  String get pauseAction => 'إيقاف مؤقت';

  @override
  String get resumeAction => 'استئناف';

  @override
  String focusCycleTitle(int current, int total) {
    return 'التركيز $current/$total';
  }

  @override
  String get focusPausedSuffix => ' · متوقف مؤقتًا';

  @override
  String get focusShortBreak => 'استراحة قصيرة';

  @override
  String get focusLongBreak => 'استراحة طويلة';

  @override
  String get focusBreakOver => 'انتهت الاستراحة';

  @override
  String focusSuspendingSummary(int minutes) {
    return '$minutes دقيقة من التركيز، مع تعليق التطبيقات المحددة';
  }

  @override
  String get groupsSection => 'المجموعات';

  @override
  String get appsSection => 'التطبيقات';

  @override
  String get gateBody => 'أدخل رمز الاسترداد لفتح جلسة مدتها 10 دقائق.';

  @override
  String provisionOutput(String path, String output) {
    return 'المسار المستخدم: $path\n$output';
  }

  @override
  String get noStoreMsg => 'تعذّر فتح أي متجر أو متصفح لصفحة Shizuku.';

  @override
  String get setupAndOwner => 'الإعداد ومالك الجهاز';

  @override
  String get setupTitle => 'الإعداد';

  @override
  String get dnsNeedsOwnerMsg =>
      'يتطلب DNS الخاص مالك الجهاز — أكمل الإعداد أولًا.';

  @override
  String get forcedRemovalTitle => 'الإزالة القسرية بعد 48 ساعة';

  @override
  String forcedInProgressSub(String remaining) {
    return 'جارٍ — تبقّى $remaining (يتقدّم أثناء تشغيل التطبيق)';
  }

  @override
  String get dnsApplyTimeout =>
      'انتهت مهلة تطبيق مضيف DNS. تحقق من حالة DNS الحالية قبل إعادة المحاولة.';

  @override
  String get dnsNotServing => 'مضيف DNS المختار لا يستجيب. اختر مضيفًا آخر.';

  @override
  String get dnsApplyFailed => 'فشل تطبيق مضيف DNS الخاص.';

  @override
  String dnsAppliedMsg(String host) {
    return 'تم فرض DNS الخاص على $host (تم التحقق).';
  }

  @override
  String get ownerStillActiveMsg => 'ما زال مالك الجهاز نشطًا بعد الإزالة';

  @override
  String get noCapableBrowser =>
      'لا يعلن أي متصفح مثبّت عن URLBlocklist في قيوده المُدارة، فلا يوجد ما تُدفع إليه السياسة. المتصفحات غير الداعمة تُعالج بقواعد التعليق (التعليق التلقائي في v1.1).';

  @override
  String get blocklistsSection => 'قوائم الحظر';

  @override
  String get noBlocklistsYet =>
      'لا قوائم حظر بعد. أنشئ واحدة لبدء حظر المواقع.';

  @override
  String get usageWarningsBody =>
      'تحذّر كل مرحلة مرة واحدة قبل انتهاء الحد اليومي للتطبيق بعدد الدقائق المضبوط. تُحفظ المراحل لتطلقها خدمة إمكانية الوصول؛ ويعتمد وصول الإشعار على المُشعِر الأصلي.';

  @override
  String get removeStageTooltip => 'إزالة المرحلة';

  @override
  String get vibrationCountLabel => 'عدد الاهتزازات';

  @override
  String get noLogsYet => 'لم تُسجَّل أي عمليات تعليق.';

  @override
  String impulseActiveLeft(String time) {
    return 'قفل الاندفاع نشط — تبقّى $time';
  }

  @override
  String get impulseNoEarlyStop =>
      'كما في الأصل، لا إيقاف مبكرًا للقفل: ينتهي من تلقاء نفسه عند انتهاء المؤقّت، وتُحرَّر حينها التطبيقات التي علّقها.';

  @override
  String startImpulseLock(int minutes) {
    return 'بدء قفل الاندفاع ($minutes دقيقة)';
  }

  @override
  String get settingsLocked => 'الإعدادات مقفلة';

  @override
  String get settingsLockedSub =>
      'لا يمكن تغيير إعدادات قفل الاندفاع إلا أثناء جلسة استرداد. اضغط لفتح واحدة.';

  @override
  String durationMinutes(int minutes) {
    return '$minutes دقيقة (15–360)';
  }

  @override
  String minutesShort(int minutes) {
    return '$minutes د';
  }

  @override
  String get accessChallengesSection => 'تحديات الوصول';

  @override
  String get shuffledKeypad => 'لوحة مفاتيح مخلوطة لرمز الاسترداد';

  @override
  String focusIdleSummary(int focus, int breakTime) {
    return '$focus د تركيز · $breakTime د استراحة';
  }

  @override
  String get startAction => 'ابدأ';

  @override
  String get endRecovery => 'إنهاء (الاسترداد)';

  @override
  String get waitingBody =>
      'انتهت الاستراحة. لا شيء معلّق أثناء الانتظار — ابدأ التركيز التالي عندما تكون جاهزًا، أو أَنهِ الجلسة.';

  @override
  String get focusPauseNote =>
      'الإيقاف المؤقت مجاني بينما تبقى التطبيقات معلّقة. اضغط مطولًا على إيقاف مؤقت لتحريرها بدلًا من ذلك (يتطلب جلسة استرداد).';

  @override
  String get focusNativeNote =>
      'تحتفظ خدمة التركيز الأصلية بالجلسة: تنجو من إغلاق التطبيق، وتحافظ على تعليقاتها بين المراحل، وهذه الشاشة تعكسها.';

  @override
  String groupsSuspendedCount(int count) {
    return '$count مجموعة معلّقة أثناء التركيز';
  }

  @override
  String restrictionsAppliedCount(int count) {
    return '$count قيد مطبّق أثناء التركيز';
  }

  @override
  String memberCount(int count) {
    return '$count تطبيق';
  }

  @override
  String get noOwnerRestrictionsBody =>
      'تعمل قيود النظام فقط بينما عزم هو مالك الجهاز. أكمل خطوات الإعداد أولًا — لا تُزيَّف القيود بدونه.';

  @override
  String get restrictionsUpdated => 'تم تحديث القيود والتحقق منها.';

  @override
  String usedToday(String time) {
    return 'استُخدم $time اليوم';
  }

  @override
  String get badgeSystem => 'نظام';

  @override
  String get badgeHidden => 'مخفي';

  @override
  String get badgeSuspended => 'معلّق';

  @override
  String get badgeUninstallBlocked => 'إلغاء التثبيت محظور';

  @override
  String get loadingShort => 'جارٍ التحميل…';

  @override
  String todayLimitLine(String limit) {
    return 'اليوم: $limit';
  }

  @override
  String get managedRestrictions => 'القيود المُدارة';

  @override
  String timeLimitUpdatedDesc(String app) {
    return 'تم تحديث حد الوقت لـ$app';
  }

  @override
  String timeWindowsUpdatedDesc(String app) {
    return 'تم تحديث النوافذ الزمنية لـ$app';
  }

  @override
  String get timeLimitEditorTitle => 'حد الوقت (بالدقائق)';

  @override
  String dayLimitLabel(String day) {
    return '$day (0 = بلا حد)';
  }

  @override
  String get noGroupsYetMsg =>
      'لا مجموعات بعد. أنشئ واحدة لمشاركة حد عبر التطبيقات.';

  @override
  String membersUpdatedDesc(String name) {
    return 'تم تحديث أعضاء $name';
  }

  @override
  String groupLimitUpdatedDesc(String name) {
    return 'تم تحديث حد $name';
  }

  @override
  String noRestrictionsFor(String app) {
    return 'لا قيود متاحة لـ$app. هذا التطبيق لا يعلن عن أي قيود مُدارة.';
  }

  @override
  String restrictionsForTitle(String app) {
    return 'القيود — $app';
  }

  @override
  String get unsavedTitle => 'تغييرات غير محفوظة';

  @override
  String get unsavedBody => 'لديك تغييرات قيود غير محفوظة. تجاهلها؟';

  @override
  String get saving => 'جارٍ الحفظ…';

  @override
  String unsupportedType(String type) {
    return 'نوع قيد غير مدعوم: $type';
  }

  @override
  String get removeValueTooltip => 'إزالة القيمة';

  @override
  String get removeItemTooltip => 'إزالة العنصر';

  @override
  String restrictionsUpdatedDesc(String app) {
    return 'تم تحديث قيود $app';
  }

  @override
  String get generalSettings => 'الإعدادات العامة';

  @override
  String get protectionTools => 'أدوات الحماية';

  @override
  String get preferencesSection => 'التفضيلات';
}

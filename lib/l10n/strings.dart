import 'package:flutter/widgets.dart';

import '../data/community.dart' show RequestStatus, Urgency;
import '../data/rent_logic.dart' show DueState;
import '../data/models.dart';

/// English / Arabic UI strings. Access with `context.t`.
///
/// Kept as plain getters (no code generation) so a missing translation is a
/// compile error rather than a runtime surprise.
class L10n {
  const L10n(this.ar);
  final bool ar;

  String _tr(String en, String arabic) => ar ? arabic : en;

  // App & navigation
  String get appName => _tr('Home Management System', 'نظام إدارة العقارات');
  String get dashboard => _tr('Home', 'الرئيسية');
  String get properties => _tr('Properties', 'العقارات');
  String get rent => _tr('Rent', 'الإيجار');
  String get expenses => _tr('Expenses', 'المصروفات');
  String get invoices => _tr('Invoices', 'الفواتير');
  String get tenants => _tr('Tenants', 'المستأجرون');
  String get settings => _tr('Settings', 'الإعدادات');
  String get backups => _tr('Backups', 'النسخ الاحتياطي');

  // Common actions
  String get save => _tr('Save', 'حفظ');
  String get cancel => _tr('Cancel', 'إلغاء');
  String get delete => _tr('Delete', 'حذف');
  String get edit => _tr('Edit', 'تعديل');
  String get add => _tr('Add', 'إضافة');
  String get confirm => _tr('Confirm', 'تأكيد');
  String get close => _tr('Close', 'إغلاق');
  String get all => _tr('All', 'الكل');
  String get none => _tr('None', 'لا يوجد');
  String get requiredField => _tr('Required', 'مطلوب');
  String get invalidNumber => _tr('Enter a valid number', 'أدخل رقمًا صحيحًا');
  String get deleteConfirm =>
      _tr('Delete this item? This cannot be undone.', 'حذف هذا العنصر؟ لا يمكن التراجع.');
  String get notes => _tr('Notes', 'ملاحظات');
  String get name => _tr('Name', 'الاسم');
  String get phone => _tr('Phone', 'الهاتف');
  String get email => _tr('Email', 'البريد الإلكتروني');
  String get address => _tr('Address', 'العنوان');
  String get amount => _tr('Amount', 'المبلغ');
  String get date => _tr('Date', 'التاريخ');
  String get type => _tr('Type', 'النوع');
  String get total => _tr('Total', 'الإجمالي');
  String get month => _tr('Month', 'الشهر');
  String get somethingWrong => _tr('Something went wrong', 'حدث خطأ ما');
  String get nothingYet => _tr('Nothing here yet', 'لا توجد بيانات بعد');

  // Auth
  String get signIn => _tr('Sign in', 'تسجيل الدخول');
  String get signUp => _tr('Create account', 'إنشاء حساب');
  String get signOut => _tr('Sign out', 'تسجيل الخروج');
  String get password => _tr('Password', 'كلمة المرور');
  String get continueWithGoogle => _tr('Continue with Google', 'المتابعة باستخدام Google');
  String get haveAccount => _tr('Already have an account? Sign in', 'لديك حساب؟ سجّل الدخول');
  String get noAccount => _tr('New here? Create an account', 'جديد؟ أنشئ حسابًا');
  String get forgotPassword => _tr('Forgot password?', 'نسيت كلمة المرور؟');
  String get resetSent => _tr('Password reset email sent', 'تم إرسال رابط إعادة التعيين');
  String get authTagline => _tr(
      'Buildings, flats, shared expenses and invoices in one place.',
      'العقارات والشقق والمصروفات المشتركة والفواتير في مكان واحد.');
  String get passwordTooShort =>
      _tr('At least 6 characters', '٦ أحرف على الأقل');

  // Dashboard
  String get expectedRent => _tr('Expected rent', 'الإيجار المتوقع');
  String get collected => _tr('Collected', 'المحصّل');
  String get outstanding => _tr('Outstanding', 'المتبقي');
  String get netIncome => _tr('Net (collected − expenses)', 'الصافي (المحصّل − المصروفات)');
  String get occupancy => _tr('Occupancy', 'نسبة الإشغال');
  String unitsOccupied(int o, int t) =>
      _tr('$o of $t units occupied', '$o من $t وحدة مشغولة');
  String get overdueTenants => _tr('Overdue rent', 'إيجارات متأخرة');
  String get noOverdue => _tr('No overdue rent this month', 'لا توجد إيجارات متأخرة هذا الشهر');
  String get quickActions => _tr('Quick actions', 'إجراءات سريعة');
  String get recordPayment => _tr('Record payment', 'تسجيل دفعة');
  String get addExpense => _tr('Add expense', 'إضافة مصروف');
  String get newInvoice => _tr('New invoice', 'فاتورة جديدة');
  String get lastBackup => _tr('Last backup', 'آخر نسخة احتياطية');
  String get neverBackedUp => _tr('Never backed up', 'لم يتم النسخ بعد');
  String get getStarted => _tr(
      'Start by adding your first building with its floors and flats.',
      'ابدأ بإضافة أول عقار بأدواره وشققه.');

  // Properties & units
  String get addProperty => _tr('Add property', 'إضافة عقار');
  String get editProperty => _tr('Edit property', 'تعديل العقار');
  String get property => _tr('Property', 'العقار');
  String get units => _tr('Units', 'الوحدات');
  String get unit => _tr('Unit', 'الوحدة');
  String get addUnit => _tr('Add unit', 'إضافة وحدة');
  String get editUnit => _tr('Edit unit', 'تعديل الوحدة');
  String get unitName => _tr('Unit name / number', 'اسم / رقم الوحدة');
  String get floor => _tr('Floor', 'الدور');
  String get area => _tr('Area (m²)', 'المساحة (م²)');
  String get defaultRent => _tr('Default monthly rent', 'الإيجار الشهري الافتراضي');
  String get occupied => _tr('Occupied', 'مشغولة');
  String get vacant => _tr('Vacant', 'شاغرة');
  String get wholeBuilding => _tr('Whole building', 'العقار بالكامل');
  String unitsCount(int n) => _tr('$n units', '$n وحدة');
  String get noUnits => _tr('No units yet. Add the first one.', 'لا توجد وحدات بعد. أضف أول وحدة.');
  String get deletePropertyBlocked => _tr(
      'Remove this property\'s units first.', 'احذف وحدات هذا العقار أولًا.');
  String get deleteUnitBlocked =>
      _tr('Unlink the resident account from this flat first.', 'ألغِ ربط حساب الساكن بهذه الشقة أولًا.');
  String get currentTenant => _tr('Current tenant', 'المستأجر الحالي');
  String get addTenantHere => _tr('Add tenant to this unit', 'إضافة مستأجر لهذه الوحدة');

  // Building structure (floors, flats, status, fixed monthly cost)
  String get numberOfFloors => _tr('Number of floors', 'عدد الأدوار');
  String get numberOfFlats => _tr('Number of flats', 'عدد الشقق');
  String get buildingStructure => _tr('Building structure', 'هيكل العقار');
  String get monthlyFees => _tr('Fixed monthly cost', 'التكلفة الشهرية الثابتة');
  String get feeOccupiedLabel => _tr('Monthly cost – owner living', 'التكلفة الشهرية – المالك مقيم');
  String get feeClosedLabel => _tr('Monthly cost – flat closed', 'التكلفة الشهرية – الشقة مغلقة');
  String get feesHint => _tr(
      'Used as the starting cost for each flat. You can change any flat afterwards.',
      'تُستخدم كقيمة مبدئية لكل شقة، ويمكن تعديل أي شقة بعد ذلك.');
  String get flatMonthlyFee => _tr('Fixed monthly cost', 'التكلفة الشهرية الثابتة');
  String get setUpFlats => _tr('Set up flats', 'إعداد الشقق');
  String get addFlats => _tr('Add flats', 'إضافة شقق');
  String get howManyFlats => _tr('How many flats to add?', 'كم شقة تريد إضافتها؟');
  String get flatName => _tr('Flat name', 'اسم الشقة');
  String get flatNameHint => _tr("e.g. Mr. Mahmoud Essam's Flat", 'مثال: شقة أ/ محمود عصام');
  String defaultFlatName(int n) => _tr('Flat $n', 'شقة $n');
  String flatNumber(int n) => _tr('Flat $n', 'شقة $n');
  String floorsCount(int n) => _tr('$n floors', '$n أدوار');
  String get roof => _tr('Roof', 'السطح');
  String get hasGroundFloorLabel => _tr('Ground floor', 'دور أرضي');
  String get hasGroundFloorHint => _tr('Flats or units on the ground floor', 'يوجد شقق أو وحدات في الدور الأرضي');
  String get hasRoofLabel => _tr('Roof', 'السطح');
  String get hasRoofHint => _tr('Flats or units on the roof', 'يوجد شقق أو وحدات على السطح');
  String get upperFloors => _tr('Number of floors (above ground)', 'عدد الأدوار (فوق الأرضي)');
  String structureLabel(Property p) => [
        if (p.hasGroundFloor) groundFloor,
        if (p.floors > 0) floorsCount(p.floors),
        if (p.hasRoof) roof,
      ].join(' + ');
  String get groundFloor => _tr('Ground floor', 'الدور الأرضي');
  String floorN(int n) => _tr('Floor $n', 'الدور $n');
  String get status => _tr('Status', 'الحالة');
  String get applyToAll => _tr('Apply to all', 'تطبيق على الكل');
  String get monthlyTotal => _tr('Total fixed monthly cost', 'إجمالي التكلفة الشهرية');
  String flatsSummary(int occupied, int closed) =>
      _tr('$occupied occupied · $closed closed', '$occupied مشغولة · $closed مغلقة');
  String flatsSaved(int n) => _tr('$n flats saved', 'تم حفظ $n شقة');
  String get noFloor => _tr('No floor set', 'بدون دور');
  String get perMonth => _tr('/ month', '/ شهريًا');
  String get flatsSetupHint => _tr(
      'Name each flat, choose its floor and status, and set its fixed monthly cost.',
      'سمِّ كل شقة واختر دورها وحالتها وحدد تكلفتها الشهرية الثابتة.');

  // Tenants
  String get addTenant => _tr('Add tenant', 'إضافة مستأجر');
  String get editTenant => _tr('Edit tenant', 'تعديل المستأجر');
  String get tenant => _tr('Tenant', 'المستأجر');
  String get monthlyRent => _tr('Monthly rent', 'الإيجار الشهري');
  String get dueDay => _tr('Due day of month', 'يوم الاستحقاق من الشهر');
  String get leaseStart => _tr('Lease start', 'بداية العقد');
  String get leaseEnd => _tr('Lease end (optional)', 'نهاية العقد (اختياري)');
  String get deposit => _tr('Security deposit', 'مبلغ التأمين');
  String get active => _tr('Active', 'نشط');
  String get ended => _tr('Ended', 'منتهي');
  String get endLease => _tr('End lease', 'إنهاء العقد');
  String get endLeaseConfirm => _tr(
      'Mark this lease as ended today? The unit becomes vacant.',
      'إنهاء العقد اليوم؟ ستصبح الوحدة شاغرة.');
  String get paymentHistory => _tr('Payment history', 'سجل المدفوعات');
  String get noPayments => _tr('No payments yet', 'لا توجد مدفوعات بعد');
  String get selectUnit => _tr('Select a unit', 'اختر وحدة');
  String get unitTaken => _tr(
      'This unit already has an active tenant.', 'هذه الوحدة بها مستأجر نشط بالفعل.');
  String get noUnitsForTenant => _tr(
      'Add a property and a unit before adding tenants.',
      'أضف عقارًا ووحدة قبل إضافة المستأجرين.');
  String dueOn(int day) => _tr('Due on day $day', 'يستحق يوم $day');
  String get showEnded => _tr('Show ended leases', 'عرض العقود المنتهية');

  // Rent
  String get paid => _tr('Paid', 'مدفوع');
  String get partial => _tr('Partial', 'جزئي');
  String get unpaid => _tr('Unpaid', 'غير مدفوع');
  String get overdue => _tr('Overdue', 'متأخر');
  String get remaining => _tr('Remaining', 'المتبقي');
  String get forMonth => _tr('For month', 'عن شهر');
  String get method => _tr('Method', 'طريقة الدفع');
  String get noRentDue => _tr(
      'No active leases for this month.', 'لا توجد عقود نشطة لهذا الشهر.');
  String paidOf(String paid, String expected) =>
      _tr('$paid of $expected', '$paid من $expected');
  String get deletePayment => _tr('Delete payment', 'حذف الدفعة');

  // Expenses
  String get editExpense => _tr('Edit expense', 'تعديل المصروف');
  String get category => _tr('Category', 'الفئة');
  String get vendor => _tr('Vendor / provider', 'المورد / الجهة');
  String get billToTenant => _tr('Recharge to tenant on invoice', 'تحميله على المستأجر في الفاتورة');
  String get billToTenantHint => _tr(
      'Requires a specific unit', 'يتطلب اختيار وحدة محددة');
  String get noExpenses => _tr('No expenses for this month', 'لا توجد مصروفات لهذا الشهر');
  String get allProperties => _tr('All properties', 'كل العقارات');

  // Expense splitting & monthly dues
  String get splitBetweenFlats => _tr('Split between flats', 'التقسيم على الشقق');
  String get floorsThatShare => _tr('Floors that share this cost', 'الأدوار المشاركة في التكلفة');
  String get enterAmountToSplit => _tr('Enter an amount to see each flat\'s share.', 'أدخل المبلغ لعرض نصيب كل شقة.');
  String get noFlatsToSplit => _tr('No flats match. Include more floors or another split.', 'لا توجد شقق مطابقة. أضف أدوارًا أو اختر طريقة أخرى.');
  String splitSummary(int n, String amount) =>
      _tr('$amount split between $n flats', 'تقسيم $amount على $n شقة');
  String splitNote(int n) => _tr('Split between $n flats', 'مقسّم على $n شقة');
  String get splitSavedHint => _tr(
      'Shares are saved with the expense and appear in each flat\'s monthly dues.',
      'تُحفظ الأنصبة مع المصروف وتظهر في المستحقات الشهرية لكل شقة.');
  String get selectUnitForInvoice => _tr('Choose a flat', 'اختر شقة');
  String get invoiceAutofillHint => _tr(
      'Filled in with the flat\'s fixed monthly cost and its share of this month\'s expenses. You can edit any line.',
      'تم ملؤها بالتكلفة الشهرية الثابتة للشقة ونصيبها من مصروفات هذا الشهر. يمكنك تعديل أي بند.');
  String get duesThisMonth => _tr('Dues this month', 'مستحقات هذا الشهر');
  String acrossFlats(int n) => _tr(n == 1 ? 'Across 1 flat' : 'Across $n flats', 'على $n شقة');
  String get duesPerFlat => _tr('Dues per flat', 'المستحقات لكل شقة');
  String viewAllFlats(int n) => _tr('View all $n flats', 'عرض كل الشقق ($n)');
  String get monthlyDues => _tr('Monthly dues', 'المستحقات الشهرية');
  String get sharedExpenses => _tr('Shared expenses', 'المصروفات المشتركة');
  String get totalDue => _tr('Total due', 'إجمالي المستحق');
  String splitMethod(SplitMethod m) => switch (m) {
        SplitMethod.none => _tr("Don't split", 'بدون تقسيم'),
        SplitMethod.equal => _tr('Equally – all flats', 'بالتساوي – كل الشقق'),
        SplitMethod.occupied => _tr('Equally – occupied flats', 'بالتساوي – الشقق المشغولة'),
        SplitMethod.area => _tr('By flat area', 'حسب مساحة الشقة'),
      };

  // Resident accounts
  String get switchToResident => _tr('Switch to resident view', 'التبديل إلى واجهة الساكن');
  String get switchToManager => _tr('Switch to manager view', 'التبديل إلى واجهة المدير');
  String get bothRolesHint => _tr(
      'Your account is both a building manager and a flat resident.',
      'حسابك مدير عقار وساكن شقة في نفس الوقت.');
  String get iAmA => _tr('I am a…', 'أنا…');
  String get roleManager => _tr('Building manager', 'مدير عقار');
  String get roleResident => _tr('Flat owner / resident', 'مالك / ساكن شقة');
  String get roleManagerHint => _tr(
      'Manage buildings, flats, expenses and invoices.', 'إدارة العقارات والشقق والمصروفات والفواتير.');
  String get roleResidentHint => _tr(
      'Link your account to your flat with the code from your building manager.',
      'اربط حسابك بشقتك باستخدام الكود من مدير العقار.');
  String get residentAccess => _tr('Resident accounts', 'حسابات السكان');
  String residentsLinked(int n) => _tr('$n linked', '$n مرتبط');
  String get residentAccessHint => _tr(
      'Create a building code and share it with flat owners. They sign up, pick their flat, and you approve them.',
      'أنشئ كودًا للعقار وشاركه مع ملاك الشقق. يسجلون ويختارون شقتهم ثم توافق عليهم.');
  String get createBuildingCode => _tr('Create building code', 'إنشاء كود العقار');
  String get buildingCode => _tr('Building code', 'كود العقار');
  String get copy => _tr('Copy', 'نسخ');
  String get codeCopied => _tr('Code copied', 'تم نسخ الكود');
  String get disableCode => _tr('Generate new code', 'إنشاء كود جديد');
  String get disableCodeConfirm => _tr(
      'Replace this code with a new one? The old code stops working. Residents already linked keep their access.',
      'استبدال هذا الكود بكود جديد؟ سيتوقف الكود القديم. السكان المرتبطون يحتفظون بالوصول.');
  String codeLabel(String code) => _tr('Code: $code', 'الكود: $code');
  String get shareCodeHint => _tr(
      'Share this code with flat owners. Each one signs up as "Flat owner / resident" and picks their flat.',
      'شارك هذا الكود مع ملاك الشقق. يسجل كل منهم كـ "مالك / ساكن شقة" ويختار شقته.');
  String requestsWaiting(int n) =>
      _tr(n == 1 ? '1 resident waiting for approval' : '$n residents waiting for approval', '$n طلب في انتظار الموافقة');
  String get joinRequests => _tr('Join requests', 'طلبات الانضمام');
  String get noRequests => _tr('No requests waiting', 'لا توجد طلبات في الانتظار');
  String get approve => _tr('Approve', 'موافقة');
  String get reject => _tr('Decline', 'رفض');
  String rejectConfirm(String name) => _tr('Decline $name\'s request?', 'رفض طلب $name؟');
  String get requestApproved => _tr('Resident linked to the flat', 'تم ربط الساكن بالشقة');
  String flatAlreadyLinked(String name) =>
      _tr('This flat is already linked to $name. Unlink them first.', 'هذه الشقة مرتبطة بالفعل بـ $name. ألغِ الربط أولًا.');
  String get recentDecisions => _tr('Recent', 'الأحدث');
  String requestStatus(RequestStatus s) => switch (s) {
        RequestStatus.pending => _tr('Pending', 'قيد الانتظار'),
        RequestStatus.approved => _tr('Approved', 'مقبول'),
        RequestStatus.rejected => _tr('Declined', 'مرفوض'),
        RequestStatus.removed => _tr('Unlinked', 'أُلغي الربط'),
      };
  String get residentAccount => _tr('Resident account', 'حساب الساكن');
  String get noResidentAccount => _tr('No resident account linked', 'لا يوجد حساب ساكن مرتبط');
  String get noResidentAccountHint => _tr(
      'Share the building code so the owner can link this flat.', 'شارك كود العقار ليتمكن المالك من ربط الشقة.');
  String get unlink => _tr('Unlink', 'إلغاء الربط');
  String unlinkConfirm(String name) => _tr(
      'Unlink $name from this flat? They will lose access to its dues and invoices.',
      'إلغاء ربط $name بهذه الشقة؟ سيفقد الوصول إلى مستحقاتها وفواتيرها.');
  String residentLabel(String name) => _tr('Resident: $name', 'الساكن: $name');

  String get joinYourBuilding => _tr('Join your building', 'الانضمام إلى عقارك');
  String get joinIntro => _tr(
      'Enter the building code you received from your building manager, then choose your flat.',
      'أدخل كود العقار الذي استلمته من مدير العقار ثم اختر شقتك.');
  String get find => _tr('Find', 'بحث');
  String get codeNotFound => _tr('No building found for this code', 'لا يوجد عقار بهذا الكود');
  String get noFreeFlats => _tr('All flats in this building are already linked. Contact your building manager.',
      'كل الشقق في هذا العقار مرتبطة بالفعل. تواصل مع مدير العقار.');
  String get yourFlat => _tr('Your flat', 'شقتك');
  String get selectYourFlat => _tr('Choose your flat', 'اختر شقتك');
  String get yourName => _tr('Your name', 'اسمك');
  String get sendRequest => _tr('Send request', 'إرسال الطلب');
  String get approvalNote => _tr(
      'Your building manager will confirm that this is your flat.', 'سيؤكد مدير العقار أن هذه شقتك.');
  String get waitingForApproval => _tr('Waiting for approval', 'في انتظار الموافقة');
  String get waitingHint => _tr(
      'Your building manager needs to approve your request. This page updates automatically.',
      'يجب أن يوافق مدير العقار على طلبك. تتحدث هذه الصفحة تلقائيًا.');
  String requestNotApproved(RequestStatus s) => s == RequestStatus.removed
      ? _tr('Your flat link was removed', 'تم إلغاء ربط شقتك')
      : _tr('Your request was declined', 'تم رفض طلبك');
  String get tryAgainHint => _tr(
      'Check the code and flat with your building manager, then send a new request.',
      'تأكد من الكود والشقة مع مدير العقار ثم أرسل طلبًا جديدًا.');
  String get cancelRequest => _tr('Cancel request', 'إلغاء الطلب');
  String get tryAgain => _tr('Send a new request', 'إرسال طلب جديد');
  String get myDues => _tr('My dues', 'مستحقاتي');
  String get buildingExpenses => _tr('Building expenses', 'مصروفات العقار');
  String get breakdown => _tr('Breakdown', 'التفاصيل');
  String get buildingTotal => _tr('Building total', 'إجمالي العقار');
  String get yourShare => _tr('Your share', 'نصيبك');

  // Resident expense submissions
  String get suggestExpense => _tr('Add expense', 'إضافة مصروف');
  String get suggestExpenseHint => _tr(
      'Your building manager reviews every expense before it is added and split between the flats.',
      'يراجع مدير العقار كل مصروف قبل إضافته وتقسيمه على الشقق.');
  String get sendForApproval => _tr('Send for approval', 'إرسال للموافقة');
  String get proposalNotesHint => _tr('e.g. receipt number, what was fixed', 'مثال: رقم الإيصال، ما الذي تم إصلاحه');
  String get expenseSubmitted => _tr('Sent to your building manager for approval', 'تم الإرسال إلى مدير العقار للموافقة');
  String get mySubmissions => _tr('My submissions', 'طلباتي');
  String proposalStatus(RequestStatus s) => switch (s) {
        RequestStatus.pending => _tr('Waiting', 'قيد المراجعة'),
        RequestStatus.approved => _tr('Approved', 'مقبول'),
        _ => _tr('Declined', 'مرفوض'),
      };
  String get withdraw => _tr('Withdraw', 'سحب');
  String get withdrawConfirm => _tr('Withdraw this expense?', 'سحب هذا المصروف؟');
  String get withdrawHint => _tr('Press and hold a waiting expense to withdraw it.', 'اضغط مطولًا على مصروف قيد المراجعة لسحبه.');
  String expensesWaiting(int n) => _tr(
      n == 1 ? '1 resident expense waiting for approval' : '$n resident expenses waiting for approval',
      '$n مصروف من السكان في انتظار الموافقة');
  String get expenseApprovals => _tr('Expense approvals', 'الموافقة على المصروفات');
  String get noExpensesWaiting => _tr('No expenses waiting for approval', 'لا توجد مصروفات في انتظار الموافقة');
  String submittedBy(String name, String flat) => _tr('Submitted by $name · $flat', 'مقدم من $name · $flat');
  String addedByResident(String name) => _tr('Added by $name', 'أضافه $name');
  String get editAndApprove => _tr('Edit & approve', 'تعديل وموافقة');
  String get expenseApproved => _tr('Expense approved and split between flats', 'تمت الموافقة على المصروف وتقسيمه على الشقق');
  String get declineExpense => _tr('Decline expense', 'رفض المصروف');
  String get reasonOptional => _tr('Reason (optional, shown to the resident)', 'السبب (اختياري، يظهر للساكن)');

  // Notifications
  String get notificationsTitle => _tr('Notifications', 'الإشعارات');
  String get markAllRead => _tr('Mark all read', 'تحديد الكل كمقروء');
  String get noNotifications => _tr('No notifications yet', 'لا توجد إشعارات بعد');
  String get sendMessage => _tr('Send message', 'إرسال رسالة');
  String get send => _tr('Send', 'إرسال');
  String get sendTo => _tr('Send to', 'إرسال إلى');
  String get allBuildings => _tr('All buildings', 'كل العقارات');
  String get allFlatsInBuilding => _tr('All flats in this building', 'كل الشقق في هذا العقار');
  String recipientsCount(int n) => _tr(n == 1 ? '1 resident' : '$n residents', '$n ساكن');
  String get noRecipients => _tr(
      'No linked residents here yet. Residents join with the building code.',
      'لا يوجد سكان مرتبطون هنا بعد. ينضم السكان بكود العقار.');
  String get messageTitle => _tr('Title', 'العنوان');
  String get messageTitleHint => _tr('e.g. Water cut on Sunday', 'مثال: انقطاع المياه يوم الأحد');
  String get messageBody => _tr('Message', 'الرسالة');
  String messageSent(int n) => _tr('Sent to $n residents', 'تم الإرسال إلى $n ساكن');
  String get sentMessages => _tr('Sent messages', 'الرسائل المرسلة');
  String get notifyResidents => _tr('Notify residents', 'إشعار السكان');
  String get notifyResidentsHint => _tr(
      'Send a notification to the linked residents of this building',
      'إرسال إشعار إلى السكان المرتبطين بهذا العقار');

  // Introduction & credits
  String get skip => _tr('Skip', 'تخطي');
  String get next => _tr('Next', 'التالي');
  String get getStartedButton => _tr('Get started', 'ابدأ الآن');
  String get introTitle1 => _tr('Your buildings, organised', 'عقاراتك منظمة');
  String get introBody1 => _tr(
      'Add buildings with a ground floor, numbered floors and a roof, then name each flat and set its fixed monthly cost. Several owners can share one flat.',
      'أضف العقارات بالدور الأرضي والأدوار والسطح، ثم سمِّ كل شقة وحدد تكلفتها الشهرية الثابتة. يمكن لأكثر من مالك مشاركة الشقة نفسها.');
  String get introTitle2 => _tr('Expenses split fairly', 'تقسيم عادل للمصروفات');
  String get introBody2 => _tr(
      'Log electricity, water, the elevator or repairs once, with photos of the receipt. The app splits each bill by floor or flat and shows what every flat owes.',
      'سجّل الكهرباء أو المياه أو المصعد أو الصيانة مرة واحدة مع صور الإيصال، ويقسم التطبيق كل فاتورة على الأدوار أو الشقق ويعرض مستحقات كل شقة.');
  String get introTitle3 => _tr('Dues paid, at a glance', 'المستحقات والمدفوعات بنظرة واحدة');
  String get introBody3 => _tr(
      'Residents tap "I\'ve paid" and attach proof; the manager confirms. The home page shows expenses, income, late flats and the fund balance, monthly or yearly.',
      'يضغط السكان "دفعت" ويرفقون إثبات الدفع، ويؤكد المدير. وتعرض الصفحة الرئيسية المصروفات والإيرادات والشقق المتأخرة ورصيد الصندوق، شهريًا أو سنويًا.');
  String get introTitle4 => _tr('Requests the manager approves', 'طلبات يوافق عليها المدير');
  String get introBody4 => _tr(
      'Residents send maintenance requests and suggest expenses, and ask to mark their flat occupied or not. The manager approves and sets each flat\'s share.',
      'يرسل السكان طلبات الصيانة ويقترحون المصروفات، ويطلبون تغيير حالة إشغال الشقة. ويوافق المدير ويحدد نصيب كل شقة.');
  String get introTitle5 => _tr('Your flat, kept private', 'شقتك بخصوصية تامة');
  String get introBody5 => _tr(
      'Record your own flat\'s expenses, like a repair inside the flat. Only the flat\'s residents and the building manager can see them.',
      'سجّل مصروفات شقتك الخاصة، مثل إصلاح داخل الشقة. لا يراها إلا سكان الشقة ومدير العقار.');
  String get introTitle6 => _tr('Everyone stays informed', 'الجميع على اطلاع');
  String get introBody6 => _tr(
      'New expenses, approvals, payments and the manager\'s messages arrive as phone notifications. Data is backed up to Google Drive.',
      'تصل المصروفات الجديدة والموافقات والمدفوعات ورسائل المدير كإشعارات على الهاتف، وتُحفظ البيانات احتياطيًا على Google Drive.');
  String get introTitle7 => _tr('Your account, your way', 'حسابك كما تحب');
  String get introBody7 => _tr(
      'Sign up with your phone number, email or Google. The More tab lets you change your name and phone and follow your maintenance requests, in Arabic or English.',
      'سجّل برقم هاتفك أو بريدك أو حساب جوجل. ومن تبويب "المزيد" يمكنك تغيير اسمك ورقمك ومتابعة طلبات الصيانة، بالعربية أو الإنجليزية.');
  // Shared flats and resident-set flat status
  String residentAccountsCount(int n) => _tr('$n resident accounts', '$n حسابات سكان');
  String get sharedFlatHint => _tr(
      'Everyone linked here can see and manage this flat: dues, payments, requests and its status.',
      'كل المرتبطين هنا يمكنهم متابعة وإدارة الشقة: المستحقات والمدفوعات والطلبات وحالتها.');
  String get flatHasResidents => _tr('has residents, you will be added', 'بها سكان، ستتم إضافتك');
  String get noFlatsInBuilding =>
      _tr('This building has no flats yet. Contact your building manager.', 'لا توجد شقق في هذا العقار بعد. تواصل مع مدير العقار.');
  String get myFlatStatus => _tr('My flat', 'شقتي');
  String get flatOccupied => _tr('Living here', 'نسكن بها');
  String get flatClosed => _tr('Not occupied', 'غير مشغولة');
  String get flatStatusHint => _tr(
      'Choose whether someone lives in the flat. The change needs your building manager\'s approval.',
      'اختر إن كان أحد يسكن الشقة. التغيير يحتاج موافقة مدير العقار.');
  String flatStatusFees(String occupied, String closed) => _tr(
      'Fixed monthly cost: $occupied when occupied, $closed when not occupied.',
      'التكلفة الشهرية الثابتة: $occupied عند السكن، و$closed عند عدم الإشغال.');
  String get flatStatusSaved => _tr('Flat status updated', 'تم تحديث حالة الشقة');
  // Private flat expenses
  String get flatExpensesTab => _tr('Flat expenses', 'مصروفات الشقة');
  String get flatExpenses => _tr('Flat\'s own expenses', 'مصروفات الشقة الخاصة');
  String get addFlatExpense => _tr('Add flat expense', 'إضافة مصروف للشقة');
  String get editFlatExpense => _tr('Flat expense', 'مصروف الشقة');
  String get flatExpensesPrivacy => _tr(
      'Private: only residents of this flat and your building manager can see these. They are not shared with other flats.',
      'خاص: لا يراها إلا سكان هذه الشقة ومدير العقار، ولا تُقسَّم على الشقق الأخرى.');
  String get flatExpensesManagerHint => _tr(
      'Recorded by the flat\'s residents for their own flat. Not part of the building\'s expenses or dues.',
      'سجّلها سكان الشقة لشقتهم فقط، وليست ضمن مصروفات العقار أو المستحقات.');
  String get noFlatExpenses => _tr('No flat expenses this month', 'لا توجد مصروفات للشقة هذا الشهر');
  String get flatExpenseTitle => _tr('What was it for?', 'ما هو المصروف؟');
  String get flatExpenseTitleHint => _tr('e.g. Kitchen tap repair', 'مثال: إصلاح حنفية المطبخ');
  String get flatExpenseSaved => _tr('Flat expense saved', 'تم حفظ مصروف الشقة');
  String addedByLine(String name) => _tr('Added by $name', 'أضافه $name');
  // Phone sign-up
  String get orSignInWith => _tr('or use', 'أو استخدم');
  String get phoneNumber => _tr('Phone number', 'رقم الهاتف');
  String get phoneFormatHint => _tr('Egyptian numbers like 010…, or +country code', 'أرقام مصرية مثل 010… أو + كود الدولة');
  String get invalidPhone => _tr('Enter a valid phone number', 'أدخل رقم هاتف صحيح');
  String get firstName => _tr('First name', 'الاسم الأول');
  String get lastName => _tr('Last name', 'اسم العائلة');
  String get invalidEmail => _tr('Enter a valid email', 'أدخل بريدًا إلكترونيًا صحيحًا');
  String get phoneAlreadyRegistered =>
      _tr('This phone number already has an account. Sign in instead.', 'هذا الرقم لديه حساب بالفعل. سجّل الدخول بدلًا من ذلك.');
  String get emailAlreadyRegistered =>
      _tr('This email already has an account. Sign in instead.', 'هذا البريد لديه حساب بالفعل. سجّل الدخول بدلًا من ذلك.');
  String get phoneOrPasswordWrong => _tr('Wrong phone number or password', 'رقم الهاتف أو كلمة المرور غير صحيحة');
  String get emailOrPasswordWrong => _tr('Wrong email or password', 'البريد الإلكتروني أو كلمة المرور غير صحيحة');
  String get tooManyAttempts =>
      _tr('Too many attempts. Wait a few minutes and try again.', 'محاولات كثيرة. انتظر بضع دقائق ثم حاول مرة أخرى.');
  String get noInternet => _tr('No internet connection', 'لا يوجد اتصال بالإنترنت');
  String get phoneResetHint => _tr(
      'Phone accounts can\'t reset the password by email. Ask your building manager for help, or sign in with Google.',
      'لا يمكن إعادة تعيين كلمة مرور حسابات الهاتف عبر البريد. اطلب المساعدة من مدير العقار أو سجّل الدخول بجوجل.');
  // Photo attachments
  String get photos => _tr('Photos', 'الصور');
  String get receiptPhotos => _tr('Photos of receipts or bills', 'صور الإيصالات أو الفواتير');
  String get problemPhotos => _tr('Photos of the problem', 'صور المشكلة');
  String get paymentProof => _tr('Proof of payment (receipt or transfer screenshot)', 'إثبات الدفع (إيصال أو لقطة شاشة للتحويل)');
  String get addPhoto => _tr('Add photo', 'إضافة صورة');
  String get takePhoto => _tr('Take a photo', 'التقاط صورة');
  String get chooseFromGallery => _tr('Choose from gallery', 'اختيار من المعرض');
  String get photoUnreadable => _tr('This photo couldn\'t be read. Try another one.', 'تعذرت قراءة هذه الصورة. جرّب صورة أخرى.');
  // Flat status change requests
  String get statusRequestSent =>
      _tr('Request sent. Your building manager will approve the change.', 'تم إرسال الطلب. سيوافق مدير العقار على التغيير.');
  String get statusRequestCancelled => _tr('Request withdrawn', 'تم سحب الطلب');
  String statusRequestWaiting(String to) =>
      _tr('Waiting for your building manager to approve: $to', 'في انتظار موافقة مدير العقار: $to');
  String statusRequestDeclined(String to) =>
      _tr('Your request to change to "$to" was declined.', 'تم رفض طلب التغيير إلى "$to".');
  String statusRequestsWaiting(int n) => _tr(
      n == 1 ? '1 flat status change waiting' : '$n flat status changes waiting',
      '$n طلب تغيير حالة شقة في الانتظار');
  String get statusRequests => _tr('Flat status requests', 'طلبات تغيير حالة الشقق');
  String get statusRequestsHint => _tr(
      'Residents asked to change whether their flat is occupied. Approving updates the flat and its fixed monthly cost.',
      'طلب السكان تغيير حالة إشغال شققهم. الموافقة تحدّث الشقة وتكلفتها الشهرية الثابتة.');
  String get noStatusRequests => _tr('No requests waiting', 'لا توجد طلبات في الانتظار');
  String get declineStatusChange => _tr('Decline status change', 'رفض تغيير الحالة');
  String get statusChangeApproved => _tr('Flat status updated', 'تم تحديث حالة الشقة');
  String get statusChangeDeclined => _tr('Request declined', 'تم رفض الطلب');
  // More tab
  String get more => _tr('More', 'المزيد');
  String get app => _tr('App', 'التطبيق');
  String get building => _tr('Building', 'العقار');
  String get settingsHint => _tr('Business profile, Google Drive backups', 'بيانات النشاط، النسخ الاحتياطي على جوجل درايف');
  String get noNameYet => _tr('Add your name', 'أضف اسمك');
  String get changeName => _tr('Change name', 'تغيير الاسم');
  String get changePhone => _tr('Change phone number', 'تغيير رقم الهاتف');
  String get myMaintenanceRequests => _tr('My maintenance requests', 'طلبات الصيانة الخاصة بي');
  String get maintenanceRequests => _tr('Maintenance requests', 'طلبات الصيانة');
  String maintenanceRequestsCount(int all, int waiting) => _tr(
      waiting > 0 ? '$all requests · $waiting waiting' : (all == 1 ? '1 request' : '$all requests'),
      waiting > 0 ? '$all طلب · $waiting في الانتظار' : '$all طلب');
  String get noMaintenanceRequests => _tr('No maintenance requests', 'لا توجد طلبات صيانة');
  String get managerNote => _tr('Manager\'s note', 'ملاحظة المدير');
  String get signOutConfirm => _tr('Sign out of this account?', 'تسجيل الخروج من هذا الحساب؟');
  String get nameUpdated => _tr('Name updated', 'تم تحديث الاسم');
  String get phoneUpdated => _tr('Phone number updated', 'تم تحديث رقم الهاتف');
  String signInPhoneStays(String phone) => _tr(
      'This updates the number shown to your building manager. You still sign in with $phone.',
      'سيتم تحديث الرقم الظاهر لمدير العقار. ستظل تسجّل الدخول بالرقم $phone.');
  // Home page welcome
  String get welcome => _tr('Welcome', 'أهلًا بك');
  String welcomeName(String name) => _tr('Welcome, $name', 'أهلًا، $name');
  String get goodMorning => _tr('Good morning', 'صباح الخير');
  String get goodAfternoon => _tr('Good afternoon', 'نهارك سعيد');
  String get goodEvening => _tr('Good evening', 'مساء الخير');
  String get stillLoading => _tr('This is taking longer than usual', 'التحميل يستغرق وقتاً أطول من المعتاد');
  String get stillLoadingHint => _tr(
      'Check your internet connection, then try again. If it keeps happening, sign out and sign in again.',
      'تأكد من اتصالك بالإنترنت ثم حاول مرة أخرى. إذا تكرر ذلك، سجّل الخروج ثم سجّل الدخول من جديد.');
  String get retry => _tr('Try again', 'حاول مرة أخرى');
  String get flatNotFound => _tr('Your flat could not be found', 'تعذر العثور على شقتك');
  String get flatNotFoundHint => _tr(
      'It may have been removed or renamed. Ask your building manager to check your link, or send a new join request.',
      'ربما تم حذفها أو تغيير اسمها. اطلب من مدير العقار مراجعة الربط، أو أرسل طلب انضمام جديد.');
  String get developedBy => _tr('Developed by Mahmoud Essam', 'تم التطوير بواسطة محمود عصام');
  String get about => _tr('About', 'حول التطبيق');
  String get showIntroAgain => _tr('Show the introduction again', 'عرض المقدمة مرة أخرى');

  // Payments, overview, maintenance
  String get overview => _tr('Overview', 'نظرة عامة');
  String get monthly => _tr('Monthly', 'شهري');
  String get annually => _tr('Annually', 'سنوي');
  String get income => _tr('Income', 'الإيرادات');
  String get lateFlats => _tr('Late flats', 'شقق متأخرة');
  String get noLateFlats => _tr('Everyone is up to date', 'لا توجد متأخرات');
  String lateMonths(int n) => _tr(n == 1 ? '1 month unpaid' : '$n months unpaid', '$n شهر غير مدفوع');
  String get lateFlatsHint => _tr(
      'Flats with dues left unpaid from previous months. Tap one to open that month and record a payment.',
      'شقق لديها مستحقات غير مدفوعة من شهور سابقة. اضغط على شقة لفتح الشهر وتسجيل الدفع.');
  String get fundBalance => _tr('Fund balance', 'رصيد الصندوق');
  String get fundCaption => _tr('Held for maintenance', 'محفوظ للصيانة');
  String get fundOpeningLabel => _tr('Money already in the fund', 'المبلغ الموجود في الصندوق حاليًا');
  String get fundOpeningHint => _tr(
      'Starting balance. The fund then grows with confirmed payments and goes down with expenses.',
      'الرصيد الافتتاحي. يزيد الصندوق بالمدفوعات المؤكدة وينقص بالمصروفات.');
  String dueState(DueState s) => switch (s) {
        DueState.paid => _tr('Paid', 'مدفوع'),
        DueState.claimed => _tr('Awaiting confirmation', 'في انتظار التأكيد'),
        DueState.unpaid => _tr('Unpaid', 'غير مدفوع'),
        DueState.nothingDue => _tr('Nothing due', 'لا مستحقات'),
      };
  String paymentStatusLine(DuesPaymentStatus s) => switch (s) {
        DuesPaymentStatus.claimed => _tr('Marked as paid', 'تم الإبلاغ بالدفع'),
        DuesPaymentStatus.confirmed => _tr('Payment confirmed', 'تم تأكيد الدفع'),
        DuesPaymentStatus.rejected => _tr('Payment not confirmed', 'لم يتم تأكيد الدفع'),
      };
  String get iHavePaid => _tr("I've paid", 'قمت بالدفع');
  String get claimHint => _tr(
      'Your building manager will confirm once the money is received.',
      'سيؤكد مدير العقار بعد استلام المبلغ.');
  String get paymentNoteHint => _tr('e.g. transfer reference', 'مثال: رقم التحويل');
  String get paymentClaimSent => _tr('Sent to your building manager to confirm', 'تم الإرسال إلى مدير العقار للتأكيد');
  String get markAsPaid => _tr('Mark as paid', 'تسجيل كمدفوع');
  String get confirmPayment => _tr('Confirm', 'تأكيد');
  String get confirmPayments => _tr('Confirm payments', 'تأكيد المدفوعات');
  String get rejectPayment => _tr('Payment not received', 'لم يتم استلام الدفعة');
  String get undoPayment => _tr('Undo payment', 'إلغاء الدفعة');
  String get undoPaymentConfirm => _tr('Remove this payment? The flat will show as unpaid.', 'حذف هذه الدفعة؟ ستظهر الشقة كغير مدفوعة.');
  String get paymentConfirmedTitle => _tr('Payment confirmed', 'تم تأكيد دفعتك');
  String get paymentRejectedTitle => _tr('Payment not confirmed', 'لم يتم تأكيد دفعتك');
  String paymentsToConfirm(int n) =>
      _tr(n == 1 ? '1 payment to confirm' : '$n payments to confirm', '$n دفعة في انتظار التأكيد');
  String get noPaymentsToConfirm => _tr('No payments waiting for confirmation', 'لا توجد مدفوعات في انتظار التأكيد');
  String paidSummary(int paid, int total, int waiting) => _tr(
      '$paid of $total flats paid${waiting > 0 ? ' · $waiting awaiting confirmation' : ''}',
      '$paid من $total شقة دفعت${waiting > 0 ? ' · $waiting في انتظار التأكيد' : ''}');
  String get maintenanceRequest => _tr('Maintenance request', 'طلب صيانة');
  String get maintenanceHint => _tr(
      'Describe what needs fixing. Your building manager reviews it, sets the cost and how it is shared between the flats.',
      'صف ما يحتاج إلى إصلاح. يراجعه مدير العقار ويحدد التكلفة وطريقة تقسيمها على الشقق.');
  String get whatNeedsFixing => _tr('What needs fixing?', 'ما الذي يحتاج إلى إصلاح؟');
  String get whatNeedsFixingHint => _tr('e.g. Elevator stuck on floor 3', 'مثال: المصعد متوقف في الدور الثالث');
  String get details => _tr('Details', 'التفاصيل');
  String get detailsHint => _tr('Where, since when, anything the technician should know', 'المكان، منذ متى، وأي معلومة تفيد الفني');
  String get urgency => _tr('Urgency', 'الأولوية');
  String urgencyLabel(Urgency u) => switch (u) {
        Urgency.low => _tr('Low', 'منخفضة'),
        Urgency.normal => _tr('Normal', 'عادية'),
        Urgency.urgent => _tr('Urgent', 'عاجلة'),
      };
  String get estimatedCost => _tr('Estimated cost (optional)', 'التكلفة التقديرية (اختياري)');
  String get estimatedCostShort => _tr('estimate', 'تقديري');
  String get maintenanceSent => _tr('Maintenance request sent for approval', 'تم إرسال طلب الصيانة للموافقة');
  String get approveAndSetShares => _tr('Approve & set shares', 'موافقة وتحديد الأنصبة');

  // Invoices
  String get invoice => _tr('Invoice', 'فاتورة');
  String get invoiceNo => _tr('Invoice no.', 'رقم الفاتورة');
  String get issueDate => _tr('Issue date', 'تاريخ الإصدار');
  String get dueDate => _tr('Due date', 'تاريخ الاستحقاق');
  String get items => _tr('Items', 'البنود');
  String get description => _tr('Description', 'الوصف');
  String get addItem => _tr('Add item', 'إضافة بند');
  String get rentFor => _tr('Rent for', 'إيجار شهر');
  String get billTo => _tr('Bill to', 'فاتورة إلى');
  String get markPaid => _tr('Mark as paid', 'تحديد كمدفوعة');
  String get markUnpaid => _tr('Mark as unpaid', 'تحديد كغير مدفوعة');
  String get cancelInvoice => _tr('Cancel invoice', 'إلغاء الفاتورة');
  String get cancelled => _tr('Cancelled', 'ملغاة');
  String get share => _tr('Share PDF', 'مشاركة PDF');
  String get print => _tr('Print', 'طباعة');
  String get preview => _tr('Preview', 'معاينة');
  String get noInvoices => _tr('No invoices yet', 'لا توجد فواتير بعد');
  String get atLeastOneItem => _tr('Add at least one item', 'أضف بندًا واحدًا على الأقل');
  String get includeUtilities => _tr(
      'Include rechargeable utilities for this month',
      'إضافة المرافق القابلة للتحميل لهذا الشهر');
  String get alsoRecordPayment => _tr(
      'Also record the rent as a payment?', 'تسجيل الإيجار كدفعة أيضًا؟');
  String get thankYou => _tr('Thank you for your payment.', 'شكرًا لسدادكم.');
  String get selectTenant => _tr('Select a tenant', 'اختر مستأجرًا');

  // Settings
  String get language => _tr('Language', 'اللغة');
  String get systemDefault => _tr('System', 'النظام');
  String get businessProfile => _tr('Invoice details', 'بيانات الفاتورة');
  String get businessName => _tr('Landlord / company name', 'اسم المالك / الشركة');
  String get currency => _tr('Currency code', 'رمز العملة');
  String get invoicePrefix => _tr('Invoice number prefix', 'بادئة رقم الفاتورة');
  String get account => _tr('Account', 'الحساب');
  String get saved => _tr('Saved', 'تم الحفظ');

  // Backups
  String get googleDrive => _tr('Google Drive', 'Google Drive');
  String get connectDrive => _tr('Connect Google Drive', 'ربط Google Drive');
  String get disconnect => _tr('Disconnect', 'إلغاء الربط');
  String get connectedAs => _tr('Connected as', 'متصل بحساب');
  String get backupNow => _tr('Back up now', 'نسخ احتياطي الآن');
  String get autoBackup => _tr('Automatic backup', 'النسخ التلقائي');
  String get off => _tr('Off', 'متوقف');
  String get daily => _tr('Daily', 'يوميًا');
  String get weekly => _tr('Weekly', 'أسبوعيًا');
  String get autoBackupHint => _tr(
      'Runs when you open the app and the last backup is older than the chosen interval. The 30 most recent backups are kept.',
      'يعمل عند فتح التطبيق إذا كانت آخر نسخة أقدم من المدة المحددة. يتم الاحتفاظ بآخر ٣٠ نسخة.');
  String get backupDone => _tr('Backup uploaded to Google Drive', 'تم رفع النسخة إلى Google Drive');
  String get backupFailed => _tr('Backup failed', 'فشل النسخ الاحتياطي');
  String get driveBackups => _tr('Backups in Drive', 'النسخ في Drive');
  String get restore => _tr('Restore', 'استعادة');
  String get restoreConfirm => _tr(
      'Replace ALL current data with this backup? Current data will be lost.',
      'استبدال كل البيانات الحالية بهذه النسخة؟ ستفقد البيانات الحالية.');
  String get restoreDone => _tr('Data restored', 'تمت الاستعادة');
  String get noBackups => _tr('No backups yet', 'لا توجد نسخ بعد');
  String get driveNotConnected => _tr(
      'Connect a Google account to store backups in a "Home Management Backups" folder in your Drive.',
      'اربط حساب Google لحفظ النسخ في مجلد "Home Management Backups" في Drive.');
  String get working => _tr('Working…', 'جارٍ التنفيذ…');

  // Enum labels
  String propertyType(PropertyType t) => switch (t) {
        PropertyType.residential => _tr('Residential', 'سكني'),
        PropertyType.commercial => _tr('Commercial', 'تجاري'),
        PropertyType.mixed => _tr('Mixed use', 'متعدد الاستخدام'),
      };

  String unitType(UnitType t) => switch (t) {
        UnitType.apartment => _tr('Apartment', 'شقة'),
        UnitType.shop => _tr('Shop', 'محل'),
        UnitType.office => _tr('Office', 'مكتب'),
        UnitType.warehouse => _tr('Warehouse', 'مخزن'),
        UnitType.other => _tr('Other', 'أخرى'),
      };

  String paymentMethod(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => _tr('Cash', 'نقدًا'),
        PaymentMethod.bankTransfer => _tr('Bank transfer', 'تحويل بنكي'),
        PaymentMethod.cheque => _tr('Cheque', 'شيك'),
        PaymentMethod.wallet => _tr('Mobile wallet', 'محفظة إلكترونية'),
        PaymentMethod.other => _tr('Other', 'أخرى'),
      };

  String expenseCategory(ExpenseCategory c) => switch (c) {
        ExpenseCategory.electricity => _tr('Electricity', 'كهرباء'),
        ExpenseCategory.water => _tr('Water', 'مياه'),
        ExpenseCategory.gas => _tr('Gas', 'غاز'),
        ExpenseCategory.internet => _tr('Internet', 'إنترنت'),
        ExpenseCategory.maintenance => _tr('Maintenance', 'صيانة'),
        ExpenseCategory.cleaning => _tr('Cleaning', 'نظافة'),
        ExpenseCategory.security => _tr('Security', 'أمن وحراسة'),
        ExpenseCategory.elevator => _tr('Elevator', 'مصعد'),
        ExpenseCategory.taxes => _tr('Taxes & fees', 'ضرائب ورسوم'),
        ExpenseCategory.other => _tr('Other', 'أخرى'),
      };

  String unitStatus(UnitStatus s) => switch (s) {
        UnitStatus.ownerResident => _tr('Owner living', 'المالك مقيم'),
        UnitStatus.closed => _tr('Closed', 'مغلقة'),
        UnitStatus.rented => _tr('Rented', 'مؤجرة'),
      };

  String floorLabel(String floor) {
    final n = int.tryParse(floor.trim());
    if (floor.trim().isEmpty) return noFloor;
    if (floor.trim() == kRoofFloor) return roof;
    if (n == null) return floor;
    return n == 0 ? groundFloor : floorN(n);
  }

  String invoiceStatus(InvoiceStatus s) => switch (s) {
        InvoiceStatus.paid => paid,
        InvoiceStatus.unpaid => unpaid,
        InvoiceStatus.cancelled => cancelled,
      };
}

extension L10nContext on BuildContext {
  L10n get t => L10n(Localizations.localeOf(this).languageCode == 'ar');
}

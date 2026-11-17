// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $InboxItemsTable extends InboxItems
    with TableInfo<$InboxItemsTable, InboxItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rawTextMeta =
      const VerificationMeta('rawText');
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
      'raw_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('general'));
  static const VerificationMeta _isProcessedMeta =
      const VerificationMeta('isProcessed');
  @override
  late final GeneratedColumn<bool> isProcessed = GeneratedColumn<bool>(
      'is_processed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_processed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, rawText, category, isProcessed, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbox_items';
  @override
  VerificationContext validateIntegrity(Insertable<InboxItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('raw_text')) {
      context.handle(_rawTextMeta,
          rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta));
    } else if (isInserting) {
      context.missing(_rawTextMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('is_processed')) {
      context.handle(
          _isProcessedMeta,
          isProcessed.isAcceptableOrUnknown(
              data['is_processed']!, _isProcessedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InboxItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      rawText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}raw_text'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      isProcessed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_processed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $InboxItemsTable createAlias(String alias) {
    return $InboxItemsTable(attachedDatabase, alias);
  }
}

class InboxItem extends DataClass implements Insertable<InboxItem> {
  final String id;
  final String rawText;
  final String category;
  final bool isProcessed;
  final DateTime createdAt;
  const InboxItem(
      {required this.id,
      required this.rawText,
      required this.category,
      required this.isProcessed,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['raw_text'] = Variable<String>(rawText);
    map['category'] = Variable<String>(category);
    map['is_processed'] = Variable<bool>(isProcessed);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  InboxItemsCompanion toCompanion(bool nullToAbsent) {
    return InboxItemsCompanion(
      id: Value(id),
      rawText: Value(rawText),
      category: Value(category),
      isProcessed: Value(isProcessed),
      createdAt: Value(createdAt),
    );
  }

  factory InboxItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxItem(
      id: serializer.fromJson<String>(json['id']),
      rawText: serializer.fromJson<String>(json['rawText']),
      category: serializer.fromJson<String>(json['category']),
      isProcessed: serializer.fromJson<bool>(json['isProcessed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rawText': serializer.toJson<String>(rawText),
      'category': serializer.toJson<String>(category),
      'isProcessed': serializer.toJson<bool>(isProcessed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  InboxItem copyWith(
          {String? id,
          String? rawText,
          String? category,
          bool? isProcessed,
          DateTime? createdAt}) =>
      InboxItem(
        id: id ?? this.id,
        rawText: rawText ?? this.rawText,
        category: category ?? this.category,
        isProcessed: isProcessed ?? this.isProcessed,
        createdAt: createdAt ?? this.createdAt,
      );
  InboxItem copyWithCompanion(InboxItemsCompanion data) {
    return InboxItem(
      id: data.id.present ? data.id.value : this.id,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      category: data.category.present ? data.category.value : this.category,
      isProcessed:
          data.isProcessed.present ? data.isProcessed.value : this.isProcessed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxItem(')
          ..write('id: $id, ')
          ..write('rawText: $rawText, ')
          ..write('category: $category, ')
          ..write('isProcessed: $isProcessed, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, rawText, category, isProcessed, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxItem &&
          other.id == this.id &&
          other.rawText == this.rawText &&
          other.category == this.category &&
          other.isProcessed == this.isProcessed &&
          other.createdAt == this.createdAt);
}

class InboxItemsCompanion extends UpdateCompanion<InboxItem> {
  final Value<String> id;
  final Value<String> rawText;
  final Value<String> category;
  final Value<bool> isProcessed;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const InboxItemsCompanion({
    this.id = const Value.absent(),
    this.rawText = const Value.absent(),
    this.category = const Value.absent(),
    this.isProcessed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InboxItemsCompanion.insert({
    required String id,
    required String rawText,
    this.category = const Value.absent(),
    this.isProcessed = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        rawText = Value(rawText),
        createdAt = Value(createdAt);
  static Insertable<InboxItem> custom({
    Expression<String>? id,
    Expression<String>? rawText,
    Expression<String>? category,
    Expression<bool>? isProcessed,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rawText != null) 'raw_text': rawText,
      if (category != null) 'category': category,
      if (isProcessed != null) 'is_processed': isProcessed,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InboxItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? rawText,
      Value<String>? category,
      Value<bool>? isProcessed,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return InboxItemsCompanion(
      id: id ?? this.id,
      rawText: rawText ?? this.rawText,
      category: category ?? this.category,
      isProcessed: isProcessed ?? this.isProcessed,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (isProcessed.present) {
      map['is_processed'] = Variable<bool>(isProcessed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboxItemsCompanion(')
          ..write('id: $id, ')
          ..write('rawText: $rawText, ')
          ..write('category: $category, ')
          ..write('isProcessed: $isProcessed, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GoalsTable extends Goals with TableInfo<$GoalsTable, Goal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _targetDateMeta =
      const VerificationMeta('targetDate');
  @override
  late final GeneratedColumn<String> targetDate = GeneratedColumn<String>(
      'target_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, title, description, targetDate, status, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'goals';
  @override
  VerificationContext validateIntegrity(Insertable<Goal> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('target_date')) {
      context.handle(
          _targetDateMeta,
          targetDate.isAcceptableOrUnknown(
              data['target_date']!, _targetDateMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Goal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Goal(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      targetDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}target_date']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $GoalsTable createAlias(String alias) {
    return $GoalsTable(attachedDatabase, alias);
  }
}

class Goal extends DataClass implements Insertable<Goal> {
  final String id;
  final String title;
  final String? description;
  final String? targetDate;
  final String status;
  final DateTime createdAt;
  const Goal(
      {required this.id,
      required this.title,
      this.description,
      this.targetDate,
      required this.status,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<String>(targetDate);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  GoalsCompanion toCompanion(bool nullToAbsent) {
    return GoalsCompanion(
      id: Value(id),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory Goal.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Goal(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      targetDate: serializer.fromJson<String?>(json['targetDate']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'targetDate': serializer.toJson<String?>(targetDate),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Goal copyWith(
          {String? id,
          String? title,
          Value<String?> description = const Value.absent(),
          Value<String?> targetDate = const Value.absent(),
          String? status,
          DateTime? createdAt}) =>
      Goal(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description.present ? description.value : this.description,
        targetDate: targetDate.present ? targetDate.value : this.targetDate,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
  Goal copyWithCompanion(GoalsCompanion data) {
    return Goal(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      targetDate:
          data.targetDate.present ? data.targetDate.value : this.targetDate,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Goal(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('targetDate: $targetDate, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, description, targetDate, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Goal &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.targetDate == this.targetDate &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class GoalsCompanion extends UpdateCompanion<Goal> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<String?> targetDate;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const GoalsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GoalsCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt);
  static Insertable<Goal> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? targetDate,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (targetDate != null) 'target_date': targetDate,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GoalsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String?>? description,
      Value<String?>? targetDate,
      Value<String>? status,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return GoalsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      targetDate: targetDate ?? this.targetDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (targetDate.present) {
      map['target_date'] = Variable<String>(targetDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GoalsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('targetDate: $targetDate, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _goalIdMeta = const VerificationMeta('goalId');
  @override
  late final GeneratedColumn<String> goalId = GeneratedColumn<String>(
      'goal_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES goals (id) ON DELETE SET NULL'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _targetDateMeta =
      const VerificationMeta('targetDate');
  @override
  late final GeneratedColumn<String> targetDate = GeneratedColumn<String>(
      'target_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, goalId, title, description, status, targetDate, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(Insertable<Project> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('goal_id')) {
      context.handle(_goalIdMeta,
          goalId.isAcceptableOrUnknown(data['goal_id']!, _goalIdMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('target_date')) {
      context.handle(
          _targetDateMeta,
          targetDate.isAcceptableOrUnknown(
              data['target_date']!, _targetDateMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      goalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}goal_id']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      targetDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}target_date']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final String id;
  final String? goalId;
  final String title;
  final String? description;
  final String status;
  final String? targetDate;
  final DateTime createdAt;
  const Project(
      {required this.id,
      this.goalId,
      required this.title,
      this.description,
      required this.status,
      this.targetDate,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || goalId != null) {
      map['goal_id'] = Variable<String>(goalId);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<String>(targetDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      goalId:
          goalId == null && nullToAbsent ? const Value.absent() : Value(goalId),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      createdAt: Value(createdAt),
    );
  }

  factory Project.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<String>(json['id']),
      goalId: serializer.fromJson<String?>(json['goalId']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      targetDate: serializer.fromJson<String?>(json['targetDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'goalId': serializer.toJson<String?>(goalId),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'targetDate': serializer.toJson<String?>(targetDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Project copyWith(
          {String? id,
          Value<String?> goalId = const Value.absent(),
          String? title,
          Value<String?> description = const Value.absent(),
          String? status,
          Value<String?> targetDate = const Value.absent(),
          DateTime? createdAt}) =>
      Project(
        id: id ?? this.id,
        goalId: goalId.present ? goalId.value : this.goalId,
        title: title ?? this.title,
        description: description.present ? description.value : this.description,
        status: status ?? this.status,
        targetDate: targetDate.present ? targetDate.value : this.targetDate,
        createdAt: createdAt ?? this.createdAt,
      );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      goalId: data.goalId.present ? data.goalId.value : this.goalId,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      status: data.status.present ? data.status.value : this.status,
      targetDate:
          data.targetDate.present ? data.targetDate.value : this.targetDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('targetDate: $targetDate, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, goalId, title, description, status, targetDate, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.goalId == this.goalId &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.targetDate == this.targetDate &&
          other.createdAt == this.createdAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<String> id;
  final Value<String?> goalId;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> status;
  final Value<String?> targetDate;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.goalId = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    this.goalId = const Value.absent(),
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.targetDate = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt);
  static Insertable<Project> custom({
    Expression<String>? id,
    Expression<String>? goalId,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<String>? targetDate,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (goalId != null) 'goal_id': goalId,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (targetDate != null) 'target_date': targetDate,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith(
      {Value<String>? id,
      Value<String?>? goalId,
      Value<String>? title,
      Value<String?>? description,
      Value<String>? status,
      Value<String?>? targetDate,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ProjectsCompanion(
      id: id ?? this.id,
      goalId: goalId ?? this.goalId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      targetDate: targetDate ?? this.targetDate,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (goalId.present) {
      map['goal_id'] = Variable<String>(goalId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (targetDate.present) {
      map['target_date'] = Variable<String>(targetDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('targetDate: $targetDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MilestonesTable extends Milestones
    with TableInfo<$MilestonesTable, Milestone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MilestonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _projectIdMeta =
      const VerificationMeta('projectId');
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
      'project_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES projects (id) ON DELETE CASCADE'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _dueDateMeta =
      const VerificationMeta('dueDate');
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
      'due_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isCompletedMeta =
      const VerificationMeta('isCompleted');
  @override
  late final GeneratedColumn<bool> isCompleted = GeneratedColumn<bool>(
      'is_completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, projectId, title, dueDate, isCompleted, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'milestones';
  @override
  VerificationContext validateIntegrity(Insertable<Milestone> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(_projectIdMeta,
          projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta));
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(_dueDateMeta,
          dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta));
    }
    if (data.containsKey('is_completed')) {
      context.handle(
          _isCompletedMeta,
          isCompleted.isAcceptableOrUnknown(
              data['is_completed']!, _isCompletedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Milestone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Milestone(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      projectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      dueDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}due_date']),
      isCompleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_completed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MilestonesTable createAlias(String alias) {
    return $MilestonesTable(attachedDatabase, alias);
  }
}

class Milestone extends DataClass implements Insertable<Milestone> {
  final String id;
  final String projectId;
  final String title;
  final String? dueDate;
  final bool isCompleted;
  final DateTime createdAt;
  const Milestone(
      {required this.id,
      required this.projectId,
      required this.title,
      this.dueDate,
      required this.isCompleted,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    map['is_completed'] = Variable<bool>(isCompleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MilestonesCompanion toCompanion(bool nullToAbsent) {
    return MilestonesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      title: Value(title),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      isCompleted: Value(isCompleted),
      createdAt: Value(createdAt),
    );
  }

  factory Milestone.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Milestone(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      title: serializer.fromJson<String>(json['title']),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      isCompleted: serializer.fromJson<bool>(json['isCompleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'title': serializer.toJson<String>(title),
      'dueDate': serializer.toJson<String?>(dueDate),
      'isCompleted': serializer.toJson<bool>(isCompleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Milestone copyWith(
          {String? id,
          String? projectId,
          String? title,
          Value<String?> dueDate = const Value.absent(),
          bool? isCompleted,
          DateTime? createdAt}) =>
      Milestone(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        title: title ?? this.title,
        dueDate: dueDate.present ? dueDate.value : this.dueDate,
        isCompleted: isCompleted ?? this.isCompleted,
        createdAt: createdAt ?? this.createdAt,
      );
  Milestone copyWithCompanion(MilestonesCompanion data) {
    return Milestone(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      title: data.title.present ? data.title.value : this.title,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      isCompleted:
          data.isCompleted.present ? data.isCompleted.value : this.isCompleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Milestone(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('dueDate: $dueDate, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, projectId, title, dueDate, isCompleted, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Milestone &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.title == this.title &&
          other.dueDate == this.dueDate &&
          other.isCompleted == this.isCompleted &&
          other.createdAt == this.createdAt);
}

class MilestonesCompanion extends UpdateCompanion<Milestone> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> title;
  final Value<String?> dueDate;
  final Value<bool> isCompleted;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MilestonesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.title = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.isCompleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MilestonesCompanion.insert({
    required String id,
    required String projectId,
    required String title,
    this.dueDate = const Value.absent(),
    this.isCompleted = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        projectId = Value(projectId),
        title = Value(title),
        createdAt = Value(createdAt);
  static Insertable<Milestone> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? title,
    Expression<String>? dueDate,
    Expression<bool>? isCompleted,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (title != null) 'title': title,
      if (dueDate != null) 'due_date': dueDate,
      if (isCompleted != null) 'is_completed': isCompleted,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MilestonesCompanion copyWith(
      {Value<String>? id,
      Value<String>? projectId,
      Value<String>? title,
      Value<String?>? dueDate,
      Value<bool>? isCompleted,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return MilestonesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (isCompleted.present) {
      map['is_completed'] = Variable<bool>(isCompleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MilestonesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('dueDate: $dueDate, ')
          ..write('isCompleted: $isCompleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TasksTable extends Tasks with TableInfo<$TasksTable, Task> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 300),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('inbox'));
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
      'priority', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('medium'));
  static const VerificationMeta _dueDateMeta =
      const VerificationMeta('dueDate');
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
      'due_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _scheduledDateMeta =
      const VerificationMeta('scheduledDate');
  @override
  late final GeneratedColumn<String> scheduledDate = GeneratedColumn<String>(
      'scheduled_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _estimatedDurationMinutesMeta =
      const VerificationMeta('estimatedDurationMinutes');
  @override
  late final GeneratedColumn<int> estimatedDurationMinutes =
      GeneratedColumn<int>('estimated_duration_minutes', aliasedName, true,
          type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _projectIdMeta =
      const VerificationMeta('projectId');
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
      'project_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES projects (id) ON DELETE SET NULL'));
  static const VerificationMeta _milestoneIdMeta =
      const VerificationMeta('milestoneId');
  @override
  late final GeneratedColumn<String> milestoneId = GeneratedColumn<String>(
      'milestone_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES milestones (id) ON DELETE SET NULL'));
  static const VerificationMeta _subtasksJsonMeta =
      const VerificationMeta('subtasksJson');
  @override
  late final GeneratedColumn<String> subtasksJson = GeneratedColumn<String>(
      'subtasks_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _labelsJsonMeta =
      const VerificationMeta('labelsJson');
  @override
  late final GeneratedColumn<String> labelsJson = GeneratedColumn<String>(
      'labels_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isMyDayMeta =
      const VerificationMeta('isMyDay');
  @override
  late final GeneratedColumn<bool> isMyDay = GeneratedColumn<bool>(
      'is_my_day', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_my_day" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _recurrenceRuleMeta =
      const VerificationMeta('recurrenceRule');
  @override
  late final GeneratedColumn<String> recurrenceRule = GeneratedColumn<String>(
      'recurrence_rule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        description,
        status,
        priority,
        dueDate,
        scheduledDate,
        estimatedDurationMinutes,
        projectId,
        milestoneId,
        subtasksJson,
        labelsJson,
        isPinned,
        isMyDay,
        recurrenceRule,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(Insertable<Task> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('due_date')) {
      context.handle(_dueDateMeta,
          dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta));
    }
    if (data.containsKey('scheduled_date')) {
      context.handle(
          _scheduledDateMeta,
          scheduledDate.isAcceptableOrUnknown(
              data['scheduled_date']!, _scheduledDateMeta));
    }
    if (data.containsKey('estimated_duration_minutes')) {
      context.handle(
          _estimatedDurationMinutesMeta,
          estimatedDurationMinutes.isAcceptableOrUnknown(
              data['estimated_duration_minutes']!,
              _estimatedDurationMinutesMeta));
    }
    if (data.containsKey('project_id')) {
      context.handle(_projectIdMeta,
          projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta));
    }
    if (data.containsKey('milestone_id')) {
      context.handle(
          _milestoneIdMeta,
          milestoneId.isAcceptableOrUnknown(
              data['milestone_id']!, _milestoneIdMeta));
    }
    if (data.containsKey('subtasks_json')) {
      context.handle(
          _subtasksJsonMeta,
          subtasksJson.isAcceptableOrUnknown(
              data['subtasks_json']!, _subtasksJsonMeta));
    }
    if (data.containsKey('labels_json')) {
      context.handle(
          _labelsJsonMeta,
          labelsJson.isAcceptableOrUnknown(
              data['labels_json']!, _labelsJsonMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('is_my_day')) {
      context.handle(_isMyDayMeta,
          isMyDay.isAcceptableOrUnknown(data['is_my_day']!, _isMyDayMeta));
    }
    if (data.containsKey('recurrence_rule')) {
      context.handle(
          _recurrenceRuleMeta,
          recurrenceRule.isAcceptableOrUnknown(
              data['recurrence_rule']!, _recurrenceRuleMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Task map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Task(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}priority'])!,
      dueDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}due_date']),
      scheduledDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}scheduled_date']),
      estimatedDurationMinutes: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}estimated_duration_minutes']),
      projectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_id']),
      milestoneId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}milestone_id']),
      subtasksJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}subtasks_json'])!,
      labelsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}labels_json'])!,
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      isMyDay: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_my_day'])!,
      recurrenceRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recurrence_rule']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class Task extends DataClass implements Insertable<Task> {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? dueDate;
  final String? scheduledDate;
  final int? estimatedDurationMinutes;
  final String? projectId;
  final String? milestoneId;
  final String subtasksJson;
  final String labelsJson;
  final bool isPinned;
  final bool isMyDay;
  final String? recurrenceRule;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Task(
      {required this.id,
      required this.title,
      this.description,
      required this.status,
      required this.priority,
      this.dueDate,
      this.scheduledDate,
      this.estimatedDurationMinutes,
      this.projectId,
      this.milestoneId,
      required this.subtasksJson,
      required this.labelsJson,
      required this.isPinned,
      required this.isMyDay,
      this.recurrenceRule,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['priority'] = Variable<String>(priority);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    if (!nullToAbsent || scheduledDate != null) {
      map['scheduled_date'] = Variable<String>(scheduledDate);
    }
    if (!nullToAbsent || estimatedDurationMinutes != null) {
      map['estimated_duration_minutes'] =
          Variable<int>(estimatedDurationMinutes);
    }
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || milestoneId != null) {
      map['milestone_id'] = Variable<String>(milestoneId);
    }
    map['subtasks_json'] = Variable<String>(subtasksJson);
    map['labels_json'] = Variable<String>(labelsJson);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_my_day'] = Variable<bool>(isMyDay);
    if (!nullToAbsent || recurrenceRule != null) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      priority: Value(priority),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      scheduledDate: scheduledDate == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledDate),
      estimatedDurationMinutes: estimatedDurationMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedDurationMinutes),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      milestoneId: milestoneId == null && nullToAbsent
          ? const Value.absent()
          : Value(milestoneId),
      subtasksJson: Value(subtasksJson),
      labelsJson: Value(labelsJson),
      isPinned: Value(isPinned),
      isMyDay: Value(isMyDay),
      recurrenceRule: recurrenceRule == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrenceRule),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Task.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Task(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      priority: serializer.fromJson<String>(json['priority']),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      scheduledDate: serializer.fromJson<String?>(json['scheduledDate']),
      estimatedDurationMinutes:
          serializer.fromJson<int?>(json['estimatedDurationMinutes']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      milestoneId: serializer.fromJson<String?>(json['milestoneId']),
      subtasksJson: serializer.fromJson<String>(json['subtasksJson']),
      labelsJson: serializer.fromJson<String>(json['labelsJson']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isMyDay: serializer.fromJson<bool>(json['isMyDay']),
      recurrenceRule: serializer.fromJson<String?>(json['recurrenceRule']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'priority': serializer.toJson<String>(priority),
      'dueDate': serializer.toJson<String?>(dueDate),
      'scheduledDate': serializer.toJson<String?>(scheduledDate),
      'estimatedDurationMinutes':
          serializer.toJson<int?>(estimatedDurationMinutes),
      'projectId': serializer.toJson<String?>(projectId),
      'milestoneId': serializer.toJson<String?>(milestoneId),
      'subtasksJson': serializer.toJson<String>(subtasksJson),
      'labelsJson': serializer.toJson<String>(labelsJson),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isMyDay': serializer.toJson<bool>(isMyDay),
      'recurrenceRule': serializer.toJson<String?>(recurrenceRule),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Task copyWith(
          {String? id,
          String? title,
          Value<String?> description = const Value.absent(),
          String? status,
          String? priority,
          Value<String?> dueDate = const Value.absent(),
          Value<String?> scheduledDate = const Value.absent(),
          Value<int?> estimatedDurationMinutes = const Value.absent(),
          Value<String?> projectId = const Value.absent(),
          Value<String?> milestoneId = const Value.absent(),
          String? subtasksJson,
          String? labelsJson,
          bool? isPinned,
          bool? isMyDay,
          Value<String?> recurrenceRule = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description.present ? description.value : this.description,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        dueDate: dueDate.present ? dueDate.value : this.dueDate,
        scheduledDate:
            scheduledDate.present ? scheduledDate.value : this.scheduledDate,
        estimatedDurationMinutes: estimatedDurationMinutes.present
            ? estimatedDurationMinutes.value
            : this.estimatedDurationMinutes,
        projectId: projectId.present ? projectId.value : this.projectId,
        milestoneId: milestoneId.present ? milestoneId.value : this.milestoneId,
        subtasksJson: subtasksJson ?? this.subtasksJson,
        labelsJson: labelsJson ?? this.labelsJson,
        isPinned: isPinned ?? this.isPinned,
        isMyDay: isMyDay ?? this.isMyDay,
        recurrenceRule:
            recurrenceRule.present ? recurrenceRule.value : this.recurrenceRule,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Task copyWithCompanion(TasksCompanion data) {
    return Task(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description:
          data.description.present ? data.description.value : this.description,
      status: data.status.present ? data.status.value : this.status,
      priority: data.priority.present ? data.priority.value : this.priority,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      scheduledDate: data.scheduledDate.present
          ? data.scheduledDate.value
          : this.scheduledDate,
      estimatedDurationMinutes: data.estimatedDurationMinutes.present
          ? data.estimatedDurationMinutes.value
          : this.estimatedDurationMinutes,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      milestoneId:
          data.milestoneId.present ? data.milestoneId.value : this.milestoneId,
      subtasksJson: data.subtasksJson.present
          ? data.subtasksJson.value
          : this.subtasksJson,
      labelsJson:
          data.labelsJson.present ? data.labelsJson.value : this.labelsJson,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isMyDay: data.isMyDay.present ? data.isMyDay.value : this.isMyDay,
      recurrenceRule: data.recurrenceRule.present
          ? data.recurrenceRule.value
          : this.recurrenceRule,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Task(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('dueDate: $dueDate, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('estimatedDurationMinutes: $estimatedDurationMinutes, ')
          ..write('projectId: $projectId, ')
          ..write('milestoneId: $milestoneId, ')
          ..write('subtasksJson: $subtasksJson, ')
          ..write('labelsJson: $labelsJson, ')
          ..write('isPinned: $isPinned, ')
          ..write('isMyDay: $isMyDay, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      description,
      status,
      priority,
      dueDate,
      scheduledDate,
      estimatedDurationMinutes,
      projectId,
      milestoneId,
      subtasksJson,
      labelsJson,
      isPinned,
      isMyDay,
      recurrenceRule,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Task &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.priority == this.priority &&
          other.dueDate == this.dueDate &&
          other.scheduledDate == this.scheduledDate &&
          other.estimatedDurationMinutes == this.estimatedDurationMinutes &&
          other.projectId == this.projectId &&
          other.milestoneId == this.milestoneId &&
          other.subtasksJson == this.subtasksJson &&
          other.labelsJson == this.labelsJson &&
          other.isPinned == this.isPinned &&
          other.isMyDay == this.isMyDay &&
          other.recurrenceRule == this.recurrenceRule &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TasksCompanion extends UpdateCompanion<Task> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> description;
  final Value<String> status;
  final Value<String> priority;
  final Value<String?> dueDate;
  final Value<String?> scheduledDate;
  final Value<int?> estimatedDurationMinutes;
  final Value<String?> projectId;
  final Value<String?> milestoneId;
  final Value<String> subtasksJson;
  final Value<String> labelsJson;
  final Value<bool> isPinned;
  final Value<bool> isMyDay;
  final Value<String?> recurrenceRule;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.scheduledDate = const Value.absent(),
    this.estimatedDurationMinutes = const Value.absent(),
    this.projectId = const Value.absent(),
    this.milestoneId = const Value.absent(),
    this.subtasksJson = const Value.absent(),
    this.labelsJson = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isMyDay = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.scheduledDate = const Value.absent(),
    this.estimatedDurationMinutes = const Value.absent(),
    this.projectId = const Value.absent(),
    this.milestoneId = const Value.absent(),
    this.subtasksJson = const Value.absent(),
    this.labelsJson = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isMyDay = const Value.absent(),
    this.recurrenceRule = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Task> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<String>? priority,
    Expression<String>? dueDate,
    Expression<String>? scheduledDate,
    Expression<int>? estimatedDurationMinutes,
    Expression<String>? projectId,
    Expression<String>? milestoneId,
    Expression<String>? subtasksJson,
    Expression<String>? labelsJson,
    Expression<bool>? isPinned,
    Expression<bool>? isMyDay,
    Expression<String>? recurrenceRule,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (dueDate != null) 'due_date': dueDate,
      if (scheduledDate != null) 'scheduled_date': scheduledDate,
      if (estimatedDurationMinutes != null)
        'estimated_duration_minutes': estimatedDurationMinutes,
      if (projectId != null) 'project_id': projectId,
      if (milestoneId != null) 'milestone_id': milestoneId,
      if (subtasksJson != null) 'subtasks_json': subtasksJson,
      if (labelsJson != null) 'labels_json': labelsJson,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isMyDay != null) 'is_my_day': isMyDay,
      if (recurrenceRule != null) 'recurrence_rule': recurrenceRule,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String?>? description,
      Value<String>? status,
      Value<String>? priority,
      Value<String?>? dueDate,
      Value<String?>? scheduledDate,
      Value<int?>? estimatedDurationMinutes,
      Value<String?>? projectId,
      Value<String?>? milestoneId,
      Value<String>? subtasksJson,
      Value<String>? labelsJson,
      Value<bool>? isPinned,
      Value<bool>? isMyDay,
      Value<String?>? recurrenceRule,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return TasksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      projectId: projectId ?? this.projectId,
      milestoneId: milestoneId ?? this.milestoneId,
      subtasksJson: subtasksJson ?? this.subtasksJson,
      labelsJson: labelsJson ?? this.labelsJson,
      isPinned: isPinned ?? this.isPinned,
      isMyDay: isMyDay ?? this.isMyDay,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (scheduledDate.present) {
      map['scheduled_date'] = Variable<String>(scheduledDate.value);
    }
    if (estimatedDurationMinutes.present) {
      map['estimated_duration_minutes'] =
          Variable<int>(estimatedDurationMinutes.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (milestoneId.present) {
      map['milestone_id'] = Variable<String>(milestoneId.value);
    }
    if (subtasksJson.present) {
      map['subtasks_json'] = Variable<String>(subtasksJson.value);
    }
    if (labelsJson.present) {
      map['labels_json'] = Variable<String>(labelsJson.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isMyDay.present) {
      map['is_my_day'] = Variable<bool>(isMyDay.value);
    }
    if (recurrenceRule.present) {
      map['recurrence_rule'] = Variable<String>(recurrenceRule.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('priority: $priority, ')
          ..write('dueDate: $dueDate, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('estimatedDurationMinutes: $estimatedDurationMinutes, ')
          ..write('projectId: $projectId, ')
          ..write('milestoneId: $milestoneId, ')
          ..write('subtasksJson: $subtasksJson, ')
          ..write('labelsJson: $labelsJson, ')
          ..write('isPinned: $isPinned, ')
          ..write('isMyDay: $isMyDay, ')
          ..write('recurrenceRule: $recurrenceRule, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 250),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('general'));
  static const VerificationMeta _projectIdMeta =
      const VerificationMeta('projectId');
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
      'project_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES projects (id) ON DELETE SET NULL'));
  static const VerificationMeta _goalIdMeta = const VerificationMeta('goalId');
  @override
  late final GeneratedColumn<String> goalId = GeneratedColumn<String>(
      'goal_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES goals (id) ON DELETE SET NULL'));
  static const VerificationMeta _tagsJsonMeta =
      const VerificationMeta('tagsJson');
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
      'tags_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isTrashedMeta =
      const VerificationMeta('isTrashed');
  @override
  late final GeneratedColumn<bool> isTrashed = GeneratedColumn<bool>(
      'is_trashed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_trashed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        content,
        category,
        projectId,
        goalId,
        tagsJson,
        isPinned,
        isFavorite,
        isArchived,
        isTrashed,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(Insertable<Note> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('project_id')) {
      context.handle(_projectIdMeta,
          projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta));
    }
    if (data.containsKey('goal_id')) {
      context.handle(_goalIdMeta,
          goalId.isAcceptableOrUnknown(data['goal_id']!, _goalIdMeta));
    }
    if (data.containsKey('tags_json')) {
      context.handle(_tagsJsonMeta,
          tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('is_trashed')) {
      context.handle(_isTrashedMeta,
          isTrashed.isAcceptableOrUnknown(data['is_trashed']!, _isTrashedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      projectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_id']),
      goalId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}goal_id']),
      tagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags_json'])!,
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      isTrashed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_trashed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class Note extends DataClass implements Insertable<Note> {
  final String id;
  final String title;
  final String content;
  final String category;
  final String? projectId;
  final String? goalId;
  final String tagsJson;
  final bool isPinned;
  final bool isFavorite;
  final bool isArchived;
  final bool isTrashed;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Note(
      {required this.id,
      required this.title,
      required this.content,
      required this.category,
      this.projectId,
      this.goalId,
      required this.tagsJson,
      required this.isPinned,
      required this.isFavorite,
      required this.isArchived,
      required this.isTrashed,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['content'] = Variable<String>(content);
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || goalId != null) {
      map['goal_id'] = Variable<String>(goalId);
    }
    map['tags_json'] = Variable<String>(tagsJson);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['is_archived'] = Variable<bool>(isArchived);
    map['is_trashed'] = Variable<bool>(isTrashed);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      title: Value(title),
      content: Value(content),
      category: Value(category),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      goalId:
          goalId == null && nullToAbsent ? const Value.absent() : Value(goalId),
      tagsJson: Value(tagsJson),
      isPinned: Value(isPinned),
      isFavorite: Value(isFavorite),
      isArchived: Value(isArchived),
      isTrashed: Value(isTrashed),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Note.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      content: serializer.fromJson<String>(json['content']),
      category: serializer.fromJson<String>(json['category']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      goalId: serializer.fromJson<String?>(json['goalId']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      isTrashed: serializer.fromJson<bool>(json['isTrashed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'content': serializer.toJson<String>(content),
      'category': serializer.toJson<String>(category),
      'projectId': serializer.toJson<String?>(projectId),
      'goalId': serializer.toJson<String?>(goalId),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'isArchived': serializer.toJson<bool>(isArchived),
      'isTrashed': serializer.toJson<bool>(isTrashed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Note copyWith(
          {String? id,
          String? title,
          String? content,
          String? category,
          Value<String?> projectId = const Value.absent(),
          Value<String?> goalId = const Value.absent(),
          String? tagsJson,
          bool? isPinned,
          bool? isFavorite,
          bool? isArchived,
          bool? isTrashed,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        category: category ?? this.category,
        projectId: projectId.present ? projectId.value : this.projectId,
        goalId: goalId.present ? goalId.value : this.goalId,
        tagsJson: tagsJson ?? this.tagsJson,
        isPinned: isPinned ?? this.isPinned,
        isFavorite: isFavorite ?? this.isFavorite,
        isArchived: isArchived ?? this.isArchived,
        isTrashed: isTrashed ?? this.isTrashed,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      content: data.content.present ? data.content.value : this.content,
      category: data.category.present ? data.category.value : this.category,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      goalId: data.goalId.present ? data.goalId.value : this.goalId,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      isTrashed: data.isTrashed.present ? data.isTrashed.value : this.isTrashed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('projectId: $projectId, ')
          ..write('goalId: $goalId, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('isPinned: $isPinned, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isArchived: $isArchived, ')
          ..write('isTrashed: $isTrashed, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      content,
      category,
      projectId,
      goalId,
      tagsJson,
      isPinned,
      isFavorite,
      isArchived,
      isTrashed,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.title == this.title &&
          other.content == this.content &&
          other.category == this.category &&
          other.projectId == this.projectId &&
          other.goalId == this.goalId &&
          other.tagsJson == this.tagsJson &&
          other.isPinned == this.isPinned &&
          other.isFavorite == this.isFavorite &&
          other.isArchived == this.isArchived &&
          other.isTrashed == this.isTrashed &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> content;
  final Value<String> category;
  final Value<String?> projectId;
  final Value<String?> goalId;
  final Value<String> tagsJson;
  final Value<bool> isPinned;
  final Value<bool> isFavorite;
  final Value<bool> isArchived;
  final Value<bool> isTrashed;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.content = const Value.absent(),
    this.category = const Value.absent(),
    this.projectId = const Value.absent(),
    this.goalId = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isTrashed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    required String title,
    required String content,
    this.category = const Value.absent(),
    this.projectId = const Value.absent(),
    this.goalId = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.isTrashed = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        content = Value(content),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Note> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? content,
    Expression<String>? category,
    Expression<String>? projectId,
    Expression<String>? goalId,
    Expression<String>? tagsJson,
    Expression<bool>? isPinned,
    Expression<bool>? isFavorite,
    Expression<bool>? isArchived,
    Expression<bool>? isTrashed,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (category != null) 'category': category,
      if (projectId != null) 'project_id': projectId,
      if (goalId != null) 'goal_id': goalId,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isArchived != null) 'is_archived': isArchived,
      if (isTrashed != null) 'is_trashed': isTrashed,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? content,
      Value<String>? category,
      Value<String?>? projectId,
      Value<String?>? goalId,
      Value<String>? tagsJson,
      Value<bool>? isPinned,
      Value<bool>? isFavorite,
      Value<bool>? isArchived,
      Value<bool>? isTrashed,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return NotesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      projectId: projectId ?? this.projectId,
      goalId: goalId ?? this.goalId,
      tagsJson: tagsJson ?? this.tagsJson,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (goalId.present) {
      map['goal_id'] = Variable<String>(goalId.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (isTrashed.present) {
      map['is_trashed'] = Variable<bool>(isTrashed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('content: $content, ')
          ..write('category: $category, ')
          ..write('projectId: $projectId, ')
          ..write('goalId: $goalId, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('isPinned: $isPinned, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('isArchived: $isArchived, ')
          ..write('isTrashed: $isTrashed, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CalendarEventsTable extends CalendarEvents
    with TableInfo<$CalendarEventsTable, CalendarEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalendarEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 250),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _dateIsoMeta =
      const VerificationMeta('dateIso');
  @override
  late final GeneratedColumn<String> dateIso = GeneratedColumn<String>(
      'date_iso', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _endDateIsoMeta =
      const VerificationMeta('endDateIso');
  @override
  late final GeneratedColumn<String> endDateIso = GeneratedColumn<String>(
      'end_date_iso', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _startTimeMeta =
      const VerificationMeta('startTime');
  @override
  late final GeneratedColumn<String> startTime = GeneratedColumn<String>(
      'start_time', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _endTimeMeta =
      const VerificationMeta('endTime');
  @override
  late final GeneratedColumn<String> endTime = GeneratedColumn<String>(
      'end_time', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isAllDayMeta =
      const VerificationMeta('isAllDay');
  @override
  late final GeneratedColumn<bool> isAllDay = GeneratedColumn<bool>(
      'is_all_day', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_all_day" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('personal'));
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('#1B4D3E'));
  static const VerificationMeta _hasReminderMeta =
      const VerificationMeta('hasReminder');
  @override
  late final GeneratedColumn<bool> hasReminder = GeneratedColumn<bool>(
      'has_reminder', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("has_reminder" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        dateIso,
        endDateIso,
        startTime,
        endTime,
        isAllDay,
        category,
        colorHex,
        hasReminder,
        notes,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calendar_events';
  @override
  VerificationContext validateIntegrity(Insertable<CalendarEvent> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('date_iso')) {
      context.handle(_dateIsoMeta,
          dateIso.isAcceptableOrUnknown(data['date_iso']!, _dateIsoMeta));
    } else if (isInserting) {
      context.missing(_dateIsoMeta);
    }
    if (data.containsKey('end_date_iso')) {
      context.handle(
          _endDateIsoMeta,
          endDateIso.isAcceptableOrUnknown(
              data['end_date_iso']!, _endDateIsoMeta));
    }
    if (data.containsKey('start_time')) {
      context.handle(_startTimeMeta,
          startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta));
    }
    if (data.containsKey('end_time')) {
      context.handle(_endTimeMeta,
          endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta));
    }
    if (data.containsKey('is_all_day')) {
      context.handle(_isAllDayMeta,
          isAllDay.isAcceptableOrUnknown(data['is_all_day']!, _isAllDayMeta));
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    }
    if (data.containsKey('has_reminder')) {
      context.handle(
          _hasReminderMeta,
          hasReminder.isAcceptableOrUnknown(
              data['has_reminder']!, _hasReminderMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalendarEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalendarEvent(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      dateIso: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date_iso'])!,
      endDateIso: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}end_date_iso']),
      startTime: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}start_time']),
      endTime: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}end_time']),
      isAllDay: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_all_day'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      hasReminder: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}has_reminder'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CalendarEventsTable createAlias(String alias) {
    return $CalendarEventsTable(attachedDatabase, alias);
  }
}

class CalendarEvent extends DataClass implements Insertable<CalendarEvent> {
  final String id;
  final String title;
  final String dateIso;
  final String? endDateIso;
  final String? startTime;
  final String? endTime;
  final bool isAllDay;
  final String category;
  final String colorHex;
  final bool hasReminder;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const CalendarEvent(
      {required this.id,
      required this.title,
      required this.dateIso,
      this.endDateIso,
      this.startTime,
      this.endTime,
      required this.isAllDay,
      required this.category,
      required this.colorHex,
      required this.hasReminder,
      this.notes,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['date_iso'] = Variable<String>(dateIso);
    if (!nullToAbsent || endDateIso != null) {
      map['end_date_iso'] = Variable<String>(endDateIso);
    }
    if (!nullToAbsent || startTime != null) {
      map['start_time'] = Variable<String>(startTime);
    }
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<String>(endTime);
    }
    map['is_all_day'] = Variable<bool>(isAllDay);
    map['category'] = Variable<String>(category);
    map['color_hex'] = Variable<String>(colorHex);
    map['has_reminder'] = Variable<bool>(hasReminder);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CalendarEventsCompanion toCompanion(bool nullToAbsent) {
    return CalendarEventsCompanion(
      id: Value(id),
      title: Value(title),
      dateIso: Value(dateIso),
      endDateIso: endDateIso == null && nullToAbsent
          ? const Value.absent()
          : Value(endDateIso),
      startTime: startTime == null && nullToAbsent
          ? const Value.absent()
          : Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      isAllDay: Value(isAllDay),
      category: Value(category),
      colorHex: Value(colorHex),
      hasReminder: Value(hasReminder),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalendarEvent(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      dateIso: serializer.fromJson<String>(json['dateIso']),
      endDateIso: serializer.fromJson<String?>(json['endDateIso']),
      startTime: serializer.fromJson<String?>(json['startTime']),
      endTime: serializer.fromJson<String?>(json['endTime']),
      isAllDay: serializer.fromJson<bool>(json['isAllDay']),
      category: serializer.fromJson<String>(json['category']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      hasReminder: serializer.fromJson<bool>(json['hasReminder']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'dateIso': serializer.toJson<String>(dateIso),
      'endDateIso': serializer.toJson<String?>(endDateIso),
      'startTime': serializer.toJson<String?>(startTime),
      'endTime': serializer.toJson<String?>(endTime),
      'isAllDay': serializer.toJson<bool>(isAllDay),
      'category': serializer.toJson<String>(category),
      'colorHex': serializer.toJson<String>(colorHex),
      'hasReminder': serializer.toJson<bool>(hasReminder),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CalendarEvent copyWith(
          {String? id,
          String? title,
          String? dateIso,
          Value<String?> endDateIso = const Value.absent(),
          Value<String?> startTime = const Value.absent(),
          Value<String?> endTime = const Value.absent(),
          bool? isAllDay,
          String? category,
          String? colorHex,
          bool? hasReminder,
          Value<String?> notes = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      CalendarEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        dateIso: dateIso ?? this.dateIso,
        endDateIso: endDateIso.present ? endDateIso.value : this.endDateIso,
        startTime: startTime.present ? startTime.value : this.startTime,
        endTime: endTime.present ? endTime.value : this.endTime,
        isAllDay: isAllDay ?? this.isAllDay,
        category: category ?? this.category,
        colorHex: colorHex ?? this.colorHex,
        hasReminder: hasReminder ?? this.hasReminder,
        notes: notes.present ? notes.value : this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  CalendarEvent copyWithCompanion(CalendarEventsCompanion data) {
    return CalendarEvent(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      dateIso: data.dateIso.present ? data.dateIso.value : this.dateIso,
      endDateIso:
          data.endDateIso.present ? data.endDateIso.value : this.endDateIso,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      isAllDay: data.isAllDay.present ? data.isAllDay.value : this.isAllDay,
      category: data.category.present ? data.category.value : this.category,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      hasReminder:
          data.hasReminder.present ? data.hasReminder.value : this.hasReminder,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEvent(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('dateIso: $dateIso, ')
          ..write('endDateIso: $endDateIso, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('category: $category, ')
          ..write('colorHex: $colorHex, ')
          ..write('hasReminder: $hasReminder, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      dateIso,
      endDateIso,
      startTime,
      endTime,
      isAllDay,
      category,
      colorHex,
      hasReminder,
      notes,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalendarEvent &&
          other.id == this.id &&
          other.title == this.title &&
          other.dateIso == this.dateIso &&
          other.endDateIso == this.endDateIso &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.isAllDay == this.isAllDay &&
          other.category == this.category &&
          other.colorHex == this.colorHex &&
          other.hasReminder == this.hasReminder &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CalendarEventsCompanion extends UpdateCompanion<CalendarEvent> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> dateIso;
  final Value<String?> endDateIso;
  final Value<String?> startTime;
  final Value<String?> endTime;
  final Value<bool> isAllDay;
  final Value<String> category;
  final Value<String> colorHex;
  final Value<bool> hasReminder;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CalendarEventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.dateIso = const Value.absent(),
    this.endDateIso = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.category = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.hasReminder = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CalendarEventsCompanion.insert({
    required String id,
    required String title,
    required String dateIso,
    this.endDateIso = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.isAllDay = const Value.absent(),
    this.category = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.hasReminder = const Value.absent(),
    this.notes = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        dateIso = Value(dateIso),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<CalendarEvent> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? dateIso,
    Expression<String>? endDateIso,
    Expression<String>? startTime,
    Expression<String>? endTime,
    Expression<bool>? isAllDay,
    Expression<String>? category,
    Expression<String>? colorHex,
    Expression<bool>? hasReminder,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (dateIso != null) 'date_iso': dateIso,
      if (endDateIso != null) 'end_date_iso': endDateIso,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (isAllDay != null) 'is_all_day': isAllDay,
      if (category != null) 'category': category,
      if (colorHex != null) 'color_hex': colorHex,
      if (hasReminder != null) 'has_reminder': hasReminder,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CalendarEventsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? dateIso,
      Value<String?>? endDateIso,
      Value<String?>? startTime,
      Value<String?>? endTime,
      Value<bool>? isAllDay,
      Value<String>? category,
      Value<String>? colorHex,
      Value<bool>? hasReminder,
      Value<String?>? notes,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CalendarEventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      dateIso: dateIso ?? this.dateIso,
      endDateIso: endDateIso ?? this.endDateIso,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      category: category ?? this.category,
      colorHex: colorHex ?? this.colorHex,
      hasReminder: hasReminder ?? this.hasReminder,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (dateIso.present) {
      map['date_iso'] = Variable<String>(dateIso.value);
    }
    if (endDateIso.present) {
      map['end_date_iso'] = Variable<String>(endDateIso.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<String>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<String>(endTime.value);
    }
    if (isAllDay.present) {
      map['is_all_day'] = Variable<bool>(isAllDay.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (hasReminder.present) {
      map['has_reminder'] = Variable<bool>(hasReminder.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalendarEventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('dateIso: $dateIso, ')
          ..write('endDateIso: $endDateIso, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('isAllDay: $isAllDay, ')
          ..write('category: $category, ')
          ..write('colorHex: $colorHex, ')
          ..write('hasReminder: $hasReminder, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FinancialCategoriesTable extends FinancialCategories
    with TableInfo<$FinancialCategoriesTable, FinancialCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinancialCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 100),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorHexMeta =
      const VerificationMeta('colorHex');
  @override
  late final GeneratedColumn<String> colorHex = GeneratedColumn<String>(
      'color_hex', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('#4CAF50'));
  static const VerificationMeta _isDefaultMeta =
      const VerificationMeta('isDefault');
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
      'is_default', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_default" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_categories (id) ON DELETE RESTRICT'));
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, type, colorHex, isDefault, isArchived, parentId, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'financial_categories';
  @override
  VerificationContext validateIntegrity(Insertable<FinancialCategory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('color_hex')) {
      context.handle(_colorHexMeta,
          colorHex.isAcceptableOrUnknown(data['color_hex']!, _colorHexMeta));
    }
    if (data.containsKey('is_default')) {
      context.handle(_isDefaultMeta,
          isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FinancialCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FinancialCategory(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      colorHex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}color_hex'])!,
      isDefault: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_default'])!,
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $FinancialCategoriesTable createAlias(String alias) {
    return $FinancialCategoriesTable(attachedDatabase, alias);
  }
}

class FinancialCategory extends DataClass
    implements Insertable<FinancialCategory> {
  final String id;
  final String name;
  final String type;
  final String colorHex;
  final bool isDefault;
  final bool isArchived;
  final String? parentId;
  final int sortOrder;
  const FinancialCategory(
      {required this.id,
      required this.name,
      required this.type,
      required this.colorHex,
      required this.isDefault,
      required this.isArchived,
      this.parentId,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['color_hex'] = Variable<String>(colorHex);
    map['is_default'] = Variable<bool>(isDefault);
    map['is_archived'] = Variable<bool>(isArchived);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  FinancialCategoriesCompanion toCompanion(bool nullToAbsent) {
    return FinancialCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      colorHex: Value(colorHex),
      isDefault: Value(isDefault),
      isArchived: Value(isArchived),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      sortOrder: Value(sortOrder),
    );
  }

  factory FinancialCategory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FinancialCategory(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      colorHex: serializer.fromJson<String>(json['colorHex']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'colorHex': serializer.toJson<String>(colorHex),
      'isDefault': serializer.toJson<bool>(isDefault),
      'isArchived': serializer.toJson<bool>(isArchived),
      'parentId': serializer.toJson<String?>(parentId),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  FinancialCategory copyWith(
          {String? id,
          String? name,
          String? type,
          String? colorHex,
          bool? isDefault,
          bool? isArchived,
          Value<String?> parentId = const Value.absent(),
          int? sortOrder}) =>
      FinancialCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        colorHex: colorHex ?? this.colorHex,
        isDefault: isDefault ?? this.isDefault,
        isArchived: isArchived ?? this.isArchived,
        parentId: parentId.present ? parentId.value : this.parentId,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  FinancialCategory copyWithCompanion(FinancialCategoriesCompanion data) {
    return FinancialCategory(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      colorHex: data.colorHex.present ? data.colorHex.value : this.colorHex,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinancialCategory(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('colorHex: $colorHex, ')
          ..write('isDefault: $isDefault, ')
          ..write('isArchived: $isArchived, ')
          ..write('parentId: $parentId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, name, type, colorHex, isDefault, isArchived, parentId, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialCategory &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.colorHex == this.colorHex &&
          other.isDefault == this.isDefault &&
          other.isArchived == this.isArchived &&
          other.parentId == this.parentId &&
          other.sortOrder == this.sortOrder);
}

class FinancialCategoriesCompanion extends UpdateCompanion<FinancialCategory> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> colorHex;
  final Value<bool> isDefault;
  final Value<bool> isArchived;
  final Value<String?> parentId;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const FinancialCategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.colorHex = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.parentId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinancialCategoriesCompanion.insert({
    required String id,
    required String name,
    required String type,
    this.colorHex = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.parentId = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        type = Value(type);
  static Insertable<FinancialCategory> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? colorHex,
    Expression<bool>? isDefault,
    Expression<bool>? isArchived,
    Expression<String>? parentId,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (colorHex != null) 'color_hex': colorHex,
      if (isDefault != null) 'is_default': isDefault,
      if (isArchived != null) 'is_archived': isArchived,
      if (parentId != null) 'parent_id': parentId,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinancialCategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? type,
      Value<String>? colorHex,
      Value<bool>? isDefault,
      Value<bool>? isArchived,
      Value<String?>? parentId,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return FinancialCategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      colorHex: colorHex ?? this.colorHex,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      parentId: parentId ?? this.parentId,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (colorHex.present) {
      map['color_hex'] = Variable<String>(colorHex.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinancialCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('colorHex: $colorHex, ')
          ..write('isDefault: $isDefault, ')
          ..write('isArchived: $isArchived, ')
          ..write('parentId: $parentId, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FinancialTransactionsTable extends FinancialTransactions
    with TableInfo<$FinancialTransactionsTable, FinancialTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinancialTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_categories (id) ON DELETE RESTRICT'));
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _transactionDateMeta =
      const VerificationMeta('transactionDate');
  @override
  late final GeneratedColumn<String> transactionDate = GeneratedColumn<String>(
      'transaction_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _payeeMeta = const VerificationMeta('payee');
  @override
  late final GeneratedColumn<String> payee = GeneratedColumn<String>(
      'payee', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _destinationAccountIdMeta =
      const VerificationMeta('destinationAccountId');
  @override
  late final GeneratedColumn<String> destinationAccountId =
      GeneratedColumn<String>('destination_account_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isSupersededMeta =
      const VerificationMeta('isSuperseded');
  @override
  late final GeneratedColumn<bool> isSuperseded = GeneratedColumn<bool>(
      'is_superseded', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_superseded" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _correctedFromIdMeta =
      const VerificationMeta('correctedFromId');
  @override
  late final GeneratedColumn<String> correctedFromId = GeneratedColumn<String>(
      'corrected_from_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _correctionReasonMeta =
      const VerificationMeta('correctionReason');
  @override
  late final GeneratedColumn<String> correctionReason = GeneratedColumn<String>(
      'correction_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        categoryId,
        amountCents,
        type,
        transactionDate,
        note,
        payee,
        accountId,
        destinationAccountId,
        isSuperseded,
        correctedFromId,
        correctionReason,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'financial_transactions';
  @override
  VerificationContext validateIntegrity(
      Insertable<FinancialTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('transaction_date')) {
      context.handle(
          _transactionDateMeta,
          transactionDate.isAcceptableOrUnknown(
              data['transaction_date']!, _transactionDateMeta));
    } else if (isInserting) {
      context.missing(_transactionDateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('payee')) {
      context.handle(
          _payeeMeta, payee.isAcceptableOrUnknown(data['payee']!, _payeeMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('destination_account_id')) {
      context.handle(
          _destinationAccountIdMeta,
          destinationAccountId.isAcceptableOrUnknown(
              data['destination_account_id']!, _destinationAccountIdMeta));
    }
    if (data.containsKey('is_superseded')) {
      context.handle(
          _isSupersededMeta,
          isSuperseded.isAcceptableOrUnknown(
              data['is_superseded']!, _isSupersededMeta));
    }
    if (data.containsKey('corrected_from_id')) {
      context.handle(
          _correctedFromIdMeta,
          correctedFromId.isAcceptableOrUnknown(
              data['corrected_from_id']!, _correctedFromIdMeta));
    }
    if (data.containsKey('correction_reason')) {
      context.handle(
          _correctionReasonMeta,
          correctionReason.isAcceptableOrUnknown(
              data['correction_reason']!, _correctionReasonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FinancialTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FinancialTransaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      transactionDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}transaction_date'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      payee: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payee']),
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id']),
      destinationAccountId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}destination_account_id']),
      isSuperseded: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_superseded'])!,
      correctedFromId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}corrected_from_id']),
      correctionReason: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}correction_reason']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FinancialTransactionsTable createAlias(String alias) {
    return $FinancialTransactionsTable(attachedDatabase, alias);
  }
}

class FinancialTransaction extends DataClass
    implements Insertable<FinancialTransaction> {
  final String id;
  final String categoryId;
  final int amountCents;
  final String type;
  final String transactionDate;
  final String? note;
  final String? payee;
  final String? accountId;
  final String? destinationAccountId;
  final bool isSuperseded;
  final String? correctedFromId;
  final String? correctionReason;
  final DateTime createdAt;
  const FinancialTransaction(
      {required this.id,
      required this.categoryId,
      required this.amountCents,
      required this.type,
      required this.transactionDate,
      this.note,
      this.payee,
      this.accountId,
      this.destinationAccountId,
      required this.isSuperseded,
      this.correctedFromId,
      this.correctionReason,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['category_id'] = Variable<String>(categoryId);
    map['amount_cents'] = Variable<int>(amountCents);
    map['type'] = Variable<String>(type);
    map['transaction_date'] = Variable<String>(transactionDate);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || payee != null) {
      map['payee'] = Variable<String>(payee);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    if (!nullToAbsent || destinationAccountId != null) {
      map['destination_account_id'] = Variable<String>(destinationAccountId);
    }
    map['is_superseded'] = Variable<bool>(isSuperseded);
    if (!nullToAbsent || correctedFromId != null) {
      map['corrected_from_id'] = Variable<String>(correctedFromId);
    }
    if (!nullToAbsent || correctionReason != null) {
      map['correction_reason'] = Variable<String>(correctionReason);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FinancialTransactionsCompanion toCompanion(bool nullToAbsent) {
    return FinancialTransactionsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      amountCents: Value(amountCents),
      type: Value(type),
      transactionDate: Value(transactionDate),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      payee:
          payee == null && nullToAbsent ? const Value.absent() : Value(payee),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      destinationAccountId: destinationAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationAccountId),
      isSuperseded: Value(isSuperseded),
      correctedFromId: correctedFromId == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedFromId),
      correctionReason: correctionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(correctionReason),
      createdAt: Value(createdAt),
    );
  }

  factory FinancialTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FinancialTransaction(
      id: serializer.fromJson<String>(json['id']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      type: serializer.fromJson<String>(json['type']),
      transactionDate: serializer.fromJson<String>(json['transactionDate']),
      note: serializer.fromJson<String?>(json['note']),
      payee: serializer.fromJson<String?>(json['payee']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      destinationAccountId:
          serializer.fromJson<String?>(json['destinationAccountId']),
      isSuperseded: serializer.fromJson<bool>(json['isSuperseded']),
      correctedFromId: serializer.fromJson<String?>(json['correctedFromId']),
      correctionReason: serializer.fromJson<String?>(json['correctionReason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'categoryId': serializer.toJson<String>(categoryId),
      'amountCents': serializer.toJson<int>(amountCents),
      'type': serializer.toJson<String>(type),
      'transactionDate': serializer.toJson<String>(transactionDate),
      'note': serializer.toJson<String?>(note),
      'payee': serializer.toJson<String?>(payee),
      'accountId': serializer.toJson<String?>(accountId),
      'destinationAccountId': serializer.toJson<String?>(destinationAccountId),
      'isSuperseded': serializer.toJson<bool>(isSuperseded),
      'correctedFromId': serializer.toJson<String?>(correctedFromId),
      'correctionReason': serializer.toJson<String?>(correctionReason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FinancialTransaction copyWith(
          {String? id,
          String? categoryId,
          int? amountCents,
          String? type,
          String? transactionDate,
          Value<String?> note = const Value.absent(),
          Value<String?> payee = const Value.absent(),
          Value<String?> accountId = const Value.absent(),
          Value<String?> destinationAccountId = const Value.absent(),
          bool? isSuperseded,
          Value<String?> correctedFromId = const Value.absent(),
          Value<String?> correctionReason = const Value.absent(),
          DateTime? createdAt}) =>
      FinancialTransaction(
        id: id ?? this.id,
        categoryId: categoryId ?? this.categoryId,
        amountCents: amountCents ?? this.amountCents,
        type: type ?? this.type,
        transactionDate: transactionDate ?? this.transactionDate,
        note: note.present ? note.value : this.note,
        payee: payee.present ? payee.value : this.payee,
        accountId: accountId.present ? accountId.value : this.accountId,
        destinationAccountId: destinationAccountId.present
            ? destinationAccountId.value
            : this.destinationAccountId,
        isSuperseded: isSuperseded ?? this.isSuperseded,
        correctedFromId: correctedFromId.present
            ? correctedFromId.value
            : this.correctedFromId,
        correctionReason: correctionReason.present
            ? correctionReason.value
            : this.correctionReason,
        createdAt: createdAt ?? this.createdAt,
      );
  FinancialTransaction copyWithCompanion(FinancialTransactionsCompanion data) {
    return FinancialTransaction(
      id: data.id.present ? data.id.value : this.id,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      type: data.type.present ? data.type.value : this.type,
      transactionDate: data.transactionDate.present
          ? data.transactionDate.value
          : this.transactionDate,
      note: data.note.present ? data.note.value : this.note,
      payee: data.payee.present ? data.payee.value : this.payee,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      destinationAccountId: data.destinationAccountId.present
          ? data.destinationAccountId.value
          : this.destinationAccountId,
      isSuperseded: data.isSuperseded.present
          ? data.isSuperseded.value
          : this.isSuperseded,
      correctedFromId: data.correctedFromId.present
          ? data.correctedFromId.value
          : this.correctedFromId,
      correctionReason: data.correctionReason.present
          ? data.correctionReason.value
          : this.correctionReason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinancialTransaction(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountCents: $amountCents, ')
          ..write('type: $type, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('note: $note, ')
          ..write('payee: $payee, ')
          ..write('accountId: $accountId, ')
          ..write('destinationAccountId: $destinationAccountId, ')
          ..write('isSuperseded: $isSuperseded, ')
          ..write('correctedFromId: $correctedFromId, ')
          ..write('correctionReason: $correctionReason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      categoryId,
      amountCents,
      type,
      transactionDate,
      note,
      payee,
      accountId,
      destinationAccountId,
      isSuperseded,
      correctedFromId,
      correctionReason,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialTransaction &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.amountCents == this.amountCents &&
          other.type == this.type &&
          other.transactionDate == this.transactionDate &&
          other.note == this.note &&
          other.payee == this.payee &&
          other.accountId == this.accountId &&
          other.destinationAccountId == this.destinationAccountId &&
          other.isSuperseded == this.isSuperseded &&
          other.correctedFromId == this.correctedFromId &&
          other.correctionReason == this.correctionReason &&
          other.createdAt == this.createdAt);
}

class FinancialTransactionsCompanion
    extends UpdateCompanion<FinancialTransaction> {
  final Value<String> id;
  final Value<String> categoryId;
  final Value<int> amountCents;
  final Value<String> type;
  final Value<String> transactionDate;
  final Value<String?> note;
  final Value<String?> payee;
  final Value<String?> accountId;
  final Value<String?> destinationAccountId;
  final Value<bool> isSuperseded;
  final Value<String?> correctedFromId;
  final Value<String?> correctionReason;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FinancialTransactionsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.type = const Value.absent(),
    this.transactionDate = const Value.absent(),
    this.note = const Value.absent(),
    this.payee = const Value.absent(),
    this.accountId = const Value.absent(),
    this.destinationAccountId = const Value.absent(),
    this.isSuperseded = const Value.absent(),
    this.correctedFromId = const Value.absent(),
    this.correctionReason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinancialTransactionsCompanion.insert({
    required String id,
    required String categoryId,
    required int amountCents,
    required String type,
    required String transactionDate,
    this.note = const Value.absent(),
    this.payee = const Value.absent(),
    this.accountId = const Value.absent(),
    this.destinationAccountId = const Value.absent(),
    this.isSuperseded = const Value.absent(),
    this.correctedFromId = const Value.absent(),
    this.correctionReason = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        categoryId = Value(categoryId),
        amountCents = Value(amountCents),
        type = Value(type),
        transactionDate = Value(transactionDate),
        createdAt = Value(createdAt);
  static Insertable<FinancialTransaction> custom({
    Expression<String>? id,
    Expression<String>? categoryId,
    Expression<int>? amountCents,
    Expression<String>? type,
    Expression<String>? transactionDate,
    Expression<String>? note,
    Expression<String>? payee,
    Expression<String>? accountId,
    Expression<String>? destinationAccountId,
    Expression<bool>? isSuperseded,
    Expression<String>? correctedFromId,
    Expression<String>? correctionReason,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (amountCents != null) 'amount_cents': amountCents,
      if (type != null) 'type': type,
      if (transactionDate != null) 'transaction_date': transactionDate,
      if (note != null) 'note': note,
      if (payee != null) 'payee': payee,
      if (accountId != null) 'account_id': accountId,
      if (destinationAccountId != null)
        'destination_account_id': destinationAccountId,
      if (isSuperseded != null) 'is_superseded': isSuperseded,
      if (correctedFromId != null) 'corrected_from_id': correctedFromId,
      if (correctionReason != null) 'correction_reason': correctionReason,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinancialTransactionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? categoryId,
      Value<int>? amountCents,
      Value<String>? type,
      Value<String>? transactionDate,
      Value<String?>? note,
      Value<String?>? payee,
      Value<String?>? accountId,
      Value<String?>? destinationAccountId,
      Value<bool>? isSuperseded,
      Value<String?>? correctedFromId,
      Value<String?>? correctionReason,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return FinancialTransactionsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      amountCents: amountCents ?? this.amountCents,
      type: type ?? this.type,
      transactionDate: transactionDate ?? this.transactionDate,
      note: note ?? this.note,
      payee: payee ?? this.payee,
      accountId: accountId ?? this.accountId,
      destinationAccountId: destinationAccountId ?? this.destinationAccountId,
      isSuperseded: isSuperseded ?? this.isSuperseded,
      correctedFromId: correctedFromId ?? this.correctedFromId,
      correctionReason: correctionReason ?? this.correctionReason,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (transactionDate.present) {
      map['transaction_date'] = Variable<String>(transactionDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (payee.present) {
      map['payee'] = Variable<String>(payee.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (destinationAccountId.present) {
      map['destination_account_id'] =
          Variable<String>(destinationAccountId.value);
    }
    if (isSuperseded.present) {
      map['is_superseded'] = Variable<bool>(isSuperseded.value);
    }
    if (correctedFromId.present) {
      map['corrected_from_id'] = Variable<String>(correctedFromId.value);
    }
    if (correctionReason.present) {
      map['correction_reason'] = Variable<String>(correctionReason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinancialTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amountCents: $amountCents, ')
          ..write('type: $type, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('note: $note, ')
          ..write('payee: $payee, ')
          ..write('accountId: $accountId, ')
          ..write('destinationAccountId: $destinationAccountId, ')
          ..write('isSuperseded: $isSuperseded, ')
          ..write('correctedFromId: $correctedFromId, ')
          ..write('correctionReason: $correctionReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTableTable extends AccountsTable
    with TableInfo<$AccountsTableTable, AccountsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 150),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _subTypeMeta =
      const VerificationMeta('subType');
  @override
  late final GeneratedColumn<String> subType = GeneratedColumn<String>(
      'sub_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('cash'));
  static const VerificationMeta _isSystemMeta =
      const VerificationMeta('isSystem');
  @override
  late final GeneratedColumn<bool> isSystem = GeneratedColumn<bool>(
      'is_system', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_system" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _currencyCodeMeta =
      const VerificationMeta('currencyCode');
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
      'currency_code', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('ETB'));
  static const VerificationMeta _openingBalanceCentsMeta =
      const VerificationMeta('openingBalanceCents');
  @override
  late final GeneratedColumn<int> openingBalanceCents = GeneratedColumn<int>(
      'opening_balance_cents', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _openingBalanceDateMeta =
      const VerificationMeta('openingBalanceDate');
  @override
  late final GeneratedColumn<String> openingBalanceDate =
      GeneratedColumn<String>('opening_balance_date', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        type,
        subType,
        isSystem,
        currencyCode,
        openingBalanceCents,
        openingBalanceDate,
        isArchived,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts_table';
  @override
  VerificationContext validateIntegrity(Insertable<AccountsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('sub_type')) {
      context.handle(_subTypeMeta,
          subType.isAcceptableOrUnknown(data['sub_type']!, _subTypeMeta));
    }
    if (data.containsKey('is_system')) {
      context.handle(_isSystemMeta,
          isSystem.isAcceptableOrUnknown(data['is_system']!, _isSystemMeta));
    }
    if (data.containsKey('currency_code')) {
      context.handle(
          _currencyCodeMeta,
          currencyCode.isAcceptableOrUnknown(
              data['currency_code']!, _currencyCodeMeta));
    }
    if (data.containsKey('opening_balance_cents')) {
      context.handle(
          _openingBalanceCentsMeta,
          openingBalanceCents.isAcceptableOrUnknown(
              data['opening_balance_cents']!, _openingBalanceCentsMeta));
    }
    if (data.containsKey('opening_balance_date')) {
      context.handle(
          _openingBalanceDateMeta,
          openingBalanceDate.isAcceptableOrUnknown(
              data['opening_balance_date']!, _openingBalanceDateMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AccountsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AccountsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      subType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sub_type'])!,
      isSystem: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_system'])!,
      currencyCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}currency_code'])!,
      openingBalanceCents: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}opening_balance_cents'])!,
      openingBalanceDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}opening_balance_date']),
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $AccountsTableTable createAlias(String alias) {
    return $AccountsTableTable(attachedDatabase, alias);
  }
}

class AccountsTableData extends DataClass
    implements Insertable<AccountsTableData> {
  final String id;
  final String name;
  final String type;
  final String subType;
  final bool isSystem;
  final String currencyCode;
  final int openingBalanceCents;
  final String? openingBalanceDate;
  final bool isArchived;
  final DateTime createdAt;
  const AccountsTableData(
      {required this.id,
      required this.name,
      required this.type,
      required this.subType,
      required this.isSystem,
      required this.currencyCode,
      required this.openingBalanceCents,
      this.openingBalanceDate,
      required this.isArchived,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['sub_type'] = Variable<String>(subType);
    map['is_system'] = Variable<bool>(isSystem);
    map['currency_code'] = Variable<String>(currencyCode);
    map['opening_balance_cents'] = Variable<int>(openingBalanceCents);
    if (!nullToAbsent || openingBalanceDate != null) {
      map['opening_balance_date'] = Variable<String>(openingBalanceDate);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AccountsTableCompanion toCompanion(bool nullToAbsent) {
    return AccountsTableCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      subType: Value(subType),
      isSystem: Value(isSystem),
      currencyCode: Value(currencyCode),
      openingBalanceCents: Value(openingBalanceCents),
      openingBalanceDate: openingBalanceDate == null && nullToAbsent
          ? const Value.absent()
          : Value(openingBalanceDate),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
    );
  }

  factory AccountsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AccountsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      subType: serializer.fromJson<String>(json['subType']),
      isSystem: serializer.fromJson<bool>(json['isSystem']),
      currencyCode: serializer.fromJson<String>(json['currencyCode']),
      openingBalanceCents:
          serializer.fromJson<int>(json['openingBalanceCents']),
      openingBalanceDate:
          serializer.fromJson<String?>(json['openingBalanceDate']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'subType': serializer.toJson<String>(subType),
      'isSystem': serializer.toJson<bool>(isSystem),
      'currencyCode': serializer.toJson<String>(currencyCode),
      'openingBalanceCents': serializer.toJson<int>(openingBalanceCents),
      'openingBalanceDate': serializer.toJson<String?>(openingBalanceDate),
      'isArchived': serializer.toJson<bool>(isArchived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AccountsTableData copyWith(
          {String? id,
          String? name,
          String? type,
          String? subType,
          bool? isSystem,
          String? currencyCode,
          int? openingBalanceCents,
          Value<String?> openingBalanceDate = const Value.absent(),
          bool? isArchived,
          DateTime? createdAt}) =>
      AccountsTableData(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        subType: subType ?? this.subType,
        isSystem: isSystem ?? this.isSystem,
        currencyCode: currencyCode ?? this.currencyCode,
        openingBalanceCents: openingBalanceCents ?? this.openingBalanceCents,
        openingBalanceDate: openingBalanceDate.present
            ? openingBalanceDate.value
            : this.openingBalanceDate,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt ?? this.createdAt,
      );
  AccountsTableData copyWithCompanion(AccountsTableCompanion data) {
    return AccountsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      subType: data.subType.present ? data.subType.value : this.subType,
      isSystem: data.isSystem.present ? data.isSystem.value : this.isSystem,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      openingBalanceCents: data.openingBalanceCents.present
          ? data.openingBalanceCents.value
          : this.openingBalanceCents,
      openingBalanceDate: data.openingBalanceDate.present
          ? data.openingBalanceDate.value
          : this.openingBalanceDate,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AccountsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('subType: $subType, ')
          ..write('isSystem: $isSystem, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('openingBalanceCents: $openingBalanceCents, ')
          ..write('openingBalanceDate: $openingBalanceDate, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      type,
      subType,
      isSystem,
      currencyCode,
      openingBalanceCents,
      openingBalanceDate,
      isArchived,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.subType == this.subType &&
          other.isSystem == this.isSystem &&
          other.currencyCode == this.currencyCode &&
          other.openingBalanceCents == this.openingBalanceCents &&
          other.openingBalanceDate == this.openingBalanceDate &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt);
}

class AccountsTableCompanion extends UpdateCompanion<AccountsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> subType;
  final Value<bool> isSystem;
  final Value<String> currencyCode;
  final Value<int> openingBalanceCents;
  final Value<String?> openingBalanceDate;
  final Value<bool> isArchived;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AccountsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.subType = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.openingBalanceCents = const Value.absent(),
    this.openingBalanceDate = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsTableCompanion.insert({
    required String id,
    required String name,
    required String type,
    this.subType = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.openingBalanceCents = const Value.absent(),
    this.openingBalanceDate = const Value.absent(),
    this.isArchived = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        type = Value(type),
        createdAt = Value(createdAt);
  static Insertable<AccountsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? subType,
    Expression<bool>? isSystem,
    Expression<String>? currencyCode,
    Expression<int>? openingBalanceCents,
    Expression<String>? openingBalanceDate,
    Expression<bool>? isArchived,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (subType != null) 'sub_type': subType,
      if (isSystem != null) 'is_system': isSystem,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (openingBalanceCents != null)
        'opening_balance_cents': openingBalanceCents,
      if (openingBalanceDate != null)
        'opening_balance_date': openingBalanceDate,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? type,
      Value<String>? subType,
      Value<bool>? isSystem,
      Value<String>? currencyCode,
      Value<int>? openingBalanceCents,
      Value<String?>? openingBalanceDate,
      Value<bool>? isArchived,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return AccountsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      subType: subType ?? this.subType,
      isSystem: isSystem ?? this.isSystem,
      currencyCode: currencyCode ?? this.currencyCode,
      openingBalanceCents: openingBalanceCents ?? this.openingBalanceCents,
      openingBalanceDate: openingBalanceDate ?? this.openingBalanceDate,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (subType.present) {
      map['sub_type'] = Variable<String>(subType.value);
    }
    if (isSystem.present) {
      map['is_system'] = Variable<bool>(isSystem.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (openingBalanceCents.present) {
      map['opening_balance_cents'] = Variable<int>(openingBalanceCents.value);
    }
    if (openingBalanceDate.present) {
      map['opening_balance_date'] = Variable<String>(openingBalanceDate.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('subType: $subType, ')
          ..write('isSystem: $isSystem, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('openingBalanceCents: $openingBalanceCents, ')
          ..write('openingBalanceDate: $openingBalanceDate, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JournalEntriesTableTable extends JournalEntriesTable
    with TableInfo<$JournalEntriesTableTable, JournalEntriesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JournalEntriesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entryTypeMeta =
      const VerificationMeta('entryType');
  @override
  late final GeneratedColumn<String> entryType = GeneratedColumn<String>(
      'entry_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _occurrenceDateMeta =
      const VerificationMeta('occurrenceDate');
  @override
  late final GeneratedColumn<String> occurrenceDate = GeneratedColumn<String>(
      'occurrence_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isVoidedMeta =
      const VerificationMeta('isVoided');
  @override
  late final GeneratedColumn<bool> isVoided = GeneratedColumn<bool>(
      'is_voided', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_voided" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _voidReasonMeta =
      const VerificationMeta('voidReason');
  @override
  late final GeneratedColumn<String> voidReason = GeneratedColumn<String>(
      'void_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _legacySourceTxIdMeta =
      const VerificationMeta('legacySourceTxId');
  @override
  late final GeneratedColumn<String> legacySourceTxId = GeneratedColumn<String>(
      'legacy_source_tx_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _correctedFromEntryIdMeta =
      const VerificationMeta('correctedFromEntryId');
  @override
  late final GeneratedColumn<String> correctedFromEntryId =
      GeneratedColumn<String>(
          'corrected_from_entry_id', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entryType,
        description,
        occurrenceDate,
        isVoided,
        voidReason,
        legacySourceTxId,
        correctedFromEntryId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'journal_entries_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<JournalEntriesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_type')) {
      context.handle(_entryTypeMeta,
          entryType.isAcceptableOrUnknown(data['entry_type']!, _entryTypeMeta));
    } else if (isInserting) {
      context.missing(_entryTypeMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('occurrence_date')) {
      context.handle(
          _occurrenceDateMeta,
          occurrenceDate.isAcceptableOrUnknown(
              data['occurrence_date']!, _occurrenceDateMeta));
    } else if (isInserting) {
      context.missing(_occurrenceDateMeta);
    }
    if (data.containsKey('is_voided')) {
      context.handle(_isVoidedMeta,
          isVoided.isAcceptableOrUnknown(data['is_voided']!, _isVoidedMeta));
    }
    if (data.containsKey('void_reason')) {
      context.handle(
          _voidReasonMeta,
          voidReason.isAcceptableOrUnknown(
              data['void_reason']!, _voidReasonMeta));
    }
    if (data.containsKey('legacy_source_tx_id')) {
      context.handle(
          _legacySourceTxIdMeta,
          legacySourceTxId.isAcceptableOrUnknown(
              data['legacy_source_tx_id']!, _legacySourceTxIdMeta));
    }
    if (data.containsKey('corrected_from_entry_id')) {
      context.handle(
          _correctedFromEntryIdMeta,
          correctedFromEntryId.isAcceptableOrUnknown(
              data['corrected_from_entry_id']!, _correctedFromEntryIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JournalEntriesTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JournalEntriesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      entryType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entry_type'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      occurrenceDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}occurrence_date'])!,
      isVoided: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_voided'])!,
      voidReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}void_reason']),
      legacySourceTxId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}legacy_source_tx_id']),
      correctedFromEntryId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}corrected_from_entry_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $JournalEntriesTableTable createAlias(String alias) {
    return $JournalEntriesTableTable(attachedDatabase, alias);
  }
}

class JournalEntriesTableData extends DataClass
    implements Insertable<JournalEntriesTableData> {
  final String id;
  final String entryType;
  final String description;
  final String occurrenceDate;
  final bool isVoided;
  final String? voidReason;
  final String? legacySourceTxId;
  final String? correctedFromEntryId;
  final DateTime createdAt;
  const JournalEntriesTableData(
      {required this.id,
      required this.entryType,
      required this.description,
      required this.occurrenceDate,
      required this.isVoided,
      this.voidReason,
      this.legacySourceTxId,
      this.correctedFromEntryId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_type'] = Variable<String>(entryType);
    map['description'] = Variable<String>(description);
    map['occurrence_date'] = Variable<String>(occurrenceDate);
    map['is_voided'] = Variable<bool>(isVoided);
    if (!nullToAbsent || voidReason != null) {
      map['void_reason'] = Variable<String>(voidReason);
    }
    if (!nullToAbsent || legacySourceTxId != null) {
      map['legacy_source_tx_id'] = Variable<String>(legacySourceTxId);
    }
    if (!nullToAbsent || correctedFromEntryId != null) {
      map['corrected_from_entry_id'] = Variable<String>(correctedFromEntryId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  JournalEntriesTableCompanion toCompanion(bool nullToAbsent) {
    return JournalEntriesTableCompanion(
      id: Value(id),
      entryType: Value(entryType),
      description: Value(description),
      occurrenceDate: Value(occurrenceDate),
      isVoided: Value(isVoided),
      voidReason: voidReason == null && nullToAbsent
          ? const Value.absent()
          : Value(voidReason),
      legacySourceTxId: legacySourceTxId == null && nullToAbsent
          ? const Value.absent()
          : Value(legacySourceTxId),
      correctedFromEntryId: correctedFromEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedFromEntryId),
      createdAt: Value(createdAt),
    );
  }

  factory JournalEntriesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JournalEntriesTableData(
      id: serializer.fromJson<String>(json['id']),
      entryType: serializer.fromJson<String>(json['entryType']),
      description: serializer.fromJson<String>(json['description']),
      occurrenceDate: serializer.fromJson<String>(json['occurrenceDate']),
      isVoided: serializer.fromJson<bool>(json['isVoided']),
      voidReason: serializer.fromJson<String?>(json['voidReason']),
      legacySourceTxId: serializer.fromJson<String?>(json['legacySourceTxId']),
      correctedFromEntryId:
          serializer.fromJson<String?>(json['correctedFromEntryId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryType': serializer.toJson<String>(entryType),
      'description': serializer.toJson<String>(description),
      'occurrenceDate': serializer.toJson<String>(occurrenceDate),
      'isVoided': serializer.toJson<bool>(isVoided),
      'voidReason': serializer.toJson<String?>(voidReason),
      'legacySourceTxId': serializer.toJson<String?>(legacySourceTxId),
      'correctedFromEntryId': serializer.toJson<String?>(correctedFromEntryId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  JournalEntriesTableData copyWith(
          {String? id,
          String? entryType,
          String? description,
          String? occurrenceDate,
          bool? isVoided,
          Value<String?> voidReason = const Value.absent(),
          Value<String?> legacySourceTxId = const Value.absent(),
          Value<String?> correctedFromEntryId = const Value.absent(),
          DateTime? createdAt}) =>
      JournalEntriesTableData(
        id: id ?? this.id,
        entryType: entryType ?? this.entryType,
        description: description ?? this.description,
        occurrenceDate: occurrenceDate ?? this.occurrenceDate,
        isVoided: isVoided ?? this.isVoided,
        voidReason: voidReason.present ? voidReason.value : this.voidReason,
        legacySourceTxId: legacySourceTxId.present
            ? legacySourceTxId.value
            : this.legacySourceTxId,
        correctedFromEntryId: correctedFromEntryId.present
            ? correctedFromEntryId.value
            : this.correctedFromEntryId,
        createdAt: createdAt ?? this.createdAt,
      );
  JournalEntriesTableData copyWithCompanion(JournalEntriesTableCompanion data) {
    return JournalEntriesTableData(
      id: data.id.present ? data.id.value : this.id,
      entryType: data.entryType.present ? data.entryType.value : this.entryType,
      description:
          data.description.present ? data.description.value : this.description,
      occurrenceDate: data.occurrenceDate.present
          ? data.occurrenceDate.value
          : this.occurrenceDate,
      isVoided: data.isVoided.present ? data.isVoided.value : this.isVoided,
      voidReason:
          data.voidReason.present ? data.voidReason.value : this.voidReason,
      legacySourceTxId: data.legacySourceTxId.present
          ? data.legacySourceTxId.value
          : this.legacySourceTxId,
      correctedFromEntryId: data.correctedFromEntryId.present
          ? data.correctedFromEntryId.value
          : this.correctedFromEntryId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesTableData(')
          ..write('id: $id, ')
          ..write('entryType: $entryType, ')
          ..write('description: $description, ')
          ..write('occurrenceDate: $occurrenceDate, ')
          ..write('isVoided: $isVoided, ')
          ..write('voidReason: $voidReason, ')
          ..write('legacySourceTxId: $legacySourceTxId, ')
          ..write('correctedFromEntryId: $correctedFromEntryId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entryType, description, occurrenceDate,
      isVoided, voidReason, legacySourceTxId, correctedFromEntryId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JournalEntriesTableData &&
          other.id == this.id &&
          other.entryType == this.entryType &&
          other.description == this.description &&
          other.occurrenceDate == this.occurrenceDate &&
          other.isVoided == this.isVoided &&
          other.voidReason == this.voidReason &&
          other.legacySourceTxId == this.legacySourceTxId &&
          other.correctedFromEntryId == this.correctedFromEntryId &&
          other.createdAt == this.createdAt);
}

class JournalEntriesTableCompanion
    extends UpdateCompanion<JournalEntriesTableData> {
  final Value<String> id;
  final Value<String> entryType;
  final Value<String> description;
  final Value<String> occurrenceDate;
  final Value<bool> isVoided;
  final Value<String?> voidReason;
  final Value<String?> legacySourceTxId;
  final Value<String?> correctedFromEntryId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const JournalEntriesTableCompanion({
    this.id = const Value.absent(),
    this.entryType = const Value.absent(),
    this.description = const Value.absent(),
    this.occurrenceDate = const Value.absent(),
    this.isVoided = const Value.absent(),
    this.voidReason = const Value.absent(),
    this.legacySourceTxId = const Value.absent(),
    this.correctedFromEntryId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JournalEntriesTableCompanion.insert({
    required String id,
    required String entryType,
    required String description,
    required String occurrenceDate,
    this.isVoided = const Value.absent(),
    this.voidReason = const Value.absent(),
    this.legacySourceTxId = const Value.absent(),
    this.correctedFromEntryId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        entryType = Value(entryType),
        description = Value(description),
        occurrenceDate = Value(occurrenceDate),
        createdAt = Value(createdAt);
  static Insertable<JournalEntriesTableData> custom({
    Expression<String>? id,
    Expression<String>? entryType,
    Expression<String>? description,
    Expression<String>? occurrenceDate,
    Expression<bool>? isVoided,
    Expression<String>? voidReason,
    Expression<String>? legacySourceTxId,
    Expression<String>? correctedFromEntryId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryType != null) 'entry_type': entryType,
      if (description != null) 'description': description,
      if (occurrenceDate != null) 'occurrence_date': occurrenceDate,
      if (isVoided != null) 'is_voided': isVoided,
      if (voidReason != null) 'void_reason': voidReason,
      if (legacySourceTxId != null) 'legacy_source_tx_id': legacySourceTxId,
      if (correctedFromEntryId != null)
        'corrected_from_entry_id': correctedFromEntryId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JournalEntriesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? entryType,
      Value<String>? description,
      Value<String>? occurrenceDate,
      Value<bool>? isVoided,
      Value<String?>? voidReason,
      Value<String?>? legacySourceTxId,
      Value<String?>? correctedFromEntryId,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return JournalEntriesTableCompanion(
      id: id ?? this.id,
      entryType: entryType ?? this.entryType,
      description: description ?? this.description,
      occurrenceDate: occurrenceDate ?? this.occurrenceDate,
      isVoided: isVoided ?? this.isVoided,
      voidReason: voidReason ?? this.voidReason,
      legacySourceTxId: legacySourceTxId ?? this.legacySourceTxId,
      correctedFromEntryId: correctedFromEntryId ?? this.correctedFromEntryId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryType.present) {
      map['entry_type'] = Variable<String>(entryType.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (occurrenceDate.present) {
      map['occurrence_date'] = Variable<String>(occurrenceDate.value);
    }
    if (isVoided.present) {
      map['is_voided'] = Variable<bool>(isVoided.value);
    }
    if (voidReason.present) {
      map['void_reason'] = Variable<String>(voidReason.value);
    }
    if (legacySourceTxId.present) {
      map['legacy_source_tx_id'] = Variable<String>(legacySourceTxId.value);
    }
    if (correctedFromEntryId.present) {
      map['corrected_from_entry_id'] =
          Variable<String>(correctedFromEntryId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JournalEntriesTableCompanion(')
          ..write('id: $id, ')
          ..write('entryType: $entryType, ')
          ..write('description: $description, ')
          ..write('occurrenceDate: $occurrenceDate, ')
          ..write('isVoided: $isVoided, ')
          ..write('voidReason: $voidReason, ')
          ..write('legacySourceTxId: $legacySourceTxId, ')
          ..write('correctedFromEntryId: $correctedFromEntryId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PartiesTableTable extends PartiesTable
    with TableInfo<$PartiesTableTable, PartiesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PartiesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 150),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, phone, notes, isArchived, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'parties_table';
  @override
  VerificationContext validateIntegrity(Insertable<PartiesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PartiesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PartiesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PartiesTableTable createAlias(String alias) {
    return $PartiesTableTable(attachedDatabase, alias);
  }
}

class PartiesTableData extends DataClass
    implements Insertable<PartiesTableData> {
  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final bool isArchived;
  final DateTime createdAt;
  const PartiesTableData(
      {required this.id,
      required this.name,
      this.phone,
      this.notes,
      required this.isArchived,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['is_archived'] = Variable<bool>(isArchived);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PartiesTableCompanion toCompanion(bool nullToAbsent) {
    return PartiesTableCompanion(
      id: Value(id),
      name: Value(name),
      phone:
          phone == null && nullToAbsent ? const Value.absent() : Value(phone),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      isArchived: Value(isArchived),
      createdAt: Value(createdAt),
    );
  }

  factory PartiesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PartiesTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      notes: serializer.fromJson<String?>(json['notes']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'notes': serializer.toJson<String?>(notes),
      'isArchived': serializer.toJson<bool>(isArchived),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PartiesTableData copyWith(
          {String? id,
          String? name,
          Value<String?> phone = const Value.absent(),
          Value<String?> notes = const Value.absent(),
          bool? isArchived,
          DateTime? createdAt}) =>
      PartiesTableData(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone.present ? phone.value : this.phone,
        notes: notes.present ? notes.value : this.notes,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt ?? this.createdAt,
      );
  PartiesTableData copyWithCompanion(PartiesTableCompanion data) {
    return PartiesTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      notes: data.notes.present ? data.notes.value : this.notes,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PartiesTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, phone, notes, isArchived, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PartiesTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.notes == this.notes &&
          other.isArchived == this.isArchived &&
          other.createdAt == this.createdAt);
}

class PartiesTableCompanion extends UpdateCompanion<PartiesTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> notes;
  final Value<bool> isArchived;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PartiesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PartiesTableCompanion.insert({
    required String id,
    required String name,
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.isArchived = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<PartiesTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? notes,
    Expression<bool>? isArchived,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
      if (isArchived != null) 'is_archived': isArchived,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PartiesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? phone,
      Value<String?>? notes,
      Value<bool>? isArchived,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PartiesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PartiesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('isArchived: $isArchived, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DebtsTableTable extends DebtsTable
    with TableInfo<$DebtsTableTable, DebtsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DebtsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _originEntryIdMeta =
      const VerificationMeta('originEntryId');
  @override
  late final GeneratedColumn<String> originEntryId = GeneratedColumn<String>(
      'origin_entry_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _partyIdMeta =
      const VerificationMeta('partyId');
  @override
  late final GeneratedColumn<String> partyId = GeneratedColumn<String>(
      'party_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES parties_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _debtTypeMeta =
      const VerificationMeta('debtType');
  @override
  late final GeneratedColumn<String> debtType = GeneratedColumn<String>(
      'debt_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _principalCentsMeta =
      const VerificationMeta('principalCents');
  @override
  late final GeneratedColumn<int> principalCents = GeneratedColumn<int>(
      'principal_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _outstandingCentsMeta =
      const VerificationMeta('outstandingCents');
  @override
  late final GeneratedColumn<int> outstandingCents = GeneratedColumn<int>(
      'outstanding_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dueDateMeta =
      const VerificationMeta('dueDate');
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
      'due_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _writeOffEntryIdMeta =
      const VerificationMeta('writeOffEntryId');
  @override
  late final GeneratedColumn<String> writeOffEntryId = GeneratedColumn<String>(
      'write_off_entry_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        originEntryId,
        partyId,
        debtType,
        principalCents,
        outstandingCents,
        dueDate,
        status,
        writeOffEntryId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'debts_table';
  @override
  VerificationContext validateIntegrity(Insertable<DebtsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('origin_entry_id')) {
      context.handle(
          _originEntryIdMeta,
          originEntryId.isAcceptableOrUnknown(
              data['origin_entry_id']!, _originEntryIdMeta));
    } else if (isInserting) {
      context.missing(_originEntryIdMeta);
    }
    if (data.containsKey('party_id')) {
      context.handle(_partyIdMeta,
          partyId.isAcceptableOrUnknown(data['party_id']!, _partyIdMeta));
    } else if (isInserting) {
      context.missing(_partyIdMeta);
    }
    if (data.containsKey('debt_type')) {
      context.handle(_debtTypeMeta,
          debtType.isAcceptableOrUnknown(data['debt_type']!, _debtTypeMeta));
    } else if (isInserting) {
      context.missing(_debtTypeMeta);
    }
    if (data.containsKey('principal_cents')) {
      context.handle(
          _principalCentsMeta,
          principalCents.isAcceptableOrUnknown(
              data['principal_cents']!, _principalCentsMeta));
    } else if (isInserting) {
      context.missing(_principalCentsMeta);
    }
    if (data.containsKey('outstanding_cents')) {
      context.handle(
          _outstandingCentsMeta,
          outstandingCents.isAcceptableOrUnknown(
              data['outstanding_cents']!, _outstandingCentsMeta));
    } else if (isInserting) {
      context.missing(_outstandingCentsMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(_dueDateMeta,
          dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('write_off_entry_id')) {
      context.handle(
          _writeOffEntryIdMeta,
          writeOffEntryId.isAcceptableOrUnknown(
              data['write_off_entry_id']!, _writeOffEntryIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DebtsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DebtsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      originEntryId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}origin_entry_id'])!,
      partyId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}party_id'])!,
      debtType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}debt_type'])!,
      principalCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}principal_cents'])!,
      outstandingCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}outstanding_cents'])!,
      dueDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}due_date']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      writeOffEntryId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}write_off_entry_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $DebtsTableTable createAlias(String alias) {
    return $DebtsTableTable(attachedDatabase, alias);
  }
}

class DebtsTableData extends DataClass implements Insertable<DebtsTableData> {
  final String id;
  final String originEntryId;
  final String partyId;
  final String debtType;
  final int principalCents;
  final int outstandingCents;
  final String? dueDate;
  final String status;
  final String? writeOffEntryId;
  final DateTime createdAt;
  const DebtsTableData(
      {required this.id,
      required this.originEntryId,
      required this.partyId,
      required this.debtType,
      required this.principalCents,
      required this.outstandingCents,
      this.dueDate,
      required this.status,
      this.writeOffEntryId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['origin_entry_id'] = Variable<String>(originEntryId);
    map['party_id'] = Variable<String>(partyId);
    map['debt_type'] = Variable<String>(debtType);
    map['principal_cents'] = Variable<int>(principalCents);
    map['outstanding_cents'] = Variable<int>(outstandingCents);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<String>(dueDate);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || writeOffEntryId != null) {
      map['write_off_entry_id'] = Variable<String>(writeOffEntryId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DebtsTableCompanion toCompanion(bool nullToAbsent) {
    return DebtsTableCompanion(
      id: Value(id),
      originEntryId: Value(originEntryId),
      partyId: Value(partyId),
      debtType: Value(debtType),
      principalCents: Value(principalCents),
      outstandingCents: Value(outstandingCents),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      status: Value(status),
      writeOffEntryId: writeOffEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(writeOffEntryId),
      createdAt: Value(createdAt),
    );
  }

  factory DebtsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DebtsTableData(
      id: serializer.fromJson<String>(json['id']),
      originEntryId: serializer.fromJson<String>(json['originEntryId']),
      partyId: serializer.fromJson<String>(json['partyId']),
      debtType: serializer.fromJson<String>(json['debtType']),
      principalCents: serializer.fromJson<int>(json['principalCents']),
      outstandingCents: serializer.fromJson<int>(json['outstandingCents']),
      dueDate: serializer.fromJson<String?>(json['dueDate']),
      status: serializer.fromJson<String>(json['status']),
      writeOffEntryId: serializer.fromJson<String?>(json['writeOffEntryId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'originEntryId': serializer.toJson<String>(originEntryId),
      'partyId': serializer.toJson<String>(partyId),
      'debtType': serializer.toJson<String>(debtType),
      'principalCents': serializer.toJson<int>(principalCents),
      'outstandingCents': serializer.toJson<int>(outstandingCents),
      'dueDate': serializer.toJson<String?>(dueDate),
      'status': serializer.toJson<String>(status),
      'writeOffEntryId': serializer.toJson<String?>(writeOffEntryId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DebtsTableData copyWith(
          {String? id,
          String? originEntryId,
          String? partyId,
          String? debtType,
          int? principalCents,
          int? outstandingCents,
          Value<String?> dueDate = const Value.absent(),
          String? status,
          Value<String?> writeOffEntryId = const Value.absent(),
          DateTime? createdAt}) =>
      DebtsTableData(
        id: id ?? this.id,
        originEntryId: originEntryId ?? this.originEntryId,
        partyId: partyId ?? this.partyId,
        debtType: debtType ?? this.debtType,
        principalCents: principalCents ?? this.principalCents,
        outstandingCents: outstandingCents ?? this.outstandingCents,
        dueDate: dueDate.present ? dueDate.value : this.dueDate,
        status: status ?? this.status,
        writeOffEntryId: writeOffEntryId.present
            ? writeOffEntryId.value
            : this.writeOffEntryId,
        createdAt: createdAt ?? this.createdAt,
      );
  DebtsTableData copyWithCompanion(DebtsTableCompanion data) {
    return DebtsTableData(
      id: data.id.present ? data.id.value : this.id,
      originEntryId: data.originEntryId.present
          ? data.originEntryId.value
          : this.originEntryId,
      partyId: data.partyId.present ? data.partyId.value : this.partyId,
      debtType: data.debtType.present ? data.debtType.value : this.debtType,
      principalCents: data.principalCents.present
          ? data.principalCents.value
          : this.principalCents,
      outstandingCents: data.outstandingCents.present
          ? data.outstandingCents.value
          : this.outstandingCents,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      status: data.status.present ? data.status.value : this.status,
      writeOffEntryId: data.writeOffEntryId.present
          ? data.writeOffEntryId.value
          : this.writeOffEntryId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DebtsTableData(')
          ..write('id: $id, ')
          ..write('originEntryId: $originEntryId, ')
          ..write('partyId: $partyId, ')
          ..write('debtType: $debtType, ')
          ..write('principalCents: $principalCents, ')
          ..write('outstandingCents: $outstandingCents, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('writeOffEntryId: $writeOffEntryId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      originEntryId,
      partyId,
      debtType,
      principalCents,
      outstandingCents,
      dueDate,
      status,
      writeOffEntryId,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DebtsTableData &&
          other.id == this.id &&
          other.originEntryId == this.originEntryId &&
          other.partyId == this.partyId &&
          other.debtType == this.debtType &&
          other.principalCents == this.principalCents &&
          other.outstandingCents == this.outstandingCents &&
          other.dueDate == this.dueDate &&
          other.status == this.status &&
          other.writeOffEntryId == this.writeOffEntryId &&
          other.createdAt == this.createdAt);
}

class DebtsTableCompanion extends UpdateCompanion<DebtsTableData> {
  final Value<String> id;
  final Value<String> originEntryId;
  final Value<String> partyId;
  final Value<String> debtType;
  final Value<int> principalCents;
  final Value<int> outstandingCents;
  final Value<String?> dueDate;
  final Value<String> status;
  final Value<String?> writeOffEntryId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DebtsTableCompanion({
    this.id = const Value.absent(),
    this.originEntryId = const Value.absent(),
    this.partyId = const Value.absent(),
    this.debtType = const Value.absent(),
    this.principalCents = const Value.absent(),
    this.outstandingCents = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.status = const Value.absent(),
    this.writeOffEntryId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DebtsTableCompanion.insert({
    required String id,
    required String originEntryId,
    required String partyId,
    required String debtType,
    required int principalCents,
    required int outstandingCents,
    this.dueDate = const Value.absent(),
    this.status = const Value.absent(),
    this.writeOffEntryId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        originEntryId = Value(originEntryId),
        partyId = Value(partyId),
        debtType = Value(debtType),
        principalCents = Value(principalCents),
        outstandingCents = Value(outstandingCents),
        createdAt = Value(createdAt);
  static Insertable<DebtsTableData> custom({
    Expression<String>? id,
    Expression<String>? originEntryId,
    Expression<String>? partyId,
    Expression<String>? debtType,
    Expression<int>? principalCents,
    Expression<int>? outstandingCents,
    Expression<String>? dueDate,
    Expression<String>? status,
    Expression<String>? writeOffEntryId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (originEntryId != null) 'origin_entry_id': originEntryId,
      if (partyId != null) 'party_id': partyId,
      if (debtType != null) 'debt_type': debtType,
      if (principalCents != null) 'principal_cents': principalCents,
      if (outstandingCents != null) 'outstanding_cents': outstandingCents,
      if (dueDate != null) 'due_date': dueDate,
      if (status != null) 'status': status,
      if (writeOffEntryId != null) 'write_off_entry_id': writeOffEntryId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DebtsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? originEntryId,
      Value<String>? partyId,
      Value<String>? debtType,
      Value<int>? principalCents,
      Value<int>? outstandingCents,
      Value<String?>? dueDate,
      Value<String>? status,
      Value<String?>? writeOffEntryId,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return DebtsTableCompanion(
      id: id ?? this.id,
      originEntryId: originEntryId ?? this.originEntryId,
      partyId: partyId ?? this.partyId,
      debtType: debtType ?? this.debtType,
      principalCents: principalCents ?? this.principalCents,
      outstandingCents: outstandingCents ?? this.outstandingCents,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      writeOffEntryId: writeOffEntryId ?? this.writeOffEntryId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (originEntryId.present) {
      map['origin_entry_id'] = Variable<String>(originEntryId.value);
    }
    if (partyId.present) {
      map['party_id'] = Variable<String>(partyId.value);
    }
    if (debtType.present) {
      map['debt_type'] = Variable<String>(debtType.value);
    }
    if (principalCents.present) {
      map['principal_cents'] = Variable<int>(principalCents.value);
    }
    if (outstandingCents.present) {
      map['outstanding_cents'] = Variable<int>(outstandingCents.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (writeOffEntryId.present) {
      map['write_off_entry_id'] = Variable<String>(writeOffEntryId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DebtsTableCompanion(')
          ..write('id: $id, ')
          ..write('originEntryId: $originEntryId, ')
          ..write('partyId: $partyId, ')
          ..write('debtType: $debtType, ')
          ..write('principalCents: $principalCents, ')
          ..write('outstandingCents: $outstandingCents, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('writeOffEntryId: $writeOffEntryId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecurringRulesTableTable extends RecurringRulesTable
    with TableInfo<$RecurringRulesTableTable, RecurringRulesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringRulesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _ruleTypeMeta =
      const VerificationMeta('ruleType');
  @override
  late final GeneratedColumn<String> ruleType = GeneratedColumn<String>(
      'rule_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _frequencyMeta =
      const VerificationMeta('frequency');
  @override
  late final GeneratedColumn<String> frequency = GeneratedColumn<String>(
      'frequency', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _intervalMeta =
      const VerificationMeta('interval');
  @override
  late final GeneratedColumn<int> interval = GeneratedColumn<int>(
      'interval', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _startDateMeta =
      const VerificationMeta('startDate');
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
      'start_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nextOccurrenceDateMeta =
      const VerificationMeta('nextOccurrenceDate');
  @override
  late final GeneratedColumn<String> nextOccurrenceDate =
      GeneratedColumn<String>('next_occurrence_date', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _endDateMeta =
      const VerificationMeta('endDate');
  @override
  late final GeneratedColumn<String> endDate = GeneratedColumn<String>(
      'end_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES accounts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _destinationAccountIdMeta =
      const VerificationMeta('destinationAccountId');
  @override
  late final GeneratedColumn<String> destinationAccountId =
      GeneratedColumn<String>(
          'destination_account_id', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'REFERENCES accounts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_categories (id) ON DELETE RESTRICT'));
  static const VerificationMeta _linkedDebtIdMeta =
      const VerificationMeta('linkedDebtId');
  @override
  late final GeneratedColumn<String> linkedDebtId = GeneratedColumn<String>(
      'linked_debt_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES debts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _autoPostMeta =
      const VerificationMeta('autoPost');
  @override
  late final GeneratedColumn<bool> autoPost = GeneratedColumn<bool>(
      'auto_post', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("auto_post" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        ruleType,
        amountCents,
        frequency,
        interval,
        startDate,
        nextOccurrenceDate,
        endDate,
        accountId,
        destinationAccountId,
        categoryId,
        linkedDebtId,
        isActive,
        autoPost,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurring_rules_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<RecurringRulesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('rule_type')) {
      context.handle(_ruleTypeMeta,
          ruleType.isAcceptableOrUnknown(data['rule_type']!, _ruleTypeMeta));
    } else if (isInserting) {
      context.missing(_ruleTypeMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('frequency')) {
      context.handle(_frequencyMeta,
          frequency.isAcceptableOrUnknown(data['frequency']!, _frequencyMeta));
    } else if (isInserting) {
      context.missing(_frequencyMeta);
    }
    if (data.containsKey('interval')) {
      context.handle(_intervalMeta,
          interval.isAcceptableOrUnknown(data['interval']!, _intervalMeta));
    }
    if (data.containsKey('start_date')) {
      context.handle(_startDateMeta,
          startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta));
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('next_occurrence_date')) {
      context.handle(
          _nextOccurrenceDateMeta,
          nextOccurrenceDate.isAcceptableOrUnknown(
              data['next_occurrence_date']!, _nextOccurrenceDateMeta));
    } else if (isInserting) {
      context.missing(_nextOccurrenceDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(_endDateMeta,
          endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    }
    if (data.containsKey('destination_account_id')) {
      context.handle(
          _destinationAccountIdMeta,
          destinationAccountId.isAcceptableOrUnknown(
              data['destination_account_id']!, _destinationAccountIdMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('linked_debt_id')) {
      context.handle(
          _linkedDebtIdMeta,
          linkedDebtId.isAcceptableOrUnknown(
              data['linked_debt_id']!, _linkedDebtIdMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('auto_post')) {
      context.handle(_autoPostMeta,
          autoPost.isAcceptableOrUnknown(data['auto_post']!, _autoPostMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecurringRulesTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecurringRulesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      ruleType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rule_type'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      frequency: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}frequency'])!,
      interval: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}interval'])!,
      startDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}start_date'])!,
      nextOccurrenceDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}next_occurrence_date'])!,
      endDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}end_date']),
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id']),
      destinationAccountId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}destination_account_id']),
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
      linkedDebtId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}linked_debt_id']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      autoPost: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}auto_post'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $RecurringRulesTableTable createAlias(String alias) {
    return $RecurringRulesTableTable(attachedDatabase, alias);
  }
}

class RecurringRulesTableData extends DataClass
    implements Insertable<RecurringRulesTableData> {
  final String id;
  final String title;
  final String ruleType;
  final int amountCents;
  final String frequency;
  final int interval;
  final String startDate;
  final String nextOccurrenceDate;
  final String? endDate;
  final String? accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? linkedDebtId;
  final bool isActive;
  final bool autoPost;
  final DateTime createdAt;
  const RecurringRulesTableData(
      {required this.id,
      required this.title,
      required this.ruleType,
      required this.amountCents,
      required this.frequency,
      required this.interval,
      required this.startDate,
      required this.nextOccurrenceDate,
      this.endDate,
      this.accountId,
      this.destinationAccountId,
      this.categoryId,
      this.linkedDebtId,
      required this.isActive,
      required this.autoPost,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['rule_type'] = Variable<String>(ruleType);
    map['amount_cents'] = Variable<int>(amountCents);
    map['frequency'] = Variable<String>(frequency);
    map['interval'] = Variable<int>(interval);
    map['start_date'] = Variable<String>(startDate);
    map['next_occurrence_date'] = Variable<String>(nextOccurrenceDate);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<String>(endDate);
    }
    if (!nullToAbsent || accountId != null) {
      map['account_id'] = Variable<String>(accountId);
    }
    if (!nullToAbsent || destinationAccountId != null) {
      map['destination_account_id'] = Variable<String>(destinationAccountId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || linkedDebtId != null) {
      map['linked_debt_id'] = Variable<String>(linkedDebtId);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['auto_post'] = Variable<bool>(autoPost);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RecurringRulesTableCompanion toCompanion(bool nullToAbsent) {
    return RecurringRulesTableCompanion(
      id: Value(id),
      title: Value(title),
      ruleType: Value(ruleType),
      amountCents: Value(amountCents),
      frequency: Value(frequency),
      interval: Value(interval),
      startDate: Value(startDate),
      nextOccurrenceDate: Value(nextOccurrenceDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      accountId: accountId == null && nullToAbsent
          ? const Value.absent()
          : Value(accountId),
      destinationAccountId: destinationAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationAccountId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      linkedDebtId: linkedDebtId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedDebtId),
      isActive: Value(isActive),
      autoPost: Value(autoPost),
      createdAt: Value(createdAt),
    );
  }

  factory RecurringRulesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecurringRulesTableData(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      ruleType: serializer.fromJson<String>(json['ruleType']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      frequency: serializer.fromJson<String>(json['frequency']),
      interval: serializer.fromJson<int>(json['interval']),
      startDate: serializer.fromJson<String>(json['startDate']),
      nextOccurrenceDate:
          serializer.fromJson<String>(json['nextOccurrenceDate']),
      endDate: serializer.fromJson<String?>(json['endDate']),
      accountId: serializer.fromJson<String?>(json['accountId']),
      destinationAccountId:
          serializer.fromJson<String?>(json['destinationAccountId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      linkedDebtId: serializer.fromJson<String?>(json['linkedDebtId']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      autoPost: serializer.fromJson<bool>(json['autoPost']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'ruleType': serializer.toJson<String>(ruleType),
      'amountCents': serializer.toJson<int>(amountCents),
      'frequency': serializer.toJson<String>(frequency),
      'interval': serializer.toJson<int>(interval),
      'startDate': serializer.toJson<String>(startDate),
      'nextOccurrenceDate': serializer.toJson<String>(nextOccurrenceDate),
      'endDate': serializer.toJson<String?>(endDate),
      'accountId': serializer.toJson<String?>(accountId),
      'destinationAccountId': serializer.toJson<String?>(destinationAccountId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'linkedDebtId': serializer.toJson<String?>(linkedDebtId),
      'isActive': serializer.toJson<bool>(isActive),
      'autoPost': serializer.toJson<bool>(autoPost),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RecurringRulesTableData copyWith(
          {String? id,
          String? title,
          String? ruleType,
          int? amountCents,
          String? frequency,
          int? interval,
          String? startDate,
          String? nextOccurrenceDate,
          Value<String?> endDate = const Value.absent(),
          Value<String?> accountId = const Value.absent(),
          Value<String?> destinationAccountId = const Value.absent(),
          Value<String?> categoryId = const Value.absent(),
          Value<String?> linkedDebtId = const Value.absent(),
          bool? isActive,
          bool? autoPost,
          DateTime? createdAt}) =>
      RecurringRulesTableData(
        id: id ?? this.id,
        title: title ?? this.title,
        ruleType: ruleType ?? this.ruleType,
        amountCents: amountCents ?? this.amountCents,
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        startDate: startDate ?? this.startDate,
        nextOccurrenceDate: nextOccurrenceDate ?? this.nextOccurrenceDate,
        endDate: endDate.present ? endDate.value : this.endDate,
        accountId: accountId.present ? accountId.value : this.accountId,
        destinationAccountId: destinationAccountId.present
            ? destinationAccountId.value
            : this.destinationAccountId,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        linkedDebtId:
            linkedDebtId.present ? linkedDebtId.value : this.linkedDebtId,
        isActive: isActive ?? this.isActive,
        autoPost: autoPost ?? this.autoPost,
        createdAt: createdAt ?? this.createdAt,
      );
  RecurringRulesTableData copyWithCompanion(RecurringRulesTableCompanion data) {
    return RecurringRulesTableData(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      ruleType: data.ruleType.present ? data.ruleType.value : this.ruleType,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      frequency: data.frequency.present ? data.frequency.value : this.frequency,
      interval: data.interval.present ? data.interval.value : this.interval,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      nextOccurrenceDate: data.nextOccurrenceDate.present
          ? data.nextOccurrenceDate.value
          : this.nextOccurrenceDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      destinationAccountId: data.destinationAccountId.present
          ? data.destinationAccountId.value
          : this.destinationAccountId,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      linkedDebtId: data.linkedDebtId.present
          ? data.linkedDebtId.value
          : this.linkedDebtId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      autoPost: data.autoPost.present ? data.autoPost.value : this.autoPost,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecurringRulesTableData(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('ruleType: $ruleType, ')
          ..write('amountCents: $amountCents, ')
          ..write('frequency: $frequency, ')
          ..write('interval: $interval, ')
          ..write('startDate: $startDate, ')
          ..write('nextOccurrenceDate: $nextOccurrenceDate, ')
          ..write('endDate: $endDate, ')
          ..write('accountId: $accountId, ')
          ..write('destinationAccountId: $destinationAccountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('linkedDebtId: $linkedDebtId, ')
          ..write('isActive: $isActive, ')
          ..write('autoPost: $autoPost, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      ruleType,
      amountCents,
      frequency,
      interval,
      startDate,
      nextOccurrenceDate,
      endDate,
      accountId,
      destinationAccountId,
      categoryId,
      linkedDebtId,
      isActive,
      autoPost,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurringRulesTableData &&
          other.id == this.id &&
          other.title == this.title &&
          other.ruleType == this.ruleType &&
          other.amountCents == this.amountCents &&
          other.frequency == this.frequency &&
          other.interval == this.interval &&
          other.startDate == this.startDate &&
          other.nextOccurrenceDate == this.nextOccurrenceDate &&
          other.endDate == this.endDate &&
          other.accountId == this.accountId &&
          other.destinationAccountId == this.destinationAccountId &&
          other.categoryId == this.categoryId &&
          other.linkedDebtId == this.linkedDebtId &&
          other.isActive == this.isActive &&
          other.autoPost == this.autoPost &&
          other.createdAt == this.createdAt);
}

class RecurringRulesTableCompanion
    extends UpdateCompanion<RecurringRulesTableData> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> ruleType;
  final Value<int> amountCents;
  final Value<String> frequency;
  final Value<int> interval;
  final Value<String> startDate;
  final Value<String> nextOccurrenceDate;
  final Value<String?> endDate;
  final Value<String?> accountId;
  final Value<String?> destinationAccountId;
  final Value<String?> categoryId;
  final Value<String?> linkedDebtId;
  final Value<bool> isActive;
  final Value<bool> autoPost;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RecurringRulesTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.ruleType = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.frequency = const Value.absent(),
    this.interval = const Value.absent(),
    this.startDate = const Value.absent(),
    this.nextOccurrenceDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.accountId = const Value.absent(),
    this.destinationAccountId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.linkedDebtId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.autoPost = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecurringRulesTableCompanion.insert({
    required String id,
    required String title,
    required String ruleType,
    required int amountCents,
    required String frequency,
    this.interval = const Value.absent(),
    required String startDate,
    required String nextOccurrenceDate,
    this.endDate = const Value.absent(),
    this.accountId = const Value.absent(),
    this.destinationAccountId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.linkedDebtId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.autoPost = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        ruleType = Value(ruleType),
        amountCents = Value(amountCents),
        frequency = Value(frequency),
        startDate = Value(startDate),
        nextOccurrenceDate = Value(nextOccurrenceDate),
        createdAt = Value(createdAt);
  static Insertable<RecurringRulesTableData> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? ruleType,
    Expression<int>? amountCents,
    Expression<String>? frequency,
    Expression<int>? interval,
    Expression<String>? startDate,
    Expression<String>? nextOccurrenceDate,
    Expression<String>? endDate,
    Expression<String>? accountId,
    Expression<String>? destinationAccountId,
    Expression<String>? categoryId,
    Expression<String>? linkedDebtId,
    Expression<bool>? isActive,
    Expression<bool>? autoPost,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (ruleType != null) 'rule_type': ruleType,
      if (amountCents != null) 'amount_cents': amountCents,
      if (frequency != null) 'frequency': frequency,
      if (interval != null) 'interval': interval,
      if (startDate != null) 'start_date': startDate,
      if (nextOccurrenceDate != null)
        'next_occurrence_date': nextOccurrenceDate,
      if (endDate != null) 'end_date': endDate,
      if (accountId != null) 'account_id': accountId,
      if (destinationAccountId != null)
        'destination_account_id': destinationAccountId,
      if (categoryId != null) 'category_id': categoryId,
      if (linkedDebtId != null) 'linked_debt_id': linkedDebtId,
      if (isActive != null) 'is_active': isActive,
      if (autoPost != null) 'auto_post': autoPost,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecurringRulesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<String>? ruleType,
      Value<int>? amountCents,
      Value<String>? frequency,
      Value<int>? interval,
      Value<String>? startDate,
      Value<String>? nextOccurrenceDate,
      Value<String?>? endDate,
      Value<String?>? accountId,
      Value<String?>? destinationAccountId,
      Value<String?>? categoryId,
      Value<String?>? linkedDebtId,
      Value<bool>? isActive,
      Value<bool>? autoPost,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return RecurringRulesTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      ruleType: ruleType ?? this.ruleType,
      amountCents: amountCents ?? this.amountCents,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      startDate: startDate ?? this.startDate,
      nextOccurrenceDate: nextOccurrenceDate ?? this.nextOccurrenceDate,
      endDate: endDate ?? this.endDate,
      accountId: accountId ?? this.accountId,
      destinationAccountId: destinationAccountId ?? this.destinationAccountId,
      categoryId: categoryId ?? this.categoryId,
      linkedDebtId: linkedDebtId ?? this.linkedDebtId,
      isActive: isActive ?? this.isActive,
      autoPost: autoPost ?? this.autoPost,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (ruleType.present) {
      map['rule_type'] = Variable<String>(ruleType.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (frequency.present) {
      map['frequency'] = Variable<String>(frequency.value);
    }
    if (interval.present) {
      map['interval'] = Variable<int>(interval.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (nextOccurrenceDate.present) {
      map['next_occurrence_date'] = Variable<String>(nextOccurrenceDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<String>(endDate.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (destinationAccountId.present) {
      map['destination_account_id'] =
          Variable<String>(destinationAccountId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (linkedDebtId.present) {
      map['linked_debt_id'] = Variable<String>(linkedDebtId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (autoPost.present) {
      map['auto_post'] = Variable<bool>(autoPost.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringRulesTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('ruleType: $ruleType, ')
          ..write('amountCents: $amountCents, ')
          ..write('frequency: $frequency, ')
          ..write('interval: $interval, ')
          ..write('startDate: $startDate, ')
          ..write('nextOccurrenceDate: $nextOccurrenceDate, ')
          ..write('endDate: $endDate, ')
          ..write('accountId: $accountId, ')
          ..write('destinationAccountId: $destinationAccountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('linkedDebtId: $linkedDebtId, ')
          ..write('isActive: $isActive, ')
          ..write('autoPost: $autoPost, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FinancialCommitmentsTable extends FinancialCommitments
    with TableInfo<$FinancialCommitmentsTable, FinancialCommitment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinancialCommitmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _dueDateMeta =
      const VerificationMeta('dueDate');
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
      'due_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isPaidMeta = const VerificationMeta('isPaid');
  @override
  late final GeneratedColumn<bool> isPaid = GeneratedColumn<bool>(
      'is_paid', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_paid" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('outflow'));
  static const VerificationMeta _legacyPaidUnverifiedMeta =
      const VerificationMeta('legacyPaidUnverified');
  @override
  late final GeneratedColumn<bool> legacyPaidUnverified = GeneratedColumn<bool>(
      'legacy_paid_unverified', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("legacy_paid_unverified" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _recurringRuleMeta =
      const VerificationMeta('recurringRule');
  @override
  late final GeneratedColumn<String> recurringRule = GeneratedColumn<String>(
      'recurring_rule', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkedAccountIdMeta =
      const VerificationMeta('linkedAccountId');
  @override
  late final GeneratedColumn<String> linkedAccountId = GeneratedColumn<String>(
      'linked_account_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES accounts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_categories (id) ON DELETE RESTRICT'));
  static const VerificationMeta _linkedDebtIdMeta =
      const VerificationMeta('linkedDebtId');
  @override
  late final GeneratedColumn<String> linkedDebtId = GeneratedColumn<String>(
      'linked_debt_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES debts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _settlementEntryIdMeta =
      const VerificationMeta('settlementEntryId');
  @override
  late final GeneratedColumn<String> settlementEntryId =
      GeneratedColumn<String>('settlement_entry_id', aliasedName, true,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _recurringRuleIdMeta =
      const VerificationMeta('recurringRuleId');
  @override
  late final GeneratedColumn<String> recurringRuleId = GeneratedColumn<String>(
      'recurring_rule_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES recurring_rules_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        amountCents,
        dueDate,
        isPaid,
        direction,
        legacyPaidUnverified,
        recurringRule,
        linkedAccountId,
        categoryId,
        linkedDebtId,
        settlementEntryId,
        recurringRuleId,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'financial_commitments';
  @override
  VerificationContext validateIntegrity(
      Insertable<FinancialCommitment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(_dueDateMeta,
          dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta));
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('is_paid')) {
      context.handle(_isPaidMeta,
          isPaid.isAcceptableOrUnknown(data['is_paid']!, _isPaidMeta));
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    }
    if (data.containsKey('legacy_paid_unverified')) {
      context.handle(
          _legacyPaidUnverifiedMeta,
          legacyPaidUnverified.isAcceptableOrUnknown(
              data['legacy_paid_unverified']!, _legacyPaidUnverifiedMeta));
    }
    if (data.containsKey('recurring_rule')) {
      context.handle(
          _recurringRuleMeta,
          recurringRule.isAcceptableOrUnknown(
              data['recurring_rule']!, _recurringRuleMeta));
    }
    if (data.containsKey('linked_account_id')) {
      context.handle(
          _linkedAccountIdMeta,
          linkedAccountId.isAcceptableOrUnknown(
              data['linked_account_id']!, _linkedAccountIdMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('linked_debt_id')) {
      context.handle(
          _linkedDebtIdMeta,
          linkedDebtId.isAcceptableOrUnknown(
              data['linked_debt_id']!, _linkedDebtIdMeta));
    }
    if (data.containsKey('settlement_entry_id')) {
      context.handle(
          _settlementEntryIdMeta,
          settlementEntryId.isAcceptableOrUnknown(
              data['settlement_entry_id']!, _settlementEntryIdMeta));
    }
    if (data.containsKey('recurring_rule_id')) {
      context.handle(
          _recurringRuleIdMeta,
          recurringRuleId.isAcceptableOrUnknown(
              data['recurring_rule_id']!, _recurringRuleIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FinancialCommitment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FinancialCommitment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      dueDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}due_date'])!,
      isPaid: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_paid'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      legacyPaidUnverified: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}legacy_paid_unverified'])!,
      recurringRule: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recurring_rule']),
      linkedAccountId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}linked_account_id']),
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
      linkedDebtId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}linked_debt_id']),
      settlementEntryId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}settlement_entry_id']),
      recurringRuleId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recurring_rule_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FinancialCommitmentsTable createAlias(String alias) {
    return $FinancialCommitmentsTable(attachedDatabase, alias);
  }
}

class FinancialCommitment extends DataClass
    implements Insertable<FinancialCommitment> {
  final String id;
  final String title;
  final int amountCents;
  final String dueDate;
  final bool isPaid;
  final String direction;
  final bool legacyPaidUnverified;
  final String? recurringRule;
  final String? linkedAccountId;
  final String? categoryId;
  final String? linkedDebtId;
  final String? settlementEntryId;
  final String? recurringRuleId;
  final DateTime createdAt;
  const FinancialCommitment(
      {required this.id,
      required this.title,
      required this.amountCents,
      required this.dueDate,
      required this.isPaid,
      required this.direction,
      required this.legacyPaidUnverified,
      this.recurringRule,
      this.linkedAccountId,
      this.categoryId,
      this.linkedDebtId,
      this.settlementEntryId,
      this.recurringRuleId,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['amount_cents'] = Variable<int>(amountCents);
    map['due_date'] = Variable<String>(dueDate);
    map['is_paid'] = Variable<bool>(isPaid);
    map['direction'] = Variable<String>(direction);
    map['legacy_paid_unverified'] = Variable<bool>(legacyPaidUnverified);
    if (!nullToAbsent || recurringRule != null) {
      map['recurring_rule'] = Variable<String>(recurringRule);
    }
    if (!nullToAbsent || linkedAccountId != null) {
      map['linked_account_id'] = Variable<String>(linkedAccountId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || linkedDebtId != null) {
      map['linked_debt_id'] = Variable<String>(linkedDebtId);
    }
    if (!nullToAbsent || settlementEntryId != null) {
      map['settlement_entry_id'] = Variable<String>(settlementEntryId);
    }
    if (!nullToAbsent || recurringRuleId != null) {
      map['recurring_rule_id'] = Variable<String>(recurringRuleId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FinancialCommitmentsCompanion toCompanion(bool nullToAbsent) {
    return FinancialCommitmentsCompanion(
      id: Value(id),
      title: Value(title),
      amountCents: Value(amountCents),
      dueDate: Value(dueDate),
      isPaid: Value(isPaid),
      direction: Value(direction),
      legacyPaidUnverified: Value(legacyPaidUnverified),
      recurringRule: recurringRule == null && nullToAbsent
          ? const Value.absent()
          : Value(recurringRule),
      linkedAccountId: linkedAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedAccountId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      linkedDebtId: linkedDebtId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedDebtId),
      settlementEntryId: settlementEntryId == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementEntryId),
      recurringRuleId: recurringRuleId == null && nullToAbsent
          ? const Value.absent()
          : Value(recurringRuleId),
      createdAt: Value(createdAt),
    );
  }

  factory FinancialCommitment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FinancialCommitment(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      dueDate: serializer.fromJson<String>(json['dueDate']),
      isPaid: serializer.fromJson<bool>(json['isPaid']),
      direction: serializer.fromJson<String>(json['direction']),
      legacyPaidUnverified:
          serializer.fromJson<bool>(json['legacyPaidUnverified']),
      recurringRule: serializer.fromJson<String?>(json['recurringRule']),
      linkedAccountId: serializer.fromJson<String?>(json['linkedAccountId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      linkedDebtId: serializer.fromJson<String?>(json['linkedDebtId']),
      settlementEntryId:
          serializer.fromJson<String?>(json['settlementEntryId']),
      recurringRuleId: serializer.fromJson<String?>(json['recurringRuleId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'amountCents': serializer.toJson<int>(amountCents),
      'dueDate': serializer.toJson<String>(dueDate),
      'isPaid': serializer.toJson<bool>(isPaid),
      'direction': serializer.toJson<String>(direction),
      'legacyPaidUnverified': serializer.toJson<bool>(legacyPaidUnverified),
      'recurringRule': serializer.toJson<String?>(recurringRule),
      'linkedAccountId': serializer.toJson<String?>(linkedAccountId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'linkedDebtId': serializer.toJson<String?>(linkedDebtId),
      'settlementEntryId': serializer.toJson<String?>(settlementEntryId),
      'recurringRuleId': serializer.toJson<String?>(recurringRuleId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FinancialCommitment copyWith(
          {String? id,
          String? title,
          int? amountCents,
          String? dueDate,
          bool? isPaid,
          String? direction,
          bool? legacyPaidUnverified,
          Value<String?> recurringRule = const Value.absent(),
          Value<String?> linkedAccountId = const Value.absent(),
          Value<String?> categoryId = const Value.absent(),
          Value<String?> linkedDebtId = const Value.absent(),
          Value<String?> settlementEntryId = const Value.absent(),
          Value<String?> recurringRuleId = const Value.absent(),
          DateTime? createdAt}) =>
      FinancialCommitment(
        id: id ?? this.id,
        title: title ?? this.title,
        amountCents: amountCents ?? this.amountCents,
        dueDate: dueDate ?? this.dueDate,
        isPaid: isPaid ?? this.isPaid,
        direction: direction ?? this.direction,
        legacyPaidUnverified: legacyPaidUnverified ?? this.legacyPaidUnverified,
        recurringRule:
            recurringRule.present ? recurringRule.value : this.recurringRule,
        linkedAccountId: linkedAccountId.present
            ? linkedAccountId.value
            : this.linkedAccountId,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        linkedDebtId:
            linkedDebtId.present ? linkedDebtId.value : this.linkedDebtId,
        settlementEntryId: settlementEntryId.present
            ? settlementEntryId.value
            : this.settlementEntryId,
        recurringRuleId: recurringRuleId.present
            ? recurringRuleId.value
            : this.recurringRuleId,
        createdAt: createdAt ?? this.createdAt,
      );
  FinancialCommitment copyWithCompanion(FinancialCommitmentsCompanion data) {
    return FinancialCommitment(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      isPaid: data.isPaid.present ? data.isPaid.value : this.isPaid,
      direction: data.direction.present ? data.direction.value : this.direction,
      legacyPaidUnverified: data.legacyPaidUnverified.present
          ? data.legacyPaidUnverified.value
          : this.legacyPaidUnverified,
      recurringRule: data.recurringRule.present
          ? data.recurringRule.value
          : this.recurringRule,
      linkedAccountId: data.linkedAccountId.present
          ? data.linkedAccountId.value
          : this.linkedAccountId,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      linkedDebtId: data.linkedDebtId.present
          ? data.linkedDebtId.value
          : this.linkedDebtId,
      settlementEntryId: data.settlementEntryId.present
          ? data.settlementEntryId.value
          : this.settlementEntryId,
      recurringRuleId: data.recurringRuleId.present
          ? data.recurringRuleId.value
          : this.recurringRuleId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinancialCommitment(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('amountCents: $amountCents, ')
          ..write('dueDate: $dueDate, ')
          ..write('isPaid: $isPaid, ')
          ..write('direction: $direction, ')
          ..write('legacyPaidUnverified: $legacyPaidUnverified, ')
          ..write('recurringRule: $recurringRule, ')
          ..write('linkedAccountId: $linkedAccountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('linkedDebtId: $linkedDebtId, ')
          ..write('settlementEntryId: $settlementEntryId, ')
          ..write('recurringRuleId: $recurringRuleId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      amountCents,
      dueDate,
      isPaid,
      direction,
      legacyPaidUnverified,
      recurringRule,
      linkedAccountId,
      categoryId,
      linkedDebtId,
      settlementEntryId,
      recurringRuleId,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialCommitment &&
          other.id == this.id &&
          other.title == this.title &&
          other.amountCents == this.amountCents &&
          other.dueDate == this.dueDate &&
          other.isPaid == this.isPaid &&
          other.direction == this.direction &&
          other.legacyPaidUnverified == this.legacyPaidUnverified &&
          other.recurringRule == this.recurringRule &&
          other.linkedAccountId == this.linkedAccountId &&
          other.categoryId == this.categoryId &&
          other.linkedDebtId == this.linkedDebtId &&
          other.settlementEntryId == this.settlementEntryId &&
          other.recurringRuleId == this.recurringRuleId &&
          other.createdAt == this.createdAt);
}

class FinancialCommitmentsCompanion
    extends UpdateCompanion<FinancialCommitment> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> amountCents;
  final Value<String> dueDate;
  final Value<bool> isPaid;
  final Value<String> direction;
  final Value<bool> legacyPaidUnverified;
  final Value<String?> recurringRule;
  final Value<String?> linkedAccountId;
  final Value<String?> categoryId;
  final Value<String?> linkedDebtId;
  final Value<String?> settlementEntryId;
  final Value<String?> recurringRuleId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FinancialCommitmentsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.isPaid = const Value.absent(),
    this.direction = const Value.absent(),
    this.legacyPaidUnverified = const Value.absent(),
    this.recurringRule = const Value.absent(),
    this.linkedAccountId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.linkedDebtId = const Value.absent(),
    this.settlementEntryId = const Value.absent(),
    this.recurringRuleId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinancialCommitmentsCompanion.insert({
    required String id,
    required String title,
    required int amountCents,
    required String dueDate,
    this.isPaid = const Value.absent(),
    this.direction = const Value.absent(),
    this.legacyPaidUnverified = const Value.absent(),
    this.recurringRule = const Value.absent(),
    this.linkedAccountId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.linkedDebtId = const Value.absent(),
    this.settlementEntryId = const Value.absent(),
    this.recurringRuleId = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        amountCents = Value(amountCents),
        dueDate = Value(dueDate),
        createdAt = Value(createdAt);
  static Insertable<FinancialCommitment> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? amountCents,
    Expression<String>? dueDate,
    Expression<bool>? isPaid,
    Expression<String>? direction,
    Expression<bool>? legacyPaidUnverified,
    Expression<String>? recurringRule,
    Expression<String>? linkedAccountId,
    Expression<String>? categoryId,
    Expression<String>? linkedDebtId,
    Expression<String>? settlementEntryId,
    Expression<String>? recurringRuleId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (amountCents != null) 'amount_cents': amountCents,
      if (dueDate != null) 'due_date': dueDate,
      if (isPaid != null) 'is_paid': isPaid,
      if (direction != null) 'direction': direction,
      if (legacyPaidUnverified != null)
        'legacy_paid_unverified': legacyPaidUnverified,
      if (recurringRule != null) 'recurring_rule': recurringRule,
      if (linkedAccountId != null) 'linked_account_id': linkedAccountId,
      if (categoryId != null) 'category_id': categoryId,
      if (linkedDebtId != null) 'linked_debt_id': linkedDebtId,
      if (settlementEntryId != null) 'settlement_entry_id': settlementEntryId,
      if (recurringRuleId != null) 'recurring_rule_id': recurringRuleId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinancialCommitmentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<int>? amountCents,
      Value<String>? dueDate,
      Value<bool>? isPaid,
      Value<String>? direction,
      Value<bool>? legacyPaidUnverified,
      Value<String?>? recurringRule,
      Value<String?>? linkedAccountId,
      Value<String?>? categoryId,
      Value<String?>? linkedDebtId,
      Value<String?>? settlementEntryId,
      Value<String?>? recurringRuleId,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return FinancialCommitmentsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      amountCents: amountCents ?? this.amountCents,
      dueDate: dueDate ?? this.dueDate,
      isPaid: isPaid ?? this.isPaid,
      direction: direction ?? this.direction,
      legacyPaidUnverified: legacyPaidUnverified ?? this.legacyPaidUnverified,
      recurringRule: recurringRule ?? this.recurringRule,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
      categoryId: categoryId ?? this.categoryId,
      linkedDebtId: linkedDebtId ?? this.linkedDebtId,
      settlementEntryId: settlementEntryId ?? this.settlementEntryId,
      recurringRuleId: recurringRuleId ?? this.recurringRuleId,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (isPaid.present) {
      map['is_paid'] = Variable<bool>(isPaid.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (legacyPaidUnverified.present) {
      map['legacy_paid_unverified'] =
          Variable<bool>(legacyPaidUnverified.value);
    }
    if (recurringRule.present) {
      map['recurring_rule'] = Variable<String>(recurringRule.value);
    }
    if (linkedAccountId.present) {
      map['linked_account_id'] = Variable<String>(linkedAccountId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (linkedDebtId.present) {
      map['linked_debt_id'] = Variable<String>(linkedDebtId.value);
    }
    if (settlementEntryId.present) {
      map['settlement_entry_id'] = Variable<String>(settlementEntryId.value);
    }
    if (recurringRuleId.present) {
      map['recurring_rule_id'] = Variable<String>(recurringRuleId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinancialCommitmentsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('amountCents: $amountCents, ')
          ..write('dueDate: $dueDate, ')
          ..write('isPaid: $isPaid, ')
          ..write('direction: $direction, ')
          ..write('legacyPaidUnverified: $legacyPaidUnverified, ')
          ..write('recurringRule: $recurringRule, ')
          ..write('linkedAccountId: $linkedAccountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('linkedDebtId: $linkedDebtId, ')
          ..write('settlementEntryId: $settlementEntryId, ')
          ..write('recurringRuleId: $recurringRuleId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CommitmentSettlementsTableTable extends CommitmentSettlementsTable
    with
        TableInfo<$CommitmentSettlementsTableTable,
            CommitmentSettlementsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommitmentSettlementsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _commitmentIdMeta =
      const VerificationMeta('commitmentId');
  @override
  late final GeneratedColumn<String> commitmentId = GeneratedColumn<String>(
      'commitment_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_commitments (id) ON DELETE RESTRICT'));
  static const VerificationMeta _entryIdMeta =
      const VerificationMeta('entryId');
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
      'entry_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _settledDateMeta =
      const VerificationMeta('settledDate');
  @override
  late final GeneratedColumn<String> settledDate = GeneratedColumn<String>(
      'settled_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, commitmentId, entryId, amountCents, settledDate, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'commitment_settlements_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<CommitmentSettlementsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('commitment_id')) {
      context.handle(
          _commitmentIdMeta,
          commitmentId.isAcceptableOrUnknown(
              data['commitment_id']!, _commitmentIdMeta));
    } else if (isInserting) {
      context.missing(_commitmentIdMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(_entryIdMeta,
          entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta));
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('settled_date')) {
      context.handle(
          _settledDateMeta,
          settledDate.isAcceptableOrUnknown(
              data['settled_date']!, _settledDateMeta));
    } else if (isInserting) {
      context.missing(_settledDateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CommitmentSettlementsTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CommitmentSettlementsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      commitmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}commitment_id'])!,
      entryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entry_id'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      settledDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}settled_date'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CommitmentSettlementsTableTable createAlias(String alias) {
    return $CommitmentSettlementsTableTable(attachedDatabase, alias);
  }
}

class CommitmentSettlementsTableData extends DataClass
    implements Insertable<CommitmentSettlementsTableData> {
  final String id;
  final String commitmentId;
  final String entryId;
  final int amountCents;
  final String settledDate;
  final DateTime createdAt;
  const CommitmentSettlementsTableData(
      {required this.id,
      required this.commitmentId,
      required this.entryId,
      required this.amountCents,
      required this.settledDate,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['commitment_id'] = Variable<String>(commitmentId);
    map['entry_id'] = Variable<String>(entryId);
    map['amount_cents'] = Variable<int>(amountCents);
    map['settled_date'] = Variable<String>(settledDate);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CommitmentSettlementsTableCompanion toCompanion(bool nullToAbsent) {
    return CommitmentSettlementsTableCompanion(
      id: Value(id),
      commitmentId: Value(commitmentId),
      entryId: Value(entryId),
      amountCents: Value(amountCents),
      settledDate: Value(settledDate),
      createdAt: Value(createdAt),
    );
  }

  factory CommitmentSettlementsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CommitmentSettlementsTableData(
      id: serializer.fromJson<String>(json['id']),
      commitmentId: serializer.fromJson<String>(json['commitmentId']),
      entryId: serializer.fromJson<String>(json['entryId']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      settledDate: serializer.fromJson<String>(json['settledDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'commitmentId': serializer.toJson<String>(commitmentId),
      'entryId': serializer.toJson<String>(entryId),
      'amountCents': serializer.toJson<int>(amountCents),
      'settledDate': serializer.toJson<String>(settledDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CommitmentSettlementsTableData copyWith(
          {String? id,
          String? commitmentId,
          String? entryId,
          int? amountCents,
          String? settledDate,
          DateTime? createdAt}) =>
      CommitmentSettlementsTableData(
        id: id ?? this.id,
        commitmentId: commitmentId ?? this.commitmentId,
        entryId: entryId ?? this.entryId,
        amountCents: amountCents ?? this.amountCents,
        settledDate: settledDate ?? this.settledDate,
        createdAt: createdAt ?? this.createdAt,
      );
  CommitmentSettlementsTableData copyWithCompanion(
      CommitmentSettlementsTableCompanion data) {
    return CommitmentSettlementsTableData(
      id: data.id.present ? data.id.value : this.id,
      commitmentId: data.commitmentId.present
          ? data.commitmentId.value
          : this.commitmentId,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      settledDate:
          data.settledDate.present ? data.settledDate.value : this.settledDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CommitmentSettlementsTableData(')
          ..write('id: $id, ')
          ..write('commitmentId: $commitmentId, ')
          ..write('entryId: $entryId, ')
          ..write('amountCents: $amountCents, ')
          ..write('settledDate: $settledDate, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, commitmentId, entryId, amountCents, settledDate, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommitmentSettlementsTableData &&
          other.id == this.id &&
          other.commitmentId == this.commitmentId &&
          other.entryId == this.entryId &&
          other.amountCents == this.amountCents &&
          other.settledDate == this.settledDate &&
          other.createdAt == this.createdAt);
}

class CommitmentSettlementsTableCompanion
    extends UpdateCompanion<CommitmentSettlementsTableData> {
  final Value<String> id;
  final Value<String> commitmentId;
  final Value<String> entryId;
  final Value<int> amountCents;
  final Value<String> settledDate;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const CommitmentSettlementsTableCompanion({
    this.id = const Value.absent(),
    this.commitmentId = const Value.absent(),
    this.entryId = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.settledDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CommitmentSettlementsTableCompanion.insert({
    required String id,
    required String commitmentId,
    required String entryId,
    required int amountCents,
    required String settledDate,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        commitmentId = Value(commitmentId),
        entryId = Value(entryId),
        amountCents = Value(amountCents),
        settledDate = Value(settledDate),
        createdAt = Value(createdAt);
  static Insertable<CommitmentSettlementsTableData> custom({
    Expression<String>? id,
    Expression<String>? commitmentId,
    Expression<String>? entryId,
    Expression<int>? amountCents,
    Expression<String>? settledDate,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (commitmentId != null) 'commitment_id': commitmentId,
      if (entryId != null) 'entry_id': entryId,
      if (amountCents != null) 'amount_cents': amountCents,
      if (settledDate != null) 'settled_date': settledDate,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CommitmentSettlementsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? commitmentId,
      Value<String>? entryId,
      Value<int>? amountCents,
      Value<String>? settledDate,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return CommitmentSettlementsTableCompanion(
      id: id ?? this.id,
      commitmentId: commitmentId ?? this.commitmentId,
      entryId: entryId ?? this.entryId,
      amountCents: amountCents ?? this.amountCents,
      settledDate: settledDate ?? this.settledDate,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (commitmentId.present) {
      map['commitment_id'] = Variable<String>(commitmentId.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (settledDate.present) {
      map['settled_date'] = Variable<String>(settledDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommitmentSettlementsTableCompanion(')
          ..write('id: $id, ')
          ..write('commitmentId: $commitmentId, ')
          ..write('entryId: $entryId, ')
          ..write('amountCents: $amountCents, ')
          ..write('settledDate: $settledDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavingsGoalsTable extends SavingsGoals
    with TableInfo<$SavingsGoalsTable, SavingsGoal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavingsGoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _targetCentsMeta =
      const VerificationMeta('targetCents');
  @override
  late final GeneratedColumn<int> targetCents = GeneratedColumn<int>(
      'target_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _currentAllocatedCentsMeta =
      const VerificationMeta('currentAllocatedCents');
  @override
  late final GeneratedColumn<int> currentAllocatedCents = GeneratedColumn<int>(
      'current_allocated_cents', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _targetDateMeta =
      const VerificationMeta('targetDate');
  @override
  late final GeneratedColumn<String> targetDate = GeneratedColumn<String>(
      'target_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkedAccountIdMeta =
      const VerificationMeta('linkedAccountId');
  @override
  late final GeneratedColumn<String> linkedAccountId = GeneratedColumn<String>(
      'linked_account_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES accounts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('active'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        targetCents,
        currentAllocatedCents,
        targetDate,
        linkedAccountId,
        status,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'savings_goals';
  @override
  VerificationContext validateIntegrity(Insertable<SavingsGoal> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('target_cents')) {
      context.handle(
          _targetCentsMeta,
          targetCents.isAcceptableOrUnknown(
              data['target_cents']!, _targetCentsMeta));
    } else if (isInserting) {
      context.missing(_targetCentsMeta);
    }
    if (data.containsKey('current_allocated_cents')) {
      context.handle(
          _currentAllocatedCentsMeta,
          currentAllocatedCents.isAcceptableOrUnknown(
              data['current_allocated_cents']!, _currentAllocatedCentsMeta));
    }
    if (data.containsKey('target_date')) {
      context.handle(
          _targetDateMeta,
          targetDate.isAcceptableOrUnknown(
              data['target_date']!, _targetDateMeta));
    }
    if (data.containsKey('linked_account_id')) {
      context.handle(
          _linkedAccountIdMeta,
          linkedAccountId.isAcceptableOrUnknown(
              data['linked_account_id']!, _linkedAccountIdMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavingsGoal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavingsGoal(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      targetCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}target_cents'])!,
      currentAllocatedCents: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}current_allocated_cents'])!,
      targetDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}target_date']),
      linkedAccountId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}linked_account_id']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $SavingsGoalsTable createAlias(String alias) {
    return $SavingsGoalsTable(attachedDatabase, alias);
  }
}

class SavingsGoal extends DataClass implements Insertable<SavingsGoal> {
  final String id;
  final String title;
  final int targetCents;
  final int currentAllocatedCents;
  final String? targetDate;
  final String? linkedAccountId;
  final String status;
  final DateTime createdAt;
  const SavingsGoal(
      {required this.id,
      required this.title,
      required this.targetCents,
      required this.currentAllocatedCents,
      this.targetDate,
      this.linkedAccountId,
      required this.status,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['target_cents'] = Variable<int>(targetCents);
    map['current_allocated_cents'] = Variable<int>(currentAllocatedCents);
    if (!nullToAbsent || targetDate != null) {
      map['target_date'] = Variable<String>(targetDate);
    }
    if (!nullToAbsent || linkedAccountId != null) {
      map['linked_account_id'] = Variable<String>(linkedAccountId);
    }
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SavingsGoalsCompanion toCompanion(bool nullToAbsent) {
    return SavingsGoalsCompanion(
      id: Value(id),
      title: Value(title),
      targetCents: Value(targetCents),
      currentAllocatedCents: Value(currentAllocatedCents),
      targetDate: targetDate == null && nullToAbsent
          ? const Value.absent()
          : Value(targetDate),
      linkedAccountId: linkedAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedAccountId),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory SavingsGoal.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavingsGoal(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      targetCents: serializer.fromJson<int>(json['targetCents']),
      currentAllocatedCents:
          serializer.fromJson<int>(json['currentAllocatedCents']),
      targetDate: serializer.fromJson<String?>(json['targetDate']),
      linkedAccountId: serializer.fromJson<String?>(json['linkedAccountId']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'targetCents': serializer.toJson<int>(targetCents),
      'currentAllocatedCents': serializer.toJson<int>(currentAllocatedCents),
      'targetDate': serializer.toJson<String?>(targetDate),
      'linkedAccountId': serializer.toJson<String?>(linkedAccountId),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SavingsGoal copyWith(
          {String? id,
          String? title,
          int? targetCents,
          int? currentAllocatedCents,
          Value<String?> targetDate = const Value.absent(),
          Value<String?> linkedAccountId = const Value.absent(),
          String? status,
          DateTime? createdAt}) =>
      SavingsGoal(
        id: id ?? this.id,
        title: title ?? this.title,
        targetCents: targetCents ?? this.targetCents,
        currentAllocatedCents:
            currentAllocatedCents ?? this.currentAllocatedCents,
        targetDate: targetDate.present ? targetDate.value : this.targetDate,
        linkedAccountId: linkedAccountId.present
            ? linkedAccountId.value
            : this.linkedAccountId,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
  SavingsGoal copyWithCompanion(SavingsGoalsCompanion data) {
    return SavingsGoal(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      targetCents:
          data.targetCents.present ? data.targetCents.value : this.targetCents,
      currentAllocatedCents: data.currentAllocatedCents.present
          ? data.currentAllocatedCents.value
          : this.currentAllocatedCents,
      targetDate:
          data.targetDate.present ? data.targetDate.value : this.targetDate,
      linkedAccountId: data.linkedAccountId.present
          ? data.linkedAccountId.value
          : this.linkedAccountId,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavingsGoal(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('targetCents: $targetCents, ')
          ..write('currentAllocatedCents: $currentAllocatedCents, ')
          ..write('targetDate: $targetDate, ')
          ..write('linkedAccountId: $linkedAccountId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, targetCents, currentAllocatedCents,
      targetDate, linkedAccountId, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavingsGoal &&
          other.id == this.id &&
          other.title == this.title &&
          other.targetCents == this.targetCents &&
          other.currentAllocatedCents == this.currentAllocatedCents &&
          other.targetDate == this.targetDate &&
          other.linkedAccountId == this.linkedAccountId &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class SavingsGoalsCompanion extends UpdateCompanion<SavingsGoal> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> targetCents;
  final Value<int> currentAllocatedCents;
  final Value<String?> targetDate;
  final Value<String?> linkedAccountId;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SavingsGoalsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.targetCents = const Value.absent(),
    this.currentAllocatedCents = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.linkedAccountId = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavingsGoalsCompanion.insert({
    required String id,
    required String title,
    required int targetCents,
    this.currentAllocatedCents = const Value.absent(),
    this.targetDate = const Value.absent(),
    this.linkedAccountId = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        title = Value(title),
        targetCents = Value(targetCents),
        createdAt = Value(createdAt);
  static Insertable<SavingsGoal> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? targetCents,
    Expression<int>? currentAllocatedCents,
    Expression<String>? targetDate,
    Expression<String>? linkedAccountId,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (targetCents != null) 'target_cents': targetCents,
      if (currentAllocatedCents != null)
        'current_allocated_cents': currentAllocatedCents,
      if (targetDate != null) 'target_date': targetDate,
      if (linkedAccountId != null) 'linked_account_id': linkedAccountId,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavingsGoalsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<int>? targetCents,
      Value<int>? currentAllocatedCents,
      Value<String?>? targetDate,
      Value<String?>? linkedAccountId,
      Value<String>? status,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return SavingsGoalsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      targetCents: targetCents ?? this.targetCents,
      currentAllocatedCents:
          currentAllocatedCents ?? this.currentAllocatedCents,
      targetDate: targetDate ?? this.targetDate,
      linkedAccountId: linkedAccountId ?? this.linkedAccountId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (targetCents.present) {
      map['target_cents'] = Variable<int>(targetCents.value);
    }
    if (currentAllocatedCents.present) {
      map['current_allocated_cents'] =
          Variable<int>(currentAllocatedCents.value);
    }
    if (targetDate.present) {
      map['target_date'] = Variable<String>(targetDate.value);
    }
    if (linkedAccountId.present) {
      map['linked_account_id'] = Variable<String>(linkedAccountId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavingsGoalsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('targetCents: $targetCents, ')
          ..write('currentAllocatedCents: $currentAllocatedCents, ')
          ..write('targetDate: $targetDate, ')
          ..write('linkedAccountId: $linkedAccountId, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemindersTable extends Reminders
    with TableInfo<$RemindersTable, Reminder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _targetIdMeta =
      const VerificationMeta('targetId');
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
      'target_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _targetTypeMeta =
      const VerificationMeta('targetType');
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
      'target_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _channelIdMeta =
      const VerificationMeta('channelId');
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
      'channel_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _triggerTimeUtcMeta =
      const VerificationMeta('triggerTimeUtc');
  @override
  late final GeneratedColumn<DateTime> triggerTimeUtc =
      GeneratedColumn<DateTime>('trigger_time_utc', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        targetId,
        targetType,
        title,
        channelId,
        triggerTimeUtc,
        isActive,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminders';
  @override
  VerificationContext validateIntegrity(Insertable<Reminder> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(_targetIdMeta,
          targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta));
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('target_type')) {
      context.handle(
          _targetTypeMeta,
          targetType.isAcceptableOrUnknown(
              data['target_type']!, _targetTypeMeta));
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('channel_id')) {
      context.handle(_channelIdMeta,
          channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta));
    }
    if (data.containsKey('trigger_time_utc')) {
      context.handle(
          _triggerTimeUtcMeta,
          triggerTimeUtc.isAcceptableOrUnknown(
              data['trigger_time_utc']!, _triggerTimeUtcMeta));
    } else if (isInserting) {
      context.missing(_triggerTimeUtcMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Reminder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Reminder(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      targetId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}target_id'])!,
      targetType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}target_type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title']),
      channelId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}channel_id']),
      triggerTimeUtc: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}trigger_time_utc'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $RemindersTable createAlias(String alias) {
    return $RemindersTable(attachedDatabase, alias);
  }
}

class Reminder extends DataClass implements Insertable<Reminder> {
  final String id;
  final String targetId;
  final String targetType;
  final String? title;
  final String? channelId;
  final DateTime triggerTimeUtc;
  final bool isActive;
  final DateTime createdAt;
  const Reminder(
      {required this.id,
      required this.targetId,
      required this.targetType,
      this.title,
      this.channelId,
      required this.triggerTimeUtc,
      required this.isActive,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['target_id'] = Variable<String>(targetId);
    map['target_type'] = Variable<String>(targetType);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || channelId != null) {
      map['channel_id'] = Variable<String>(channelId);
    }
    map['trigger_time_utc'] = Variable<DateTime>(triggerTimeUtc);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RemindersCompanion toCompanion(bool nullToAbsent) {
    return RemindersCompanion(
      id: Value(id),
      targetId: Value(targetId),
      targetType: Value(targetType),
      title:
          title == null && nullToAbsent ? const Value.absent() : Value(title),
      channelId: channelId == null && nullToAbsent
          ? const Value.absent()
          : Value(channelId),
      triggerTimeUtc: Value(triggerTimeUtc),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory Reminder.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Reminder(
      id: serializer.fromJson<String>(json['id']),
      targetId: serializer.fromJson<String>(json['targetId']),
      targetType: serializer.fromJson<String>(json['targetType']),
      title: serializer.fromJson<String?>(json['title']),
      channelId: serializer.fromJson<String?>(json['channelId']),
      triggerTimeUtc: serializer.fromJson<DateTime>(json['triggerTimeUtc']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'targetId': serializer.toJson<String>(targetId),
      'targetType': serializer.toJson<String>(targetType),
      'title': serializer.toJson<String?>(title),
      'channelId': serializer.toJson<String?>(channelId),
      'triggerTimeUtc': serializer.toJson<DateTime>(triggerTimeUtc),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Reminder copyWith(
          {String? id,
          String? targetId,
          String? targetType,
          Value<String?> title = const Value.absent(),
          Value<String?> channelId = const Value.absent(),
          DateTime? triggerTimeUtc,
          bool? isActive,
          DateTime? createdAt}) =>
      Reminder(
        id: id ?? this.id,
        targetId: targetId ?? this.targetId,
        targetType: targetType ?? this.targetType,
        title: title.present ? title.value : this.title,
        channelId: channelId.present ? channelId.value : this.channelId,
        triggerTimeUtc: triggerTimeUtc ?? this.triggerTimeUtc,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
      );
  Reminder copyWithCompanion(RemindersCompanion data) {
    return Reminder(
      id: data.id.present ? data.id.value : this.id,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      targetType:
          data.targetType.present ? data.targetType.value : this.targetType,
      title: data.title.present ? data.title.value : this.title,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      triggerTimeUtc: data.triggerTimeUtc.present
          ? data.triggerTimeUtc.value
          : this.triggerTimeUtc,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Reminder(')
          ..write('id: $id, ')
          ..write('targetId: $targetId, ')
          ..write('targetType: $targetType, ')
          ..write('title: $title, ')
          ..write('channelId: $channelId, ')
          ..write('triggerTimeUtc: $triggerTimeUtc, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, targetId, targetType, title, channelId,
      triggerTimeUtc, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Reminder &&
          other.id == this.id &&
          other.targetId == this.targetId &&
          other.targetType == this.targetType &&
          other.title == this.title &&
          other.channelId == this.channelId &&
          other.triggerTimeUtc == this.triggerTimeUtc &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class RemindersCompanion extends UpdateCompanion<Reminder> {
  final Value<String> id;
  final Value<String> targetId;
  final Value<String> targetType;
  final Value<String?> title;
  final Value<String?> channelId;
  final Value<DateTime> triggerTimeUtc;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RemindersCompanion({
    this.id = const Value.absent(),
    this.targetId = const Value.absent(),
    this.targetType = const Value.absent(),
    this.title = const Value.absent(),
    this.channelId = const Value.absent(),
    this.triggerTimeUtc = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemindersCompanion.insert({
    required String id,
    required String targetId,
    required String targetType,
    this.title = const Value.absent(),
    this.channelId = const Value.absent(),
    required DateTime triggerTimeUtc,
    this.isActive = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        targetId = Value(targetId),
        targetType = Value(targetType),
        triggerTimeUtc = Value(triggerTimeUtc),
        createdAt = Value(createdAt);
  static Insertable<Reminder> custom({
    Expression<String>? id,
    Expression<String>? targetId,
    Expression<String>? targetType,
    Expression<String>? title,
    Expression<String>? channelId,
    Expression<DateTime>? triggerTimeUtc,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetId != null) 'target_id': targetId,
      if (targetType != null) 'target_type': targetType,
      if (title != null) 'title': title,
      if (channelId != null) 'channel_id': channelId,
      if (triggerTimeUtc != null) 'trigger_time_utc': triggerTimeUtc,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemindersCompanion copyWith(
      {Value<String>? id,
      Value<String>? targetId,
      Value<String>? targetType,
      Value<String?>? title,
      Value<String?>? channelId,
      Value<DateTime>? triggerTimeUtc,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return RemindersCompanion(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      targetType: targetType ?? this.targetType,
      title: title ?? this.title,
      channelId: channelId ?? this.channelId,
      triggerTimeUtc: triggerTimeUtc ?? this.triggerTimeUtc,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (triggerTimeUtc.present) {
      map['trigger_time_utc'] = Variable<DateTime>(triggerTimeUtc.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemindersCompanion(')
          ..write('id: $id, ')
          ..write('targetId: $targetId, ')
          ..write('targetType: $targetType, ')
          ..write('title: $title, ')
          ..write('channelId: $channelId, ')
          ..write('triggerTimeUtc: $triggerTimeUtc, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSetting(
      {required this.key, required this.value, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      AppSetting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value),
        updatedAt = Value(updatedAt);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<String>? key,
      Value<String>? value,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PostingsTableTable extends PostingsTable
    with TableInfo<$PostingsTableTable, PostingsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PostingsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entryIdMeta =
      const VerificationMeta('entryId');
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
      'entry_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _accountIdMeta =
      const VerificationMeta('accountId');
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
      'account_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES accounts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _amountCentsMeta =
      const VerificationMeta('amountCents');
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
      'amount_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _directionMeta =
      const VerificationMeta('direction');
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
      'direction', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _accountMovementDateMeta =
      const VerificationMeta('accountMovementDate');
  @override
  late final GeneratedColumn<String> accountMovementDate =
      GeneratedColumn<String>('account_movement_date', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_categories (id) ON DELETE RESTRICT'));
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entryId,
        accountId,
        amountCents,
        direction,
        accountMovementDate,
        categoryId,
        note
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'postings_table';
  @override
  VerificationContext validateIntegrity(Insertable<PostingsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(_entryIdMeta,
          entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta));
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(_accountIdMeta,
          accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta));
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
          _amountCentsMeta,
          amountCents.isAcceptableOrUnknown(
              data['amount_cents']!, _amountCentsMeta));
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(_directionMeta,
          direction.isAcceptableOrUnknown(data['direction']!, _directionMeta));
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('account_movement_date')) {
      context.handle(
          _accountMovementDateMeta,
          accountMovementDate.isAcceptableOrUnknown(
              data['account_movement_date']!, _accountMovementDateMeta));
    } else if (isInserting) {
      context.missing(_accountMovementDateMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PostingsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PostingsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      entryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entry_id'])!,
      accountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}account_id'])!,
      amountCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}amount_cents'])!,
      direction: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}direction'])!,
      accountMovementDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}account_movement_date'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
    );
  }

  @override
  $PostingsTableTable createAlias(String alias) {
    return $PostingsTableTable(attachedDatabase, alias);
  }
}

class PostingsTableData extends DataClass
    implements Insertable<PostingsTableData> {
  final String id;
  final String entryId;
  final String accountId;
  final int amountCents;
  final String direction;
  final String accountMovementDate;
  final String? categoryId;
  final String? note;
  const PostingsTableData(
      {required this.id,
      required this.entryId,
      required this.accountId,
      required this.amountCents,
      required this.direction,
      required this.accountMovementDate,
      this.categoryId,
      this.note});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['account_id'] = Variable<String>(accountId);
    map['amount_cents'] = Variable<int>(amountCents);
    map['direction'] = Variable<String>(direction);
    map['account_movement_date'] = Variable<String>(accountMovementDate);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  PostingsTableCompanion toCompanion(bool nullToAbsent) {
    return PostingsTableCompanion(
      id: Value(id),
      entryId: Value(entryId),
      accountId: Value(accountId),
      amountCents: Value(amountCents),
      direction: Value(direction),
      accountMovementDate: Value(accountMovementDate),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory PostingsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PostingsTableData(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      accountId: serializer.fromJson<String>(json['accountId']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      direction: serializer.fromJson<String>(json['direction']),
      accountMovementDate:
          serializer.fromJson<String>(json['accountMovementDate']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'accountId': serializer.toJson<String>(accountId),
      'amountCents': serializer.toJson<int>(amountCents),
      'direction': serializer.toJson<String>(direction),
      'accountMovementDate': serializer.toJson<String>(accountMovementDate),
      'categoryId': serializer.toJson<String?>(categoryId),
      'note': serializer.toJson<String?>(note),
    };
  }

  PostingsTableData copyWith(
          {String? id,
          String? entryId,
          String? accountId,
          int? amountCents,
          String? direction,
          String? accountMovementDate,
          Value<String?> categoryId = const Value.absent(),
          Value<String?> note = const Value.absent()}) =>
      PostingsTableData(
        id: id ?? this.id,
        entryId: entryId ?? this.entryId,
        accountId: accountId ?? this.accountId,
        amountCents: amountCents ?? this.amountCents,
        direction: direction ?? this.direction,
        accountMovementDate: accountMovementDate ?? this.accountMovementDate,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        note: note.present ? note.value : this.note,
      );
  PostingsTableData copyWithCompanion(PostingsTableCompanion data) {
    return PostingsTableData(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      amountCents:
          data.amountCents.present ? data.amountCents.value : this.amountCents,
      direction: data.direction.present ? data.direction.value : this.direction,
      accountMovementDate: data.accountMovementDate.present
          ? data.accountMovementDate.value
          : this.accountMovementDate,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PostingsTableData(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('accountId: $accountId, ')
          ..write('amountCents: $amountCents, ')
          ..write('direction: $direction, ')
          ..write('accountMovementDate: $accountMovementDate, ')
          ..write('categoryId: $categoryId, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entryId, accountId, amountCents,
      direction, accountMovementDate, categoryId, note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PostingsTableData &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.accountId == this.accountId &&
          other.amountCents == this.amountCents &&
          other.direction == this.direction &&
          other.accountMovementDate == this.accountMovementDate &&
          other.categoryId == this.categoryId &&
          other.note == this.note);
}

class PostingsTableCompanion extends UpdateCompanion<PostingsTableData> {
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> accountId;
  final Value<int> amountCents;
  final Value<String> direction;
  final Value<String> accountMovementDate;
  final Value<String?> categoryId;
  final Value<String?> note;
  final Value<int> rowid;
  const PostingsTableCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.accountId = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.direction = const Value.absent(),
    this.accountMovementDate = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PostingsTableCompanion.insert({
    required String id,
    required String entryId,
    required String accountId,
    required int amountCents,
    required String direction,
    required String accountMovementDate,
    this.categoryId = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        entryId = Value(entryId),
        accountId = Value(accountId),
        amountCents = Value(amountCents),
        direction = Value(direction),
        accountMovementDate = Value(accountMovementDate);
  static Insertable<PostingsTableData> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? accountId,
    Expression<int>? amountCents,
    Expression<String>? direction,
    Expression<String>? accountMovementDate,
    Expression<String>? categoryId,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (accountId != null) 'account_id': accountId,
      if (amountCents != null) 'amount_cents': amountCents,
      if (direction != null) 'direction': direction,
      if (accountMovementDate != null)
        'account_movement_date': accountMovementDate,
      if (categoryId != null) 'category_id': categoryId,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PostingsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? entryId,
      Value<String>? accountId,
      Value<int>? amountCents,
      Value<String>? direction,
      Value<String>? accountMovementDate,
      Value<String?>? categoryId,
      Value<String?>? note,
      Value<int>? rowid}) {
    return PostingsTableCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      accountId: accountId ?? this.accountId,
      amountCents: amountCents ?? this.amountCents,
      direction: direction ?? this.direction,
      accountMovementDate: accountMovementDate ?? this.accountMovementDate,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (accountMovementDate.present) {
      map['account_movement_date'] =
          Variable<String>(accountMovementDate.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PostingsTableCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('accountId: $accountId, ')
          ..write('amountCents: $amountCents, ')
          ..write('direction: $direction, ')
          ..write('accountMovementDate: $accountMovementDate, ')
          ..write('categoryId: $categoryId, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettlementAllocationsTableTable extends SettlementAllocationsTable
    with
        TableInfo<$SettlementAllocationsTableTable,
            SettlementAllocationsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettlementAllocationsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _settlementEntryIdMeta =
      const VerificationMeta('settlementEntryId');
  @override
  late final GeneratedColumn<String> settlementEntryId =
      GeneratedColumn<String>('settlement_entry_id', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: true,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'REFERENCES journal_entries_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _debtIdMeta = const VerificationMeta('debtId');
  @override
  late final GeneratedColumn<String> debtId = GeneratedColumn<String>(
      'debt_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES debts_table (id) ON DELETE RESTRICT'));
  static const VerificationMeta _allocatedCentsMeta =
      const VerificationMeta('allocatedCents');
  @override
  late final GeneratedColumn<int> allocatedCents = GeneratedColumn<int>(
      'allocated_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _settlementDateMeta =
      const VerificationMeta('settlementDate');
  @override
  late final GeneratedColumn<String> settlementDate = GeneratedColumn<String>(
      'settlement_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, settlementEntryId, debtId, allocatedCents, settlementDate];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settlement_allocations_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<SettlementAllocationsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('settlement_entry_id')) {
      context.handle(
          _settlementEntryIdMeta,
          settlementEntryId.isAcceptableOrUnknown(
              data['settlement_entry_id']!, _settlementEntryIdMeta));
    } else if (isInserting) {
      context.missing(_settlementEntryIdMeta);
    }
    if (data.containsKey('debt_id')) {
      context.handle(_debtIdMeta,
          debtId.isAcceptableOrUnknown(data['debt_id']!, _debtIdMeta));
    } else if (isInserting) {
      context.missing(_debtIdMeta);
    }
    if (data.containsKey('allocated_cents')) {
      context.handle(
          _allocatedCentsMeta,
          allocatedCents.isAcceptableOrUnknown(
              data['allocated_cents']!, _allocatedCentsMeta));
    } else if (isInserting) {
      context.missing(_allocatedCentsMeta);
    }
    if (data.containsKey('settlement_date')) {
      context.handle(
          _settlementDateMeta,
          settlementDate.isAcceptableOrUnknown(
              data['settlement_date']!, _settlementDateMeta));
    } else if (isInserting) {
      context.missing(_settlementDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SettlementAllocationsTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettlementAllocationsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      settlementEntryId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}settlement_entry_id'])!,
      debtId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}debt_id'])!,
      allocatedCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}allocated_cents'])!,
      settlementDate: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}settlement_date'])!,
    );
  }

  @override
  $SettlementAllocationsTableTable createAlias(String alias) {
    return $SettlementAllocationsTableTable(attachedDatabase, alias);
  }
}

class SettlementAllocationsTableData extends DataClass
    implements Insertable<SettlementAllocationsTableData> {
  final String id;
  final String settlementEntryId;
  final String debtId;
  final int allocatedCents;
  final String settlementDate;
  const SettlementAllocationsTableData(
      {required this.id,
      required this.settlementEntryId,
      required this.debtId,
      required this.allocatedCents,
      required this.settlementDate});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['settlement_entry_id'] = Variable<String>(settlementEntryId);
    map['debt_id'] = Variable<String>(debtId);
    map['allocated_cents'] = Variable<int>(allocatedCents);
    map['settlement_date'] = Variable<String>(settlementDate);
    return map;
  }

  SettlementAllocationsTableCompanion toCompanion(bool nullToAbsent) {
    return SettlementAllocationsTableCompanion(
      id: Value(id),
      settlementEntryId: Value(settlementEntryId),
      debtId: Value(debtId),
      allocatedCents: Value(allocatedCents),
      settlementDate: Value(settlementDate),
    );
  }

  factory SettlementAllocationsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettlementAllocationsTableData(
      id: serializer.fromJson<String>(json['id']),
      settlementEntryId: serializer.fromJson<String>(json['settlementEntryId']),
      debtId: serializer.fromJson<String>(json['debtId']),
      allocatedCents: serializer.fromJson<int>(json['allocatedCents']),
      settlementDate: serializer.fromJson<String>(json['settlementDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'settlementEntryId': serializer.toJson<String>(settlementEntryId),
      'debtId': serializer.toJson<String>(debtId),
      'allocatedCents': serializer.toJson<int>(allocatedCents),
      'settlementDate': serializer.toJson<String>(settlementDate),
    };
  }

  SettlementAllocationsTableData copyWith(
          {String? id,
          String? settlementEntryId,
          String? debtId,
          int? allocatedCents,
          String? settlementDate}) =>
      SettlementAllocationsTableData(
        id: id ?? this.id,
        settlementEntryId: settlementEntryId ?? this.settlementEntryId,
        debtId: debtId ?? this.debtId,
        allocatedCents: allocatedCents ?? this.allocatedCents,
        settlementDate: settlementDate ?? this.settlementDate,
      );
  SettlementAllocationsTableData copyWithCompanion(
      SettlementAllocationsTableCompanion data) {
    return SettlementAllocationsTableData(
      id: data.id.present ? data.id.value : this.id,
      settlementEntryId: data.settlementEntryId.present
          ? data.settlementEntryId.value
          : this.settlementEntryId,
      debtId: data.debtId.present ? data.debtId.value : this.debtId,
      allocatedCents: data.allocatedCents.present
          ? data.allocatedCents.value
          : this.allocatedCents,
      settlementDate: data.settlementDate.present
          ? data.settlementDate.value
          : this.settlementDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettlementAllocationsTableData(')
          ..write('id: $id, ')
          ..write('settlementEntryId: $settlementEntryId, ')
          ..write('debtId: $debtId, ')
          ..write('allocatedCents: $allocatedCents, ')
          ..write('settlementDate: $settlementDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, settlementEntryId, debtId, allocatedCents, settlementDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettlementAllocationsTableData &&
          other.id == this.id &&
          other.settlementEntryId == this.settlementEntryId &&
          other.debtId == this.debtId &&
          other.allocatedCents == this.allocatedCents &&
          other.settlementDate == this.settlementDate);
}

class SettlementAllocationsTableCompanion
    extends UpdateCompanion<SettlementAllocationsTableData> {
  final Value<String> id;
  final Value<String> settlementEntryId;
  final Value<String> debtId;
  final Value<int> allocatedCents;
  final Value<String> settlementDate;
  final Value<int> rowid;
  const SettlementAllocationsTableCompanion({
    this.id = const Value.absent(),
    this.settlementEntryId = const Value.absent(),
    this.debtId = const Value.absent(),
    this.allocatedCents = const Value.absent(),
    this.settlementDate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettlementAllocationsTableCompanion.insert({
    required String id,
    required String settlementEntryId,
    required String debtId,
    required int allocatedCents,
    required String settlementDate,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        settlementEntryId = Value(settlementEntryId),
        debtId = Value(debtId),
        allocatedCents = Value(allocatedCents),
        settlementDate = Value(settlementDate);
  static Insertable<SettlementAllocationsTableData> custom({
    Expression<String>? id,
    Expression<String>? settlementEntryId,
    Expression<String>? debtId,
    Expression<int>? allocatedCents,
    Expression<String>? settlementDate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (settlementEntryId != null) 'settlement_entry_id': settlementEntryId,
      if (debtId != null) 'debt_id': debtId,
      if (allocatedCents != null) 'allocated_cents': allocatedCents,
      if (settlementDate != null) 'settlement_date': settlementDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettlementAllocationsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? settlementEntryId,
      Value<String>? debtId,
      Value<int>? allocatedCents,
      Value<String>? settlementDate,
      Value<int>? rowid}) {
    return SettlementAllocationsTableCompanion(
      id: id ?? this.id,
      settlementEntryId: settlementEntryId ?? this.settlementEntryId,
      debtId: debtId ?? this.debtId,
      allocatedCents: allocatedCents ?? this.allocatedCents,
      settlementDate: settlementDate ?? this.settlementDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (settlementEntryId.present) {
      map['settlement_entry_id'] = Variable<String>(settlementEntryId.value);
    }
    if (debtId.present) {
      map['debt_id'] = Variable<String>(debtId.value);
    }
    if (allocatedCents.present) {
      map['allocated_cents'] = Variable<int>(allocatedCents.value);
    }
    if (settlementDate.present) {
      map['settlement_date'] = Variable<String>(settlementDate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettlementAllocationsTableCompanion(')
          ..write('id: $id, ')
          ..write('settlementEntryId: $settlementEntryId, ')
          ..write('debtId: $debtId, ')
          ..write('allocatedCents: $allocatedCents, ')
          ..write('settlementDate: $settlementDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTableTable extends BudgetsTable
    with TableInfo<$BudgetsTableTable, BudgetsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES financial_categories (id) ON DELETE RESTRICT'));
  static const VerificationMeta _monthIsoMeta =
      const VerificationMeta('monthIso');
  @override
  late final GeneratedColumn<String> monthIso = GeneratedColumn<String>(
      'month_iso', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _limitCentsMeta =
      const VerificationMeta('limitCents');
  @override
  late final GeneratedColumn<int> limitCents = GeneratedColumn<int>(
      'limit_cents', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _rolloverEnabledMeta =
      const VerificationMeta('rolloverEnabled');
  @override
  late final GeneratedColumn<bool> rolloverEnabled = GeneratedColumn<bool>(
      'rollover_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("rollover_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        categoryId,
        monthIso,
        limitCents,
        rolloverEnabled,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets_table';
  @override
  VerificationContext validateIntegrity(Insertable<BudgetsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('month_iso')) {
      context.handle(_monthIsoMeta,
          monthIso.isAcceptableOrUnknown(data['month_iso']!, _monthIsoMeta));
    } else if (isInserting) {
      context.missing(_monthIsoMeta);
    }
    if (data.containsKey('limit_cents')) {
      context.handle(
          _limitCentsMeta,
          limitCents.isAcceptableOrUnknown(
              data['limit_cents']!, _limitCentsMeta));
    } else if (isInserting) {
      context.missing(_limitCentsMeta);
    }
    if (data.containsKey('rollover_enabled')) {
      context.handle(
          _rolloverEnabledMeta,
          rolloverEnabled.isAcceptableOrUnknown(
              data['rollover_enabled']!, _rolloverEnabledMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BudgetsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BudgetsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id'])!,
      monthIso: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}month_iso'])!,
      limitCents: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}limit_cents'])!,
      rolloverEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}rollover_enabled'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $BudgetsTableTable createAlias(String alias) {
    return $BudgetsTableTable(attachedDatabase, alias);
  }
}

class BudgetsTableData extends DataClass
    implements Insertable<BudgetsTableData> {
  final String id;
  final String categoryId;
  final String monthIso;
  final int limitCents;
  final bool rolloverEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const BudgetsTableData(
      {required this.id,
      required this.categoryId,
      required this.monthIso,
      required this.limitCents,
      required this.rolloverEnabled,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['category_id'] = Variable<String>(categoryId);
    map['month_iso'] = Variable<String>(monthIso);
    map['limit_cents'] = Variable<int>(limitCents);
    map['rollover_enabled'] = Variable<bool>(rolloverEnabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BudgetsTableCompanion toCompanion(bool nullToAbsent) {
    return BudgetsTableCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      monthIso: Value(monthIso),
      limitCents: Value(limitCents),
      rolloverEnabled: Value(rolloverEnabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory BudgetsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BudgetsTableData(
      id: serializer.fromJson<String>(json['id']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      monthIso: serializer.fromJson<String>(json['monthIso']),
      limitCents: serializer.fromJson<int>(json['limitCents']),
      rolloverEnabled: serializer.fromJson<bool>(json['rolloverEnabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'categoryId': serializer.toJson<String>(categoryId),
      'monthIso': serializer.toJson<String>(monthIso),
      'limitCents': serializer.toJson<int>(limitCents),
      'rolloverEnabled': serializer.toJson<bool>(rolloverEnabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  BudgetsTableData copyWith(
          {String? id,
          String? categoryId,
          String? monthIso,
          int? limitCents,
          bool? rolloverEnabled,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      BudgetsTableData(
        id: id ?? this.id,
        categoryId: categoryId ?? this.categoryId,
        monthIso: monthIso ?? this.monthIso,
        limitCents: limitCents ?? this.limitCents,
        rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  BudgetsTableData copyWithCompanion(BudgetsTableCompanion data) {
    return BudgetsTableData(
      id: data.id.present ? data.id.value : this.id,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
      monthIso: data.monthIso.present ? data.monthIso.value : this.monthIso,
      limitCents:
          data.limitCents.present ? data.limitCents.value : this.limitCents,
      rolloverEnabled: data.rolloverEnabled.present
          ? data.rolloverEnabled.value
          : this.rolloverEnabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsTableData(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('monthIso: $monthIso, ')
          ..write('limitCents: $limitCents, ')
          ..write('rolloverEnabled: $rolloverEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, categoryId, monthIso, limitCents,
      rolloverEnabled, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BudgetsTableData &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.monthIso == this.monthIso &&
          other.limitCents == this.limitCents &&
          other.rolloverEnabled == this.rolloverEnabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BudgetsTableCompanion extends UpdateCompanion<BudgetsTableData> {
  final Value<String> id;
  final Value<String> categoryId;
  final Value<String> monthIso;
  final Value<int> limitCents;
  final Value<bool> rolloverEnabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BudgetsTableCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.monthIso = const Value.absent(),
    this.limitCents = const Value.absent(),
    this.rolloverEnabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetsTableCompanion.insert({
    required String id,
    required String categoryId,
    required String monthIso,
    required int limitCents,
    this.rolloverEnabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        categoryId = Value(categoryId),
        monthIso = Value(monthIso),
        limitCents = Value(limitCents),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<BudgetsTableData> custom({
    Expression<String>? id,
    Expression<String>? categoryId,
    Expression<String>? monthIso,
    Expression<int>? limitCents,
    Expression<bool>? rolloverEnabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (monthIso != null) 'month_iso': monthIso,
      if (limitCents != null) 'limit_cents': limitCents,
      if (rolloverEnabled != null) 'rollover_enabled': rolloverEnabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? categoryId,
      Value<String>? monthIso,
      Value<int>? limitCents,
      Value<bool>? rolloverEnabled,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return BudgetsTableCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      monthIso: monthIso ?? this.monthIso,
      limitCents: limitCents ?? this.limitCents,
      rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (monthIso.present) {
      map['month_iso'] = Variable<String>(monthIso.value);
    }
    if (limitCents.present) {
      map['limit_cents'] = Variable<int>(limitCents.value);
    }
    if (rolloverEnabled.present) {
      map['rollover_enabled'] = Variable<bool>(rolloverEnabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsTableCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('monthIso: $monthIso, ')
          ..write('limitCents: $limitCents, ')
          ..write('rolloverEnabled: $rolloverEnabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $InboxItemsTable inboxItems = $InboxItemsTable(this);
  late final $GoalsTable goals = $GoalsTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $MilestonesTable milestones = $MilestonesTable(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $CalendarEventsTable calendarEvents = $CalendarEventsTable(this);
  late final $FinancialCategoriesTable financialCategories =
      $FinancialCategoriesTable(this);
  late final $FinancialTransactionsTable financialTransactions =
      $FinancialTransactionsTable(this);
  late final $AccountsTableTable accountsTable = $AccountsTableTable(this);
  late final $JournalEntriesTableTable journalEntriesTable =
      $JournalEntriesTableTable(this);
  late final $PartiesTableTable partiesTable = $PartiesTableTable(this);
  late final $DebtsTableTable debtsTable = $DebtsTableTable(this);
  late final $RecurringRulesTableTable recurringRulesTable =
      $RecurringRulesTableTable(this);
  late final $FinancialCommitmentsTable financialCommitments =
      $FinancialCommitmentsTable(this);
  late final $CommitmentSettlementsTableTable commitmentSettlementsTable =
      $CommitmentSettlementsTableTable(this);
  late final $SavingsGoalsTable savingsGoals = $SavingsGoalsTable(this);
  late final $RemindersTable reminders = $RemindersTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $PostingsTableTable postingsTable = $PostingsTableTable(this);
  late final $SettlementAllocationsTableTable settlementAllocationsTable =
      $SettlementAllocationsTableTable(this);
  late final $BudgetsTableTable budgetsTable = $BudgetsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        inboxItems,
        goals,
        projects,
        milestones,
        tasks,
        notes,
        calendarEvents,
        financialCategories,
        financialTransactions,
        accountsTable,
        journalEntriesTable,
        partiesTable,
        debtsTable,
        recurringRulesTable,
        financialCommitments,
        commitmentSettlementsTable,
        savingsGoals,
        reminders,
        appSettings,
        postingsTable,
        settlementAllocationsTable,
        budgetsTable
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('goals',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('projects', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('projects',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('milestones', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('projects',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('tasks', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('milestones',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('tasks', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('projects',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('notes', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('goals',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('notes', kind: UpdateKind.update),
            ],
          ),
        ],
      );
}

typedef $$InboxItemsTableCreateCompanionBuilder = InboxItemsCompanion Function({
  required String id,
  required String rawText,
  Value<String> category,
  Value<bool> isProcessed,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$InboxItemsTableUpdateCompanionBuilder = InboxItemsCompanion Function({
  Value<String> id,
  Value<String> rawText,
  Value<String> category,
  Value<bool> isProcessed,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$InboxItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $InboxItemsTable,
    InboxItem,
    $$InboxItemsTableFilterComposer,
    $$InboxItemsTableOrderingComposer,
    $$InboxItemsTableCreateCompanionBuilder,
    $$InboxItemsTableUpdateCompanionBuilder> {
  $$InboxItemsTableTableManager(_$AppDatabase db, $InboxItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$InboxItemsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$InboxItemsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> rawText = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<bool> isProcessed = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              InboxItemsCompanion(
            id: id,
            rawText: rawText,
            category: category,
            isProcessed: isProcessed,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String rawText,
            Value<String> category = const Value.absent(),
            Value<bool> isProcessed = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              InboxItemsCompanion.insert(
            id: id,
            rawText: rawText,
            category: category,
            isProcessed: isProcessed,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$InboxItemsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $InboxItemsTable> {
  $$InboxItemsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get rawText => $state.composableBuilder(
      column: $state.table.rawText,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isProcessed => $state.composableBuilder(
      column: $state.table.isProcessed,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$InboxItemsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $InboxItemsTable> {
  $$InboxItemsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get rawText => $state.composableBuilder(
      column: $state.table.rawText,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isProcessed => $state.composableBuilder(
      column: $state.table.isProcessed,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$GoalsTableCreateCompanionBuilder = GoalsCompanion Function({
  required String id,
  required String title,
  Value<String?> description,
  Value<String?> targetDate,
  Value<String> status,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$GoalsTableUpdateCompanionBuilder = GoalsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String?> description,
  Value<String?> targetDate,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$GoalsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $GoalsTable,
    Goal,
    $$GoalsTableFilterComposer,
    $$GoalsTableOrderingComposer,
    $$GoalsTableCreateCompanionBuilder,
    $$GoalsTableUpdateCompanionBuilder> {
  $$GoalsTableTableManager(_$AppDatabase db, $GoalsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$GoalsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$GoalsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> targetDate = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GoalsCompanion(
            id: id,
            title: title,
            description: description,
            targetDate: targetDate,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            Value<String?> description = const Value.absent(),
            Value<String?> targetDate = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              GoalsCompanion.insert(
            id: id,
            title: title,
            description: description,
            targetDate: targetDate,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$GoalsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get targetDate => $state.composableBuilder(
      column: $state.table.targetDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ComposableFilter projectsRefs(
      ComposableFilter Function($$ProjectsTableFilterComposer f) f) {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.goalId,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter notesRefs(
      ComposableFilter Function($$NotesTableFilterComposer f) f) {
    final $$NotesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.notes,
        getReferencedColumn: (t) => t.goalId,
        builder: (joinBuilder, parentComposers) => $$NotesTableFilterComposer(
            ComposerState(
                $state.db, $state.db.notes, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$GoalsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $GoalsTable> {
  $$GoalsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get targetDate => $state.composableBuilder(
      column: $state.table.targetDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$ProjectsTableCreateCompanionBuilder = ProjectsCompanion Function({
  required String id,
  Value<String?> goalId,
  required String title,
  Value<String?> description,
  Value<String> status,
  Value<String?> targetDate,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<String> id,
  Value<String?> goalId,
  Value<String> title,
  Value<String?> description,
  Value<String> status,
  Value<String?> targetDate,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$ProjectsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableCreateCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder> {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$ProjectsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$ProjectsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> goalId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> targetDate = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProjectsCompanion(
            id: id,
            goalId: goalId,
            title: title,
            description: description,
            status: status,
            targetDate: targetDate,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> goalId = const Value.absent(),
            required String title,
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> targetDate = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ProjectsCompanion.insert(
            id: id,
            goalId: goalId,
            title: title,
            description: description,
            status: status,
            targetDate: targetDate,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$ProjectsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get targetDate => $state.composableBuilder(
      column: $state.table.targetDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$GoalsTableFilterComposer get goalId {
    final $$GoalsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.goalId,
        referencedTable: $state.db.goals,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) => $$GoalsTableFilterComposer(
            ComposerState(
                $state.db, $state.db.goals, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter milestonesRefs(
      ComposableFilter Function($$MilestonesTableFilterComposer f) f) {
    final $$MilestonesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.milestones,
        getReferencedColumn: (t) => t.projectId,
        builder: (joinBuilder, parentComposers) =>
            $$MilestonesTableFilterComposer(ComposerState($state.db,
                $state.db.milestones, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter tasksRefs(
      ComposableFilter Function($$TasksTableFilterComposer f) f) {
    final $$TasksTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.tasks,
        getReferencedColumn: (t) => t.projectId,
        builder: (joinBuilder, parentComposers) => $$TasksTableFilterComposer(
            ComposerState(
                $state.db, $state.db.tasks, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter notesRefs(
      ComposableFilter Function($$NotesTableFilterComposer f) f) {
    final $$NotesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.notes,
        getReferencedColumn: (t) => t.projectId,
        builder: (joinBuilder, parentComposers) => $$NotesTableFilterComposer(
            ComposerState(
                $state.db, $state.db.notes, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get targetDate => $state.composableBuilder(
      column: $state.table.targetDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$GoalsTableOrderingComposer get goalId {
    final $$GoalsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.goalId,
        referencedTable: $state.db.goals,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) => $$GoalsTableOrderingComposer(
            ComposerState(
                $state.db, $state.db.goals, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$MilestonesTableCreateCompanionBuilder = MilestonesCompanion Function({
  required String id,
  required String projectId,
  required String title,
  Value<String?> dueDate,
  Value<bool> isCompleted,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$MilestonesTableUpdateCompanionBuilder = MilestonesCompanion Function({
  Value<String> id,
  Value<String> projectId,
  Value<String> title,
  Value<String?> dueDate,
  Value<bool> isCompleted,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$MilestonesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MilestonesTable,
    Milestone,
    $$MilestonesTableFilterComposer,
    $$MilestonesTableOrderingComposer,
    $$MilestonesTableCreateCompanionBuilder,
    $$MilestonesTableUpdateCompanionBuilder> {
  $$MilestonesTableTableManager(_$AppDatabase db, $MilestonesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$MilestonesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$MilestonesTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> projectId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> dueDate = const Value.absent(),
            Value<bool> isCompleted = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MilestonesCompanion(
            id: id,
            projectId: projectId,
            title: title,
            dueDate: dueDate,
            isCompleted: isCompleted,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String projectId,
            required String title,
            Value<String?> dueDate = const Value.absent(),
            Value<bool> isCompleted = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MilestonesCompanion.insert(
            id: id,
            projectId: projectId,
            title: title,
            dueDate: dueDate,
            isCompleted: isCompleted,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$MilestonesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $MilestonesTable> {
  $$MilestonesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isCompleted => $state.composableBuilder(
      column: $state.table.isCompleted,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter tasksRefs(
      ComposableFilter Function($$TasksTableFilterComposer f) f) {
    final $$TasksTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.tasks,
        getReferencedColumn: (t) => t.milestoneId,
        builder: (joinBuilder, parentComposers) => $$TasksTableFilterComposer(
            ComposerState(
                $state.db, $state.db.tasks, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$MilestonesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $MilestonesTable> {
  $$MilestonesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isCompleted => $state.composableBuilder(
      column: $state.table.isCompleted,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableOrderingComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  required String title,
  Value<String?> description,
  Value<String> status,
  Value<String> priority,
  Value<String?> dueDate,
  Value<String?> scheduledDate,
  Value<int?> estimatedDurationMinutes,
  Value<String?> projectId,
  Value<String?> milestoneId,
  Value<String> subtasksJson,
  Value<String> labelsJson,
  Value<bool> isPinned,
  Value<bool> isMyDay,
  Value<String?> recurrenceRule,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String?> description,
  Value<String> status,
  Value<String> priority,
  Value<String?> dueDate,
  Value<String?> scheduledDate,
  Value<int?> estimatedDurationMinutes,
  Value<String?> projectId,
  Value<String?> milestoneId,
  Value<String> subtasksJson,
  Value<String> labelsJson,
  Value<bool> isPinned,
  Value<bool> isMyDay,
  Value<String?> recurrenceRule,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$TasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TasksTable,
    Task,
    $$TasksTableFilterComposer,
    $$TasksTableOrderingComposer,
    $$TasksTableCreateCompanionBuilder,
    $$TasksTableUpdateCompanionBuilder> {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$TasksTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$TasksTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> priority = const Value.absent(),
            Value<String?> dueDate = const Value.absent(),
            Value<String?> scheduledDate = const Value.absent(),
            Value<int?> estimatedDurationMinutes = const Value.absent(),
            Value<String?> projectId = const Value.absent(),
            Value<String?> milestoneId = const Value.absent(),
            Value<String> subtasksJson = const Value.absent(),
            Value<String> labelsJson = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isMyDay = const Value.absent(),
            Value<String?> recurrenceRule = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion(
            id: id,
            title: title,
            description: description,
            status: status,
            priority: priority,
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            estimatedDurationMinutes: estimatedDurationMinutes,
            projectId: projectId,
            milestoneId: milestoneId,
            subtasksJson: subtasksJson,
            labelsJson: labelsJson,
            isPinned: isPinned,
            isMyDay: isMyDay,
            recurrenceRule: recurrenceRule,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            Value<String?> description = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> priority = const Value.absent(),
            Value<String?> dueDate = const Value.absent(),
            Value<String?> scheduledDate = const Value.absent(),
            Value<int?> estimatedDurationMinutes = const Value.absent(),
            Value<String?> projectId = const Value.absent(),
            Value<String?> milestoneId = const Value.absent(),
            Value<String> subtasksJson = const Value.absent(),
            Value<String> labelsJson = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isMyDay = const Value.absent(),
            Value<String?> recurrenceRule = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              TasksCompanion.insert(
            id: id,
            title: title,
            description: description,
            status: status,
            priority: priority,
            dueDate: dueDate,
            scheduledDate: scheduledDate,
            estimatedDurationMinutes: estimatedDurationMinutes,
            projectId: projectId,
            milestoneId: milestoneId,
            subtasksJson: subtasksJson,
            labelsJson: labelsJson,
            isPinned: isPinned,
            isMyDay: isMyDay,
            recurrenceRule: recurrenceRule,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$TasksTableFilterComposer
    extends FilterComposer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get priority => $state.composableBuilder(
      column: $state.table.priority,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get scheduledDate => $state.composableBuilder(
      column: $state.table.scheduledDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get estimatedDurationMinutes => $state.composableBuilder(
      column: $state.table.estimatedDurationMinutes,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get subtasksJson => $state.composableBuilder(
      column: $state.table.subtasksJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get labelsJson => $state.composableBuilder(
      column: $state.table.labelsJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isPinned => $state.composableBuilder(
      column: $state.table.isPinned,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isMyDay => $state.composableBuilder(
      column: $state.table.isMyDay,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get recurrenceRule => $state.composableBuilder(
      column: $state.table.recurrenceRule,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  $$MilestonesTableFilterComposer get milestoneId {
    final $$MilestonesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.milestoneId,
        referencedTable: $state.db.milestones,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MilestonesTableFilterComposer(ComposerState($state.db,
                $state.db.milestones, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$TasksTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get priority => $state.composableBuilder(
      column: $state.table.priority,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get scheduledDate => $state.composableBuilder(
      column: $state.table.scheduledDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get estimatedDurationMinutes => $state.composableBuilder(
      column: $state.table.estimatedDurationMinutes,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get subtasksJson => $state.composableBuilder(
      column: $state.table.subtasksJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get labelsJson => $state.composableBuilder(
      column: $state.table.labelsJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isPinned => $state.composableBuilder(
      column: $state.table.isPinned,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isMyDay => $state.composableBuilder(
      column: $state.table.isMyDay,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get recurrenceRule => $state.composableBuilder(
      column: $state.table.recurrenceRule,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableOrderingComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  $$MilestonesTableOrderingComposer get milestoneId {
    final $$MilestonesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.milestoneId,
        referencedTable: $state.db.milestones,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$MilestonesTableOrderingComposer(ComposerState($state.db,
                $state.db.milestones, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$NotesTableCreateCompanionBuilder = NotesCompanion Function({
  required String id,
  required String title,
  required String content,
  Value<String> category,
  Value<String?> projectId,
  Value<String?> goalId,
  Value<String> tagsJson,
  Value<bool> isPinned,
  Value<bool> isFavorite,
  Value<bool> isArchived,
  Value<bool> isTrashed,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$NotesTableUpdateCompanionBuilder = NotesCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> content,
  Value<String> category,
  Value<String?> projectId,
  Value<String?> goalId,
  Value<String> tagsJson,
  Value<bool> isPinned,
  Value<bool> isFavorite,
  Value<bool> isArchived,
  Value<bool> isTrashed,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$NotesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $NotesTable,
    Note,
    $$NotesTableFilterComposer,
    $$NotesTableOrderingComposer,
    $$NotesTableCreateCompanionBuilder,
    $$NotesTableUpdateCompanionBuilder> {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$NotesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$NotesTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String?> projectId = const Value.absent(),
            Value<String?> goalId = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<bool> isTrashed = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NotesCompanion(
            id: id,
            title: title,
            content: content,
            category: category,
            projectId: projectId,
            goalId: goalId,
            tagsJson: tagsJson,
            isPinned: isPinned,
            isFavorite: isFavorite,
            isArchived: isArchived,
            isTrashed: isTrashed,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required String content,
            Value<String> category = const Value.absent(),
            Value<String?> projectId = const Value.absent(),
            Value<String?> goalId = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<bool> isTrashed = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              NotesCompanion.insert(
            id: id,
            title: title,
            content: content,
            category: category,
            projectId: projectId,
            goalId: goalId,
            tagsJson: tagsJson,
            isPinned: isPinned,
            isFavorite: isFavorite,
            isArchived: isArchived,
            isTrashed: isTrashed,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$NotesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get content => $state.composableBuilder(
      column: $state.table.content,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get tagsJson => $state.composableBuilder(
      column: $state.table.tagsJson,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isPinned => $state.composableBuilder(
      column: $state.table.isPinned,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isFavorite => $state.composableBuilder(
      column: $state.table.isFavorite,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isTrashed => $state.composableBuilder(
      column: $state.table.isTrashed,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  $$GoalsTableFilterComposer get goalId {
    final $$GoalsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.goalId,
        referencedTable: $state.db.goals,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) => $$GoalsTableFilterComposer(
            ComposerState(
                $state.db, $state.db.goals, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$NotesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get content => $state.composableBuilder(
      column: $state.table.content,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get tagsJson => $state.composableBuilder(
      column: $state.table.tagsJson,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isPinned => $state.composableBuilder(
      column: $state.table.isPinned,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isFavorite => $state.composableBuilder(
      column: $state.table.isFavorite,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isTrashed => $state.composableBuilder(
      column: $state.table.isTrashed,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableOrderingComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  $$GoalsTableOrderingComposer get goalId {
    final $$GoalsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.goalId,
        referencedTable: $state.db.goals,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) => $$GoalsTableOrderingComposer(
            ComposerState(
                $state.db, $state.db.goals, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$CalendarEventsTableCreateCompanionBuilder = CalendarEventsCompanion
    Function({
  required String id,
  required String title,
  required String dateIso,
  Value<String?> endDateIso,
  Value<String?> startTime,
  Value<String?> endTime,
  Value<bool> isAllDay,
  Value<String> category,
  Value<String> colorHex,
  Value<bool> hasReminder,
  Value<String?> notes,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$CalendarEventsTableUpdateCompanionBuilder = CalendarEventsCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<String> dateIso,
  Value<String?> endDateIso,
  Value<String?> startTime,
  Value<String?> endTime,
  Value<bool> isAllDay,
  Value<String> category,
  Value<String> colorHex,
  Value<bool> hasReminder,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CalendarEventsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CalendarEventsTable,
    CalendarEvent,
    $$CalendarEventsTableFilterComposer,
    $$CalendarEventsTableOrderingComposer,
    $$CalendarEventsTableCreateCompanionBuilder,
    $$CalendarEventsTableUpdateCompanionBuilder> {
  $$CalendarEventsTableTableManager(
      _$AppDatabase db, $CalendarEventsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$CalendarEventsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$CalendarEventsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> dateIso = const Value.absent(),
            Value<String?> endDateIso = const Value.absent(),
            Value<String?> startTime = const Value.absent(),
            Value<String?> endTime = const Value.absent(),
            Value<bool> isAllDay = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<bool> hasReminder = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CalendarEventsCompanion(
            id: id,
            title: title,
            dateIso: dateIso,
            endDateIso: endDateIso,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            category: category,
            colorHex: colorHex,
            hasReminder: hasReminder,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required String dateIso,
            Value<String?> endDateIso = const Value.absent(),
            Value<String?> startTime = const Value.absent(),
            Value<String?> endTime = const Value.absent(),
            Value<bool> isAllDay = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<bool> hasReminder = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CalendarEventsCompanion.insert(
            id: id,
            title: title,
            dateIso: dateIso,
            endDateIso: endDateIso,
            startTime: startTime,
            endTime: endTime,
            isAllDay: isAllDay,
            category: category,
            colorHex: colorHex,
            hasReminder: hasReminder,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$CalendarEventsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get dateIso => $state.composableBuilder(
      column: $state.table.dateIso,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get endDateIso => $state.composableBuilder(
      column: $state.table.endDateIso,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get startTime => $state.composableBuilder(
      column: $state.table.startTime,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get endTime => $state.composableBuilder(
      column: $state.table.endTime,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isAllDay => $state.composableBuilder(
      column: $state.table.isAllDay,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get colorHex => $state.composableBuilder(
      column: $state.table.colorHex,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get hasReminder => $state.composableBuilder(
      column: $state.table.hasReminder,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get notes => $state.composableBuilder(
      column: $state.table.notes,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$CalendarEventsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $CalendarEventsTable> {
  $$CalendarEventsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get dateIso => $state.composableBuilder(
      column: $state.table.dateIso,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get endDateIso => $state.composableBuilder(
      column: $state.table.endDateIso,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get startTime => $state.composableBuilder(
      column: $state.table.startTime,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get endTime => $state.composableBuilder(
      column: $state.table.endTime,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isAllDay => $state.composableBuilder(
      column: $state.table.isAllDay,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get colorHex => $state.composableBuilder(
      column: $state.table.colorHex,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get hasReminder => $state.composableBuilder(
      column: $state.table.hasReminder,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get notes => $state.composableBuilder(
      column: $state.table.notes,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$FinancialCategoriesTableCreateCompanionBuilder
    = FinancialCategoriesCompanion Function({
  required String id,
  required String name,
  required String type,
  Value<String> colorHex,
  Value<bool> isDefault,
  Value<bool> isArchived,
  Value<String?> parentId,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$FinancialCategoriesTableUpdateCompanionBuilder
    = FinancialCategoriesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> type,
  Value<String> colorHex,
  Value<bool> isDefault,
  Value<bool> isArchived,
  Value<String?> parentId,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$FinancialCategoriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FinancialCategoriesTable,
    FinancialCategory,
    $$FinancialCategoriesTableFilterComposer,
    $$FinancialCategoriesTableOrderingComposer,
    $$FinancialCategoriesTableCreateCompanionBuilder,
    $$FinancialCategoriesTableUpdateCompanionBuilder> {
  $$FinancialCategoriesTableTableManager(
      _$AppDatabase db, $FinancialCategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$FinancialCategoriesTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$FinancialCategoriesTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> colorHex = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FinancialCategoriesCompanion(
            id: id,
            name: name,
            type: type,
            colorHex: colorHex,
            isDefault: isDefault,
            isArchived: isArchived,
            parentId: parentId,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String type,
            Value<String> colorHex = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FinancialCategoriesCompanion.insert(
            id: id,
            name: name,
            type: type,
            colorHex: colorHex,
            isDefault: isDefault,
            isArchived: isArchived,
            parentId: parentId,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
        ));
}

class $$FinancialCategoriesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $FinancialCategoriesTable> {
  $$FinancialCategoriesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get colorHex => $state.composableBuilder(
      column: $state.table.colorHex,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isDefault => $state.composableBuilder(
      column: $state.table.isDefault,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get sortOrder => $state.composableBuilder(
      column: $state.table.sortOrder,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$FinancialCategoriesTableFilterComposer get parentId {
    final $$FinancialCategoriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.parentId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  ComposableFilter financialTransactionsRefs(
      ComposableFilter Function($$FinancialTransactionsTableFilterComposer f)
          f) {
    final $$FinancialTransactionsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.financialTransactions,
            getReferencedColumn: (t) => t.categoryId,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialTransactionsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialTransactions,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter recurringRulesTableRefs(
      ComposableFilter Function($$RecurringRulesTableTableFilterComposer f) f) {
    final $$RecurringRulesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.recurringRulesTable,
            getReferencedColumn: (t) => t.categoryId,
            builder: (joinBuilder, parentComposers) =>
                $$RecurringRulesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.recurringRulesTable,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter financialCommitmentsRefs(
      ComposableFilter Function($$FinancialCommitmentsTableFilterComposer f)
          f) {
    final $$FinancialCommitmentsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.categoryId,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter postingsTableRefs(
      ComposableFilter Function($$PostingsTableTableFilterComposer f) f) {
    final $$PostingsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.postingsTable,
        getReferencedColumn: (t) => t.categoryId,
        builder: (joinBuilder, parentComposers) =>
            $$PostingsTableTableFilterComposer(ComposerState($state.db,
                $state.db.postingsTable, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter budgetsTableRefs(
      ComposableFilter Function($$BudgetsTableTableFilterComposer f) f) {
    final $$BudgetsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.budgetsTable,
        getReferencedColumn: (t) => t.categoryId,
        builder: (joinBuilder, parentComposers) =>
            $$BudgetsTableTableFilterComposer(ComposerState($state.db,
                $state.db.budgetsTable, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$FinancialCategoriesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $FinancialCategoriesTable> {
  $$FinancialCategoriesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get colorHex => $state.composableBuilder(
      column: $state.table.colorHex,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isDefault => $state.composableBuilder(
      column: $state.table.isDefault,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get sortOrder => $state.composableBuilder(
      column: $state.table.sortOrder,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$FinancialCategoriesTableOrderingComposer get parentId {
    final $$FinancialCategoriesTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.parentId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$FinancialTransactionsTableCreateCompanionBuilder
    = FinancialTransactionsCompanion Function({
  required String id,
  required String categoryId,
  required int amountCents,
  required String type,
  required String transactionDate,
  Value<String?> note,
  Value<String?> payee,
  Value<String?> accountId,
  Value<String?> destinationAccountId,
  Value<bool> isSuperseded,
  Value<String?> correctedFromId,
  Value<String?> correctionReason,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$FinancialTransactionsTableUpdateCompanionBuilder
    = FinancialTransactionsCompanion Function({
  Value<String> id,
  Value<String> categoryId,
  Value<int> amountCents,
  Value<String> type,
  Value<String> transactionDate,
  Value<String?> note,
  Value<String?> payee,
  Value<String?> accountId,
  Value<String?> destinationAccountId,
  Value<bool> isSuperseded,
  Value<String?> correctedFromId,
  Value<String?> correctionReason,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$FinancialTransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FinancialTransactionsTable,
    FinancialTransaction,
    $$FinancialTransactionsTableFilterComposer,
    $$FinancialTransactionsTableOrderingComposer,
    $$FinancialTransactionsTableCreateCompanionBuilder,
    $$FinancialTransactionsTableUpdateCompanionBuilder> {
  $$FinancialTransactionsTableTableManager(
      _$AppDatabase db, $FinancialTransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$FinancialTransactionsTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$FinancialTransactionsTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> categoryId = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> transactionDate = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String?> payee = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String?> destinationAccountId = const Value.absent(),
            Value<bool> isSuperseded = const Value.absent(),
            Value<String?> correctedFromId = const Value.absent(),
            Value<String?> correctionReason = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FinancialTransactionsCompanion(
            id: id,
            categoryId: categoryId,
            amountCents: amountCents,
            type: type,
            transactionDate: transactionDate,
            note: note,
            payee: payee,
            accountId: accountId,
            destinationAccountId: destinationAccountId,
            isSuperseded: isSuperseded,
            correctedFromId: correctedFromId,
            correctionReason: correctionReason,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String categoryId,
            required int amountCents,
            required String type,
            required String transactionDate,
            Value<String?> note = const Value.absent(),
            Value<String?> payee = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String?> destinationAccountId = const Value.absent(),
            Value<bool> isSuperseded = const Value.absent(),
            Value<String?> correctedFromId = const Value.absent(),
            Value<String?> correctionReason = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FinancialTransactionsCompanion.insert(
            id: id,
            categoryId: categoryId,
            amountCents: amountCents,
            type: type,
            transactionDate: transactionDate,
            note: note,
            payee: payee,
            accountId: accountId,
            destinationAccountId: destinationAccountId,
            isSuperseded: isSuperseded,
            correctedFromId: correctedFromId,
            correctionReason: correctionReason,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$FinancialTransactionsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $FinancialTransactionsTable> {
  $$FinancialTransactionsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get transactionDate => $state.composableBuilder(
      column: $state.table.transactionDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get note => $state.composableBuilder(
      column: $state.table.note,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get payee => $state.composableBuilder(
      column: $state.table.payee,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get accountId => $state.composableBuilder(
      column: $state.table.accountId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get destinationAccountId => $state.composableBuilder(
      column: $state.table.destinationAccountId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isSuperseded => $state.composableBuilder(
      column: $state.table.isSuperseded,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get correctedFromId => $state.composableBuilder(
      column: $state.table.correctedFromId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get correctionReason => $state.composableBuilder(
      column: $state.table.correctionReason,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$FinancialCategoriesTableFilterComposer get categoryId {
    final $$FinancialCategoriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

class $$FinancialTransactionsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $FinancialTransactionsTable> {
  $$FinancialTransactionsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get transactionDate => $state.composableBuilder(
      column: $state.table.transactionDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get note => $state.composableBuilder(
      column: $state.table.note,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get payee => $state.composableBuilder(
      column: $state.table.payee,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get accountId => $state.composableBuilder(
      column: $state.table.accountId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get destinationAccountId => $state.composableBuilder(
      column: $state.table.destinationAccountId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isSuperseded => $state.composableBuilder(
      column: $state.table.isSuperseded,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get correctedFromId => $state.composableBuilder(
      column: $state.table.correctedFromId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get correctionReason => $state.composableBuilder(
      column: $state.table.correctionReason,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$FinancialCategoriesTableOrderingComposer get categoryId {
    final $$FinancialCategoriesTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$AccountsTableTableCreateCompanionBuilder = AccountsTableCompanion
    Function({
  required String id,
  required String name,
  required String type,
  Value<String> subType,
  Value<bool> isSystem,
  Value<String> currencyCode,
  Value<int> openingBalanceCents,
  Value<String?> openingBalanceDate,
  Value<bool> isArchived,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$AccountsTableTableUpdateCompanionBuilder = AccountsTableCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> type,
  Value<String> subType,
  Value<bool> isSystem,
  Value<String> currencyCode,
  Value<int> openingBalanceCents,
  Value<String?> openingBalanceDate,
  Value<bool> isArchived,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$AccountsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AccountsTableTable,
    AccountsTableData,
    $$AccountsTableTableFilterComposer,
    $$AccountsTableTableOrderingComposer,
    $$AccountsTableTableCreateCompanionBuilder,
    $$AccountsTableTableUpdateCompanionBuilder> {
  $$AccountsTableTableTableManager(_$AppDatabase db, $AccountsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$AccountsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$AccountsTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String> subType = const Value.absent(),
            Value<bool> isSystem = const Value.absent(),
            Value<String> currencyCode = const Value.absent(),
            Value<int> openingBalanceCents = const Value.absent(),
            Value<String?> openingBalanceDate = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AccountsTableCompanion(
            id: id,
            name: name,
            type: type,
            subType: subType,
            isSystem: isSystem,
            currencyCode: currencyCode,
            openingBalanceCents: openingBalanceCents,
            openingBalanceDate: openingBalanceDate,
            isArchived: isArchived,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String type,
            Value<String> subType = const Value.absent(),
            Value<bool> isSystem = const Value.absent(),
            Value<String> currencyCode = const Value.absent(),
            Value<int> openingBalanceCents = const Value.absent(),
            Value<String?> openingBalanceDate = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AccountsTableCompanion.insert(
            id: id,
            name: name,
            type: type,
            subType: subType,
            isSystem: isSystem,
            currencyCode: currencyCode,
            openingBalanceCents: openingBalanceCents,
            openingBalanceDate: openingBalanceDate,
            isArchived: isArchived,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$AccountsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $AccountsTableTable> {
  $$AccountsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get subType => $state.composableBuilder(
      column: $state.table.subType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isSystem => $state.composableBuilder(
      column: $state.table.isSystem,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get currencyCode => $state.composableBuilder(
      column: $state.table.currencyCode,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get openingBalanceCents => $state.composableBuilder(
      column: $state.table.openingBalanceCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get openingBalanceDate => $state.composableBuilder(
      column: $state.table.openingBalanceDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ComposableFilter financialCommitmentsRefs(
      ComposableFilter Function($$FinancialCommitmentsTableFilterComposer f)
          f) {
    final $$FinancialCommitmentsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.linkedAccountId,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter savingsGoalsRefs(
      ComposableFilter Function($$SavingsGoalsTableFilterComposer f) f) {
    final $$SavingsGoalsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.savingsGoals,
        getReferencedColumn: (t) => t.linkedAccountId,
        builder: (joinBuilder, parentComposers) =>
            $$SavingsGoalsTableFilterComposer(ComposerState($state.db,
                $state.db.savingsGoals, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter postingsTableRefs(
      ComposableFilter Function($$PostingsTableTableFilterComposer f) f) {
    final $$PostingsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.postingsTable,
        getReferencedColumn: (t) => t.accountId,
        builder: (joinBuilder, parentComposers) =>
            $$PostingsTableTableFilterComposer(ComposerState($state.db,
                $state.db.postingsTable, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$AccountsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $AccountsTableTable> {
  $$AccountsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get subType => $state.composableBuilder(
      column: $state.table.subType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isSystem => $state.composableBuilder(
      column: $state.table.isSystem,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get currencyCode => $state.composableBuilder(
      column: $state.table.currencyCode,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get openingBalanceCents => $state.composableBuilder(
      column: $state.table.openingBalanceCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get openingBalanceDate => $state.composableBuilder(
      column: $state.table.openingBalanceDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$JournalEntriesTableTableCreateCompanionBuilder
    = JournalEntriesTableCompanion Function({
  required String id,
  required String entryType,
  required String description,
  required String occurrenceDate,
  Value<bool> isVoided,
  Value<String?> voidReason,
  Value<String?> legacySourceTxId,
  Value<String?> correctedFromEntryId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$JournalEntriesTableTableUpdateCompanionBuilder
    = JournalEntriesTableCompanion Function({
  Value<String> id,
  Value<String> entryType,
  Value<String> description,
  Value<String> occurrenceDate,
  Value<bool> isVoided,
  Value<String?> voidReason,
  Value<String?> legacySourceTxId,
  Value<String?> correctedFromEntryId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$JournalEntriesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $JournalEntriesTableTable,
    JournalEntriesTableData,
    $$JournalEntriesTableTableFilterComposer,
    $$JournalEntriesTableTableOrderingComposer,
    $$JournalEntriesTableTableCreateCompanionBuilder,
    $$JournalEntriesTableTableUpdateCompanionBuilder> {
  $$JournalEntriesTableTableTableManager(
      _$AppDatabase db, $JournalEntriesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$JournalEntriesTableTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$JournalEntriesTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> entryType = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> occurrenceDate = const Value.absent(),
            Value<bool> isVoided = const Value.absent(),
            Value<String?> voidReason = const Value.absent(),
            Value<String?> legacySourceTxId = const Value.absent(),
            Value<String?> correctedFromEntryId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              JournalEntriesTableCompanion(
            id: id,
            entryType: entryType,
            description: description,
            occurrenceDate: occurrenceDate,
            isVoided: isVoided,
            voidReason: voidReason,
            legacySourceTxId: legacySourceTxId,
            correctedFromEntryId: correctedFromEntryId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String entryType,
            required String description,
            required String occurrenceDate,
            Value<bool> isVoided = const Value.absent(),
            Value<String?> voidReason = const Value.absent(),
            Value<String?> legacySourceTxId = const Value.absent(),
            Value<String?> correctedFromEntryId = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              JournalEntriesTableCompanion.insert(
            id: id,
            entryType: entryType,
            description: description,
            occurrenceDate: occurrenceDate,
            isVoided: isVoided,
            voidReason: voidReason,
            legacySourceTxId: legacySourceTxId,
            correctedFromEntryId: correctedFromEntryId,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$JournalEntriesTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $JournalEntriesTableTable> {
  $$JournalEntriesTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get entryType => $state.composableBuilder(
      column: $state.table.entryType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get occurrenceDate => $state.composableBuilder(
      column: $state.table.occurrenceDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isVoided => $state.composableBuilder(
      column: $state.table.isVoided,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get voidReason => $state.composableBuilder(
      column: $state.table.voidReason,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get legacySourceTxId => $state.composableBuilder(
      column: $state.table.legacySourceTxId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableFilterComposer get correctedFromEntryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.correctedFromEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  ComposableFilter financialCommitmentsRefs(
      ComposableFilter Function($$FinancialCommitmentsTableFilterComposer f)
          f) {
    final $$FinancialCommitmentsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.settlementEntryId,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter commitmentSettlementsTableRefs(
      ComposableFilter Function(
              $$CommitmentSettlementsTableTableFilterComposer f)
          f) {
    final $$CommitmentSettlementsTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.commitmentSettlementsTable,
            getReferencedColumn: (t) => t.entryId,
            builder: (joinBuilder, parentComposers) =>
                $$CommitmentSettlementsTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.commitmentSettlementsTable,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter postingsTableRefs(
      ComposableFilter Function($$PostingsTableTableFilterComposer f) f) {
    final $$PostingsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.postingsTable,
        getReferencedColumn: (t) => t.entryId,
        builder: (joinBuilder, parentComposers) =>
            $$PostingsTableTableFilterComposer(ComposerState($state.db,
                $state.db.postingsTable, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter settlementAllocationsTableRefs(
      ComposableFilter Function(
              $$SettlementAllocationsTableTableFilterComposer f)
          f) {
    final $$SettlementAllocationsTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.settlementAllocationsTable,
            getReferencedColumn: (t) => t.settlementEntryId,
            builder: (joinBuilder, parentComposers) =>
                $$SettlementAllocationsTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.settlementAllocationsTable,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }
}

class $$JournalEntriesTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $JournalEntriesTableTable> {
  $$JournalEntriesTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get entryType => $state.composableBuilder(
      column: $state.table.entryType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get occurrenceDate => $state.composableBuilder(
      column: $state.table.occurrenceDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isVoided => $state.composableBuilder(
      column: $state.table.isVoided,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get voidReason => $state.composableBuilder(
      column: $state.table.voidReason,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get legacySourceTxId => $state.composableBuilder(
      column: $state.table.legacySourceTxId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableOrderingComposer get correctedFromEntryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.correctedFromEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$PartiesTableTableCreateCompanionBuilder = PartiesTableCompanion
    Function({
  required String id,
  required String name,
  Value<String?> phone,
  Value<String?> notes,
  Value<bool> isArchived,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$PartiesTableTableUpdateCompanionBuilder = PartiesTableCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String?> phone,
  Value<String?> notes,
  Value<bool> isArchived,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$PartiesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PartiesTableTable,
    PartiesTableData,
    $$PartiesTableTableFilterComposer,
    $$PartiesTableTableOrderingComposer,
    $$PartiesTableTableCreateCompanionBuilder,
    $$PartiesTableTableUpdateCompanionBuilder> {
  $$PartiesTableTableTableManager(_$AppDatabase db, $PartiesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$PartiesTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$PartiesTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PartiesTableCompanion(
            id: id,
            name: name,
            phone: phone,
            notes: notes,
            isArchived: isArchived,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> phone = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PartiesTableCompanion.insert(
            id: id,
            name: name,
            phone: phone,
            notes: notes,
            isArchived: isArchived,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$PartiesTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $PartiesTableTable> {
  $$PartiesTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get phone => $state.composableBuilder(
      column: $state.table.phone,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get notes => $state.composableBuilder(
      column: $state.table.notes,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ComposableFilter debtsTableRefs(
      ComposableFilter Function($$DebtsTableTableFilterComposer f) f) {
    final $$DebtsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.partyId,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableFilterComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$PartiesTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $PartiesTableTable> {
  $$PartiesTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get phone => $state.composableBuilder(
      column: $state.table.phone,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get notes => $state.composableBuilder(
      column: $state.table.notes,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isArchived => $state.composableBuilder(
      column: $state.table.isArchived,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$DebtsTableTableCreateCompanionBuilder = DebtsTableCompanion Function({
  required String id,
  required String originEntryId,
  required String partyId,
  required String debtType,
  required int principalCents,
  required int outstandingCents,
  Value<String?> dueDate,
  Value<String> status,
  Value<String?> writeOffEntryId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$DebtsTableTableUpdateCompanionBuilder = DebtsTableCompanion Function({
  Value<String> id,
  Value<String> originEntryId,
  Value<String> partyId,
  Value<String> debtType,
  Value<int> principalCents,
  Value<int> outstandingCents,
  Value<String?> dueDate,
  Value<String> status,
  Value<String?> writeOffEntryId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$DebtsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DebtsTableTable,
    DebtsTableData,
    $$DebtsTableTableFilterComposer,
    $$DebtsTableTableOrderingComposer,
    $$DebtsTableTableCreateCompanionBuilder,
    $$DebtsTableTableUpdateCompanionBuilder> {
  $$DebtsTableTableTableManager(_$AppDatabase db, $DebtsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$DebtsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$DebtsTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> originEntryId = const Value.absent(),
            Value<String> partyId = const Value.absent(),
            Value<String> debtType = const Value.absent(),
            Value<int> principalCents = const Value.absent(),
            Value<int> outstandingCents = const Value.absent(),
            Value<String?> dueDate = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> writeOffEntryId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DebtsTableCompanion(
            id: id,
            originEntryId: originEntryId,
            partyId: partyId,
            debtType: debtType,
            principalCents: principalCents,
            outstandingCents: outstandingCents,
            dueDate: dueDate,
            status: status,
            writeOffEntryId: writeOffEntryId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String originEntryId,
            required String partyId,
            required String debtType,
            required int principalCents,
            required int outstandingCents,
            Value<String?> dueDate = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> writeOffEntryId = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              DebtsTableCompanion.insert(
            id: id,
            originEntryId: originEntryId,
            partyId: partyId,
            debtType: debtType,
            principalCents: principalCents,
            outstandingCents: outstandingCents,
            dueDate: dueDate,
            status: status,
            writeOffEntryId: writeOffEntryId,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$DebtsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $DebtsTableTable> {
  $$DebtsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get debtType => $state.composableBuilder(
      column: $state.table.debtType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get principalCents => $state.composableBuilder(
      column: $state.table.principalCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get outstandingCents => $state.composableBuilder(
      column: $state.table.outstandingCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableFilterComposer get originEntryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.originEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$PartiesTableTableFilterComposer get partyId {
    final $$PartiesTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.partyId,
        referencedTable: $state.db.partiesTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$PartiesTableTableFilterComposer(ComposerState($state.db,
                $state.db.partiesTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$JournalEntriesTableTableFilterComposer get writeOffEntryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.writeOffEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  ComposableFilter recurringRulesTableRefs(
      ComposableFilter Function($$RecurringRulesTableTableFilterComposer f) f) {
    final $$RecurringRulesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.recurringRulesTable,
            getReferencedColumn: (t) => t.linkedDebtId,
            builder: (joinBuilder, parentComposers) =>
                $$RecurringRulesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.recurringRulesTable,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter financialCommitmentsRefs(
      ComposableFilter Function($$FinancialCommitmentsTableFilterComposer f)
          f) {
    final $$FinancialCommitmentsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.linkedDebtId,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }

  ComposableFilter settlementAllocationsTableRefs(
      ComposableFilter Function(
              $$SettlementAllocationsTableTableFilterComposer f)
          f) {
    final $$SettlementAllocationsTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.settlementAllocationsTable,
            getReferencedColumn: (t) => t.debtId,
            builder: (joinBuilder, parentComposers) =>
                $$SettlementAllocationsTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.settlementAllocationsTable,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }
}

class $$DebtsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $DebtsTableTable> {
  $$DebtsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get debtType => $state.composableBuilder(
      column: $state.table.debtType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get principalCents => $state.composableBuilder(
      column: $state.table.principalCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get outstandingCents => $state.composableBuilder(
      column: $state.table.outstandingCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableOrderingComposer get originEntryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.originEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$PartiesTableTableOrderingComposer get partyId {
    final $$PartiesTableTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.partyId,
        referencedTable: $state.db.partiesTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$PartiesTableTableOrderingComposer(ComposerState($state.db,
                $state.db.partiesTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$JournalEntriesTableTableOrderingComposer get writeOffEntryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.writeOffEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$RecurringRulesTableTableCreateCompanionBuilder
    = RecurringRulesTableCompanion Function({
  required String id,
  required String title,
  required String ruleType,
  required int amountCents,
  required String frequency,
  Value<int> interval,
  required String startDate,
  required String nextOccurrenceDate,
  Value<String?> endDate,
  Value<String?> accountId,
  Value<String?> destinationAccountId,
  Value<String?> categoryId,
  Value<String?> linkedDebtId,
  Value<bool> isActive,
  Value<bool> autoPost,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$RecurringRulesTableTableUpdateCompanionBuilder
    = RecurringRulesTableCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> ruleType,
  Value<int> amountCents,
  Value<String> frequency,
  Value<int> interval,
  Value<String> startDate,
  Value<String> nextOccurrenceDate,
  Value<String?> endDate,
  Value<String?> accountId,
  Value<String?> destinationAccountId,
  Value<String?> categoryId,
  Value<String?> linkedDebtId,
  Value<bool> isActive,
  Value<bool> autoPost,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$RecurringRulesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RecurringRulesTableTable,
    RecurringRulesTableData,
    $$RecurringRulesTableTableFilterComposer,
    $$RecurringRulesTableTableOrderingComposer,
    $$RecurringRulesTableTableCreateCompanionBuilder,
    $$RecurringRulesTableTableUpdateCompanionBuilder> {
  $$RecurringRulesTableTableTableManager(
      _$AppDatabase db, $RecurringRulesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$RecurringRulesTableTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$RecurringRulesTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> ruleType = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<String> frequency = const Value.absent(),
            Value<int> interval = const Value.absent(),
            Value<String> startDate = const Value.absent(),
            Value<String> nextOccurrenceDate = const Value.absent(),
            Value<String?> endDate = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String?> destinationAccountId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> linkedDebtId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> autoPost = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecurringRulesTableCompanion(
            id: id,
            title: title,
            ruleType: ruleType,
            amountCents: amountCents,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            nextOccurrenceDate: nextOccurrenceDate,
            endDate: endDate,
            accountId: accountId,
            destinationAccountId: destinationAccountId,
            categoryId: categoryId,
            linkedDebtId: linkedDebtId,
            isActive: isActive,
            autoPost: autoPost,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required String ruleType,
            required int amountCents,
            required String frequency,
            Value<int> interval = const Value.absent(),
            required String startDate,
            required String nextOccurrenceDate,
            Value<String?> endDate = const Value.absent(),
            Value<String?> accountId = const Value.absent(),
            Value<String?> destinationAccountId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> linkedDebtId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> autoPost = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              RecurringRulesTableCompanion.insert(
            id: id,
            title: title,
            ruleType: ruleType,
            amountCents: amountCents,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            nextOccurrenceDate: nextOccurrenceDate,
            endDate: endDate,
            accountId: accountId,
            destinationAccountId: destinationAccountId,
            categoryId: categoryId,
            linkedDebtId: linkedDebtId,
            isActive: isActive,
            autoPost: autoPost,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$RecurringRulesTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $RecurringRulesTableTable> {
  $$RecurringRulesTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get ruleType => $state.composableBuilder(
      column: $state.table.ruleType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get frequency => $state.composableBuilder(
      column: $state.table.frequency,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get interval => $state.composableBuilder(
      column: $state.table.interval,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get startDate => $state.composableBuilder(
      column: $state.table.startDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get nextOccurrenceDate => $state.composableBuilder(
      column: $state.table.nextOccurrenceDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get endDate => $state.composableBuilder(
      column: $state.table.endDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isActive => $state.composableBuilder(
      column: $state.table.isActive,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get autoPost => $state.composableBuilder(
      column: $state.table.autoPost,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$AccountsTableTableFilterComposer get accountId {
    final $$AccountsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $state.db.accountsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$AccountsTableTableFilterComposer(ComposerState($state.db,
                $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$AccountsTableTableFilterComposer get destinationAccountId {
    final $$AccountsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.destinationAccountId,
        referencedTable: $state.db.accountsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$AccountsTableTableFilterComposer(ComposerState($state.db,
                $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$FinancialCategoriesTableFilterComposer get categoryId {
    final $$FinancialCategoriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$DebtsTableTableFilterComposer get linkedDebtId {
    final $$DebtsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedDebtId,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableFilterComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter financialCommitmentsRefs(
      ComposableFilter Function($$FinancialCommitmentsTableFilterComposer f)
          f) {
    final $$FinancialCommitmentsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.recurringRuleId,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }
}

class $$RecurringRulesTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $RecurringRulesTableTable> {
  $$RecurringRulesTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get ruleType => $state.composableBuilder(
      column: $state.table.ruleType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get frequency => $state.composableBuilder(
      column: $state.table.frequency,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get interval => $state.composableBuilder(
      column: $state.table.interval,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get startDate => $state.composableBuilder(
      column: $state.table.startDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get nextOccurrenceDate => $state.composableBuilder(
      column: $state.table.nextOccurrenceDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get endDate => $state.composableBuilder(
      column: $state.table.endDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isActive => $state.composableBuilder(
      column: $state.table.isActive,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get autoPost => $state.composableBuilder(
      column: $state.table.autoPost,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$AccountsTableTableOrderingComposer get accountId {
    final $$AccountsTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.accountId,
            referencedTable: $state.db.accountsTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$AccountsTableTableOrderingComposer(ComposerState($state.db,
                    $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$AccountsTableTableOrderingComposer get destinationAccountId {
    final $$AccountsTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.destinationAccountId,
            referencedTable: $state.db.accountsTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$AccountsTableTableOrderingComposer(ComposerState($state.db,
                    $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$FinancialCategoriesTableOrderingComposer get categoryId {
    final $$FinancialCategoriesTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$DebtsTableTableOrderingComposer get linkedDebtId {
    final $$DebtsTableTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedDebtId,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableOrderingComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$FinancialCommitmentsTableCreateCompanionBuilder
    = FinancialCommitmentsCompanion Function({
  required String id,
  required String title,
  required int amountCents,
  required String dueDate,
  Value<bool> isPaid,
  Value<String> direction,
  Value<bool> legacyPaidUnverified,
  Value<String?> recurringRule,
  Value<String?> linkedAccountId,
  Value<String?> categoryId,
  Value<String?> linkedDebtId,
  Value<String?> settlementEntryId,
  Value<String?> recurringRuleId,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$FinancialCommitmentsTableUpdateCompanionBuilder
    = FinancialCommitmentsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<int> amountCents,
  Value<String> dueDate,
  Value<bool> isPaid,
  Value<String> direction,
  Value<bool> legacyPaidUnverified,
  Value<String?> recurringRule,
  Value<String?> linkedAccountId,
  Value<String?> categoryId,
  Value<String?> linkedDebtId,
  Value<String?> settlementEntryId,
  Value<String?> recurringRuleId,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$FinancialCommitmentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FinancialCommitmentsTable,
    FinancialCommitment,
    $$FinancialCommitmentsTableFilterComposer,
    $$FinancialCommitmentsTableOrderingComposer,
    $$FinancialCommitmentsTableCreateCompanionBuilder,
    $$FinancialCommitmentsTableUpdateCompanionBuilder> {
  $$FinancialCommitmentsTableTableManager(
      _$AppDatabase db, $FinancialCommitmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$FinancialCommitmentsTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$FinancialCommitmentsTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<String> dueDate = const Value.absent(),
            Value<bool> isPaid = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<bool> legacyPaidUnverified = const Value.absent(),
            Value<String?> recurringRule = const Value.absent(),
            Value<String?> linkedAccountId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> linkedDebtId = const Value.absent(),
            Value<String?> settlementEntryId = const Value.absent(),
            Value<String?> recurringRuleId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FinancialCommitmentsCompanion(
            id: id,
            title: title,
            amountCents: amountCents,
            dueDate: dueDate,
            isPaid: isPaid,
            direction: direction,
            legacyPaidUnverified: legacyPaidUnverified,
            recurringRule: recurringRule,
            linkedAccountId: linkedAccountId,
            categoryId: categoryId,
            linkedDebtId: linkedDebtId,
            settlementEntryId: settlementEntryId,
            recurringRuleId: recurringRuleId,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required int amountCents,
            required String dueDate,
            Value<bool> isPaid = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<bool> legacyPaidUnverified = const Value.absent(),
            Value<String?> recurringRule = const Value.absent(),
            Value<String?> linkedAccountId = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> linkedDebtId = const Value.absent(),
            Value<String?> settlementEntryId = const Value.absent(),
            Value<String?> recurringRuleId = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FinancialCommitmentsCompanion.insert(
            id: id,
            title: title,
            amountCents: amountCents,
            dueDate: dueDate,
            isPaid: isPaid,
            direction: direction,
            legacyPaidUnverified: legacyPaidUnverified,
            recurringRule: recurringRule,
            linkedAccountId: linkedAccountId,
            categoryId: categoryId,
            linkedDebtId: linkedDebtId,
            settlementEntryId: settlementEntryId,
            recurringRuleId: recurringRuleId,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$FinancialCommitmentsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $FinancialCommitmentsTable> {
  $$FinancialCommitmentsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isPaid => $state.composableBuilder(
      column: $state.table.isPaid,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get direction => $state.composableBuilder(
      column: $state.table.direction,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get legacyPaidUnverified => $state.composableBuilder(
      column: $state.table.legacyPaidUnverified,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get recurringRule => $state.composableBuilder(
      column: $state.table.recurringRule,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$AccountsTableTableFilterComposer get linkedAccountId {
    final $$AccountsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedAccountId,
        referencedTable: $state.db.accountsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$AccountsTableTableFilterComposer(ComposerState($state.db,
                $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$FinancialCategoriesTableFilterComposer get categoryId {
    final $$FinancialCategoriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$DebtsTableTableFilterComposer get linkedDebtId {
    final $$DebtsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedDebtId,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableFilterComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$JournalEntriesTableTableFilterComposer get settlementEntryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.settlementEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$RecurringRulesTableTableFilterComposer get recurringRuleId {
    final $$RecurringRulesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.recurringRuleId,
            referencedTable: $state.db.recurringRulesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$RecurringRulesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.recurringRulesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  ComposableFilter commitmentSettlementsTableRefs(
      ComposableFilter Function(
              $$CommitmentSettlementsTableTableFilterComposer f)
          f) {
    final $$CommitmentSettlementsTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $state.db.commitmentSettlementsTable,
            getReferencedColumn: (t) => t.commitmentId,
            builder: (joinBuilder, parentComposers) =>
                $$CommitmentSettlementsTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.commitmentSettlementsTable,
                    joinBuilder,
                    parentComposers)));
    return f(composer);
  }
}

class $$FinancialCommitmentsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $FinancialCommitmentsTable> {
  $$FinancialCommitmentsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get dueDate => $state.composableBuilder(
      column: $state.table.dueDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isPaid => $state.composableBuilder(
      column: $state.table.isPaid,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get direction => $state.composableBuilder(
      column: $state.table.direction,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get legacyPaidUnverified => $state.composableBuilder(
      column: $state.table.legacyPaidUnverified,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get recurringRule => $state.composableBuilder(
      column: $state.table.recurringRule,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$AccountsTableTableOrderingComposer get linkedAccountId {
    final $$AccountsTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.linkedAccountId,
            referencedTable: $state.db.accountsTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$AccountsTableTableOrderingComposer(ComposerState($state.db,
                    $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$FinancialCategoriesTableOrderingComposer get categoryId {
    final $$FinancialCategoriesTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$DebtsTableTableOrderingComposer get linkedDebtId {
    final $$DebtsTableTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedDebtId,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableOrderingComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$JournalEntriesTableTableOrderingComposer get settlementEntryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.settlementEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$RecurringRulesTableTableOrderingComposer get recurringRuleId {
    final $$RecurringRulesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.recurringRuleId,
            referencedTable: $state.db.recurringRulesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$RecurringRulesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.recurringRulesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$CommitmentSettlementsTableTableCreateCompanionBuilder
    = CommitmentSettlementsTableCompanion Function({
  required String id,
  required String commitmentId,
  required String entryId,
  required int amountCents,
  required String settledDate,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$CommitmentSettlementsTableTableUpdateCompanionBuilder
    = CommitmentSettlementsTableCompanion Function({
  Value<String> id,
  Value<String> commitmentId,
  Value<String> entryId,
  Value<int> amountCents,
  Value<String> settledDate,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$CommitmentSettlementsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CommitmentSettlementsTableTable,
    CommitmentSettlementsTableData,
    $$CommitmentSettlementsTableTableFilterComposer,
    $$CommitmentSettlementsTableTableOrderingComposer,
    $$CommitmentSettlementsTableTableCreateCompanionBuilder,
    $$CommitmentSettlementsTableTableUpdateCompanionBuilder> {
  $$CommitmentSettlementsTableTableTableManager(
      _$AppDatabase db, $CommitmentSettlementsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$CommitmentSettlementsTableTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$CommitmentSettlementsTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> commitmentId = const Value.absent(),
            Value<String> entryId = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<String> settledDate = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CommitmentSettlementsTableCompanion(
            id: id,
            commitmentId: commitmentId,
            entryId: entryId,
            amountCents: amountCents,
            settledDate: settledDate,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String commitmentId,
            required String entryId,
            required int amountCents,
            required String settledDate,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              CommitmentSettlementsTableCompanion.insert(
            id: id,
            commitmentId: commitmentId,
            entryId: entryId,
            amountCents: amountCents,
            settledDate: settledDate,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$CommitmentSettlementsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $CommitmentSettlementsTableTable> {
  $$CommitmentSettlementsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get settledDate => $state.composableBuilder(
      column: $state.table.settledDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$FinancialCommitmentsTableFilterComposer get commitmentId {
    final $$FinancialCommitmentsTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.commitmentId,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$JournalEntriesTableTableFilterComposer get entryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.entryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

class $$CommitmentSettlementsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $CommitmentSettlementsTableTable> {
  $$CommitmentSettlementsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get settledDate => $state.composableBuilder(
      column: $state.table.settledDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$FinancialCommitmentsTableOrderingComposer get commitmentId {
    final $$FinancialCommitmentsTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.commitmentId,
            referencedTable: $state.db.financialCommitments,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCommitmentsTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCommitments,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$JournalEntriesTableTableOrderingComposer get entryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.entryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$SavingsGoalsTableCreateCompanionBuilder = SavingsGoalsCompanion
    Function({
  required String id,
  required String title,
  required int targetCents,
  Value<int> currentAllocatedCents,
  Value<String?> targetDate,
  Value<String?> linkedAccountId,
  Value<String> status,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$SavingsGoalsTableUpdateCompanionBuilder = SavingsGoalsCompanion
    Function({
  Value<String> id,
  Value<String> title,
  Value<int> targetCents,
  Value<int> currentAllocatedCents,
  Value<String?> targetDate,
  Value<String?> linkedAccountId,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$SavingsGoalsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SavingsGoalsTable,
    SavingsGoal,
    $$SavingsGoalsTableFilterComposer,
    $$SavingsGoalsTableOrderingComposer,
    $$SavingsGoalsTableCreateCompanionBuilder,
    $$SavingsGoalsTableUpdateCompanionBuilder> {
  $$SavingsGoalsTableTableManager(_$AppDatabase db, $SavingsGoalsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$SavingsGoalsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$SavingsGoalsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> targetCents = const Value.absent(),
            Value<int> currentAllocatedCents = const Value.absent(),
            Value<String?> targetDate = const Value.absent(),
            Value<String?> linkedAccountId = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SavingsGoalsCompanion(
            id: id,
            title: title,
            targetCents: targetCents,
            currentAllocatedCents: currentAllocatedCents,
            targetDate: targetDate,
            linkedAccountId: linkedAccountId,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String title,
            required int targetCents,
            Value<int> currentAllocatedCents = const Value.absent(),
            Value<String?> targetDate = const Value.absent(),
            Value<String?> linkedAccountId = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SavingsGoalsCompanion.insert(
            id: id,
            title: title,
            targetCents: targetCents,
            currentAllocatedCents: currentAllocatedCents,
            targetDate: targetDate,
            linkedAccountId: linkedAccountId,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$SavingsGoalsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $SavingsGoalsTable> {
  $$SavingsGoalsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get targetCents => $state.composableBuilder(
      column: $state.table.targetCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get currentAllocatedCents => $state.composableBuilder(
      column: $state.table.currentAllocatedCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get targetDate => $state.composableBuilder(
      column: $state.table.targetDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$AccountsTableTableFilterComposer get linkedAccountId {
    final $$AccountsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedAccountId,
        referencedTable: $state.db.accountsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$AccountsTableTableFilterComposer(ComposerState($state.db,
                $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$SavingsGoalsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $SavingsGoalsTable> {
  $$SavingsGoalsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get targetCents => $state.composableBuilder(
      column: $state.table.targetCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get currentAllocatedCents => $state.composableBuilder(
      column: $state.table.currentAllocatedCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get targetDate => $state.composableBuilder(
      column: $state.table.targetDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get status => $state.composableBuilder(
      column: $state.table.status,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$AccountsTableTableOrderingComposer get linkedAccountId {
    final $$AccountsTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.linkedAccountId,
            referencedTable: $state.db.accountsTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$AccountsTableTableOrderingComposer(ComposerState($state.db,
                    $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$RemindersTableCreateCompanionBuilder = RemindersCompanion Function({
  required String id,
  required String targetId,
  required String targetType,
  Value<String?> title,
  Value<String?> channelId,
  required DateTime triggerTimeUtc,
  Value<bool> isActive,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$RemindersTableUpdateCompanionBuilder = RemindersCompanion Function({
  Value<String> id,
  Value<String> targetId,
  Value<String> targetType,
  Value<String?> title,
  Value<String?> channelId,
  Value<DateTime> triggerTimeUtc,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$RemindersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RemindersTable,
    Reminder,
    $$RemindersTableFilterComposer,
    $$RemindersTableOrderingComposer,
    $$RemindersTableCreateCompanionBuilder,
    $$RemindersTableUpdateCompanionBuilder> {
  $$RemindersTableTableManager(_$AppDatabase db, $RemindersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$RemindersTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$RemindersTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> targetId = const Value.absent(),
            Value<String> targetType = const Value.absent(),
            Value<String?> title = const Value.absent(),
            Value<String?> channelId = const Value.absent(),
            Value<DateTime> triggerTimeUtc = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RemindersCompanion(
            id: id,
            targetId: targetId,
            targetType: targetType,
            title: title,
            channelId: channelId,
            triggerTimeUtc: triggerTimeUtc,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String targetId,
            required String targetType,
            Value<String?> title = const Value.absent(),
            Value<String?> channelId = const Value.absent(),
            required DateTime triggerTimeUtc,
            Value<bool> isActive = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              RemindersCompanion.insert(
            id: id,
            targetId: targetId,
            targetType: targetType,
            title: title,
            channelId: channelId,
            triggerTimeUtc: triggerTimeUtc,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$RemindersTableFilterComposer
    extends FilterComposer<_$AppDatabase, $RemindersTable> {
  $$RemindersTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get targetId => $state.composableBuilder(
      column: $state.table.targetId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get targetType => $state.composableBuilder(
      column: $state.table.targetType,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get channelId => $state.composableBuilder(
      column: $state.table.channelId,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get triggerTimeUtc => $state.composableBuilder(
      column: $state.table.triggerTimeUtc,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isActive => $state.composableBuilder(
      column: $state.table.isActive,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$RemindersTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $RemindersTable> {
  $$RemindersTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get targetId => $state.composableBuilder(
      column: $state.table.targetId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get targetType => $state.composableBuilder(
      column: $state.table.targetType,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get title => $state.composableBuilder(
      column: $state.table.title,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get channelId => $state.composableBuilder(
      column: $state.table.channelId,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get triggerTimeUtc => $state.composableBuilder(
      column: $state.table.triggerTimeUtc,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isActive => $state.composableBuilder(
      column: $state.table.isActive,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  required String key,
  required String value,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$AppSettingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder> {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$AppSettingsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$AppSettingsTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$AppSettingsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer(super.$state);
  ColumnFilters<String> get key => $state.composableBuilder(
      column: $state.table.key,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get value => $state.composableBuilder(
      column: $state.table.value,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$AppSettingsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get key => $state.composableBuilder(
      column: $state.table.key,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get value => $state.composableBuilder(
      column: $state.table.value,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$PostingsTableTableCreateCompanionBuilder = PostingsTableCompanion
    Function({
  required String id,
  required String entryId,
  required String accountId,
  required int amountCents,
  required String direction,
  required String accountMovementDate,
  Value<String?> categoryId,
  Value<String?> note,
  Value<int> rowid,
});
typedef $$PostingsTableTableUpdateCompanionBuilder = PostingsTableCompanion
    Function({
  Value<String> id,
  Value<String> entryId,
  Value<String> accountId,
  Value<int> amountCents,
  Value<String> direction,
  Value<String> accountMovementDate,
  Value<String?> categoryId,
  Value<String?> note,
  Value<int> rowid,
});

class $$PostingsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PostingsTableTable,
    PostingsTableData,
    $$PostingsTableTableFilterComposer,
    $$PostingsTableTableOrderingComposer,
    $$PostingsTableTableCreateCompanionBuilder,
    $$PostingsTableTableUpdateCompanionBuilder> {
  $$PostingsTableTableTableManager(_$AppDatabase db, $PostingsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$PostingsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$PostingsTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> entryId = const Value.absent(),
            Value<String> accountId = const Value.absent(),
            Value<int> amountCents = const Value.absent(),
            Value<String> direction = const Value.absent(),
            Value<String> accountMovementDate = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PostingsTableCompanion(
            id: id,
            entryId: entryId,
            accountId: accountId,
            amountCents: amountCents,
            direction: direction,
            accountMovementDate: accountMovementDate,
            categoryId: categoryId,
            note: note,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String entryId,
            required String accountId,
            required int amountCents,
            required String direction,
            required String accountMovementDate,
            Value<String?> categoryId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PostingsTableCompanion.insert(
            id: id,
            entryId: entryId,
            accountId: accountId,
            amountCents: amountCents,
            direction: direction,
            accountMovementDate: accountMovementDate,
            categoryId: categoryId,
            note: note,
            rowid: rowid,
          ),
        ));
}

class $$PostingsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $PostingsTableTable> {
  $$PostingsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get direction => $state.composableBuilder(
      column: $state.table.direction,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get accountMovementDate => $state.composableBuilder(
      column: $state.table.accountMovementDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get note => $state.composableBuilder(
      column: $state.table.note,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableFilterComposer get entryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.entryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$AccountsTableTableFilterComposer get accountId {
    final $$AccountsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.accountId,
        referencedTable: $state.db.accountsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$AccountsTableTableFilterComposer(ComposerState($state.db,
                $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$FinancialCategoriesTableFilterComposer get categoryId {
    final $$FinancialCategoriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

class $$PostingsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $PostingsTableTable> {
  $$PostingsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get amountCents => $state.composableBuilder(
      column: $state.table.amountCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get direction => $state.composableBuilder(
      column: $state.table.direction,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get accountMovementDate => $state.composableBuilder(
      column: $state.table.accountMovementDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get note => $state.composableBuilder(
      column: $state.table.note,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableOrderingComposer get entryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.entryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$AccountsTableTableOrderingComposer get accountId {
    final $$AccountsTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.accountId,
            referencedTable: $state.db.accountsTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$AccountsTableTableOrderingComposer(ComposerState($state.db,
                    $state.db.accountsTable, joinBuilder, parentComposers)));
    return composer;
  }

  $$FinancialCategoriesTableOrderingComposer get categoryId {
    final $$FinancialCategoriesTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

typedef $$SettlementAllocationsTableTableCreateCompanionBuilder
    = SettlementAllocationsTableCompanion Function({
  required String id,
  required String settlementEntryId,
  required String debtId,
  required int allocatedCents,
  required String settlementDate,
  Value<int> rowid,
});
typedef $$SettlementAllocationsTableTableUpdateCompanionBuilder
    = SettlementAllocationsTableCompanion Function({
  Value<String> id,
  Value<String> settlementEntryId,
  Value<String> debtId,
  Value<int> allocatedCents,
  Value<String> settlementDate,
  Value<int> rowid,
});

class $$SettlementAllocationsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SettlementAllocationsTableTable,
    SettlementAllocationsTableData,
    $$SettlementAllocationsTableTableFilterComposer,
    $$SettlementAllocationsTableTableOrderingComposer,
    $$SettlementAllocationsTableTableCreateCompanionBuilder,
    $$SettlementAllocationsTableTableUpdateCompanionBuilder> {
  $$SettlementAllocationsTableTableTableManager(
      _$AppDatabase db, $SettlementAllocationsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer: $$SettlementAllocationsTableTableFilterComposer(
              ComposerState(db, table)),
          orderingComposer: $$SettlementAllocationsTableTableOrderingComposer(
              ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> settlementEntryId = const Value.absent(),
            Value<String> debtId = const Value.absent(),
            Value<int> allocatedCents = const Value.absent(),
            Value<String> settlementDate = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SettlementAllocationsTableCompanion(
            id: id,
            settlementEntryId: settlementEntryId,
            debtId: debtId,
            allocatedCents: allocatedCents,
            settlementDate: settlementDate,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String settlementEntryId,
            required String debtId,
            required int allocatedCents,
            required String settlementDate,
            Value<int> rowid = const Value.absent(),
          }) =>
              SettlementAllocationsTableCompanion.insert(
            id: id,
            settlementEntryId: settlementEntryId,
            debtId: debtId,
            allocatedCents: allocatedCents,
            settlementDate: settlementDate,
            rowid: rowid,
          ),
        ));
}

class $$SettlementAllocationsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $SettlementAllocationsTableTable> {
  $$SettlementAllocationsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get allocatedCents => $state.composableBuilder(
      column: $state.table.allocatedCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get settlementDate => $state.composableBuilder(
      column: $state.table.settlementDate,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableFilterComposer get settlementEntryId {
    final $$JournalEntriesTableTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.settlementEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$DebtsTableTableFilterComposer get debtId {
    final $$DebtsTableTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.debtId,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableFilterComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$SettlementAllocationsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $SettlementAllocationsTableTable> {
  $$SettlementAllocationsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get allocatedCents => $state.composableBuilder(
      column: $state.table.allocatedCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get settlementDate => $state.composableBuilder(
      column: $state.table.settlementDate,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$JournalEntriesTableTableOrderingComposer get settlementEntryId {
    final $$JournalEntriesTableTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.settlementEntryId,
            referencedTable: $state.db.journalEntriesTable,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$JournalEntriesTableTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.journalEntriesTable,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }

  $$DebtsTableTableOrderingComposer get debtId {
    final $$DebtsTableTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.debtId,
        referencedTable: $state.db.debtsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$DebtsTableTableOrderingComposer(ComposerState($state.db,
                $state.db.debtsTable, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$BudgetsTableTableCreateCompanionBuilder = BudgetsTableCompanion
    Function({
  required String id,
  required String categoryId,
  required String monthIso,
  required int limitCents,
  Value<bool> rolloverEnabled,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$BudgetsTableTableUpdateCompanionBuilder = BudgetsTableCompanion
    Function({
  Value<String> id,
  Value<String> categoryId,
  Value<String> monthIso,
  Value<int> limitCents,
  Value<bool> rolloverEnabled,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$BudgetsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BudgetsTableTable,
    BudgetsTableData,
    $$BudgetsTableTableFilterComposer,
    $$BudgetsTableTableOrderingComposer,
    $$BudgetsTableTableCreateCompanionBuilder,
    $$BudgetsTableTableUpdateCompanionBuilder> {
  $$BudgetsTableTableTableManager(_$AppDatabase db, $BudgetsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$BudgetsTableTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$BudgetsTableTableOrderingComposer(ComposerState(db, table)),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> categoryId = const Value.absent(),
            Value<String> monthIso = const Value.absent(),
            Value<int> limitCents = const Value.absent(),
            Value<bool> rolloverEnabled = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BudgetsTableCompanion(
            id: id,
            categoryId: categoryId,
            monthIso: monthIso,
            limitCents: limitCents,
            rolloverEnabled: rolloverEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String categoryId,
            required String monthIso,
            required int limitCents,
            Value<bool> rolloverEnabled = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BudgetsTableCompanion.insert(
            id: id,
            categoryId: categoryId,
            monthIso: monthIso,
            limitCents: limitCents,
            rolloverEnabled: rolloverEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$BudgetsTableTableFilterComposer
    extends FilterComposer<_$AppDatabase, $BudgetsTableTable> {
  $$BudgetsTableTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get monthIso => $state.composableBuilder(
      column: $state.table.monthIso,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get limitCents => $state.composableBuilder(
      column: $state.table.limitCents,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get rolloverEnabled => $state.composableBuilder(
      column: $state.table.rolloverEnabled,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$FinancialCategoriesTableFilterComposer get categoryId {
    final $$FinancialCategoriesTableFilterComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableFilterComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

class $$BudgetsTableTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $BudgetsTableTable> {
  $$BudgetsTableTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get monthIso => $state.composableBuilder(
      column: $state.table.monthIso,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get limitCents => $state.composableBuilder(
      column: $state.table.limitCents,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get rolloverEnabled => $state.composableBuilder(
      column: $state.table.rolloverEnabled,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$FinancialCategoriesTableOrderingComposer get categoryId {
    final $$FinancialCategoriesTableOrderingComposer composer =
        $state.composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.categoryId,
            referencedTable: $state.db.financialCategories,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder, parentComposers) =>
                $$FinancialCategoriesTableOrderingComposer(ComposerState(
                    $state.db,
                    $state.db.financialCategories,
                    joinBuilder,
                    parentComposers)));
    return composer;
  }
}

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$InboxItemsTableTableManager get inboxItems =>
      $$InboxItemsTableTableManager(_db, _db.inboxItems);
  $$GoalsTableTableManager get goals =>
      $$GoalsTableTableManager(_db, _db.goals);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$MilestonesTableTableManager get milestones =>
      $$MilestonesTableTableManager(_db, _db.milestones);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$CalendarEventsTableTableManager get calendarEvents =>
      $$CalendarEventsTableTableManager(_db, _db.calendarEvents);
  $$FinancialCategoriesTableTableManager get financialCategories =>
      $$FinancialCategoriesTableTableManager(_db, _db.financialCategories);
  $$FinancialTransactionsTableTableManager get financialTransactions =>
      $$FinancialTransactionsTableTableManager(_db, _db.financialTransactions);
  $$AccountsTableTableTableManager get accountsTable =>
      $$AccountsTableTableTableManager(_db, _db.accountsTable);
  $$JournalEntriesTableTableTableManager get journalEntriesTable =>
      $$JournalEntriesTableTableTableManager(_db, _db.journalEntriesTable);
  $$PartiesTableTableTableManager get partiesTable =>
      $$PartiesTableTableTableManager(_db, _db.partiesTable);
  $$DebtsTableTableTableManager get debtsTable =>
      $$DebtsTableTableTableManager(_db, _db.debtsTable);
  $$RecurringRulesTableTableTableManager get recurringRulesTable =>
      $$RecurringRulesTableTableTableManager(_db, _db.recurringRulesTable);
  $$FinancialCommitmentsTableTableManager get financialCommitments =>
      $$FinancialCommitmentsTableTableManager(_db, _db.financialCommitments);
  $$CommitmentSettlementsTableTableTableManager
      get commitmentSettlementsTable =>
          $$CommitmentSettlementsTableTableTableManager(
              _db, _db.commitmentSettlementsTable);
  $$SavingsGoalsTableTableManager get savingsGoals =>
      $$SavingsGoalsTableTableManager(_db, _db.savingsGoals);
  $$RemindersTableTableManager get reminders =>
      $$RemindersTableTableManager(_db, _db.reminders);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$PostingsTableTableTableManager get postingsTable =>
      $$PostingsTableTableTableManager(_db, _db.postingsTable);
  $$SettlementAllocationsTableTableTableManager
      get settlementAllocationsTable =>
          $$SettlementAllocationsTableTableTableManager(
              _db, _db.settlementAllocationsTable);
  $$BudgetsTableTableTableManager get budgetsTable =>
      $$BudgetsTableTableTableManager(_db, _db.budgetsTable);
}

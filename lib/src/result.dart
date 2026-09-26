enum Status { pass, warn, fail, skip }

class Finding {
  final Status status;
  final String message;

  /// Where, and what to do about it. One entry per printed line.
  final List<String> details;

  Finding(this.status, this.message, [this.details = const []]);

  Map<String, Object?> toJson() => {
        'status': status.name,
        'message': message,
        if (details.isNotEmpty) 'details': details,
      };
}

class CheckResult {
  final String id;
  final String guideline;
  final String title;
  final List<Finding> findings;

  /// Things only a person with a device can confirm.
  final List<String> manual;

  CheckResult(this.id, this.guideline, this.title, this.findings,
      [this.manual = const []]);

  Status get status {
    if (findings.any((f) => f.status == Status.fail)) return Status.fail;
    if (findings.any((f) => f.status == Status.warn)) return Status.warn;
    if (findings.isNotEmpty && findings.every((f) => f.status == Status.skip)) {
      return Status.skip;
    }
    return Status.pass;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'guideline': guideline,
        'title': title,
        'status': status.name,
        'findings': findings.map((f) => f.toJson()).toList(),
      };
}

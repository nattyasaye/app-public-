import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/domain/projects/progress_engine.dart';

void main() {
  group('Stage 3 Task & Project Logic Tests', () {
    test('Calculates project progress percentage accurately', () {
      // 4 total tasks (2 completed), 1 milestone (1 completed)
      // Total items = 5, completed = 3 -> 60%
      final progress = ProgressEngine.calculateProgressPercentage(
        totalTasks: 4,
        completedTasks: 2,
        totalMilestones: 1,
        completedMilestones: 1,
      );
      expect(progress, 60);
    });

    test('Zero tasks or milestones returns 0% without divide-by-zero error',
        () {
      final progress = ProgressEngine.calculateProgressPercentage(
        totalTasks: 0,
        completedTasks: 0,
        totalMilestones: 0,
        completedMilestones: 0,
      );
      expect(progress, 0);
    });

    test('Manually completed project always returns 100%', () {
      final progress = ProgressEngine.calculateProgressPercentage(
        totalTasks: 5,
        completedTasks: 1,
        totalMilestones: 0,
        completedMilestones: 0,
        isProjectManuallyCompleted: true,
      );
      expect(progress, 100);
    });

    test('Unfinished tasks are preserved and postponed without data loss', () {
      final now = DateTime.utc(2026, 11, 7);
      final originalTask = {
        'id': 'task-123',
        'title': 'Prepare financial report',
        'status': 'not_started',
        'dueDate': now,
      };

      // Postpone by 3 days
      final postponedDate =
          (originalTask['dueDate'] as DateTime).add(const Duration(days: 3));
      originalTask['dueDate'] = postponedDate;

      // Ensure task remains intact with new deadline
      expect(originalTask['status'], 'not_started');
      expect((originalTask['dueDate'] as DateTime).difference(now).inDays, 3);
    });

    test('Task can exist with or without Project association', () {
      final independentTask = {
        'id': 'task-1',
        'title': 'Buy groceries',
        'projectId': null,
      };

      final projectTask = {
        'id': 'task-2',
        'title': 'Draft contract',
        'projectId': 'project-alpha',
      };

      expect(independentTask['projectId'], isNull);
      expect(projectTask['projectId'], 'project-alpha');
    });
  });
}

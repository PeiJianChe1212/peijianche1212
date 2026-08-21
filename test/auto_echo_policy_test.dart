import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/ai_character.dart';
import 'package:peijianche_app/models/echo_daily_life.dart';
import 'package:peijianche_app/services/auto_echo_policy.dart';
import 'package:peijianche_app/services/echo_daily_life_service.dart';

void main() {
  const policy = AutoEchoPolicy();

  test('daily guarantee is never later than three days', () {
    final last = DateTime(2026, 8, 1, 10);
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      expect(policy.guaranteeDays(id, last), inInclusiveRange(1, 3));
      expect(
        policy.isDailyDue(
          characterId: id,
          now: last.add(const Duration(days: 3)),
          lastPublishedAt: last,
        ),
        isTrue,
      );
    }
  });

  test('frequent chat raises active share chance', () {
    expect(
      policy.activeShareChance(100),
      greaterThan(policy.activeShareChance(0)),
    );
    expect(
      policy.activeShareChance(40),
      greaterThan(policy.activeShareChance(10)),
    );
  });

  test('new character gets an arrival Echo from API-free pool', () {
    final character = AiCharacter(
      id: 'new-character',
      characterName: '新角色',
      remark: '',
      createdAt: DateTime(2026, 8, 2),
    );
    final life = const EchoDailyLifeService().create(
      character: character,
      at: DateTime(2026, 8, 2),
      initial: true,
    );
    expect(life.kind, EchoDailyLifeKind.arrival);
    expect(life.content, isNotEmpty);
  });

  test('different characters receive component-based arrival wording', () {
    final at = DateTime(2026, 8, 21, 20);
    EchoDailyLife life(String id) => const EchoDailyLifeService().create(
      character: AiCharacter(
        id: id,
        characterName: id,
        remark: '',
        createdAt: at,
      ),
      at: at,
      initial: true,
    );
    expect(
      life('arrival-role-a').content,
      isNot(life('arrival-role-b').content),
    );
    expect(life('arrival-role-a').sourceEvent, 'character_arrival');
  });

  test('each character uses its own deterministic daily-life sequence', () {
    final at = DateTime(2026, 8, 2);
    EchoDailyLife life(String id) => const EchoDailyLifeService().create(
      character: AiCharacter(
        id: id,
        characterName: id,
        remark: '',
        createdAt: at,
      ),
      at: at,
    );
    expect(life('role-a').content, isNotEmpty);
    expect(life('role-b').content, isNotEmpty);
  });
}

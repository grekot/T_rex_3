import 'package:flutter_test/flutter_test.dart';
import 'package:wspolne/wspolne.dart';

class _Item extends Shared {
  _Item(this.ownerId, this.members, this.memberEmails);

  @override
  final String id = 'X';
  @override
  final String name = 'Biedronka';
  @override
  final String ownerId;
  @override
  final List<String> members;
  @override
  final Map<String, String> memberEmails;
}

void main() {
  final list = _Item('me', ['me', 'zona'], {'me': 'ja@x.pl', 'zona': 'zona@x.pl'});
  final emails = {'zona': 'zona@x.pl', 'syn': 'syn@x.pl'};

  test('właściciel dopisuje i usuwa', () {
    final c = planSharing(list: list, myUid: 'me', selected: {'syn'}, knownEmails: emails);
    expect(c.add, {'syn': 'syn@x.pl'});
    expect(c.remove, {'zona'});
  });

  test('bez zmian, gdy zaznaczenia = obecni członkowie', () {
    expect(planSharing(list: list, myUid: 'me', selected: {'zona'}, knownEmails: emails).isEmpty, isTrue);
  });

  test('nie-właściciel tylko dopisuje; właściciela i siebie nie usuwa', () {
    final c = planSharing(list: list, myUid: 'zona', selected: {'syn'}, knownEmails: emails);
    expect(c.add.keys, ['syn']);
    expect(c.remove, isEmpty);
  });

  test('isOwner / isShared / ownerEmail', () {
    expect(list.isOwner('me'), isTrue);
    expect(list.isOwner('zona'), isFalse);
    expect(list.isShared, isTrue);
    expect(list.ownerEmail, 'ja@x.pl');
  });

  test('propozycje znajomych: osoby z moich list/miejsc spoza znajomych', () {
    expect(suggestedFriends(lists: [list], myUid: 'zona', friends: const []).map((f) => f.email), ['ja@x.pl']);
    expect(
      suggestedFriends(lists: [list], myUid: 'zona', friends: [const Friend(uid: 'me', email: 'ja@x.pl')]),
      isEmpty,
    );
  });

  test('emailKey i pomocnicze', () {
    expect(emailKey('  Zona@X.PL '), 'zona@x.pl');
    expect(parseMembers(['a', 1, 'b']), ['a', 'b']);
    expect(parseMembers(null), isEmpty);
    expect(parseMemberEmails({'a': 'x@y'}), {'a': 'x@y'});
    expect(parseMemberEmails('zle'), isEmpty);
  });
}

// Copyright (c) 2020, Rudolf Martincsek. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:couchbase_lite_dart/src/native/bindings.dart' as cbl;
import 'package:couchbase_lite_dart/couchbase_lite_dart.dart';

import 'package:test/test.dart';

import '_test_utils.dart';

void main() {
  initializeCblC();

  setUpAll(() {
    if (!Directory('_tmp').existsSync()) {
      Directory('_tmp').createSync();
    }
  });

  tearDownAll(() async {
    await asyncSleep(1000);
    if (Directory('_tmp').existsSync()) {
      await Directory('_tmp').delete(recursive: true);
    }
  });

  test('exists()', () async {
    var db = Database('exists', directory: '_tmp');
    await asyncSleep(1000);
    expect(Database.exists('exists', directory: '_tmp'), true);
    expect(Database.exists('testdb1'), false);
    addTearDown(() => db.close());
  });

  test('Copy()', () {
    expect(Database.Copy('testdb.cblite2/', 'testdb_copy', directory: '_tmp'),
        true);

    expect(
      () => Database.Copy('testdb.cblite2/', 'testdb_copy', directory: '_tmp'),
      throwsException,
    );
  }, skip: 'flaky');

  test('copy()', () {
    var db = Database('copy', directory: '_tmp');
    expect(db.copy('testdb_copy', directory: '_tmp'), true);

    expect(
      () => db.copy('testdb_copy', directory: '_tmp'),
      throwsException,
    );

    addTearDown(() => db.close());
  }, skip: 'flaky');

  test('Delete()', () async {
    var db = Database('delete1_test', directory: '_tmp');
    db.open();
    await asyncSleep(1000);
    db.close();
    Database.DeleteAsync('delete1_test', directory: '_tmp');

    print('here');

    await asyncSleep(2000);

    /*   db.close();
    await asyncSleep(1000);
    expect(
      Database.Delete('delete1_test', directory: '_tmp'),
      !Directory('_tmp/delete1_test.cblite2').existsSync(),
    );
*/
    addTearDown(() => db.close());
  });

  test('open()', () {
    var db = Database('open_test', directory: '_tmp');

    expect(
      db.open(),
      Directory('_tmp/open_test.cblite2').existsSync() && db.isOpen,
    );

    expect(
      db.open(),
      Directory('_tmp/open_test.cblite2').existsSync() && db.isOpen,
    );

    addTearDown(() => db.close());
  });

  test('close()', () {
    var db = Database('close_test', directory: '_tmp');
    db.open();

    expect(db.close(), true);
    expect(db.close(), true);

    addTearDown(() => db.close());
  });

  test('delete()', () {
    var db = Database('delete_test', directory: '_tmp');
    db.open();

    var db1 = Database('delete_test', directory: '_tmp');
    db1.open();

    expect(
      () => db.delete(),
      throwsA(predicate((e) =>
          e is CouchbaseLiteException &&
          e.domain == cbl.CBLDomain &&
          e.code == cbl.CBLErrorBusy)),
    );

    db1.close();

    expect(db.delete(),
        !Directory('test/open_test.cblite2').existsSync() && !db.isOpen);

    addTearDown(() {
      db.close();
      db1.close();
    });
  });

  test('beginBatch()', () {
    var db = Database('beginbatch', directory: '_tmp');
    expect(db.beginBatch(), true);
    addTearDown(() {
      db.endBatch();
      db.close();
    });
  });

  test('endBatch()', () {
    var db = Database('endbatch', directory: '_tmp');
    expect(
      () => db.endBatch(),
      throwsA(predicate((e) =>
          e is CouchbaseLiteException &&
          e.domain == cbl.CBLDomain &&
          e.code == cbl.CBLErrorNotInTransaction)),
    );

    db.beginBatch();

    expect(db.endBatch(), true);

    addTearDown(() => db.close());
  });

  test('count', () {
    var db = Database('count', directory: '_tmp');
    expect(db.count, 0);
    addTearDown(() => db.close());
  });

  test('saveDocument', () {
    var db = Database('savedoc', directory: '_tmp');
    expect(db.saveDocument(Document('testdoc', data: {'foo': 'bar'})), true);

    // TODO test save document with out-of-date revision

    addTearDown(() => db.close());
  });

  test('saveDocumentWithConflictHandler', () {
    var db = Database('savedoc', directory: '_tmp');

    // Conflict resolution not supported with "new" documents.
    expect(
      () => db.saveDocumentWithConflictHandler(
          Document('newdoc'), (_, __) => false),
      throwsA(predicate((e) =>
          e is CouchbaseLiteException &&
          e.domain == cbl.CBLDomain &&
          e.code == cbl.CBLErrorConflict)),
    );

    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));
    {
      final mutDoc = db.getMutableDocument('testdoc');
      mutDoc.properties['foo'] = 'baz';

      // Save new document
      db.saveDocument(Document('testdoc', data: {'foo': 'bar1'}));
      db.saveDocumentWithConflictHandler(mutDoc, (newDoc, oldDoc) {
        expect(newDoc.properties['foo'].asString, 'baz');
        expect(oldDoc.properties['foo'].asString, 'bar1');
        return true;
      });
      expect(db.getDocument('testdoc').properties['foo'].asString, 'baz');
    }

    // Keep old document
    {
      final mutDoc = db.getMutableDocument('testdoc');
      mutDoc.properties['foo'] = 'baz';

      db.saveDocument(Document('testdoc', data: {'foo': 'bar1'}));
      expect(
        () => db.saveDocumentWithConflictHandler(mutDoc, (newDoc, oldDoc) {
          expect(newDoc.properties['foo'].asString, 'baz');
          expect(oldDoc.properties['foo'].asString, 'bar1');
          return false;
        }),
        throwsA(predicate((e) =>
            e is CouchbaseLiteException &&
            e.domain == cbl.CBLDomain &&
            e.code == cbl.CBLErrorConflict)),
      );
      expect(db.getDocument('testdoc').properties['foo'].asString, 'bar1');
    }

    addTearDown(() => db.close());
  });

  test('getDocument', () {
    var db = Database('getdoc', directory: '_tmp');
    expect(db.getDocument('testdoc').isEmpty, true);

    expect(db.saveDocument(Document('testdoc', data: {'foo': 'bar'})), true);

    expect(
      db.getDocument('testdoc'),
      predicate<Document>((doc) => doc.ID == 'testdoc'),
    );
    addTearDown(() => db.close());
  });

  test('getMutableDocument', () {
    var db = Database('getmutabledoc', directory: '_tmp');
    expect(db.getDocument('testdoc').isEmpty, true);

    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));

    expect(
      db.getDocument('testdoc'),
      predicate<Document>((doc) => doc.ID == 'testdoc'),
    );
    addTearDown(() => db.close());
  });

  test('purgeDocument', () {
    var db = Database('purgedoc', directory: '_tmp');
    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));

    expect(db.purgeDocument('testdoc'), true);

    expect(db.getDocument('testdoc').isEmpty, true);

    expect(
      () => db.purgeDocument('testdoc'),
      throwsA(predicate((e) =>
          e is CouchbaseLiteException &&
          e.domain == cbl.CBLDomain &&
          e.code == cbl.CBLErrorNotFound)),
    );
    addTearDown(() => db.close());
  });

  test('setDocumentExpiration', () async {
    var db = Database('setdocexp', directory: '_tmp');
    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));

    expect(
      db.setDocumentExpiration(
        'testdoc',
        DateTime.now().add(Duration(minutes: 10)),
      ),
      true,
    );

    expect(
      db.getDocument('testdoc'),
      predicate<Document>((doc) => doc.ID == 'testdoc'),
    );

    // Check that the document gets deleted from the database after expiring
    expect(
      db.setDocumentExpiration(
        'testdoc',
        DateTime.now().add(Duration(seconds: 2)),
      ),
      true,
    );

    await Future.delayed(Duration(seconds: 5));
    expect(db.getDocument('testdoc').isEmpty, true);

    // Setting the expiration date to the past should delete the document
    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));

    expect(
      db.setDocumentExpiration(
        'testdoc',
        DateTime.now().subtract(Duration(minutes: 10)),
      ),
      true,
    );
    await Future.delayed(Duration(seconds: 5));
    expect(db.getDocument('testdoc').isEmpty, true);

    // Setting the expiration date to null should stop the document from expiring
    // even if there was a previous expiration set
    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));

    expect(
      db.setDocumentExpiration(
        'testdoc',
        DateTime.now().add(Duration(seconds: 3)),
      ),
      true,
    );

    expect(
      db.setDocumentExpiration(
        'testdoc',
        DateTime.fromMicrosecondsSinceEpoch(0),
      ),
      true,
    );

    await Future.delayed(Duration(seconds: 5));
    expect(
      db.getDocument('testdoc'),
      predicate<Document>((doc) => doc.ID == 'testdoc'),
    );

    addTearDown(() => db.close());
  });

  test('getDocumentExpiration', () async {
    var db = Database('getdocexp', directory: '_tmp');
    db.saveDocument(Document('testdoc', data: {'foo': 'bar'}));

    expect(db.documentExpiration('testdoc').microsecondsSinceEpoch, 0);

    var expiration = DateTime.now().add(Duration(minutes: 10));
    db.setDocumentExpiration('testdoc', expiration);

    expect(
      db.documentExpiration('testdoc'),
      predicate<DateTime>(
          (e) => e.millisecondsSinceEpoch == expiration.millisecondsSinceEpoch),
    );

    addTearDown(() => db.close());
  });

  test('addChangeListener', () async {
    var db = Database('dbchange', directory: '_tmp');
    var changed_docs = [];
    var change_received = false;

    var token = db.addChangeListener((change) {
      change_received = true;
      changed_docs = change.documentIDs;
    });

    expect(token, isA<String>());

    db.saveDocument(Document('testdoc1'));

    while (!change_received) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    expect(changed_docs, ['testdoc1']);

    addTearDown(() {
      db.close();
    });
  });

  test('removeChangeListener', () async {
    var db = Database('dbremchange', directory: '_tmp');
    var changed_docs = [];
    var change_received = false;
    var token = db.addChangeListener((change) {
      change_received = true;
      changed_docs = change.documentIDs;
    });

    await asyncSleep(100);
    db.removeChangeListener(token);
    await asyncSleep(100);
    db.saveDocument(Document('testdoc1'));
    await asyncSleep(1000);

    expect(change_received, false);
    expect(changed_docs, []);

    addTearDown(() => db.close());
  });

  test('addDocumentChangeListener', () async {
    var db = Database('dbdocchange', directory: '_tmp');
    var changed_doc = '';
    var change_received = false;

    var token = db.addDocumentChangeListener('testdoc', (change) {
      print('testdoc listener');
      change_received = true;
      changed_doc = change.documentID;
    });

    var changed_doc1 = '';
    var change_received1 = false;

    var token1 = db.addDocumentChangeListener('testdoc1', (change) {
      print('testdoc1 listener');
      change_received1 = true;
      changed_doc1 = change.documentID;
    });

    expect(token, isA<String>());
    expect(token1, isA<String>());

    db.saveDocument(Document('testdoc'));

    while (!change_received) {
      await asyncSleep(100);
    }

    expect(changed_doc, 'testdoc');
    expect(changed_doc1, '');
    expect(change_received1, false);

    change_received = false;
    changed_doc = '';
    db.saveDocument(Document('testdoc1'));

    await asyncSleep(1000);
    expect(change_received, false);
    expect(changed_doc, '');

    expect(change_received1, true);
    expect(changed_doc1, 'testdoc1');

    addTearDown(db.close);
  });

  test('removeDocumentChangeListener', () async {
    var db = Database('dbremdocchange', directory: '_tmp');
    var changed_doc = '';
    var change_received = false;
    var token = db.addDocumentChangeListener('testdoc', (change) {
      change_received = true;
      changed_doc = change.documentID;
    });

    await asyncSleep(100);
    db.removeDocumentChangeListener(token);
    await asyncSleep(100);
    db.saveDocument(Document('testdoc'));
    await asyncSleep(100);

    expect(change_received, false);
    expect(changed_doc, '');

    addTearDown(() => db.close());
  });

  test('index', () async {
    var db = Database('dbindex', directory: '_tmp');

    expect(
      db.createIndex('index1', ['foo, bar']),
      true,
    );

    expect(
      db.createIndex('index2', ['["foo"]'], language: CBLQueryLanguage.json),
      true,
    );

    expect(
      db.createIndex('index3', ['{"WHAT": ["foo"]}'],
          language: CBLQueryLanguage.json),
      true,
    );

    expect(
      () => db.createIndex('index2', ['foo'], language: CBLQueryLanguage.json),
      throwsA(predicate((e) =>
          e is CouchbaseLiteException &&
          e.domain == cbl.CBLDomain &&
          e.code == cbl.CBLErrorInvalidQuery)),
    );

    expect(
      db.indexNames(),
      ['index1', 'index2', 'index3'],
    );

    expect(
      db.deleteIndex('index1'),
      true,
    );

    expect(
      db.indexNames(),
      ['index2', 'index3'],
    );

    addTearDown(() => db.close());
  });

  test('bufferNotifications', () async {
    var db = Database('buffnot', directory: '_tmp');
    var notifications_ready = false;
    db.bufferNotifications(() => notifications_ready = true);

    await asyncSleep(100);
    db.addChangeListener((c) => true);
    await asyncSleep(100);
    expect(notifications_ready, false);

    db.saveDocument(Document('testdoc'));

    while (!notifications_ready) {
      await asyncSleep(100);
    }

    // We expect to get here before the test times out...
    expect(true, true);
    addTearDown(() => db.close());
  });

  test('sendNotifications', () async {
    var db = Database('sendnot', directory: '_tmp');

    var changed_docs = [];
    var notificationReady = false;
    var changed_doc = false;

    db.addChangeListener((c) => changed_docs = c.documentIDs);

    db.addDocumentChangeListener('testdoc1', (c) => changed_doc = true);

    // The idea here is that when the first notification is ready,
    // we wait one second to tell the database to send the notifications.
    // All notifications should be sent at the time.

    db.bufferNotifications(() async {
      notificationReady = true;
      await asyncSleep(1000);
      db.sendNotifications();
    });

    db.saveDocument(Document('testdoc'));

    // Still no change? Good.
    await asyncSleep(200);
    expect(notificationReady, true);
    expect(changed_docs, []);
    expect(changed_doc, false);

    db.saveDocument(Document('testdoc1'));

    // Still no change? Still good.
    await asyncSleep(200);
    expect(notificationReady, true);
    expect(changed_docs, []);
    expect(changed_doc, false);

    // Changes have arrived?
    await asyncSleep(1100);
    expect(changed_docs, ['testdoc', 'testdoc1']);
    expect(changed_doc, true);

    addTearDown(() => db.close());
  });
}

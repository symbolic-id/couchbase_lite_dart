// Copyright (c) 2020, Rudolf Martincsek. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

part of couchbase_lite_dart;

/// A [Blob] is a binary data blob associated with a document.

/// The content of the blob is not stored in the document, but externally in the database.
/// It is loaded only on demand, and can be streamed. Blobs can be arbitrarily large, although
/// Sync Gateway will only accept blobs under 20MB.
///
/// The document contains only a blob reference: a dictionary with the special marker property
/// `"@type":"blob"`, and another property `digest` whose value is a hex SHA-1 digest of the
/// blob's data. This digest is used as the key to retrieve the blob data.
/// The dictionary usually also has the property `length`, containing the blob's length in bytes,
/// and it may have the property `content_type`, containing a MIME type.
///
/// A [Blob] object acts as a proxy for such a dictionary in a [Document]. Once
/// you've loaded a document and located the [FLDict] holding the blob reference, call
/// [Blob.fromValue] on it to create a [Blob] object.
/// The object has accessors for the blob's metadata and for loading the data itself.
///
/// To create a new blob from in-memory data, call [Blob.createWithData],
///
/// To create a new blob from a stream, call [Blob.createWithStream].
///
/// Once you have a blob created add the properties of the Blob to the document
/// (or to a dictionary or array property of the document.) and save the document.
///
///Example:
/// ```dart
/// var file = File('D:/blobtest.png');
/// var data = file.readAsBytesSync();
/// var blob = Blob.createWithData('image/png', data);
///
/// //or
/// var stream = file.openRead().cast<Uint8List>();
/// blob = await Blob.createWithStream(db, 'image/png', stream);
///
/// doc = db.getMutableDocument('testdoc');
/// doc.properties['logo'] = blob.properties;
/// db.saveDocument(doc);
/// ```
class Blob {
  ffi.Pointer<cbl.CBLBlob> pointer;

  Blob._internal(this.pointer);

  /// Creates a new blob given its contents as a single block of data.
  Blob.createWithData(String contentType, Uint8List data) {
    final error = cbl.CBLError.allocate();

    var buf = pffi.allocate<ffi.Uint8>(count: data.length);
    var list = buf.asTypedList(data.length);
    list.setAll(0, data);

    pointer = cbl.CBLBlob_CreateWithData_c(
      cbl.strToUtf8(contentType),
      buf,
      list.length,
      error.addressOf,
    );

    validateError(error);
  }

  /// Creates a new blob using data from the stream. Returns a future that will
  /// complete with a new [Blob] instance when the stream is closed or with
  /// a [CouchbaseLiteException] in case of error.
  static Future<Blob> createWithStream(
      Database db, String contentType, Stream<Uint8List> stream) async {
    final result = Completer<Blob>();

    final error = cbl.CBLError.allocate();
    ffi.Pointer<cbl.CBLBlobWriteStream> _blobStream;
    try {
      _blobStream = cbl.CBLBlobWriter_New(db._db, error.addressOf);
      validateError(error);
    } on CouchbaseLiteException catch (e) {
      result.completeError(e);
      return result.future;
    }

    stream.listen(
      (data) {
        error.reset();

        var buf = pffi.allocate<ffi.Uint8>(count: data.length);
        var list = buf.asTypedList(data.length);
        list.setAll(0, data);

        cbl.CBLBlobWriter_Write(_blobStream, buf, list.length, error.addressOf);
        pffi.free(buf);
      },
      onDone: () => result.complete(
        Blob._internal(
          cbl.CBLBlob_CreateWithStream(cbl.strToUtf8(contentType), _blobStream),
        ),
      ),
      onError: (error) {
        cbl.CBLBlobWriter_Close(_blobStream);
        result.completeError(CouchbaseLiteException(
          cbl.CBLErrorDomain.CBLDomain.index,
          cbl.CBLErrorCode.CBLErrorNotFound.index,
          'Error writing blob from stream',
        ));
      },
      cancelOnError: true,
    );

    return result.future;
  }

  /// Create a [Blob] object corresponding to a blob dictionary in a document.
  factory Blob.fromValue(FLDict dict) {
    if (dict == null ||
        dict.addressOf == ffi.nullptr ||
        dict['@type'] == null ||
        dict['@type'].asString != 'blob') return null;

    return Blob._internal(cbl.CBLBlob_Get(dict.addressOf));
  }

  Uint8List _content;

  /// A blob's MIME type, if its metadata has a `content_type` property.
  String get contentType => cbl.utf8ToStr(cbl.CBLBlob_ContentType(pointer));

  /// Returns the cryptographic digest of a blob's content (from its `digest` property).
  String get digest => cbl.utf8ToStr(cbl.CBLBlob_Digest(pointer));

  /// Returns the length in bytes of a blob's content (from its `length` property).
  int get length => cbl.CBLBlob_Length(pointer);

  /// Convenience method to return the properties as a Dart map
  Map<String, dynamic> get asMap => jsonDecode(properties.json);

  /// Returns a blob's metadata. This includes the `digest`, `length` and `content_type`
  /// properties, as well as any custom ones that may have been added.
  FLDict get properties => pointer != null
      ? FLDict.fromPointer(cbl.CBLBlob_Properties(pointer))
      : null;

  /// Read a blob's content as a stream.
  Stream<Uint8List> getContentStream({int chunk = 10240}) async* {
    final error = cbl.CBLError.allocate();
    final blobStream = cbl.CBLBlob_OpenContentStream(pointer, error.addressOf);
    final data = pffi.allocate<ffi.Uint8>(count: chunk);

    if (error.domain != 0) {
      pffi.free(error.addressOf);
      return;
    }

    // We don't want to accidentally allocate gigs of memory
    chunk = max(0, min(chunk, 100240));

    var count = 0;
    do {
      error.reset();

      count = cbl.CBLBlobReader_Read(blobStream, data, chunk, error.addressOf);

      if (count > 0) {
        yield data.asTypedList(count);
      }
    } while (count > 0);

    cbl.CBLBlobReader_Close(blobStream);
    pffi.free(data);
    pffi.free(error.addressOf);
  }

  /// Reads the blob's contents into memory and returns them.
  Future<Uint8List> getContent() async =>
      _content ??= await getContentStream().reduce((p, e) {
        p.addAll(e);
        return p;
      });
}

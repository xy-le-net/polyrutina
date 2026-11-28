abstract interface class ImportMediaRepository {
  Future<String> save(String fileName, List<int> bytes);
  Future<void> delete(String path);
}

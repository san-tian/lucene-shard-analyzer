package com.example.luceneanalyzer;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.file.DirectoryStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.stream.Stream;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream;
import org.apache.lucene.index.SegmentCommitInfo;
import org.apache.lucene.index.SegmentInfos;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.FSDirectory;
import org.apache.lucene.util.Version;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@Service
public class LuceneAnalyzerService {
  public AnalysisReport analyze(MultipartFile file) {
    if (file == null || file.isEmpty()) {
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "file is required");
    }

    Path tempDir = null;
    try {
      tempDir = Files.createTempDirectory("lucene-analyze-");
      String originalName = Objects.requireNonNullElse(file.getOriginalFilename(), "upload");
      Path archivePath = tempDir.resolve(sanitizeFilename(originalName));
      try (InputStream in = file.getInputStream()) {
        Files.copy(in, archivePath, StandardCopyOption.REPLACE_EXISTING);
      }

      Path extractDir = tempDir.resolve("extract");
      Files.createDirectories(extractDir);
      extractArchive(archivePath, extractDir);

      Path indexDir = findSingleLuceneIndexDir(extractDir);
      return analyzeIndex(indexDir);
    } catch (IOException e) {
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "failed to analyze archive", e);
    } finally {
      if (tempDir != null) {
        deleteRecursively(tempDir);
      }
    }
  }

  private AnalysisReport analyzeIndex(Path indexDir) throws IOException {
    try (Directory directory = FSDirectory.open(indexDir)) {
      SegmentInfos infos = SegmentInfos.readLatestCommit(directory);
      List<SegmentReport> segments = new ArrayList<>();
      long totalDocs = 0;
      long totalDeleted = 0;
      long totalLiveDocs = 0;
      long totalSizeBytes = 0;
      Version minSegmentVersion = null;
      Version maxSegmentVersion = null;

      for (SegmentCommitInfo commitInfo : infos) {
        long docs = commitInfo.info.maxDoc();
        long deleted = commitInfo.getDelCount();
        long size = commitInfo.sizeInBytes();
        long liveDocs = docs - deleted;
        int filesCount = commitInfo.files().size();
        String codec = commitInfo.info.getCodec().getName();
        Version segmentVersion = commitInfo.info.getVersion();
        String segmentVersionString = segmentVersion == null ? "unknown" : segmentVersion.toString();
        boolean compoundFile = commitInfo.info.getUseCompoundFile();
        segments.add(new SegmentReport(
            commitInfo.info.name,
            docs,
            deleted,
            liveDocs,
            size,
            filesCount,
            codec,
            segmentVersionString,
            compoundFile));
        totalDocs += docs;
        totalDeleted += deleted;
        totalLiveDocs += liveDocs;
        totalSizeBytes += size;
        if (segmentVersion != null) {
          if (minSegmentVersion == null || segmentVersion.compareTo(minSegmentVersion) < 0) {
            minSegmentVersion = segmentVersion;
          }
          if (maxSegmentVersion == null || segmentVersion.compareTo(maxSegmentVersion) > 0) {
            maxSegmentVersion = segmentVersion;
          }
        }
      }

      Integer indexCreatedVersionMajor = infos.getIndexCreatedVersionMajor();
      if (indexCreatedVersionMajor != null && indexCreatedVersionMajor <= 0) {
        indexCreatedVersionMajor = null;
      }
      String minVersion = minSegmentVersion == null ? "unknown" : minSegmentVersion.toString();
      String maxVersion = maxSegmentVersion == null ? "unknown" : maxSegmentVersion.toString();
      Summary summary = new Summary(
          infos.size(),
          totalDocs,
          totalDeleted,
          totalLiveDocs,
          totalSizeBytes,
          indexCreatedVersionMajor,
          minVersion,
          maxVersion);
      return new AnalysisReport(summary, segments);
    } catch (IllegalArgumentException e) {
      String msg = e.getMessage() == null ? "" : e.getMessage();
      if (msg.contains("indexCreatedVersionMajor is in the future")) {
        throw new ResponseStatusException(
            HttpStatus.BAD_REQUEST,
            "lucene index version is newer than this analyzer; rebuild with a newer Lucene or recreate the shard with an older OpenSearch/Lucene version",
            e);
      }
      throw e;
    }
  }

  private void extractArchive(Path archive, Path destination) throws IOException {
    String name = archive.getFileName().toString().toLowerCase(Locale.ROOT);
    if (name.endsWith(".zip")) {
      ArchiveUtils.unzip(archive, destination);
      return;
    }

    if (name.endsWith(".tar") || name.endsWith(".tar.gz") || name.endsWith(".tgz")) {
      ArchiveUtils.untar(archive, destination, name.endsWith(".gz") || name.endsWith(".tgz"));
      return;
    }

    throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "unsupported archive format");
  }

  private Path findSingleLuceneIndexDir(Path root) throws IOException {
    List<Path> matches = new ArrayList<>();
    try (Stream<Path> stream = Files.walk(root)) {
      stream.filter(Files::isDirectory).forEach(dir -> {
        try (DirectoryStream<Path> entries = Files.newDirectoryStream(dir, "segments_*");) {
          if (entries.iterator().hasNext()) {
            matches.add(dir);
          }
        } catch (IOException e) {
          throw new UncheckedIOException(e);
        }
      });
    } catch (UncheckedIOException e) {
      throw e.getCause();
    }

    if (matches.isEmpty()) {
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "no lucene index found");
    }

    if (matches.size() > 1) {
      throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "multiple lucene indices found");
    }

    return matches.get(0);
  }

  private void deleteRecursively(Path root) {
    try {
      Files.walkFileTree(root, new SimpleFileVisitor<>() {
        @Override
        public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
          Files.deleteIfExists(file);
          return FileVisitResult.CONTINUE;
        }

        @Override
        public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
          Files.deleteIfExists(dir);
          return FileVisitResult.CONTINUE;
        }
      });
    } catch (IOException ignored) {
      // Best-effort cleanup.
    }
  }

  private String sanitizeFilename(String name) {
    return name.replaceAll("[^A-Za-z0-9._-]", "_");
  }

  static class ArchiveUtils {
    static void unzip(Path archive, Path destination) throws IOException {
      try (java.util.zip.ZipInputStream zis = new java.util.zip.ZipInputStream(Files.newInputStream(archive))) {
        java.util.zip.ZipEntry entry;
        while ((entry = zis.getNextEntry()) != null) {
          Path outPath = safeResolve(destination, entry.getName());
          if (entry.isDirectory()) {
            Files.createDirectories(outPath);
          } else {
            Files.createDirectories(outPath.getParent());
            Files.copy(zis, outPath, StandardCopyOption.REPLACE_EXISTING);
          }
        }
      }
    }

    static void untar(Path archive, Path destination, boolean gzip) throws IOException {
      InputStream input = Files.newInputStream(archive);
      if (gzip) {
        input = new GzipCompressorInputStream(input);
      }

      try (TarArchiveInputStream tis = new TarArchiveInputStream(input)) {
        TarArchiveEntry entry;
        while ((entry = tis.getNextTarEntry()) != null) {
          Path outPath = safeResolve(destination, entry.getName());
          if (entry.isDirectory()) {
            Files.createDirectories(outPath);
          } else {
            Files.createDirectories(outPath.getParent());
            Files.copy(tis, outPath, StandardCopyOption.REPLACE_EXISTING);
          }
        }
      }
    }

    static Path safeResolve(Path destination, String entryName) throws IOException {
      Path resolved = destination.resolve(entryName).normalize();
      if (!resolved.startsWith(destination)) {
        throw new IOException("entry outside target dir: " + entryName);
      }
      return resolved;
    }
  }
}

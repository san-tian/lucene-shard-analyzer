package com.example.luceneanalyzer;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.util.List;

public class AnalysisReport {
  private final Summary summary;
  private final List<SegmentReport> segments;

  public AnalysisReport(Summary summary, List<SegmentReport> segments) {
    this.summary = summary;
    this.segments = segments;
  }

  public Summary getSummary() {
    return summary;
  }

  public List<SegmentReport> getSegments() {
    return segments;
  }
}

class Summary {
  private final int segments;

  @JsonProperty("docs")
  private final long docs;

  @JsonProperty("deleted_docs")
  private final long deletedDocs;

  @JsonProperty("live_docs")
  private final long liveDocs;

  @JsonProperty("total_size_bytes")
  private final long totalSizeBytes;

  @JsonProperty("index_created_version_major")
  private final Integer indexCreatedVersionMajor;

  @JsonProperty("min_segment_version")
  private final String minSegmentVersion;

  @JsonProperty("max_segment_version")
  private final String maxSegmentVersion;

  Summary(
      int segments,
      long docs,
      long deletedDocs,
      long liveDocs,
      long totalSizeBytes,
      Integer indexCreatedVersionMajor,
      String minSegmentVersion,
      String maxSegmentVersion) {
    this.segments = segments;
    this.docs = docs;
    this.deletedDocs = deletedDocs;
    this.liveDocs = liveDocs;
    this.totalSizeBytes = totalSizeBytes;
    this.indexCreatedVersionMajor = indexCreatedVersionMajor;
    this.minSegmentVersion = minSegmentVersion;
    this.maxSegmentVersion = maxSegmentVersion;
  }

  public int getSegments() {
    return segments;
  }

  public long getDocs() {
    return docs;
  }

  public long getDeletedDocs() {
    return deletedDocs;
  }

  public long getLiveDocs() {
    return liveDocs;
  }

  public long getTotalSizeBytes() {
    return totalSizeBytes;
  }

  public Integer getIndexCreatedVersionMajor() {
    return indexCreatedVersionMajor;
  }

  public String getMinSegmentVersion() {
    return minSegmentVersion;
  }

  public String getMaxSegmentVersion() {
    return maxSegmentVersion;
  }
}

class SegmentReport {
  private final String name;

  @JsonProperty("docs")
  private final long docs;

  @JsonProperty("deleted_docs")
  private final long deletedDocs;

  @JsonProperty("live_docs")
  private final long liveDocs;

  @JsonProperty("size_bytes")
  private final long sizeBytes;

  @JsonProperty("files_count")
  private final int filesCount;

  @JsonProperty("codec")
  private final String codec;

  @JsonProperty("segment_version")
  private final String segmentVersion;

  @JsonProperty("compound_file")
  private final boolean compoundFile;

  SegmentReport(
      String name,
      long docs,
      long deletedDocs,
      long liveDocs,
      long sizeBytes,
      int filesCount,
      String codec,
      String segmentVersion,
      boolean compoundFile) {
    this.name = name;
    this.docs = docs;
    this.deletedDocs = deletedDocs;
    this.liveDocs = liveDocs;
    this.sizeBytes = sizeBytes;
    this.filesCount = filesCount;
    this.codec = codec;
    this.segmentVersion = segmentVersion;
    this.compoundFile = compoundFile;
  }

  public String getName() {
    return name;
  }

  public long getDocs() {
    return docs;
  }

  public long getDeletedDocs() {
    return deletedDocs;
  }

  public long getLiveDocs() {
    return liveDocs;
  }

  public long getSizeBytes() {
    return sizeBytes;
  }

  public int getFilesCount() {
    return filesCount;
  }

  public String getCodec() {
    return codec;
  }

  public String getSegmentVersion() {
    return segmentVersion;
  }

  public boolean isCompoundFile() {
    return compoundFile;
  }
}

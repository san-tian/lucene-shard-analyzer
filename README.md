# Task 1 - Lucene Shard Analyzer Service (Java)

This folder contains the Task 1 deliverables: a Java Spring Boot service that analyzes Lucene shard archives, plus the Docker and CI/CD setup for multi-arch images.

## What this service does

A stateless HTTP service that listens on port 8080 and exposes:

- `GET /healthz` -> returns `200 OK` with body `ok`
- `GET /info` -> returns JSON with `version`, `git_sha`, `arch`, `hostname`
- `GET /metrics` -> Prometheus metrics
- `POST /analyze` -> upload a shard archive (tar/zip) and get a JSON report

The `/analyze` endpoint expects an archive containing exactly one Lucene index directory (detected by a `segments_*` file). The report includes:

- total segments
- total docs, deleted docs, live docs
- total index size in bytes
- index created version major and min/max segment versions
- per-segment details (name, docs, deleted docs, live docs, size, files count, codec, segment version, compound file flag)

## Code layout

- `pom.xml`
- `src/main/java/com/example/luceneanalyzer/Application.java`
- `src/main/java/com/example/luceneanalyzer/AnalyzerController.java`
- `src/main/java/com/example/luceneanalyzer/LuceneAnalyzerService.java`
- `src/main/java/com/example/luceneanalyzer/AnalysisReport.java`
- `Dockerfile`
- `../.github/workflows/docker-build.yml`

## Build and run locally

```bash
cd task1
mvn -q -DskipTests package
java -jar target/*.jar
```

Then test:

```bash
curl -s http://localhost:8080/healthz
curl -s http://localhost:8080/info
curl -s http://localhost:8080/metrics
curl -F "file=@/path/to/shard.zip" http://localhost:8080/analyze
```

## Build Docker image locally

```bash
cd task1
docker build -t lucene-shard-analyzer:local .
```

Run the container:

```bash
docker run --rm -p 8080:8080 \
  -e APP_VERSION=local \
  -e GIT_SHA=local \
  lucene-shard-analyzer:local
```

## CI/CD (GitHub Actions)

Workflow: `../.github/workflows/docker-build.yml`

It builds and pushes multi-arch images (amd64/arm64) to GHCR with tags:

- `latest` (main branch)
- `sha-<shortsha>`
- `vX.Y.Z` (git tags)

## Notes

- `/analyze` returns `400` if it finds zero or multiple Lucene index directories.
- Version info in `/info` comes from `APP_VERSION` and `GIT_SHA` env vars.

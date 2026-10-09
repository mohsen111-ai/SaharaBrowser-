# Caravan downloads

**Status: plan only, nothing implemented.** Goal: split each download across 4, 6, 8, 10, 12 or 16
parallel connections (default 8) and show them as "lanes", falling back to Fenix's normal single stream
whenever splitting isn't safe or doesn't help.

## How Fenix downloads today (verified in 157.0.1 / mozilla-central)

- `DownloadService : AbstractFetchDownloadService` (Fenix), with `httpClient = components.core.client`.
- `performDownload(currentDownloadJobState, useHttpClient = false)`:
  - on a first attempt it **reuses `download.response`**, the response the engine already opened, unless
    resuming or `useHttpClient` is set;
  - otherwise `fetchDownloadResponse()` builds `Request(url, headers, private, referrerUrl)`;
  - resume sends `Range: bytes=N-`; a `206` or `200` is accepted, a `200` on resume restarts the file, and a
    missing or mismatched `Content-Range` fails the download;
  - `copyInChunks()` copies 32 KB chunks into one `OutputStream`; progress is throttled to 750 ms;
  - `verifyDownload` compares bytes copied with `contentLength`.
- File output goes through `downloadFileWriter.useFileStream(download, append, scopedStorage, ...)`:
  scoped storage creates a MediaStore row (`IS_PENDING = 1`, cleared to `0` after the write) or a SAF
  document, and wraps a `ParcelFileDescriptor` as an `OutputStream` (modes `"w"` / `"wa"`). Pre-Android-10
  uses a plain `FileOutputStream`. **Writing is strictly sequential.**
- Reusable pieces in the same package: `ContentRange.kt`, `DownloadEstimator.kt`, `DownloadStorage.kt`.

## Design

1. **Probe.** Segment only when the server answers a ranged request correctly (`Accept-Ranges: bytes` or a
   valid `206`/`Content-Range`), the size is known, and there is a stable validator (`ETag` or
   `Last-Modified`). Otherwise use the stock path. Small files get fewer lanes; below a few MB, one.
2. **Plan (pure Kotlin, unit-tested).** `SegmentPlanner` cuts the file into ranges and, when a lane
   finishes, **splits the largest remaining range** so fast connections take over slow ones' work.
3. **Write.** `SegmentedFileWriter` needs positional writes (`FileChannel` over a read/write descriptor)
   so lanes can write at their own offsets. *Open question:* confirm random-access writes work on MediaStore
   pending files and SAF providers on the Android versions in use. Fallbacks: per-lane temp files merged at
   the end, or single-stream when the target isn't seekable.
4. **Correctness.** Send `Accept-Encoding: identity` (decompression would break byte ranges) and
   `If-Range` with the validator; if the validator changes mid-download, stop and restart cleanly.
5. **Persistence.** Save the segment table about once a second next to `DownloadStorage` (Room migration or
   a sidecar file) so a download resumes lane-by-lane after the app is killed.
6. **Courtesy.** Cap total connections across all downloads and per host; on `429`/`503`/resets, halve the
   lanes and retry. This protects servers and your own link.
7. **Integration.** One small patch at `performDownload`: if eligible, hand off to the segmented downloader;
   on any error or ineligibility, run the stock code. Worst case equals stock Fenix.
8. **Surface.** Aggregate bytes into the existing `currentBytesCopied` so notifications keep working; expose
   per-lane progress to the Caravan screen. Setting `connections ∈ {4, 6, 8, 10, 12, 16}`, default 8.

## The HTTP/2 and HTTP/3 problem

Most big hosts speak HTTP/2 or HTTP/3, which carry many requests over **one** connection. If the server's
limit is per connection, 16 ranged requests share it and don't get faster. Two ways to get genuinely
separate connections:

| | Approach | Cost |
|---|---|---|
| **A (later, if needed)** | Patch GeckoView/necko so download requests are forced onto HTTP/1.1 and their own sockets; keeps cookies, private mode, proxy and DoH. | Compiling Gecko from source (hours, large disk). |
| **B (not planned)** | A separate OkHttp client pinned to HTTP/1.1. | Loses Gecko's cookie jar, so logged-in downloads break unless cookies are bridged. |

**Plan:** build step 1–8 on the existing client first (fully effective on HTTP/1.1 hosts, partly elsewhere),
benchmark, then decide on A with numbers. `network.http.max-persistent-connections-per-server` only matters
for HTTP/1.1 and also changes page loading, so it is **not raised globally** unless measurements justify it
(or until A scopes it to downloads).

## Measure before deciding

Fixed set of test files (several CDNs plus a local rate-limited server). For each: MB/s at 1, 4, 8, 16
lanes, HTTP/1.1 vs HTTP/2 vs HTTP/3 hosts, on Wi-Fi and a throttled link. Record in `docs/benchmarks/`.
Expect clear gains mainly where a CDN throttles per connection or the link is lossy or high-latency; on a
clean link one connection often already fills the pipe.

## UI

Replace or wrap `fenix/.../downloads/listscreen` (Compose) with the Caravan screen: aggregate speed meter,
per-download lanes, pause/resume, "Pause all", "Clear finished"; Settings row "Connections per download"
with the hint text per value (see [DESIGN.md](../DESIGN.md)). Lane animation follows the Motion board.

// ============================================================================
// glog.goose — counts lines in Common Log Format log files
//
// Run (from the folder where goose.exe lives):
//   goose.exe glog.goose -- count small.log            — total line count
//   goose.exe glog.goose -- count_by path small.log   — lines per URL path
//   goose.exe glog.goose -- where_ge 500 small.log    — lines with status >= 500
//
// Messages are in English so the output is readable in any Windows
// console code page (legacy cmd shows UTF-8 Cyrillic as mojibake).
// ============================================================================

import std;
import os;
import dictionary;

// ----------------------------------------------------------------------------
// Extracts the page path and the status code from a log line.
// The line looks like:
//   127.0.0.1 - frank [10/Oct/2026:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
//                                        path ↑                  status ↑
// ----------------------------------------------------------------------------
fn parse_line(line: const u8[:]) -> const u8[:], i64, bool {
    // find the opening quote
    var i = 0;
    while i < line.len && line[i] != '"' { i++; }
    if i == line.len { return "", 0, false; }      // no quotes — broken line
    i++;
    // skip the method (GET, POST, ...) up to the space
    while i < line.len && line[i] != ' ' { i++; }
    if i == line.len { return "", 0, false; }
    i++;
    // the path — from here to the next space
    let start = i;
    while i < line.len && line[i] != ' ' { i++; }
    if i == line.len { return "", 0, false; }
    let path = line[start..i];
    // find the closing quote
    while i < line.len && line[i] != '"' { i++; }
    if i == line.len { return "", 0, false; }
    i++;
    // after the closing quote: a space, then the status digits
    if i >= line.len || line[i] != ' ' { return "", 0, false; }
    i++;
    var code: i64 = 0;
    var ndig = 0;
    while i < line.len && line[i] >= '0' && line[i] <= '9' {
        code = code * 10 + (line[i] - '0');
        ndig++;
        i++;
    }
    if ndig == 0 { return "", 0, false; }
    return path, code, true;
}

fn usage() {
    print("usage:");
    print("  goose glog.goose -- count file.log");
    print("  goose glog.goose -- count_by path file.log");
    print("  goose glog.goose -- where_ge N file.log");
}

fn main() {
    let argv = args();                 // command line arguments
    if argv.len < 2 { usage(); return; }

    // Take arguments from the END: works whether or not args()
    // includes the program name at index 0.
    let file = argv[argv.len - 1];     // last one is always the file name
    let prev = argv[argv.len - 2];     // before it: command, field or number

    // read the whole file into one buffer
    var data: u8[>..] = [];
    if !read_file(file, data) {
        print("cannot read file: ", file);
        return;
    }

    var total: i64 = 0;      // good lines
    var skipped: i64 = 0;    // broken lines

    // --- "count" mode: just count lines ---
    if prev == "count" {
        each_split(data, '\n') {
            if it.len > 0 {
                let path, code, line_ok = parse_line(it);
                if line_ok { total++; } else { skipped++; }
            }
        };
        print("total lines: ", total);
        if skipped > 0 { print("skipped bad lines: ", skipped); }
        return;
    }

    // --- "count_by path" mode: count per URL path ---
    // arguments: ... count_by path file.log
    if argv.len >= 3 && argv[argv.len - 3] == "count_by" && prev == "path" {
        // hash table: path -> how many times seen.
        // Keys are slices straight into the file buffer: no string copies.
        var counts = dictionary<const u8[:], i64> {};
        each_split(data, '\n') {
            if it.len > 0 {
                let path, code, line_ok = parse_line(it);
                if line_ok {
                    counts.update(path, 0) { it += 1; };
                } else {
                    skipped++;
                }
            }
        };
        counts.each() { k, v => print(k, " ", v); };
        if skipped > 0 { print("skipped bad lines: ", skipped); }
        return;
    }

    // --- "where_ge N" mode: count lines with status >= N ---
    // arguments: ... where_ge 500 file.log
    if argv.len >= 3 && argv[argv.len - 3] == "where_ge" {
        let thr, thr_ok = parse_int(prev);
        if !thr_ok {
            print("threshold must be a number, got: ", prev);
            return;
        }
        var matched: i64 = 0;
        each_split(data, '\n') {
            if it.len > 0 {
                let path, code, line_ok = parse_line(it);
                if line_ok && code >= thr { matched++; }
            }
        };
        print("lines with status >= ", thr, ": ", matched);
        return;
    }

    usage();
}

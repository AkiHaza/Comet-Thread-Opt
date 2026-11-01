# Three-way configuration merge. Usage (all paths must name readable files):
# LC_ALL=C awk -f config_merge.awk OLD_DEFAULTS USER_CONFIG NEW_DEFAULTS > TEMP
# Replace the live file only on exit 0. No output is emitted on parse failure.
# A missing baseline is deliberately handled by the installer, never guessed.
# Keys are (package, thread); changing CPU selection or delay is a user edit.
# User order, comments, additions, edits and deletions take precedence.

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function is_comment(s) { s = trim(s); return s == "" || s ~ /^(#|\/\/)/ }
function comment_pos(s, a, b) {
    a = index(s, "#"); b = index(s, "//");
    return !a || (b && b < a) ? b : a
}
function fail(f, line, reason) {
    print paths[f] ":" line ": configuration merge refused: " reason > "/dev/stderr"
    return 0
}
function uint(s, limit) {
    if (s !~ /^[0-9]+$/) return "!"
    sub(/^0+/, "", s); if (s == "") s = "0"
    if (length(s) > length(limit) ||
        (length(s) == length(limit) && ("x" s) > ("x" limit))) return "!"
    return s
}
function delay_value(s) {
    s = trim(s)
    if (s == "") return "0"
    if (substr(s, 1, 1) != ":") return "!"
    return uint(trim(substr(s, 2)), "184467440737095516")
}
function cpu_value(s, pos, n, a, i, part, ends, count, lo, hi, swap, result) {
    pos = comment_pos(s); if (pos) s = substr(s, 1, pos - 1)
    s = trim(s); if (s == "") return "!"
    n = split(s, a, ","); result = ""
    for (i = 1; i <= n; i++) {
        part = trim(a[i])
        if (part !~ /^(e-core|p-core|hp-core|all-core)$/) {
            count = split(part, ends, "-")
            if (count > 2) return "!"
            lo = uint(trim(ends[1]), "18446744073709551615")
            hi = count == 2 ? uint(trim(ends[2]), "18446744073709551615") : lo
            if (lo == "!" || hi == "!") return "!"
            if (length(lo) > length(hi) || (length(lo) == length(hi) && ("x" lo) > ("x" hi))) {
                swap = lo; lo = hi; hi = swap
            }
            part = ("x" lo) == ("x" hi) ? lo : lo "-" hi
        }
        result = result (i > 1 ? "," : "") part
    }
    return result
}
function add_rule(f, line, pkg, thread, cpus, delay, key, cpu) {
    pkg = trim(pkg); thread = trim(thread)
    if (pkg == "" || length(pkg) >= 128 || length(thread) >= 32 ||
        pkg ~ /[{}=[:cntrl:]]/ || thread ~ /[{}=[:cntrl:]]/)
        return fail(f, line, "unsupported package or thread name")
    cpu = cpu_value(cpus); delay = delay_value(delay)
    if (cpu == "!" || delay == "!") return fail(f, line, "invalid CPU selection or delay")
    key = pkg SUBSEP thread
    if ((f SUBSEP key) in values) return fail(f, line, "duplicate package/thread key")
    values[f, key] = cpu SUBSEP delay
    packages[f, key] = pkg; threads[f, key] = thread
    cpusets[f, key] = cpu; delays[f, key] = delay
    order[f, ++rule_count[f]] = key
    line_key[f, line] = key
    return 1
}
function parse_file(f, path, status, raw, line, p, open, close_brace, equal, prefix, rest,
                    pkg, thread, delay, col, i, cpu, pos, block, block_start, tail) {
    while ((status = (getline raw < path)) > 0) {
        line++; sub(/\r$/, "", raw); original[f, line] = raw
        if (length(raw) > 255) return fail(f, line, "line exceeds AppOpt parser limit")
        p = trim(raw)
        if (is_comment(p)) { kind[f, line] = "text"; continue }
        inline_comment[f, line] = ""; end_comment[f, line] = ""
        indent[f, line] = raw; sub(/[^[:space:]].*$/, "", indent[f, line])
        if (block) {
            close_brace = index(p, "}")
            if (close_brace) {
                tail = substr(p, close_brace + 1)
                if (!is_comment(tail)) return fail(f, line, "content after block close")
                end_comment[f, line] = trim(tail)
                closes[f, line] = 1
                p = trim(substr(p, 1, close_brace - 1))
            }
            if (p == "") { kind[f, line] = "text" }
            else {
                equal = index(p, "=")
                if (!equal) return fail(f, line, "thread rule lacks =")
                thread = trim(substr(p, 1, equal - 1)); cpu = substr(p, equal + 1); delay = ""
                col = 0
                for (i = 1; i <= length(thread); i++) if (substr(thread, i, 1) == ":") col = i
                if (col && substr(thread, col + 1, 1) ~ /[0-9]/) {
                    delay = substr(thread, col); thread = substr(thread, 1, col - 1)
                }
                if (!add_rule(f, line, pkg, thread, cpu, delay)) return 0
                kind[f, line] = "member"
                pos = comment_pos(cpu); if (pos) inline_comment[f, line] = substr(cpu, pos)
            }
            if (close_brace) block = 0
            continue
        }
        open = index(p, "{"); close_brace = open ? index(substr(p, open + 1), "}") : 0
        if (close_brace) close_brace += open
        if (open && !close_brace) {
            rest = substr(p, open + 1)
            if (!is_comment(rest)) return fail(f, line, "content after block open")
            prefix = trim(substr(p, 1, open - 1)); equal = index(prefix, "=")
            pkg = trim(equal ? substr(prefix, 1, equal - 1) : prefix)
            if (pkg == "" || length(pkg) >= 128 || pkg ~ /[{}=[:cntrl:]]/)
                return fail(f, line, "invalid block package")
            if (equal) {
                cpu = substr(prefix, equal + 1)
                if (!add_rule(f, line, pkg, "", cpu, "")) return 0
                pos = comment_pos(cpu)
                if (pos) return fail(f, line, "ambiguous comment before block open")
            }
            kind[f, line] = "open"; block_package[f, line] = pkg
            end_comment[f, line] = trim(rest)
            block = 1; block_start = line
            continue
        }
        equal = index(p, "=")
        if (!equal) return fail(f, line, "rule lacks =")
        prefix = trim(substr(p, 1, equal - 1)); cpu = substr(p, equal + 1)
        if (open) {
            if (close_brace >= equal) return fail(f, line, "invalid thread braces")
            pkg = trim(substr(prefix, 1, open - 1))
            thread = substr(prefix, open + 1, close_brace - open - 1)
            delay = substr(prefix, close_brace + 1)
        } else {
            pkg = prefix; thread = ""; delay = ""
        }
        if (!add_rule(f, line, pkg, thread, cpu, delay)) return 0
        kind[f, line] = "flat"
        pos = comment_pos(cpu); if (pos) inline_comment[f, line] = substr(cpu, pos)
    }
    close(path)
    if (status < 0) return fail(f, line + 1, "cannot read input")
    if (block) return fail(f, block_start, "unterminated block")
    line_count[f] = line
    return 1
}
function push(line) {
    if (length(line) > 255) return fail(2, 0, "merged rule exceeds AppOpt parser limit")
    output[++output_count] = line
    return 1
}
function with_comment(s, comment) { return s (comment == "" ? "" : " " comment) }
function rule_text(f, key, member, thread, text, numeric_suffix, i, colon) {
    thread = threads[f, key]
    text = member ? thread : packages[f, key] (thread == "" && delays[f, key] == "0" ? "" : "{" thread "}")
    for (i = 1; i <= length(thread); i++) if (substr(thread, i, 1) == ":") colon = i
    numeric_suffix = member && colon && substr(thread, colon + 1, 1) ~ /[0-9]/
    if (delays[f, key] != "0" || numeric_suffix) text = text ":" delays[f, key]
    return text "=" cpusets[f, key]
}
function merge(ln, key, source, type, text, i, keep) {
    for (ln = 1; ln <= line_count[2]; ln++) {
        type = kind[2, ln]; key = line_key[2, ln]
        if (key == "") { if (!push(original[2, ln])) return 0; continue }
        source = 2
        if (((1 SUBSEP key) in values) && values[1, key] == values[2, key])
            source = ((3 SUBSEP key) in values) ? 3 : 0
        if (source == 2 || (source && values[source, key] == values[2, key])) {
            if (!push(original[2, ln])) return 0
            continue
        }
        text = indent[2, ln]
        if (type == "open") {
            if (source && delays[source, key] != "0") {
                if (!push(text rule_text(source, key, 0))) return 0
                text = text block_package[2, ln] " {"
            } else text = text block_package[2, ln] (source ? "=" cpusets[source, key] : "") " {"
            text = with_comment(text, end_comment[2, ln])
        } else {
            if (source) text = text rule_text(source, key, type == "member")
            text = with_comment(text, inline_comment[2, ln])
            if (closes[2, ln]) {
                if (inline_comment[2, ln] != "") {
                    if (!push(text)) return 0
                    text = indent[2, ln]
                }
                text = with_comment(text "}", end_comment[2, ln])
            }
        }
        if ((source || type == "open" || closes[2, ln] || inline_comment[2, ln] != "") && !push(text)) return 0
    }
    keep = 0
    for (i = 1; i <= rule_count[3]; i++) {
        key = order[3, i]
        if (((1 SUBSEP key) in values) || ((2 SUBSEP key) in values)) continue
        if (!keep++) {
            if (!push("") || !push("# Default rules added by module upgrade")) return 0
        }
        text = rule_text(3, key, 0)
        if (length(text) <= 255) { if (!push(text)) return 0 }
        else {
            if (!push(packages[3, key] " {") || !push("    " rule_text(3, key, 1)) || !push("}")) return 0
        }
    }
    return 1
}
BEGIN {
    if (ARGC != 4) {
        print "usage: awk -f config_merge.awk OLD_DEFAULTS USER_CONFIG NEW_DEFAULTS" > "/dev/stderr"
        exit 2
    }
    for (file = 1; file <= 3; file++) paths[file] = ARGV[file]
    for (file = 1; file <= 3; file++) if (!parse_file(file, paths[file])) exit 2
    if (!merge()) exit 2
    for (line = 1; line <= output_count; line++) print output[line]
    exit 0
}

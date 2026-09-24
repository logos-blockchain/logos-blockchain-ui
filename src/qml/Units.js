// Token amounts. One LOGOS is 10^9 lepta, and the node deals only in lepta —
// as decimal strings, because a lepta figure runs past 2^53 where Number()
// starts losing digits (the faucet note is u64::MAX). So nothing here converts
// to a number: amounts are sliced, padded and compared as strings, exact at
// any width.
//
// The UI shows LOGOS and only LOGOS. lepta is a wire detail.
//
// Deliberately not `.pragma library`: a library script runs outside any QML
// context, and these functions need Qt.locale().
//
//     format("1500000000")    → "1.5 LGO"   (grouped for the current locale)
//     canonical("1500000000") → "1.5"       (ungrouped, '.', for copy buttons)
//     normalizeInput("1.234,5") → "1234.5"  (locale text → canonical LOGOS)

// The scale is the app's assertion, not the node's: the node publishes no
// denomination. If this is ever wrong, every figure in the app is wrong by it.
// Kept in step with kLeptaPerLgo in BlockchainBackend.cpp, which converts the
// other way.
var DECIMALS = 9
var SYMBOL = "LGO"

function _digitsOnly(s) {
    return typeof s === "string" && /^[0-9]+$/.test(s)
}

function _stripLeadingZeros(v) {
    const trimmed = v.replace(/^0+/, "")
    return trimmed.length > 0 ? trimmed : "0"
}

// Splits a lepta string into [integer, fraction], both plain digit strings.
// Fraction is always DECIMALS long; trimming happens at display time.
function _split(lepta) {
    const padded = lepta.length > DECIMALS
                 ? lepta
                 : new Array(DECIMALS - lepta.length + 1).join("0") + lepta
    return [_stripLeadingZeros(padded.slice(0, padded.length - DECIMALS)),
            padded.slice(padded.length - DECIMALS)]
}

// This locale's digit-group sizes as [primary, secondary]; [0, 0] when it does
// not group. Derived from the locale rather than assumed, so Indian 2/3
// grouping comes out right.
function groupSizesFor(locale) {
    const sep = locale.groupSeparator
    if (!sep)
        return [0, 0]
    const parts = (1234567890).toLocaleString(locale, 'f', 0).split(sep)
    if (parts.length < 2)
        return [3, 3]
    const primary = parts[parts.length - 1].length
    return [primary, parts.length > 2 ? parts[parts.length - 2].length : primary]
}

// Groups a digit string. Walks the string rather than the number: these are
// u64s, and Number() loses them. `sizes`/`sep` are injectable so a test can
// check one locale's output while running under another.
function groupDigits(s, sizes, sep) {
    const g = sizes || groupSizesFor(Qt.locale())
    const separator = (sep !== undefined) ? sep : Qt.locale().groupSeparator
    if (!s || g[0] <= 0)
        return s
    let out = ""
    let sinceSep = 0
    let width = g[0]
    for (let i = s.length - 1; i >= 0; i--) {
        if (sinceSep === width) {
            out = separator + out
            sinceSep = 0
            width = g[1] > 0 ? g[1] : g[0]
        }
        out = s.charAt(i) + out
        sinceSep += 1
    }
    return out
}

// Trailing zeros carry no information, so 10^9 lepta reads "1" and not
// "1.000000000". Never rounds: a single lepta stays 0.000000001 rather than
// becoming a "0.00" that claims the balance is empty.
function _fraction(frac, decimalPoint) {
    const trimmed = frac.replace(/0+$/, "")
    return trimmed.length > 0 ? decimalPoint + trimmed : ""
}

// LOGOS for display: grouped for `locale` (default: the current one) and
// suffixed with the symbol after a non-breaking space.
function format(lepta, locale) {
    const plain = formatPlain(lepta, locale)
    return plain.length > 0 ? plain + " " + SYMBOL : ""
}

// As format(), without the symbol — for a column whose header already names
// the unit.
function formatPlain(lepta, locale) {
    if (!_digitsOnly(lepta))
        return ""
    const loc = locale || Qt.locale()
    const parts = _split(lepta)
    return groupDigits(parts[0], groupSizesFor(loc), loc.groupSeparator)
         + _fraction(parts[1], loc.decimalPoint)
}

// Short-form LOGOS for a tile that has to fit: "16.6 LGO", "1.23K LGO",
// "18.45B LGO". For headline figures only — anything the user might copy, check
// against the chain or type back in gets format() or canonical(), which never
// round.
//
// Rounds half-up, and the rounding runs on the digit strings for the same reason
// everything else here does: these amounts pass 2^53, where Number() would lose
// the digits that matter.
var _UNITS = [[12, "T"], [9, "B"], [6, "M"], [3, "K"]]
// Enough to tell 16.6 from 16.7, few enough to fit. Trailing zeros are trimmed
// after, so a whole number stays whole.
var _COMPACT_PLACES = 2

// Rounds [int, frac] to `places` decimals, half-up. Returns the same pair.
// Carries into the integer when it has to: 0.999 at 2 places is 1.00, not 0.99.
function _roundPair(intDigits, frac, places) {
    const keep = frac.slice(0, places)
    const next = frac.charAt(places)
    if (next === "" || next < "5")
        return [intDigits, keep]
    const bumped = _add(intDigits + keep, "1")
    const cut = bumped.length - places
    return [_stripLeadingZeros(bumped.slice(0, cut)), bumped.slice(cut)]
}

function compact(lepta, locale) {
    const plain = compactPlain(lepta, locale)
    return plain.length > 0 ? plain + " " + SYMBOL : ""
}

// As compact(), without the symbol.
function compactPlain(lepta, locale) {
    if (!_digitsOnly(lepta))
        return ""
    const loc = locale || Qt.locale()
    const parts = _split(lepta)
    let int = parts[0]
    let frac = parts[1]

    // Under one LOGOS there is no magnitude to abbreviate, and rounding to two
    // places would turn a real balance into "0.00". Keep two SIGNIFICANT digits
    // instead, so a single lepta still reads as something.
    if (int === "0") {
        const firstDigit = frac.search(/[1-9]/)
        if (firstDigit < 0)
            return "0"
        const rounded = _roundPair("0", frac, Math.min(firstDigit + 2, DECIMALS))
        return rounded[0] + _fraction(rounded[1], loc.decimalPoint)
    }

    // The largest unit the integer actually exceeds; -1 when it is under a
    // thousand and there is nothing to abbreviate.
    let idx = -1
    for (let i = 0; i < _UNITS.length; i++) {
        if (int.length > _UNITS[i][0]) {
            idx = i
            break
        }
    }

    if (idx < 0) {
        const small = _roundPair(int, frac, _COMPACT_PLACES)
        return groupDigits(small[0], groupSizesFor(loc), loc.groupSeparator)
             + _fraction(small[1], loc.decimalPoint)
    }

    let unit = _renderUnit(int, frac, idx)
    // Rounding can push the head past its own unit — 999,999 renders as
    // "1000.00K", which should read "1M". Stepping UP one unit settles it, and
    // one step is always enough: the carry can only ever add a single digit.
    if (unit[0].length > 3 && idx > 0)
        unit = _renderUnit(int, frac, idx - 1)

    return groupDigits(unit[0], groupSizesFor(loc), loc.groupSeparator)
         + _fraction(unit[1], loc.decimalPoint) + unit[2]
}

// The amount expressed in _UNITS[i], as [head, frac, symbol]. The digits shifted
// off the integer become the head of the fraction. An empty head means the
// amount is below the unit — only reachable from the step-up above, where the
// carry that sent us there makes it 1.
function _renderUnit(int, frac, i) {
    const shift = _UNITS[i][0]
    const head = int.length > shift ? int.slice(0, int.length - shift) : "0"
    const tail = int.length > shift ? int.slice(int.length - shift) : int
    const rounded = _roundPair(head, tail + frac, _COMPACT_PLACES)
    return [rounded[0], rounded[1], _UNITS[i][1]]
}

// LOGOS in canonical form: no grouping, '.' as the decimal point. What copy
// buttons hand over, so it pastes into anything.
function canonical(lepta) {
    if (!_digitsOnly(lepta))
        return ""
    const parts = _split(lepta)
    return parts[0] + _fraction(parts[1], ".")
}

// Exact sum of lepta strings — schoolbook addition, right to left, so it holds
// at any width. Non-numeric entries are skipped rather than poisoning the total
// with NaN.
function sumLepta(values) {
    let sum = "0"
    for (let i = 0; i < values.length; i++) {
        const v = String(values[i] || "").trim()
        if (!_digitsOnly(v))
            continue
        sum = _add(sum, v)
    }
    return _stripLeadingZeros(sum)
}

function _add(a, b) {
    let out = ""
    let carry = 0
    let i = a.length - 1
    let j = b.length - 1
    while (i >= 0 || j >= 0 || carry > 0) {
        const digit = (i >= 0 ? a.charCodeAt(i) - 48 : 0)
                    + (j >= 0 ? b.charCodeAt(j) - 48 : 0)
                    + carry
        out = String(digit % 10) + out
        carry = digit >= 10 ? 1 : 0
        i -= 1
        j -= 1
    }
    return out.length > 0 ? out : "0"
}

// Canonical LOGOS text ("1.5") -> lepta ("1500000000"). String arithmetic, like
// everything else here: a lepta figure runs past 2^53, so Number() would lose
// digits on exactly the amounts worth checking.
//
// Returns "" for anything it cannot represent EXACTLY — including more decimal
// places than the chain has. That is a refusal, not a rounding: silently
// truncating a transfer amount is the one failure mode this file exists to
// prevent.
function toLepta(canonicalText) {
    const t = String(canonicalText || "").trim()
    if (t.length === 0)
        return ""
    const dot = t.indexOf(".")
    const whole = dot < 0 ? t : t.slice(0, dot)
    let frac = dot < 0 ? "" : t.slice(dot + 1)
    if (whole.length === 0 && frac.length === 0)
        return ""
    if (!/^[0-9]*$/.test(whole) || !/^[0-9]*$/.test(frac))
        return ""
    if (frac.length > DECIMALS)
        return ""
    frac = frac + new Array(DECIMALS - frac.length + 1).join("0")
    return _stripLeadingZeros((whole.length > 0 ? whole : "0") + frac)
}

// Orders two lepta strings: -1, 0, 1, or NaN when either is not a figure.
// Length first, then lexicographically — exact at any width, no Number().
function compareLepta(a, b) {
    const x = _stripLeadingZeros(String(a || "").trim())
    const y = _stripLeadingZeros(String(b || "").trim())
    if (!_digitsOnly(x) || !_digitsOnly(y))
        return NaN
    if (x.length !== y.length)
        return x.length < y.length ? -1 : 1
    return x < y ? -1 : (x > y ? 1 : 0)
}

// Strips grouping and normalises the decimal point to '.', so "1.234,5" (de)
// and "1,234.5" (en) both become "1234.5". Locale knowledge stops here;
// everything downstream sees canonical text.
//
// ONLY this locale's decimal point counts as one. Accepting '.' as well would
// make "1.5" mean 1.5 to a de user and 15 to this function — a silent tenfold
// error on a transfer. inputRegExp() refuses the other separator for the same
// reason, so it cannot be typed in the first place.
function normalizeInput(text, locale) {
    const loc = locale || Qt.locale()
    let out = ""
    for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i)
        if (ch >= "0" && ch <= "9")
            out += ch
        else if (ch === loc.decimalPoint)
            out += "."
        // Anything else — group separators, spaces, the symbol — is dropped.
    }
    return out
}

// What an amount field accepts while typing: digits and at most one decimal
// separator followed by at most DECIMALS digits, since the token has no finer
// unit than a lepta. Partial input ("", "1.") passes — the field must not
// fight the user mid-word.
//
// Turning that text into lepta is NOT done here. The backend owns it: the u64
// bound and the error messages belong with the code that owns correctness, and
// one implementation beats two that can drift.
function inputRegExp(locale) {
    const loc = locale || Qt.locale()
    // Escaped for the character class: '.' is literal there, but a locale
    // separator could be anything.
    const sep = loc.decimalPoint.replace(/[\\\]^-]/g, "\\$&")
    return new RegExp("^[0-9]*(?:[" + sep + "][0-9]{0," + DECIMALS + "})?$")
}

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

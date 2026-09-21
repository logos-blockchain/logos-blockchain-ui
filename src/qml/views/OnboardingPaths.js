.pragma library

// Shared by the setup and network steps, which both take a path from a
// FileDialog and show it in an editable field.
//
// Was duplicated in both files. A file dialog answers with file:///…; the
// field shows a path, so that what the user sees is what they could have
// typed themselves. Two copies of that rule is two places for it to diverge.
function toLocalPath(url) {
    var s = String(url)
    return s.indexOf("file://") === 0 ? decodeURIComponent(s.substring(7)) : s
}

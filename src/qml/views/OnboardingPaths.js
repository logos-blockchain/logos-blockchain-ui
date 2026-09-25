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

// The inverse, for FileDialog.currentFolder: the directory holding `path`, as a
// URL. Browsing for a config should start where the current one lives rather
// than wherever Qt last happened to be.
function toFolderUrl(path) {
    var s = String(path).trim()
    var cut = s.lastIndexOf("/")
    if (cut <= 0)
        return ""
    return "file://" + encodeURI(s.substring(0, cut))
}

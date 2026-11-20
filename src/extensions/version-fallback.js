'use strict'

// Where the version switch in the explore panel (bottom left) goes when the current page does not
// exist in the other version: the nearest existing parent page instead of the version's start page.
//
// For a page <module>:<dir>/<name>.adoc the candidates in the other version are, in order:
//   <module>:<dir>/index.adoc, ... up to <module>:index.adoc, then ROOT:index.adoc.
// If none exists, the version's start page is used (the helper's default).
// The result is stored as the page attribute "page-version-fallbacks" (JSON: version -> URL),
// which the versionLink helper reads. Pages that exist in the other version are handled by
// page.versions and are not stored here.

const { posix: path } = require('path')

module.exports.register = function () {
  this.on('documentsConverted', ({ contentCatalog }) => {
    // component@version -> Set of "module:relative" of published pages
    const index = new Map()
    const pages = contentCatalog.getPages((page) => page.out)
    for (const page of pages) {
      const key = `${page.src.component}@${page.src.version}`
      let set = index.get(key)
      if (!set) index.set(key, (set = new Map()))
      set.set(`${page.src.module}:${page.src.relative}`, page)
    }

    for (const component of contentCatalog.getComponents()) {
      if (component.versions.length < 2) continue
      for (const page of pages) {
        if (page.src.component !== component.name || !page.asciidoc) continue
        const fallbacks = {}
        for (const { version } of component.versions) {
          if (version === page.src.version) continue
          const target = index.get(`${component.name}@${version}`)
          if (!target || target.has(`${page.src.module}:${page.src.relative}`)) continue
          const found = candidates(page.src.module, page.src.relative).map((c) => target.get(c)).find(Boolean)
          if (found) fallbacks[version] = found.pub.url
        }
        if (Object.keys(fallbacks).length) {
          page.asciidoc.attributes['page-version-fallbacks'] = JSON.stringify(fallbacks)
        }
      }
    }
  })
}

function candidates (module, relative) {
  const out = []
  let dir = path.dirname(relative)
  const self = path.basename(relative) === 'index.adoc' ? relative : null
  while (true) {
    const idx = dir === '.' ? 'index.adoc' : `${dir}/index.adoc`
    if (idx !== self) out.push(`${module}:${idx}`)
    if (dir === '.') break
    dir = path.dirname(dir)
  }
  if (module !== 'ROOT') out.push('ROOT:index.adoc')
  return out
}

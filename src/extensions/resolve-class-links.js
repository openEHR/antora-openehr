'use strict'

// Resolves the "/classes/<NAME>" links left by older bmm-publisher output (used on the release/*
// branches migrated before bmm-publisher 0.13.0) to the class definition in this site.
//
// Lookup for a link on a page of component C, version V:
//   1. a class section in C@V           (anchor "_<name>_class", "_<name>_enumeration", ...)
//   2. the same class in another component, in its latest version (e.g. String -> BASE)
// Links that cannot be resolved become plain text instead of a dead link.
// The spec repos are not changed; this runs at build time only.

const { posix: path } = require('path')

const CLASS_LINK = /<a href="\/classes\/([^"#]*)"([^>]*)>([\s\S]*?)<\/a>/g
const CLASS_ID = /\bid="_([a-z0-9_]+?)_(class|enumeration|interface)"/g

module.exports.register = function () {
  const logger = this.getLogger('resolve-class-links')

  this.on('documentsConverted', ({ contentCatalog }) => {
    const pages = contentCatalog.getPages((page) => page.out && page.contents)

    // component@version -> class name (lower case) -> { page, id }
    const byVersion = new Map()
    for (const page of pages) {
      const key = `${page.src.component}@${page.src.version}`
      let classes = byVersion.get(key)
      if (!classes) byVersion.set(key, (classes = new Map()))
      const html = page.contents.toString()
      for (const [, name, kind] of html.matchAll(CLASS_ID)) {
        if (!classes.has(name)) classes.set(name, { page, id: `_${name}_${kind}` })
      }
    }

    const latestKeys = contentCatalog.getComponents().map((c) => `${c.name}@${c.latest.version}`)

    function find (page, name) {
      const own = byVersion.get(`${page.src.component}@${page.src.version}`)
      if (own && own.has(name)) return own.get(name)
      for (const key of latestKeys) {
        const classes = byVersion.get(key)
        if (classes && classes.has(name)) return classes.get(name)
      }
    }

    let resolved = 0
    let unlinked = 0
    for (const page of pages) {
      const html = page.contents.toString()
      if (!html.includes('href="/classes/')) continue
      const out = html.replace(CLASS_LINK, (match, rawName, attrs, text) => {
        const name = decodeURIComponent(rawName).replace(/<.*$/, '').trim().toLowerCase()
        const target = name && find(page, name)
        if (!target) {
          unlinked++
          return text
        }
        resolved++
        const rel = target.page === page ? '' : relativeUrl(page.pub.url, target.page.pub.url)
        return `<a href="${rel}#${target.id}" class="xref page"${attrs}>${text}</a>`
      })
      page.contents = Buffer.from(out)
    }
    logger.info(`/classes/ links: ${resolved} resolved, ${unlinked} without a target turned into text`)
  })
}

// Relative URL between two Antora page URLs ("indexified": they end with "/").
function relativeUrl (from, to) {
  const fromDir = from.endsWith('/') ? from : path.dirname(from) + '/'
  const rel = path.relative(fromDir, to.endsWith('/') ? to : path.dirname(to))
  const file = to.endsWith('/') ? '' : path.basename(to)
  return (rel ? rel + '/' : './') + file
}
